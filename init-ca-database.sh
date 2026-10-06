#!/bin/bash
# Initialize CA database files
# Run this script before creating any certificates

set -e

usage() {
    cat <<EOF
Usage: $0 [--card | --file] [-h | --help]

Creates the CA database that 'openssl ca' needs in the current directory.
Existing files are kept, so running it again is harmless. In card mode it
first checks that the card is present and its PIN is neither expired nor
locked (read-only, no PIN).

Run it in this repository (the default CA directory), or in an empty
directory to set up a further CA there - e.g. an intermediate CA. Run all
mini-pki scripts from inside the CA directory they should work on.

EOF
    backend_help
    cat <<EOF
Creates (if missing):
  certs/ private/ newcerts/ crl/
  openssl.cnf        copied from the repository (other CA directories only)
  index.txt          register of issued certificates
  index.txt.attr     unique_subject = no (a name may be issued again)
  serial             next certificate serial number (starts at 1000)
  crlnumber          next CRL number (starts at 1000)

Optional: a pki.conf in a CA directory of its own overrides the
repository's pki.conf for that CA (CA_BACKEND, CARD_TOKEN, CARD_KEY_LABEL,
CARD_KEY_ID, CARD_KEY_TYPE ...).

Next step: create-root-ca.sh, or create-intermediate-ca.sh request
EOF
}

. "$(dirname "$0")/lib/cli.sh"
CLI_BACKEND_OPTS=1
parse_cli "$@"
set -- "${ARGS[@]}"
. "$(dirname "$0")/lib/ca-key.sh"

echo "=== Initializing CA Database ==="
echo ""

# In card mode, make sure the card is usable before setting anything up
card_preflight init

# A CA directory other than the repository gets the folders and its own
# copy of openssl.cnf (paths in it are relative to the CA directory)
for d in certs private newcerts crl; do
    if [ ! -d "$d" ]; then
        mkdir -p "$d"
        echo "✓ Created $d/"
    fi
done
chmod 700 private
if [ ! -f openssl.cnf ]; then
    cp "$PKI_DIR/openssl.cnf" openssl.cnf
    echo "✓ Copied openssl.cnf from $PKI_DIR"
fi

# Create CA database file
if [ ! -f index.txt ]; then
    touch index.txt
    echo "✓ Created index.txt"
else
    echo "✓ index.txt already exists"
fi

# Create CA database attributes file.
# openssl defaults to "unique_subject = yes", which refuses to issue a second
# certificate for a subject that is already in index.txt. This is a toolkit
# for generating certificates, not a production CA registry, so re-running a
# script for an existing name should work instead of failing with
# "There is already a certificate for /CN=...".
if [ ! -f index.txt.attr ]; then
    echo "unique_subject = no" > index.txt.attr
    echo "✓ Created index.txt.attr (unique_subject = no)"
else
    echo "✓ index.txt.attr already exists ($(tr -d '\n' < index.txt.attr))"
fi

# Create serial number file
if [ ! -f serial ]; then
    echo 1000 > serial
    echo "✓ Created serial (starting at 1000)"
else
    echo "✓ serial already exists (current: $(cat serial))"
fi

# Create CRL number file
if [ ! -f crlnumber ]; then
    echo 1000 > crlnumber
    echo "✓ Created crlnumber (starting at 1000)"
else
    echo "✓ crlnumber already exists (current: $(cat crlnumber))"
fi

echo ""
echo "=== CA Database Initialized ==="
echo ""
SCRIPTS=$(dirname "$0")
echo "Next steps (from this directory):"
echo "  $SCRIPTS/create-root-ca.sh                    a root CA, or"
echo "  $SCRIPTS/create-intermediate-ca.sh request    a CA below another one"
echo "Then issue certificates, e.g.:"
echo "  $SCRIPTS/create-server-cert.sh <hostname>"
echo "  $SCRIPTS/create-client-cert.sh <client-name>"
echo "  $SCRIPTS/create-code-signing-cert.sh <signer-name>"
echo ""
