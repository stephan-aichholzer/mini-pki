#!/usr/bin/env bash
# Read-only check of everything card mode needs: pcscd, reader, card,
# PKCS#11 modules, OpenSSL pkcs11 provider, PIN state and the configured
# CA key. Never logs in, so no PIN tries are consumed.
#
# Usage (from the repository root): card-tools/card-status.sh

usage() {
    cat <<EOF
Usage: $0 [-h | --help]

Read-only health check of everything card mode needs - never logs in, so no
PIN tries are used:

  PC/SC        pcscd running, reader present
  Card         answers (ATR), card type
  Modules      vendor PKCS#11 module (PKCS11_MODULE in pki.conf), OpenSC
  Provider     OpenSSL pkcs11 provider (local build or system)
  Token        label, serial, PIN state, remaining tries per PIN
  CA key       key CARD_KEY_LABEL on the card, card matches ca-card.manifest

Exit status 0 when all checks pass, 1 otherwise.
EOF
}

DIR=$(cd "$(dirname "$0")/.." && pwd)
. "$DIR/lib/cli.sh"
parse_cli "$@"
PKI_DIR=$DIR
# shellcheck source=../pki.conf
. "$DIR/pki.conf"
. "$DIR/lib/pkcs11-provider.sh"
. "$DIR/lib/pcsc.sh"
OPENSC_MODULE=${OPENSC_MODULE:-$(ls /usr/lib/*/opensc-pkcs11.so /usr/lib/opensc-pkcs11.so 2>/dev/null | head -1)}

ok()   { echo "  ✓ $*"; }
bad()  { echo "  ✗ $*"; PROBLEMS=$((PROBLEMS + 1)); }
info() { echo "    $*"; }
section() { printf '\n=== %s ===\n' "$1"; }
PROBLEMS=0

section "PC/SC"
if systemctl is-active --quiet pcscd 2>/dev/null || pgrep -x pcscd >/dev/null; then
    ok "pcscd is running"
else
    bad "pcscd is not running (sudo systemctl start pcscd)"
fi
if READERS=$(opensc-tool -l 2>/dev/null | tail -n +3) && [ -n "$READERS" ]; then
    ok "reader(s):"
    echo "$READERS" | sed 's/^/      /'
elif pcsc_access_denied; then
    bad "pcscd refuses access - readers are hidden, not missing"
    pcsc_access_denied_help | sed 's/^/    /'
    exit 1
else
    bad "no reader found"
    info "WSL2: attach the reader first - usbipd.exe attach --wsl --busid <BUSID> (docs/card-mode-wsl2.md)"
fi

section "Card"
if ATR=$(opensc-tool -a 2>/dev/null | tail -1) && [[ "$ATR" == *:* ]]; then
    ok "ATR $ATR"
    ok "$(opensc-tool -n 2>/dev/null | tail -1)"
else
    bad "card does not answer"
    info "'Card absent or mute' = no ATR: card inserted the wrong way round,"
    info "no contact chip, or dirty contacts. Recent pcscd messages:"
    journalctl -u pcscd --since "-5 min" --no-pager 2>/dev/null | tail -3 | sed 's/^/      /'
    exit 1
fi

section "PKCS#11 modules"
if [ -f "$PKCS11_MODULE" ]; then
    ok "vendor module $PKCS11_MODULE"
else
    bad "vendor module $PKCS11_MODULE not found (install SAC or fix PKCS11_MODULE in pki.conf)"
fi
if [ -n "$OPENSC_MODULE" ]; then
    ok "OpenSC module $OPENSC_MODULE"
else
    info "OpenSC module not found (optional)"
fi

section "OpenSSL pkcs11 provider"
resolve_pkcs11_provider
if [ -f "$PROVIDER_SO" ]; then
    ok "$PROVIDER_SO"
else
    bad "pkcs11 provider not found - build it locally: card-tools/build-pkcs11-provider.sh"
fi

[ -f "$PKCS11_MODULE" ] || { printf '\n%d problem(s) found.\n' "$PROBLEMS"; exit 1; }
TOKEN_ARGS=()
[ -n "$CARD_TOKEN" ] && TOKEN_ARGS=(--token-label "$CARD_TOKEN")

section "Token"
TOKEN_INFO=$(pkcs11-tool --module "$PKCS11_MODULE" "${TOKEN_ARGS[@]}" -T 2>/dev/null)
echo "$TOKEN_INFO" | grep -E 'token label|token model|serial num|pin min' | sed 's/^ */    /'
FLAGS=$(echo "$TOKEN_INFO" | grep 'token flags' | head -1)
if [[ "$FLAGS" == *"user PIN to be changed"* ]]; then
    bad "user PIN is expired (factory PIN) - change it first:"
    info "card-tools/.venv/bin/python card-tools/card-set-expired-pin.py"
elif [[ "$FLAGS" == *"locked"* ]]; then
    bad "a PIN is locked: $FLAGS"
else
    ok "user PIN ok"
fi
if command -v pkcs15-tool >/dev/null; then
    echo "    remaining tries:"
    pkcs15-tool --list-pins 2>/dev/null | awk '/^PIN/{name=$0} /Tries left/{print "      " name ": " $NF}'
fi

section "Configured CA key (pki.conf)"
info "CA_BACKEND=$CA_BACKEND  CARD_KEY_LABEL=$CARD_KEY_LABEL  CARD_KEY_ID=$CARD_KEY_ID  CARD_KEY_TYPE=$CARD_KEY_TYPE"
[ "$CA_BACKEND" = card ] || info "(card mode is not active - set CA_BACKEND=card in pki.conf)"
# Public key objects are visible without login
if pkcs11-tool --module "$PKCS11_MODULE" "${TOKEN_ARGS[@]}" -O --type pubkey 2>/dev/null \
        | grep -q "label: *${CARD_KEY_LABEL}\$"; then
    ok "key '$CARD_KEY_LABEL' is on the card"
else
    info "key '$CARD_KEY_LABEL' not on the card yet - create-root-ca.sh will generate it"
fi
if [ -f "$DIR/ca-card.manifest" ]; then
    WANT=$(sed -n 's/^token_serial=//p' "$DIR/ca-card.manifest")
    HAVE=$(echo "$TOKEN_INFO" | sed -n 's/^ *serial num *: *//p' | head -1)
    if [ "$WANT" = "$HAVE" ]; then
        ok "inserted card is the one recorded in ca-card.manifest ($WANT)"
    else
        bad "ca-card.manifest names card $WANT, but card $HAVE is inserted"
    fi
fi
if [ -f "$DIR/certs/ca-cert.pem" ]; then
    info "certs/ca-cert.pem: $(openssl x509 -in "$DIR/certs/ca-cert.pem" -noout -subject 2>/dev/null)"
fi

printf '\n'
if [ "$PROBLEMS" -eq 0 ]; then
    echo "All checks passed. Full object tree: card-tools/.venv/bin/python card-tools/card-tree.py --login"
else
    echo "$PROBLEMS problem(s) found."
    exit 1
fi
