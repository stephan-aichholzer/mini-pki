# Shared CA-key handling, sourced by the creation scripts.
#
# Sets up two arrays the scripts splice into their openssl calls, so the
# same script works whether the CA key is a file or lives on a smartcard:
#   CA_REQ_KEY_ARGS   - for `openssl req -x509` (self-signing the root)
#   CA_SIGN_ARGS      - for `openssl ca` (issuing certificates)

PKI_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../pki.conf
. "$PKI_DIR/pki.conf"
. "$PKI_DIR/lib/pkcs11-provider.sh"

case "$CA_BACKEND" in
file)
    CA_REQ_KEY_ARGS=(-key private/ca-key.pem)
    # openssl.cnf already points private_key at private/ca-key.pem
    CA_SIGN_ARGS=()
    CA_SECRET_NAME="CA passphrase"
    ;;
card)
    # The provider reads the vendor module path from this variable
    export PKCS11_PROVIDER_MODULE="$PKCS11_MODULE"

    resolve_pkcs11_provider
    CA_PROVIDER_ARGS=()
    if [ -n "$PROVIDER_DIR" ]; then
        CA_PROVIDER_ARGS+=(-provider-path "$PROVIDER_DIR")
    fi
    if [ ! -f "$PROVIDER_SO" ]; then
        echo "Error: OpenSSL pkcs11 provider not found ($PROVIDER_SO)." >&2
        echo "       Build it locally: card-tools/build-pkcs11-provider.sh" >&2
        echo "       (or apt install pkcs11-provider, or set PKCS11_PROVIDER_DIR in pki.conf)" >&2
        exit 1
    fi
    if [ ! -f "$PKCS11_MODULE" ]; then
        echo "Error: PKCS#11 module not found: $PKCS11_MODULE (see pki.conf)" >&2
        exit 1
    fi
    CA_PROVIDER_ARGS+=(-provider pkcs11 -provider default)

    CA_KEY_URI="pkcs11:object=${CARD_KEY_LABEL};type=private"
    if [ -n "$CARD_TOKEN" ]; then
        CA_KEY_URI="pkcs11:token=${CARD_TOKEN};object=${CARD_KEY_LABEL};type=private"
    fi

    # openssl hands -passin to the provider as the card PIN
    CA_PASSIN_ARGS=()
    if [ -n "$CARD_PIN" ]; then
        export CARD_PIN
        CA_PASSIN_ARGS=(-passin env:CARD_PIN)
    fi

    CA_REQ_KEY_ARGS=("${CA_PROVIDER_ARGS[@]}" -key "$CA_KEY_URI" "${CA_PASSIN_ARGS[@]}")
    CA_SIGN_ARGS=("${CA_PROVIDER_ARGS[@]}" -keyfile "$CA_KEY_URI" "${CA_PASSIN_ARGS[@]}")
    CA_SECRET_NAME="card PIN"
    ;;
*)
    echo "Error: unknown CA_BACKEND '$CA_BACKEND' (expected 'file' or 'card')" >&2
    exit 1
    ;;
esac

# pkcs11-tool against the configured card, logging in with CARD_PIN if set
card_tool() {
    local login=()
    if [ "$1" = "--login" ]; then
        shift
        login=(--login)
        [ -n "$CARD_PIN" ] && login+=(--pin "$CARD_PIN")
    fi
    local token=()
    [ -n "$CARD_TOKEN" ] && token=(--token-label "$CARD_TOKEN")
    # Drop the "Using slot N ..." chatter, keep real errors
    pkcs11-tool --module "$PKCS11_MODULE" "${token[@]}" "${login[@]}" "$@" \
        2> >(grep -v '^Using slot' >&2)
}

# True if the CA key already exists on the card. The public key object is
# visible without login, so this needs no PIN.
card_has_ca_key() {
    card_tool --list-objects --type pubkey 2>/dev/null \
        | grep -q "label: *${CARD_KEY_LABEL}\$"
}

# Read-only checks before a script prompts for anything, so a card problem
# shows up immediately instead of after the DN has been typed in. Never logs
# in, so no PIN tries are used. Does nothing in file mode.
#   card_preflight init   - card usable (init-ca-database.sh, create-root-ca.sh)
#   card_preflight issue  - additionally: CA key on the card, and
#                           certs/ca-cert.pem belongs to that key
card_preflight() {
    [ "$CA_BACKEND" = card ] || return 0
    local mode=${1:-init} token_info flags card_key cert_key

    echo "Card pre-flight check..."
    if ! command -v pkcs11-tool > /dev/null; then
        preflight_fail "pkcs11-tool not found (install opensc)"
    fi
    # -T lists every token and ignores --token-label, so pick ours out:
    # the slot block of CARD_TOKEN, or the first token if none is configured
    token_info=$(pkcs11-tool --module "$PKCS11_MODULE" -T 2>/dev/null \
        | awk -v want="$CARD_TOKEN" '
            /^Slot/ { if (found) exit; block = "" }
            { block = block $0 "\n" }
            /token label/ { label = $0; sub(/^[^:]*: */, "", label)
                            if (want == "" || label == want) found = 1 }
            END { if (found) printf "%s", block }') || true
    if ! echo "$token_info" | grep -q "token label"; then
        if [ -n "$CARD_TOKEN" ]; then
            preflight_fail "card '$CARD_TOKEN' (CARD_TOKEN in pki.conf) not found" \
                "Another card inserted? Tokens present: card-tools/card-status.sh"
        fi
        preflight_fail "no card found via $PKCS11_MODULE" \
            "Is pcscd running, the reader connected and the card inserted the right way?" \
            "Details: card-tools/card-status.sh"
    fi
    flags=$(echo "$token_info" | grep -m1 'token flags')
    if [[ "$flags" == *"user PIN to be changed"* ]]; then
        preflight_fail "the card's user PIN is expired (factory PIN)" \
            "Change it first: card-tools/.venv/bin/python card-tools/card-set-expired-pin.py"
    fi
    if [[ "$flags" == *"user PIN locked"* ]]; then
        preflight_fail "the card's user PIN is locked - unblock it with the admin key first"
    fi
    if [[ "$flags" == *"final user PIN entry"* ]]; then
        echo "  ! WARNING: only one user PIN try left - a wrong PIN locks the card"
    fi
    echo "  ✓ card $(echo "$token_info" | sed -n 's/^ *token label *: *//p' | head -1) ready"

    [ "$mode" = issue ] || return 0

    if ! card_has_ca_key; then
        preflight_fail "CA key '$CARD_KEY_LABEL' is not on this card" \
            "Wrong card, or CARD_KEY_LABEL in pki.conf differs from the one used by create-root-ca.sh"
    fi
    if [ ! -f certs/ca-cert.pem ]; then
        preflight_fail "certs/ca-cert.pem not found - create the CA first (./create-root-ca.sh)"
    fi
    # Same SubjectPublicKeyInfo in the certificate and on the card?
    card_key=$(card_tool --read-object --type pubkey --label "$CARD_KEY_LABEL" 2>/dev/null \
        | sha256sum | cut -d' ' -f1)
    cert_key=$(openssl x509 -in certs/ca-cert.pem -pubkey -noout \
        | openssl pkey -pubin -outform DER | sha256sum | cut -d' ' -f1)
    if [ "$card_key" != "$cert_key" ]; then
        preflight_fail "certs/ca-cert.pem does not belong to key '$CARD_KEY_LABEL' on this card" \
            "Certificates signed now would not verify. Check CARD_KEY_LABEL in pki.conf" \
            "and that this is the right card for this CA directory."
    fi
    echo "  ✓ CA key '$CARD_KEY_LABEL' on the card matches certs/ca-cert.pem"
}

preflight_fail() {
    echo "  ✗ $1" >&2
    shift
    local line
    for line in "$@"; do echo "    $line" >&2; done
    exit 1
}
