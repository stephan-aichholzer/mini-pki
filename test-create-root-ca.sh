#!/bin/bash
# Test version of create-root-ca.sh with automated inputs

set -e

echo "=== Creating Root CA (TEST MODE) ==="
echo ""

# Create passphrase file
echo "test1234" > /tmp/ca_pass.txt
chmod 600 /tmp/ca_pass.txt

# Generate CA private key
echo "Step 1: Generating CA private key..."
openssl genrsa -aes256 -out private/ca-key.pem -passout file:/tmp/ca_pass.txt 4096
chmod 400 private/ca-key.pem

echo ""
echo "Step 2: Creating self-signed root CA certificate..."

openssl req -config openssl.cnf \
      -key private/ca-key.pem \
      -new -x509 -days 3650 -sha256 -extensions v3_ca \
      -out certs/ca-cert.pem \
      -passin file:/tmp/ca_pass.txt \
      -subj "/C=US/ST=TestState/L=TestCity/O=TestOrg/OU=TestCA/CN=Test Root CA"

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
