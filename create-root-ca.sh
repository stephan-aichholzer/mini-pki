#!/bin/bash
# Script to create a self-signed Root CA certificate

set -e

echo "=== Creating Root CA ==="
echo ""
echo "This script will:"
echo "1. Generate a 4096-bit RSA private key (password protected)"
echo "2. Create a self-signed root CA certificate valid for 10 years"
echo ""

# Keys are created 0600 rather than 0400 so that a CA can be regenerated in
# place; the one case worth guarding is replacing a CA that has already issued
# certificates, because index.txt and serial still refer to the old one.
if [ -f private/ca-key.pem ] || [ -f certs/ca-cert.pem ]; then
    echo "WARNING: a CA already exists in this directory:"
    [ -f private/ca-key.pem ] && echo "  private/ca-key.pem"
    [ -f certs/ca-cert.pem ] && echo "  certs/ca-cert.pem"
    echo ""
    echo "Replacing it invalidates every certificate already issued from it."
    read -r -p "Type 'replace' to overwrite, anything else to abort: " REPLY
    if [ "$REPLY" != "replace" ]; then
        echo "Aborted. The existing CA was left untouched."
        exit 1
    fi
    echo ""
fi

# Generate CA private key
echo "Step 1: Generating CA private key..."
echo "You will be prompted to enter a passphrase (min 4 characters)"
openssl genrsa -aes256 -out private/ca-key.pem 4096
chmod 600 private/ca-key.pem

echo ""
echo "Step 2: Creating self-signed root CA certificate..."
echo "You will be prompted for:"
echo "  - The passphrase you just created"
echo "  - Certificate details (Country, State, Organization, etc.)"
echo ""

openssl req -config openssl.cnf \
      -key private/ca-key.pem \
      -new -x509 -days 3650 -sha256 -extensions v3_ca \
      -out certs/ca-cert.pem

chmod 644 certs/ca-cert.pem

# Verify the certificate really was signed by the key we just generated.
# `openssl verify` checks the self-signature against the public key embedded
# in the certificate, so this needs no further passphrase prompt.
echo ""
echo "Verifying the CA certificate..."
if ! openssl verify -CAfile certs/ca-cert.pem certs/ca-cert.pem > /dev/null; then
    echo "✗ ERROR: The CA certificate failed self-verification!"
    echo ""
    echo "The certificate does not match the key it was supposedly signed with."
    exit 1
fi
echo "✓ Verification passed: CA certificate is valid and self-signed"

echo ""
echo "=== Root CA Created Successfully ==="
echo ""
echo "Files created:"
echo "  Private Key: private/ca-key.pem (KEEP THIS SECURE!)"
echo "  Certificate: certs/ca-cert.pem"
echo ""
echo "To view the certificate:"
echo "  openssl x509 -noout -text -in certs/ca-cert.pem"
echo ""
