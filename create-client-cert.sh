#!/bin/bash
# Script to create a client certificate for mutual TLS authentication

set -e

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <client-name>"
    echo "Example: $0 client1.example.com"
    exit 1
fi

CLIENT_NAME=$1
BASENAME=$(echo $CLIENT_NAME | sed 's/[^a-zA-Z0-9._-]/_/g')

echo "=== Creating Client Certificate ==="
echo "Client Name: $CLIENT_NAME"
echo ""

# Generate private key (can be password protected for clients)
echo "Step 1: Generating private key..."
echo "Press Enter for no passphrase, or enter a passphrase for extra security"
openssl genrsa -aes256 -out private/${BASENAME}-key.pem 2048 2>/dev/null || \
    openssl genrsa -out private/${BASENAME}-key.pem 2048
chmod 400 private/${BASENAME}-key.pem

# Generate CSR
echo "Step 2: Generating Certificate Signing Request..."
echo "You will be prompted for certificate details (Country, State, Organization, etc.)"
echo "Common Name will be set to: $CLIENT_NAME"
echo ""
openssl req -config openssl.cnf -key private/${BASENAME}-key.pem \
    -new -sha256 -out certs/${BASENAME}.csr

# Sign with CA
echo "Step 3: Signing certificate with CA..."
echo "You will be prompted for the CA passphrase"
openssl ca -config openssl.cnf -extensions v3_client \
    -days 375 -notext -md sha256 \
    -in certs/${BASENAME}.csr \
    -out certs/${BASENAME}-cert.pem

chmod 444 certs/${BASENAME}-cert.pem

# Verify key and certificate match
echo ""
echo "Verifying certificate and private key match..."
PRIVATE_MODULUS=$(openssl rsa -noout -modulus -in private/${BASENAME}-key.pem 2>/dev/null | openssl md5)
CERT_MODULUS=$(openssl x509 -noout -modulus -in certs/${BASENAME}-cert.pem 2>/dev/null | openssl md5)

if [ "$PRIVATE_MODULUS" != "$CERT_MODULUS" ]; then
    echo "✗ ERROR: Private key and certificate DO NOT MATCH!"
    echo ""
    echo "This is a critical error. The certificate cannot be used with this key."
    echo "Please report this issue with details about what you entered during prompts."
    exit 1
fi
echo "✓ Verification passed: Private key and certificate match"

echo ""
echo "=== Client Certificate Created Successfully ==="
echo ""
echo "Files created:"
echo "  Private Key: private/${BASENAME}-key.pem"
echo "  Certificate: certs/${BASENAME}-cert.pem"
echo "  CSR: certs/${BASENAME}.csr"
echo ""
echo "To create PKCS#12 bundle for client (includes key + cert):"
echo "  openssl pkcs12 -export -out certs/${BASENAME}.p12 \\"
echo "    -inkey private/${BASENAME}-key.pem \\"
echo "    -in certs/${BASENAME}-cert.pem \\"
echo "    -certfile certs/ca-cert.pem"
echo ""
echo "To view the certificate:"
echo "  openssl x509 -noout -text -in certs/${BASENAME}-cert.pem"
echo ""
echo "To verify against CA:"
echo "  openssl verify -CAfile certs/ca-cert.pem certs/${BASENAME}-cert.pem"
echo ""
