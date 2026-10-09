#!/bin/bash
# Sign a file with a key on a card - a detached CMS (PKCS#7) signature.
#
#   card-sign-file.sh FILE --cert CERT.pem [--chain CHAIN.pem] --out FILE.sig
#
#   FILE           the file to sign (signed as is, byte for byte)
#   --cert FILE    the certificate of the signing key; the card holding the key
#                  is found by matching it (card-find-key.py)
#   --chain FILE   certificates to include for the verifier (e.g. the issuers)
#   --out FILE     the signature, PEM (-----BEGIN CMS-----)
#
# Verify with: openssl cms -verify -binary -inform PEM -in FILE.sig -content FILE
#              -CAfile ROOT.pem -purpose any -out /dev/null
# The card PIN comes from CARD_PIN, or OpenSSL asks for it.

set -euo pipefail
TOOLS=$(cd "$(dirname "$0")" && pwd)
FILE= CERT= CHAIN= OUT=
while [ $# -gt 0 ]; do
    a=$1; shift
    case "$a" in
        --cert) CERT=${1:?--cert needs a file}; shift ;;
        --chain) CHAIN=${1:?--chain needs a file}; shift ;;
        --out) OUT=${1:?--out needs a file}; shift ;;
        -h|--help) sed -n '2,16p' "$0" | sed 's/^# \?//'; exit 0 ;;
        -*) echo "unknown option $a (see --help)"; exit 2 ;;
        *) [ -z "$FILE" ] || { echo "only one file"; exit 2; }; FILE=$a ;;
    esac
done
for pair in FILE:FILE CERT:--cert OUT:--out; do
    v=${pair%%:*}; [ -n "${!v}" ] || { echo "missing ${pair#*:} (see --help)"; exit 2; }
done
for f in "$FILE" "$CERT" ${CHAIN:+"$CHAIN"}; do [ -f "$f" ] || { echo "Not found: $f"; exit 1; }; done

# the card holding the key; stop here if it is not inserted (the tool says why)
found=$("$TOOLS/.venv/bin/python" "$TOOLS/card-find-key.py" "$CERT") || exit 1
eval "$found"

PKI_DIR=$(cd "$TOOLS/.." && pwd)
PKCS11_PROVIDER_DIR=${PKCS11_PROVIDER_DIR:-}
. "$PKI_DIR/lib/pkcs11-provider.sh"
resolve_pkcs11_provider
export PKCS11_PROVIDER_MODULE=${PKCS11_MODULE:-/usr/lib/libeTPkcs11.so}
PROVIDER_ARGS=(-provider pkcs11 -provider default)
[ -n "${PROVIDER_DIR:-}" ] && PROVIDER_ARGS=(-provider-path "$PROVIDER_DIR" "${PROVIDER_ARGS[@]}")
PASSIN=()
[ -n "${CARD_PIN:-}" ] && { export CARD_PIN; PASSIN=(-passin env:CARD_PIN); }

# the chain without the signer's own certificate (CMS adds that one already)
EXTRA=()
if [ -n "$CHAIN" ]; then
    TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
    SIGNER_FP=$(openssl x509 -in "$CERT" -noout -fingerprint -sha256)
    awk -v d="$TMP" '/BEGIN CERT/{n++} n{print > (d "/part-" n ".pem")}' "$CHAIN"
    : > "$TMP/chain.pem"
    for c in "$TMP"/part-*.pem; do
        [ "$(openssl x509 -in "$c" -noout -fingerprint -sha256)" = "$SIGNER_FP" ] || cat "$c" >> "$TMP/chain.pem"
    done
    [ -s "$TMP/chain.pem" ] && EXTRA=(-certfile "$TMP/chain.pem")
fi
openssl cms -sign -binary -md sha256 -nosmimecap -in "$FILE" \
    -signer "$CERT" -inkey "pkcs11:token=$CARD_TOKEN;object=$CARD_KEY_LABEL;type=private" \
    "${EXTRA[@]}" "${PROVIDER_ARGS[@]}" "${PASSIN[@]}" \
    -outform PEM -out "$OUT"
openssl cms -verify -binary -inform PEM -in "$OUT" -content "$FILE" -certfile "$CERT" \
    -noverify -out /dev/null 2>/dev/null || { echo "✗ the signature in $OUT does not verify"; exit 1; }
echo "✓ $OUT - $(basename "$FILE") signed with key '$CARD_KEY_LABEL' (card $CARD_SERIAL)"
