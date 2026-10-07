#!/bin/bash
# Issue a certificate for a bare public key from the CA in the current
# directory - for keys that cannot sign a certificate request, e.g. TPM
# endorsement or attestation keys. Run with --help for usage.

set -e

usage() {
    cat <<EOF
Usage: $0 PUBKEY.pem --subject DN --profile SECTION [--extfile FILE]
          [--days N] [--out FILE] [--card | --file] [-h | --help]

Run from inside a CA directory. Issues a certificate for the public key in
PUBKEY.pem (PEM SubjectPublicKeyInfo) with this CA's key - without a
certificate request, so it works for keys that cannot or may not sign one
(TPM EK, restricted keys such as an IAK, keys known only by their public part).

  --subject DN     subject, e.g. "/O=Example/serialNumber=1234/CN=device 1234"
  --profile NAME   extension section to apply (e.g. v3_client, or a section
                   of --extfile)
  --extfile FILE   file holding that section (default: this CA's openssl.cnf)
  --days N         validity (default 375); refused if it would outlive this CA
  --out FILE       where to write the certificate
                   (default: certs/<serial>-pubkey-cert.pem)

Serial numbers come from this CA's serial file and every certificate is
recorded in index.txt and newcerts/, exactly as 'openssl ca' does - so the
certificate can be listed and revoked like any other.

EOF
    backend_help
}

. "$(dirname "$0")/lib/cli.sh"
CLI_BACKEND_OPTS=1
CLI_VALUE_OPTS="--subject --profile --extfile --days --out"
parse_cli "$@"
set -- "${ARGS[@]}"
[ $# -eq 1 ] || cli_error "expected one public key file"
PUBKEY=$1
SUBJECT=${CLI_OPT[--subject]:-}
PROFILE=${CLI_OPT[--profile]:-}
EXTFILE=${CLI_OPT[--extfile]:-openssl.cnf}
DAYS=${CLI_OPT[--days]:-375}
OUT=${CLI_OPT[--out]:-}
[ -n "$SUBJECT" ] || cli_error "--subject is required"
[ -n "$PROFILE" ] || cli_error "--profile is required"
[[ $DAYS =~ ^[1-9][0-9]*$ ]] || cli_error "--days must be a positive number"
. "$(dirname "$0")/lib/ca-key.sh"

[ -f "$PUBKEY" ] || { echo "Not found: $PUBKEY"; exit 1; }
[ -f "$EXTFILE" ] || { echo "Not found: $EXTFILE"; exit 1; }
grep -q "^\[ *$PROFILE *\]" "$EXTFILE" || { echo "✗ no [ $PROFILE ] section in $EXTFILE"; exit 1; }
if ! openssl pkey -pubin -in "$PUBKEY" -noout 2>/dev/null; then
    echo "✗ $PUBKEY is not a PEM public key"
    exit 1
fi

card_preflight issue
[ -f certs/ca-cert.pem ] || { echo "No certs/ca-cert.pem here - is this a CA directory?"; exit 1; }
[ -f index.txt ] && [ -f serial ] || { echo "No CA database here - run $(dirname "$0")/init-ca-database.sh"; exit 1; }

# A certificate must not outlive its issuer
if ! openssl x509 -checkend $((DAYS * 86400)) -noout -in certs/ca-cert.pem > /dev/null; then
    END=$(openssl x509 -noout -enddate -in certs/ca-cert.pem | sed 's/^notAfter=//')
    MAX=$(( ($(date -d "$END" +%s) - $(date +%s)) / 86400 ))
    echo "✗ --days $DAYS would outlive this CA (valid until $END) - use --days $MAX or less"
    exit 1
fi

# The next serial, the way 'openssl ca' manages it (use, then increment)
SERIAL=$(tr -d '[:space:]' < serial | tr 'a-f' 'A-F')
[[ $SERIAL =~ ^[0-9A-F]+$ ]] || { echo "✗ unreadable serial file"; exit 1; }
OUT=${OUT:-certs/${SERIAL}-pubkey-cert.pem}

if [ "$CA_BACKEND" = card ]; then
    CA_KEY_ARGS=("${CA_PROVIDER_ARGS[@]}" -CAkey "$CA_KEY_URI" "${CA_PASSIN_ARGS[@]}")
else
    CA_KEY_ARGS=(-CAkey private/ca-key.pem "${CA_PASSIN_ARGS[@]}")
fi

echo "Public key:  $(openssl pkey -pubin -in "$PUBKEY" -noout -text 2>/dev/null | head -1)"
echo "Subject:     $SUBJECT"
echo "Issuer:      $(openssl x509 -noout -subject -in certs/ca-cert.pem | sed 's/^subject=//')"
echo "Profile:     [ $PROFILE ] from $EXTFILE, $DAYS days, serial $SERIAL"
echo "You will be prompted for the $CA_SECRET_NAME"
openssl x509 -new -force_pubkey "$PUBKEY" -subj "$SUBJECT" \
    -CA certs/ca-cert.pem "${CA_KEY_ARGS[@]}" \
    -set_serial "0x$SERIAL" -days "$DAYS" -sha256 \
    -extfile "$EXTFILE" -extensions "$PROFILE" \
    -out "$OUT"
chmod 644 "$OUT"

# Same public key in the certificate as in the file?
if [ "$(openssl x509 -in "$OUT" -pubkey -noout | openssl pkey -pubin -outform DER | sha256sum)" != \
     "$(openssl pkey -pubin -in "$PUBKEY" -outform DER | sha256sum)" ]; then
    echo "✗ ERROR: the certificate does not carry the given public key"
    exit 1
fi
if ! openssl verify -CAfile "$(ca_verify_file)" "$OUT" > /dev/null; then
    echo "✗ ERROR: the certificate does not verify against this CA"
    exit 1
fi

# Record it like 'openssl ca' does: register, copy, next serial
END=$(openssl x509 -noout -enddate -in "$OUT" | sed 's/^notAfter=//')
if [ "$(date -u -d "$END" +%Y)" -lt 2050 ]; then
    ENDSTAMP=$(date -u -d "$END" +%y%m%d%H%M%SZ)
else
    ENDSTAMP=$(date -u -d "$END" +%Y%m%d%H%M%SZ)
fi
NAME=$(openssl x509 -noout -subject -nameopt compat -in "$OUT" | sed 's/^subject=//')
printf 'V\t%s\t\t%s\tunknown\t%s\n' "$ENDSTAMP" "$SERIAL" "$NAME" >> index.txt
cp "$OUT" "newcerts/${SERIAL}.pem"
printf '%X\n' $((16#$SERIAL + 1)) | sed 's/^\(.\)$/0\1/; s/^\(.\(..\)*\)$/0\1/' > serial

echo ""
echo "✓ Issued $OUT (serial $SERIAL), verifies against this CA"
echo "✓ Recorded in index.txt and newcerts/${SERIAL}.pem"
