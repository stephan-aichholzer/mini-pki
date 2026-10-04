#!/bin/bash
# Script to create a client certificate for mutual TLS authentication

set -e

. "$(dirname "$0")/lib/ca-key.sh"

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <client-name>"
    echo "Example: $0 client1.example.com"
    exit 1
fi

card_preflight issue

CLIENT_NAME=$1
BASENAME=$(echo $CLIENT_NAME | sed 's/[^a-zA-Z0-9._-]/_/g')

echo "=== Creating Client Certificate ==="
echo "Client Name: $CLIENT_NAME"
echo ""

# Ask about password protection
echo ""
# Read a whole line, not a single character: with `read -n 1` the Enter the
# user presses after "y" stays in the input buffer, and openssl's next
# passphrase prompt consumes it as an empty passphrase and aborts.
read -r -p "Do you want to password-protect the client private key? (y/N): " REPLY
if [[ $REPLY =~ ^[Yy]$ ]]; then
    USE_PASSWORD=true
else
    USE_PASSWORD=false
fi
echo ""

# Generate private key
echo "Step 1: Generating private key..."
if [ "$USE_PASSWORD" = true ]; then
    echo "You will be prompted to enter a passphrase for the private key"
    openssl genrsa -aes256 -out private/${BASENAME}-key.pem 2048
else
    echo "Generating unencrypted private key (no passphrase)"
    openssl genrsa -out private/${BASENAME}-key.pem 2048
fi
chmod 600 private/${BASENAME}-key.pem

# Generate CSR
echo "Step 2: Generating Certificate Signing Request..."
echo "You will be prompted for certificate details (Country, State, Organization, etc.)"
echo "Enter this as the Common Name: $CLIENT_NAME"
echo "(the Common Name is not filled in automatically)"
echo ""
openssl req -config openssl.cnf -key private/${BASENAME}-key.pem \
    -new -sha256 -out certs/${BASENAME}.csr

# Sign with CA
echo "Step 3: Signing certificate with CA..."
echo "You will be prompted for the $CA_SECRET_NAME"
openssl ca -config openssl.cnf -extensions v3_client \
    "${CA_SIGN_ARGS[@]}" \
    -days 375 -notext -md sha256 \
    -in certs/${BASENAME}.csr \
    -out certs/${BASENAME}-cert.pem

chmod 644 certs/${BASENAME}-cert.pem

# Verify key and certificate match
echo ""
echo "Verifying certificate and private key match..."
# Compare the raw moduli directly. Piping through `openssl md5` masked
# failures: if both openssl calls failed they each hashed empty input to the
# same digest, and the scripts reported a MATCH. Without the pipe, `set -e`
# aborts on a failed extraction, and the passphrase prompt stays visible.
if [ "$USE_PASSWORD" = true ]; then
    echo "(enter the private key passphrase once more to verify the pair)"
fi
PRIVATE_MODULUS=$(openssl rsa -noout -modulus -in private/${BASENAME}-key.pem)
CERT_MODULUS=$(openssl x509 -noout -modulus -in certs/${BASENAME}-cert.pem)

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
if [ "$USE_PASSWORD" = true ]; then
    echo "  Private Key: private/${BASENAME}-key.pem (PASSWORD PROTECTED)"
else
    echo "  Private Key: private/${BASENAME}-key.pem (no password)"
fi
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
