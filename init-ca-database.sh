#!/bin/bash
# Initialize CA database files
# Run this script before creating any certificates

set -e

usage() {
    cat <<EOF
Usage: $0 [--card | --file] [-h | --help]

Creates the CA database that 'openssl ca' needs. Existing files are kept,
so running it again is harmless. In card mode it first checks that the card
is present and its PIN is neither expired nor locked (read-only, no PIN).

EOF
    backend_help
    cat <<EOF
Creates (if missing):
  index.txt          register of issued certificates
  index.txt.attr     unique_subject = no (a name may be issued again)
  serial             next certificate serial number (starts at 1000)
  crlnumber          next CRL number (starts at 1000)

Next step: ./create-root-ca.sh
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
echo "You can now create certificates using:"
echo "  ./create-root-ca.sh"
echo "  ./create-server-cert.sh <hostname>"
echo "  ./create-client-cert.sh <client-name>"
echo "  ./create-code-signing-cert.sh <signer-name>"
echo ""
