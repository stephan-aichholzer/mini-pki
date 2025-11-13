#!/bin/bash
# Script to create a code signing certificate

set -e

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <signer-name>"
    echo "Example: $0 'John Doe' or $0 developer@example.com"
    exit 1
fi

SIGNER_NAME=$1
BASENAME=$(echo $SIGNER_NAME | sed 's/[^a-zA-Z0-9._-]/_/g')

echo "=== Creating Code Signing Certificate ==="
echo "Signer Name: $SIGNER_NAME"
echo ""

# Generate private key (should be password protected)
echo "Step 1: Generating private key..."
echo "You will be prompted to enter a passphrase (recommended for code signing)"
openssl genrsa -aes256 -out private/${BASENAME}-key.pem 2048
chmod 400 private/${BASENAME}-key.pem

# Generate CSR
echo "Step 2: Generating Certificate Signing Request..."
echo "You will be prompted for certificate details (Country, State, Organization, etc.)"
echo "Common Name will be set to: $SIGNER_NAME"
echo ""
openssl req -config openssl.cnf -key private/${BASENAME}-key.pem \
    -new -sha256 -out certs/${BASENAME}.csr

# Sign with CA
echo "Step 3: Signing certificate with CA..."
echo "You will be prompted for the CA passphrase"
openssl ca -config openssl.cnf -extensions v3_code_signing \
    -days 375 -notext -md sha256 \
    -in certs/${BASENAME}.csr \
    -out certs/${BASENAME}-cert.pem

chmod 444 certs/${BASENAME}-cert.pem

echo ""
echo "=== Code Signing Certificate Created Successfully ==="
echo ""
echo "Files created:"
echo "  Private Key: private/${BASENAME}-key.pem"
echo "  Certificate: certs/${BASENAME}-cert.pem"
echo "  CSR: certs/${BASENAME}.csr"
echo ""
echo "To view the certificate:"
echo "  openssl x509 -noout -text -in certs/${BASENAME}-cert.pem"
echo ""
echo "To verify against CA:"
echo "  openssl verify -CAfile certs/ca-cert.pem certs/${BASENAME}-cert.pem"
echo ""
echo "Usage examples:"
echo "  # Sign a file"
echo "  openssl dgst -sha256 -sign private/${BASENAME}-key.pem -out file.sig file.txt"
echo ""
echo "  # Verify signature"
echo "  openssl dgst -sha256 -verify <(openssl x509 -in certs/${BASENAME}-cert.pem -pubkey -noout) -signature file.sig file.txt"
echo ""
