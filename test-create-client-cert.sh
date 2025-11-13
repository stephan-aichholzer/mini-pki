#!/bin/bash
# Test version of create-client-cert.sh with automated inputs

set -e

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <client-name>"
    echo "Example: $0 client1.example.com"
    exit 1
fi

CLIENT_NAME=$1
BASENAME=$(echo $CLIENT_NAME | sed 's/[^a-zA-Z0-9._-]/_/g')

echo "=== Creating Client Certificate (TEST MODE) ==="
echo "Client Name: $CLIENT_NAME"
echo ""

# Generate private key (no password for testing)
echo "Step 1: Generating private key..."
openssl genrsa -out private/${BASENAME}-key.pem 2048
chmod 400 private/${BASENAME}-key.pem

# Generate CSR
echo "Step 2: Generating Certificate Signing Request..."
openssl req -config openssl.cnf -key private/${BASENAME}-key.pem \
    -new -sha256 -out certs/${BASENAME}.csr \
    -subj "/C=US/ST=State/L=City/O=Organization/OU=Clients/CN=$CLIENT_NAME"

# Sign with CA
echo "Step 3: Signing certificate with CA..."
openssl ca -config openssl.cnf -extensions v3_client \
    -days 375 -notext -md sha256 \
    -in certs/${BASENAME}.csr \
    -out certs/${BASENAME}-cert.pem \
    -passin file:/tmp/ca_pass.txt \
    -batch

chmod 444 certs/${BASENAME}-cert.pem

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
