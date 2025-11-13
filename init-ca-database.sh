#!/bin/bash
# Initialize CA database files
# Run this script before creating any certificates

set -e

echo "=== Initializing CA Database ==="
echo ""

# Create CA database file
if [ ! -f index.txt ]; then
    touch index.txt
    echo "✓ Created index.txt"
else
    echo "✓ index.txt already exists"
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
