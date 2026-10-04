#!/usr/bin/env bash
# Build the OpenSSL 3 pkcs11 provider locally - nothing is installed system-wide.
#
# Downloads the pkcs11-provider release, checks its SHA-256, builds it and
# puts pkcs11.so into card-tools/pkcs11-provider/, where lib/ca-key.sh and
# card-status.sh find it automatically.
#
# Usage (from the repository root): card-tools/build-pkcs11-provider.sh
#
# Needs: curl, tar, a C compiler, pkg-config, OpenSSL >= 3.0.7 headers
#        (Debian/Ubuntu: sudo apt install build-essential pkg-config libssl-dev python3-venv)
# meson and ninja are installed into card-tools/.venv, not system-wide.

set -e

VERSION=1.3.0

usage() {
    cat <<EOF
Usage: $0 [-h | --help]

Builds the OpenSSL 3 pkcs11 provider (pkcs11-provider $VERSION) locally - nothing
is installed system-wide. Downloads the release, checks its pinned SHA-256,
compiles it (meson and ninja go into card-tools/.venv) and checks that OpenSSL
can load the result. Run it again to rebuild.

Creates:
  card-tools/pkcs11-provider/pkcs11.so   found automatically by the scripts
  card-tools/build/                      download and build logs

Needs: curl, tar, a C compiler, pkg-config, OpenSSL >= 3.0.7 headers
  Debian/Ubuntu: sudo apt install build-essential pkg-config libssl-dev python3-venv curl
EOF
}

. "$(dirname "$0")/../lib/cli.sh"
parse_cli "$@"
# SHA-256 of the release tarball this project was tested with. The upstream
# release publishes no checksum file, so it is pinned here.
SHA256=b8bbc30cfb7865603fff1dd0fb516cce90437d8ddb267e331cd89d6121960538
URL="https://github.com/openssl-projects/pkcs11-provider/releases/download/v${VERSION}/pkcs11-provider-${VERSION}.tar.xz"

TOOLS=$(cd "$(dirname "$0")" && pwd)
BUILD="$TOOLS/build"
OUT="$TOOLS/pkcs11-provider"
VENV="$TOOLS/.venv"
TARBALL="$BUILD/pkcs11-provider-${VERSION}.tar.xz"
SRC="$BUILD/pkcs11-provider-${VERSION}"

echo "=== Building pkcs11-provider $VERSION (local) ==="

# Check build prerequisites up front, with a hint instead of a compiler error
missing=()
for cmd in curl tar cc pkg-config python3; do
    command -v "$cmd" > /dev/null || missing+=("$cmd")
done
if ! pkg-config --atleast-version=3.0.7 libcrypto 2> /dev/null; then
    missing+=("libssl-dev (OpenSSL >= 3.0.7 headers)")
fi
if [ ${#missing[@]} -gt 0 ]; then
    echo "Missing: ${missing[*]}"
    echo "Debian/Ubuntu: sudo apt install build-essential pkg-config libssl-dev python3-venv curl"
    exit 1
fi

mkdir -p "$BUILD" "$OUT"

if [ ! -f "$TARBALL" ]; then
    echo "Downloading $URL"
    curl -fL --proto '=https' -o "$TARBALL" "$URL"
fi
echo "$SHA256  $TARBALL" | sha256sum -c --quiet || {
    echo "Checksum mismatch - refusing to build. Delete $TARBALL to download again."
    exit 1
}
echo "✓ checksum ok"

rm -rf "$SRC"
tar -xf "$TARBALL" -C "$BUILD"

# meson + ninja in the card-tools venv (shared with the Python card tools)
[ -x "$VENV/bin/python" ] || python3 -m venv "$VENV"
"$VENV/bin/pip" install --quiet meson ninja
export PATH="$VENV/bin:$PATH"

echo "Compiling..."
meson setup "$SRC/build" "$SRC" --buildtype=release > "$BUILD/meson-setup.log" \
    || { cat "$BUILD/meson-setup.log"; exit 1; }
ninja -C "$SRC/build" > "$BUILD/ninja.log" || { cat "$BUILD/ninja.log"; exit 1; }

cp "$SRC/build/src/pkcs11.so" "$OUT/pkcs11.so"
rm -rf "$SRC"

# Prove OpenSSL can load it. The provider refuses to start without a module
# path, but only opens the module when a key is used - so any path will do
# for this check, and the vendor module is reported separately.
PKCS11_MODULE=$(. "$TOOLS/../pki.conf" && echo "$PKCS11_MODULE")
if PKCS11_PROVIDER_MODULE="${PKCS11_MODULE:-none}" \
        openssl list -providers -provider-path "$OUT" -provider pkcs11 2>&1 \
        | grep -q "PKCS#11 Provider"; then
    echo "✓ OpenSSL loads $OUT/pkcs11.so"
else
    echo "✗ OpenSSL could not load $OUT/pkcs11.so"
    exit 1
fi
if [ -f "$PKCS11_MODULE" ]; then
    echo "✓ vendor PKCS#11 module $PKCS11_MODULE found"
else
    echo "! vendor PKCS#11 module $PKCS11_MODULE not found yet (install the card middleware, see pki.conf)"
fi

echo ""
echo "=== Done ==="
echo "The scripts pick up card-tools/pkcs11-provider/ automatically."
echo "Check the whole setup with: card-tools/card-status.sh"
