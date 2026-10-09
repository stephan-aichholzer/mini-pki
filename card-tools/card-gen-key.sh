#!/bin/bash
# Generate a key pair on the card - the private key never exists outside it.
#
#   card-gen-key.sh --token LABEL --label LABEL --id HEX --type TYPE --pubkey-out FILE
#
#   --token LABEL      the card (token label), e.g. as found by card-find-ca.py
#   --label LABEL      label of the new key, e.g. station-ssh
#   --id HEX           CKA_ID of the new key, e.g. 04 - must be free on the card
#   --type TYPE        EC:prime256v1 (P-256) or rsa:2048 - IDPrime cards generate
#                      EC keys only on the card, never import them
#   --pubkey-out FILE  the new public key (PEM), e.g. to get a certificate for it
#
# Refuses if the label or the ID is already used on the card. The card PIN
# comes from CARD_PIN (test cards only), otherwise it is asked for (hidden).

set -euo pipefail
TOKEN= LABEL= ID= TYPE= PUB=
while [ $# -gt 0 ]; do
    a=$1; shift
    case "$a" in
        --token) TOKEN=${1:?--token needs a label}; shift ;;
        --label) LABEL=${1:?--label needs a value}; shift ;;
        --id) ID=${1:?--id needs a hex value}; shift ;;
        --type) TYPE=${1:?--type needs a value}; shift ;;
        --pubkey-out) PUB=${1:?--pubkey-out needs a file}; shift ;;
        -h|--help) sed -n '2,15p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) echo "unknown argument: $a (see --help)"; exit 2 ;;
    esac
done
for pair in TOKEN:--token LABEL:--label ID:--id TYPE:--type PUB:--pubkey-out; do
    v=${pair%%:*}; [ -n "${!v}" ] || { echo "missing ${pair#*:} (see --help)"; exit 2; }
done
[[ $ID =~ ^[0-9a-fA-F]+$ ]] || { echo "--id: hex digits, e.g. 04"; exit 2; }
MODULE=${PKCS11_MODULE:-/usr/lib/libeTPkcs11.so}
P11=(pkcs11-tool --module "$MODULE" --token-label "$TOKEN")

OBJECTS=$("${P11[@]}" -O 2>/dev/null) || { echo "✗ card '$TOKEN' not found"; exit 1; }
if grep -q "label: *$LABEL\$" <<< "$OBJECTS"; then echo "✗ the card already holds an object labelled '$LABEL'"; exit 1; fi
if grep -qi "ID: *$ID\$" <<< "$OBJECTS"; then echo "✗ ID $ID is already used on the card"; exit 1; fi

if [ -z "${CARD_PIN:-}" ]; then
    read -r -s -p "Card PIN for '$TOKEN': " CARD_PIN; echo
fi
PIN=(--pin "$CARD_PIN")
echo "Generating $TYPE on card '$TOKEN' (label '$LABEL', ID $ID)..."
"${P11[@]}" --login "${PIN[@]}" --keypairgen --key-type "$TYPE" --id "$ID" --label "$LABEL" > /dev/null
TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT
"${P11[@]}" --read-object --type pubkey --id "$ID" -o "$TMP" > /dev/null 2>&1
openssl pkey -pubin -inform DER -in "$TMP" -out "$PUB"
echo "✓ key '$LABEL' generated on the card; public key: $PUB"
