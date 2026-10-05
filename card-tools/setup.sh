#!/usr/bin/env bash
# One-shot setup for card mode: checks the system parts, builds the
# project-local parts and finishes with card-status.sh. Safe to run again.
# Run with --help for usage.

set -eo pipefail

usage() {
    cat <<EOF
Usage: $0 [--rebuild] [-h | --help]

Sets up everything card mode (CA key on a PKCS#11 smartcard) needs and checks
the result. Never uses sudo - missing system packages are listed with the
apt command to install them. Already present parts are left alone.

  1. System: smartcard stack   pcscd, CCID reader driver, OpenSC tools
  2. System: vendor module     PKCS11_MODULE from pki.conf (SafeNet SAC)
  3. System: build tools       only if the pkcs11 provider must be built
  4. Project: pkcs11 provider  card-tools/pkcs11-provider/pkcs11.so
  5. Project: Python tools     card-tools/.venv (PyKCS11, cryptography)
  6. Check                     card-tools/card-status.sh

  --rebuild   build the pkcs11 provider again even if it exists

Exit status 0 when setup and card check pass, 1 when something is missing.
EOF
}

TOOLS=$(cd "$(dirname "$0")" && pwd)
PKI_DIR=$(cd "$TOOLS/.." && pwd)
. "$PKI_DIR/lib/cli.sh"
REBUILD=0
for arg in "$@"; do
    case "$arg" in
        -h|--help) usage; exit 0 ;;
        --rebuild) REBUILD=1 ;;
        *)         cli_error "unknown argument $arg" ;;
    esac
done
. "$PKI_DIR/pki.conf"
. "$PKI_DIR/lib/pkcs11-provider.sh"

ok()   { echo "  ✓ $*"; }
miss() { echo "  ✗ $*"; }
step() { printf '\n=== %s ===\n' "$1"; }
APT=()        # Debian/Ubuntu packages to install
MISSING=0

need_cmd() {  # command, package, description
    if command -v "$1" > /dev/null; then
        ok "$3 ($1)"
    else
        miss "$3 ($1) - package $2"
        APT+=("$2")
        MISSING=1
    fi
}

step "1. Smartcard stack"
if [ -x /usr/sbin/pcscd ] || command -v pcscd > /dev/null; then
    ok "PC/SC daemon (pcscd)"
    if systemctl is-active --quiet pcscd.socket 2>/dev/null || systemctl is-active --quiet pcscd 2>/dev/null \
            || pgrep -x pcscd > /dev/null; then
        ok "pcscd is active"
    else
        echo "  ! pcscd is installed but not active: sudo systemctl enable --now pcscd.socket"
    fi
else
    miss "PC/SC daemon (pcscd) - package pcscd"
    APT+=(pcscd)
    MISSING=1
fi
if ls /usr/lib/pcsc/drivers/ifd-ccid.bundle > /dev/null 2>&1; then
    ok "CCID reader driver"
else
    miss "CCID reader driver - package libccid"
    APT+=(libccid)
    MISSING=1
fi
need_cmd pkcs11-tool opensc "OpenSC tools"

step "2. Vendor PKCS#11 module"
if [ -f "$PKCS11_MODULE" ]; then
    ok "$PKCS11_MODULE"
else
    miss "$PKCS11_MODULE not found"
    echo "    For Thales IDPrime: install SafeNet Authentication Client (SAC) from"
    echo "    Thales or your card supplier, or set PKCS11_MODULE in pki.conf."
    MISSING=1
fi

resolve_pkcs11_provider
BUILD_PROVIDER=0
if [ "$REBUILD" = 1 ] || [ ! -f "$PROVIDER_SO" ]; then
    BUILD_PROVIDER=1
fi

step "3. Build tools"
if [ "$BUILD_PROVIDER" = 1 ]; then
    need_cmd cc build-essential "C compiler"
    need_cmd pkg-config pkg-config "pkg-config"
    need_cmd curl curl "curl"
    if pkg-config --atleast-version=3.0.7 libcrypto 2> /dev/null; then
        ok "OpenSSL >= 3.0.7 headers"
    else
        miss "OpenSSL >= 3.0.7 headers - package libssl-dev"
        APT+=(libssl-dev)
        MISSING=1
    fi
else
    ok "not needed - pkcs11 provider already present"
fi
if python3 -c 'import ensurepip, venv' 2> /dev/null; then
    ok "Python venv support"
else
    miss "Python venv support - package python3-venv"
    APT+=(python3-venv)
    MISSING=1
fi

if [ ${#APT[@]} -gt 0 ]; then
    echo ""
    echo "Install the missing system packages, then run this script again:"
    echo "  sudo apt install ${APT[*]}"
fi
if [ "$MISSING" = 1 ]; then
    echo ""
    echo "Setup incomplete - nothing was built."
    exit 1
fi

step "4. OpenSSL pkcs11 provider"
if [ "$BUILD_PROVIDER" = 1 ]; then
    "$TOOLS/build-pkcs11-provider.sh" | sed 's/^/  /'
else
    ok "$PROVIDER_SO (use --rebuild to build it again)"
fi

step "5. Python card tools"
if [ ! -x "$TOOLS/.venv/bin/python" ]; then
    python3 -m venv "$TOOLS/.venv"
    ok "created card-tools/.venv"
fi
"$TOOLS/.venv/bin/pip" install --quiet --disable-pip-version-check -r "$TOOLS/requirements.txt"
if "$TOOLS/.venv/bin/python" -c 'import PyKCS11, cryptography' 2> /dev/null; then
    ok "PyKCS11 and cryptography in card-tools/.venv"
else
    miss "Python packages could not be installed"
    exit 1
fi

step "6. Check"
if "$TOOLS/card-status.sh" | sed 's/^/  /'; then
    echo ""
    echo "Setup complete. Card mode: ./create-root-ca.sh --card  (or CA_BACKEND=card in pki.conf)"
else
    echo ""
    echo "Setup done, but the card check reports problems (see above) - e.g. no card inserted."
    exit 1
fi
