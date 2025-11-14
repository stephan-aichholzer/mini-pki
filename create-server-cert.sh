#!/bin/bash
# Script to create a server certificate for TLS/HTTPS

set -e

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <common-name> [dns-names...]"
    echo "Example: $0 server.example.com www.example.com api.example.com"
    exit 1
fi

COMMON_NAME=$1
shift
DNS_NAMES="$@"

echo "=== Creating Server Certificate ==="
echo "Common Name: $COMMON_NAME"
echo ""

# Create a temporary config file with custom SANs
cat openssl.cnf > temp_server.cnf
echo "" >> temp_server.cnf
echo "[ alt_names_temp ]" >> temp_server.cnf
echo "DNS.1 = $COMMON_NAME" >> temp_server.cnf

counter=2
for dns in $DNS_NAMES; do
    echo "DNS.$counter = $dns" >> temp_server.cnf
    counter=$((counter + 1))
done

# Also add localhost and IP for testing
echo "DNS.$counter = localhost" >> temp_server.cnf
counter=$((counter + 1))
echo "IP.1 = 127.0.0.1" >> temp_server.cnf
echo "IP.2 = ::1" >> temp_server.cnf

# Update v3_server to use temp alt names
sed -i 's/subjectAltName = @alt_names_server/subjectAltName = @alt_names_temp/' temp_server.cnf

BASENAME=$(echo $COMMON_NAME | sed 's/[^a-zA-Z0-9._-]/_/g')

# Ask about password protection
echo ""
read -p "Do you want to password-protect the server private key? (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    USE_PASSWORD=true
    echo "Note: You will need to enter this passphrase when starting your server"
    echo "      or configure your server to prompt for it at startup."
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
chmod 400 private/${BASENAME}-key.pem

# Generate CSR
echo "Step 2: Generating Certificate Signing Request..."
echo "You will be prompted for certificate details (Country, State, Organization, etc.)"
echo "Common Name will be set to: $COMMON_NAME"
echo ""
openssl req -config temp_server.cnf -key private/${BASENAME}-key.pem \
    -new -sha256 -out certs/${BASENAME}.csr

# Sign with CA
echo "Step 3: Signing certificate with CA..."
echo "You will be prompted for the CA passphrase"
openssl ca -config temp_server.cnf -extensions v3_server \
    -days 375 -notext -md sha256 \
    -in certs/${BASENAME}.csr \
    -out certs/${BASENAME}-cert.pem

chmod 444 certs/${BASENAME}-cert.pem

# Cleanup
rm temp_server.cnf

# Verify key and certificate match
echo ""
echo "Verifying certificate and private key match..."
PRIVATE_MODULUS=$(openssl rsa -noout -modulus -in private/${BASENAME}-key.pem 2>/dev/null | openssl md5)
CERT_MODULUS=$(openssl x509 -noout -modulus -in certs/${BASENAME}-cert.pem 2>/dev/null | openssl md5)

if [ "$PRIVATE_MODULUS" != "$CERT_MODULUS" ]; then
    echo "✗ ERROR: Private key and certificate DO NOT MATCH!"
    echo ""
    echo "This is a critical error. The certificate cannot be used with this key."
    echo "Files created:"
    echo "  Private Key: private/${BASENAME}-key.pem"
    echo "  Certificate: certs/${BASENAME}-cert.pem"
    echo ""
    echo "Please report this issue with details about what you entered during prompts."
    exit 1
fi
echo "✓ Verification passed: Private key and certificate match"

echo ""
echo "=== Server Certificate Created Successfully ==="
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
echo "To view the certificate:"
echo "  openssl x509 -noout -text -in certs/${BASENAME}-cert.pem"
echo ""
echo "To verify against CA:"
echo "  openssl verify -CAfile certs/ca-cert.pem certs/${BASENAME}-cert.pem"
echo ""
if [ "$USE_PASSWORD" = true ]; then
    echo "To remove passphrase from private key (if needed for automated startup):"
    echo "  openssl rsa -in private/${BASENAME}-key.pem -out private/${BASENAME}-key-nopass.pem"
    echo ""
fi
