#!/bin/bash
# Issue a certificate for a bare public key with a CA whose key is on a card -
# without a CA directory. The CA certificate is given; the card holding its
# key is found by matching it (card-find-key.py). Serial numbers are random
# (128 bits), so no serial file or index is needed; keep the issued
# certificates in your own records (e.g. a production database).
#
#   card-ca-sign-pubkey.sh PUBKEY.pem --ca-cert CA.pem --subject DN --profile SECTION \
#       --extfile FILE --days N --out CERT.pem
#
#   PUBKEY.pem       the public key to certify (PEM SubjectPublicKeyInfo)
#   --ca-cert FILE   the CA certificate; its key must be on an inserted card
#   --subject DN     e.g. "/O=Example/serialNumber=1234/CN=device 1234"
#   --profile NAME   extension section in --extfile
#   --extfile FILE   file holding that section
#   --days N         validity; refused if it would outlive the CA
#   --out FILE       where to write the certificate
#
# The card PIN comes from CARD_PIN, or OpenSSL asks for it.

set -euo pipefail
TOOLS=$(cd "$(dirname "$0")" && pwd)
PUBKEY= CA_CERT= SUBJECT= PROFILE= EXTFILE= DAYS= OUT=
while [ $# -gt 0 ]; do
    a=$1; shift
    case "$a" in
        --ca-cert) CA_CERT=${1:?--ca-cert needs a file}; shift ;;
        --subject) SUBJECT=${1:?--subject needs a DN}; shift ;;
        --profile) PROFILE=${1:?--profile needs a section}; shift ;;
        --extfile) EXTFILE=${1:?--extfile needs a file}; shift ;;
        --days) DAYS=${1:?--days needs a number}; shift ;;
        --out) OUT=${1:?--out needs a file}; shift ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \?//'; exit 0 ;;
        -*) echo "unknown option $a (see --help)"; exit 2 ;;
        *) [ -z "$PUBKEY" ] || { echo "only one public key file"; exit 2; }; PUBKEY=$a ;;
    esac
done
for pair in PUBKEY:PUBKEY.pem CA_CERT:--ca-cert SUBJECT:--subject PROFILE:--profile EXTFILE:--extfile DAYS:--days OUT:--out; do
    v=${pair%%:*}; [ -n "${!v}" ] || { echo "missing ${pair#*:} (see --help)"; exit 2; }
done
for f in "$PUBKEY" "$CA_CERT" "$EXTFILE"; do [ -f "$f" ] || { echo "Not found: $f"; exit 1; }; done
openssl pkey -pubin -in "$PUBKEY" -noout 2>/dev/null || { echo "Not a public key (PEM): $PUBKEY"; exit 1; }
openssl x509 -checkend $((DAYS * 86400)) -noout -in "$CA_CERT" > /dev/null \
    || { echo "$DAYS days would outlive the CA (until $(openssl x509 -noout -enddate -in "$CA_CERT" | sed 's/^notAfter=//'))"; exit 1; }

# the card and key that belong to the CA certificate
# the card holding the key; stop here if it is not inserted (the tool says why)
found=$("$TOOLS/.venv/bin/python" "$TOOLS/card-find-key.py" "$CA_CERT") || exit 1
eval "$found"

# OpenSSL pkcs11 provider, as for the CA scripts
PKI_DIR=$(cd "$TOOLS/.." && pwd)
PKCS11_PROVIDER_DIR=${PKCS11_PROVIDER_DIR:-}
. "$PKI_DIR/lib/pkcs11-provider.sh"
resolve_pkcs11_provider
export PKCS11_PROVIDER_MODULE=${PKCS11_MODULE:-/usr/lib/libeTPkcs11.so}
PROVIDER_ARGS=(-provider pkcs11 -provider default)
[ -n "${PROVIDER_DIR:-}" ] && PROVIDER_ARGS=(-provider-path "$PROVIDER_DIR" "${PROVIDER_ARGS[@]}")
PASSIN=()
[ -n "${CARD_PIN:-}" ] && { export CARD_PIN; PASSIN=(-passin env:CARD_PIN); }

# random positive 128-bit serial
SERIAL=$(openssl rand -hex 16 | sed 's/^./0/; s/^0/4/')
openssl x509 -new -force_pubkey "$PUBKEY" -subj "$SUBJECT" \
    -CA "$CA_CERT" -CAkey "pkcs11:token=$CARD_TOKEN;object=$CARD_KEY_LABEL;type=private" \
    "${PROVIDER_ARGS[@]}" "${PASSIN[@]}" \
    -set_serial "0x$SERIAL" -days "$DAYS" -sha256 \
    -extfile "$EXTFILE" -extensions "$PROFILE" -out "$OUT"

# same public key, signed by the CA
[ "$(openssl x509 -in "$OUT" -pubkey -noout | openssl pkey -pubin -outform DER | sha256sum)" = \
  "$(openssl pkey -pubin -in "$PUBKEY" -outform DER | sha256sum)" ] || { echo "✗ public key mismatch in $OUT"; exit 1; }
openssl verify -partial_chain -CAfile "$CA_CERT" "$OUT" > /dev/null || { echo "✗ $OUT does not verify against $CA_CERT"; exit 1; }
echo "✓ $OUT - serial $(openssl x509 -noout -serial -in "$OUT" | sed 's/^serial=//'), signed by $(openssl x509 -noout -subject -nameopt multiline -in "$CA_CERT" | sed -n 's/^ *commonName *= //p') (card $CARD_SERIAL)"
