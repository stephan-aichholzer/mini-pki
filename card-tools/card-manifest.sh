#!/usr/bin/env bash
# Show which card holds this directory's CA key - also without the card.
#
# Usage (from the repository root):
#   card-tools/card-manifest.sh           show ca-card.manifest; if a card is
#                                         inserted, also say whether it matches
#   card-tools/card-manifest.sh --write   (re)create the manifest from the
#                                         inserted card, e.g. for a CA created
#                                         before manifests existed

set -e
cd "$(dirname "$0")/.."
# Only pkcs11-tool and openssl are needed here, not the OpenSSL provider
CA_BACKEND=file . lib/ca-key.sh

if [ "$1" = "--write" ]; then
    [ -f certs/ca-cert.pem ] || { echo "certs/ca-cert.pem not found"; exit 1; }
    info=$(card_token_info)
    [ -n "$info" ] || { echo "No card found - insert the CA card first"; exit 1; }
    if [ "$(card_pubkey_sha256)" != "$(cert_pubkey_sha256)" ]; then
        echo "✗ key '$CARD_KEY_LABEL' on the inserted card does not match certs/ca-cert.pem"
        echo "  Wrong card or wrong CARD_KEY_LABEL - manifest not written."
        exit 1
    fi
    write_card_manifest
    echo "✓ $CARD_MANIFEST written for card $(manifest_get token_serial)"
    exit 0
fi

if [ ! -f "$CARD_MANIFEST" ]; then
    echo "No $CARD_MANIFEST in this directory."
    echo "Create it with the CA card inserted: card-tools/card-manifest.sh --write"
    exit 1
fi

echo "=== CA card of this directory ($CARD_MANIFEST) ==="
printf '  %-14s %s\n' \
    "CA"           "$(manifest_get ca_subject)" \
    "valid until"  "$(manifest_get ca_not_after)" \
    "CA cert"      "sha256 $(manifest_get ca_cert_sha256)" \
    "card"         "$(manifest_get token_manufacturer) $(manifest_get token_model)" \
    "card label"   "$(manifest_get token_label)" \
    "card serial"  "$(manifest_get token_serial)" \
    "key"          "$(manifest_get key_label) (ID $(manifest_get key_id), $(manifest_get key_type))" \
    "PKCS#11"      "$(manifest_get pkcs11_module)" \
    "recorded"     "$(manifest_get created)"

echo ""
info=$(CARD_TOKEN= card_token_info)
if [ -z "$info" ]; then
    echo "No card inserted - insert card serial $(manifest_get token_serial) to use this CA."
    exit 0
fi
serial=$(token_field "$info" "serial num")
if [ "$serial" != "$(manifest_get token_serial)" ]; then
    echo "✗ Inserted card $serial is NOT the CA card $(manifest_get token_serial)."
    exit 1
fi
if [ "$(card_pubkey_sha256)" = "$(manifest_get key_pubkey_sha256)" ]; then
    echo "✓ Inserted card $serial is the CA card, key '$(manifest_get key_label)' present."
else
    echo "✗ Card $serial is inserted, but key '$(manifest_get key_label)' differs from the recorded one."
    exit 1
fi
