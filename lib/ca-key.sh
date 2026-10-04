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

# True if the CA key already exists on the card
card_has_ca_key() {
    card_tool --login --list-objects --type privkey 2>/dev/null \
        | grep -q "label: *${CARD_KEY_LABEL}\$"
}
