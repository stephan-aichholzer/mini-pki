#!/bin/bash
# Issue an intermediate CA certificate from the CA in the current directory
# (step 2 of create-intermediate-ca.sh). Run with --help for usage.

set -e

usage() {
    cat <<EOF
Usage: $0 CSR.pem [--pathlen N] [--days N] [--yes] [--card | --file] [-h | --help]

Run from inside the parent CA's directory. Signs the certificate request of
a new intermediate CA (made with 'create-intermediate-ca.sh request') with
this CA's key, using the profile v3_intermediate_ca.

  --pathlen N   how many CA levels may follow below the new CA
                (0 = it may only issue end-entity certificates).
                Default: one less than this CA allows, or 0 if this CA has
                no limit. Refused if this CA's own path length forbids it.
  --days N      validity in days (default 1825 = 5 years). Refused if the
                new certificate would outlive this CA's certificate.
  --yes         do not ask before signing (openssl ca -batch)

EOF
    backend_help
    cat <<EOF
Creates (in this CA directory):
  certs/<name>-ca-cert.pem    the new intermediate CA certificate
  certs/<name>-ca-chain.pem   the same plus this CA's chain up to the root -
                              hand this file to 'create-intermediate-ca.sh install'
  newcerts/<serial>.pem       openssl's copy; index.txt and serial updated

<name> is the Common Name of the request, reduced to letters, digits, '.', '_', '-'.
EOF
}

. "$(dirname "$0")/lib/cli.sh"
CLI_BACKEND_OPTS=1
CLI_VALUE_OPTS="--pathlen --days"
YES=0
filtered=()
for arg in "$@"; do
    if [ "$arg" = --yes ]; then YES=1; else filtered+=("$arg"); fi
done
parse_cli "${filtered[@]}"
set -- "${ARGS[@]}"
[ $# -eq 1 ] || cli_error "expected one CSR file"
CSR=$1
. "$(dirname "$0")/lib/ca-key.sh"
SCRIPTS=$(dirname "$0")

DAYS=${CLI_OPT[--days]:-1825}
[[ $DAYS =~ ^[1-9][0-9]*$ ]] || cli_error "--days must be a positive number"
PATHLEN=${CLI_OPT[--pathlen]:-}
[ -z "$PATHLEN" ] || [[ $PATHLEN =~ ^[0-9]+$ ]] || cli_error "--pathlen must be 0 or more"
[ -f "$CSR" ] || { echo "Not found: $CSR"; exit 1; }

echo "=== Intermediate CA, step 2 of 3: issue the certificate (backend: $CA_BACKEND) ==="
echo ""
card_preflight issue
[ -f certs/ca-cert.pem ] || { echo "No certs/ca-cert.pem here - is this the parent CA's directory?"; exit 1; }
[ -f index.txt ] || { echo "No CA database here - run $SCRIPTS/init-ca-database.sh"; exit 1; }
echo ""

# The request
if ! openssl req -verify -noout -in "$CSR" 2>/dev/null; then
    echo "✗ $CSR is not a valid certificate request (signature does not verify)"
    exit 1
fi
CN=$(openssl req -noout -subject -nameopt multiline -in "$CSR" | sed -n 's/^ *commonName *= *//p' | head -1)
[ -n "$CN" ] || { echo "✗ the request has no Common Name"; exit 1; }
NAME=$(echo "$CN" | sed 's/[^A-Za-z0-9._-]/_/g')

# This CA's own path length decides what the new CA may be
PARENT_BC=$(openssl x509 -noout -ext basicConstraints -in certs/ca-cert.pem 2>/dev/null | tail -1)
PARENT_PATHLEN=$(echo "$PARENT_BC" | sed -n 's/.*pathlen:\([0-9][0-9]*\).*/\1/p')
if [ "$PARENT_PATHLEN" = 0 ]; then
    echo "✗ This CA has path length 0 - it may only issue end-entity certificates, not CAs"
    exit 1
fi
if [ -z "$PATHLEN" ]; then
    if [ -n "$PARENT_PATHLEN" ]; then PATHLEN=$((PARENT_PATHLEN - 1)); else PATHLEN=0; fi
elif [ -n "$PARENT_PATHLEN" ] && [ "$PATHLEN" -ge "$PARENT_PATHLEN" ]; then
    echo "✗ --pathlen $PATHLEN is too large: this CA allows at most $((PARENT_PATHLEN - 1)) below the new CA"
    exit 1
fi

# A certificate must not outlive its issuer
if ! openssl x509 -checkend $((DAYS * 86400)) -noout -in certs/ca-cert.pem > /dev/null; then
    END=$(openssl x509 -noout -enddate -in certs/ca-cert.pem | sed 's/^notAfter=//')
    MAX=$(( ($(date -d "$END" +%s) - $(date +%s)) / 86400 ))
    echo "✗ --days $DAYS would outlive this CA (valid until $END) - use --days $MAX or less"
    exit 1
fi

echo "Request:     $(openssl req -noout -subject -in "$CSR")"
echo "Issuer:      $(openssl x509 -noout -subject -in certs/ca-cert.pem)"
echo "Profile:     v3_intermediate_ca, pathlen:$PATHLEN, $DAYS days"
echo ""

# openssl.cnf with the chosen path length in v3_intermediate_ca
CNF=$(mktemp)
trap 'rm -f "$CNF"' EXIT
sed "/^\[ *v3_intermediate_ca *\]/,/^\[/ s/^basicConstraints.*/basicConstraints = critical, CA:true, pathlen:$PATHLEN/" \
    openssl.cnf > "$CNF"
grep -q "pathlen:$PATHLEN" "$CNF" || { echo "✗ no [ v3_intermediate_ca ] section in openssl.cnf"; exit 1; }

BATCH=()
[ "$YES" = 1 ] && BATCH=(-batch)
echo "You will be prompted for the $CA_SECRET_NAME"
openssl ca -config "$CNF" -extensions v3_intermediate_ca \
    "${CA_SIGN_ARGS[@]}" "${BATCH[@]}" \
    -days "$DAYS" -notext -md sha256 \
    -in "$CSR" -out "certs/${NAME}-ca-cert.pem"
[ -s "certs/${NAME}-ca-cert.pem" ] || { echo "✗ no certificate was issued"; exit 1; }
chmod 644 "certs/${NAME}-ca-cert.pem"

# The new certificate plus this CA's chain up to the root
cat "certs/${NAME}-ca-cert.pem" "$(ca_verify_file)" > "certs/${NAME}-ca-chain.pem"
ROOT=$(mktemp)
trap 'rm -f "$CNF" "$ROOT"' EXIT
last_cert "certs/${NAME}-ca-chain.pem" > "$ROOT"
if ! openssl verify -CAfile "$ROOT" -untrusted "certs/${NAME}-ca-chain.pem" \
        "certs/${NAME}-ca-cert.pem" > /dev/null; then
    echo "✗ ERROR: the new certificate does not verify up to the root"
    exit 1
fi
echo ""
echo "✓ Issued certs/${NAME}-ca-cert.pem (verifies up to the root)"
echo "✓ Chain  certs/${NAME}-ca-chain.pem"
echo ""
echo "Next (step 3), in the new CA's directory - with its card inserted, if on a card:"
echo "  $SCRIPTS/create-intermediate-ca.sh install $(pwd)/certs/${NAME}-ca-chain.pem"
