#!/bin/bash
# Script to create a self-signed Root CA certificate

set -e

echo "=== Creating Root CA ==="
echo ""
echo "This script will:"
echo "1. Generate a 4096-bit RSA private key (password protected)"
echo "2. Create a self-signed root CA certificate valid for 10 years"
echo ""

# Generate CA private key
echo "Step 1: Generating CA private key..."
echo "You will be prompted to enter a passphrase (min 4 characters)"
openssl genrsa -aes256 -out private/ca-key.pem 4096
chmod 400 private/ca-key.pem

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

chmod 444 certs/ca-cert.pem

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
