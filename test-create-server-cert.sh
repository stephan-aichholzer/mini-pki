#!/bin/bash
# Test version of create-server-cert.sh with automated CA passphrase

set -e

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <common-name> [dns-names...]"
    echo "Example: $0 server.example.com www.example.com api.example.com"
    exit 1
fi

COMMON_NAME=$1
shift
DNS_NAMES="$@"

echo "=== Creating Server Certificate (TEST MODE) ==="
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

# Generate private key (no password for server keys typically)
echo "Step 1: Generating private key..."
openssl genrsa -out private/${BASENAME}-key.pem 2048
chmod 400 private/${BASENAME}-key.pem

# Generate CSR
echo "Step 2: Generating Certificate Signing Request..."
openssl req -config temp_server.cnf -key private/${BASENAME}-key.pem \
    -new -sha256 -out certs/${BASENAME}.csr \
    -subj "/C=US/ST=State/L=City/O=Organization/OU=IT/CN=$COMMON_NAME"

# Sign with CA
echo "Step 3: Signing certificate with CA..."
openssl ca -config temp_server.cnf -extensions v3_server \
    -days 375 -notext -md sha256 \
    -in certs/${BASENAME}.csr \
    -out certs/${BASENAME}-cert.pem \
    -passin file:/tmp/ca_pass.txt \
    -batch

chmod 444 certs/${BASENAME}-cert.pem

# Cleanup
rm temp_server.cnf

echo ""
echo "=== Server Certificate Created Successfully ==="
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
