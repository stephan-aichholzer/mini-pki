#!/bin/bash
# Script to create a combined PEM file for server applications
# Combines private key + certificate + CA chain into a single file

set -e

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "Usage: $0 <private-key.pem> <certificate.pem> [ca-cert.pem]"
    echo ""
    echo "Example:"
    echo "  $0 private/server-key.pem certs/server-cert.pem certs/ca-cert.pem"
    echo ""
    echo "This creates a combined PEM file containing:"
    echo "  1. Private key"
    echo "  2. Server certificate"
    echo "  3. CA certificate (optional, for chain verification)"
    echo ""
    echo "Output: certs/<basename>-combined.pem"
    exit 1
fi

PRIVATE_KEY=$1
CERTIFICATE=$2
CA_CERT=$3

# Check files exist
if [ ! -f "$PRIVATE_KEY" ]; then
    echo "Error: Private key file not found: $PRIVATE_KEY"
    exit 1
fi

if [ ! -f "$CERTIFICATE" ]; then
    echo "Error: Certificate file not found: $CERTIFICATE"
    exit 1
fi

if [ -n "$CA_CERT" ] && [ ! -f "$CA_CERT" ]; then
    echo "Error: CA certificate file not found: $CA_CERT"
    exit 1
fi

# Extract basename from certificate
CERT_BASENAME=$(basename "$CERTIFICATE" .pem | sed 's/-cert$//')
OUTPUT_FILE="certs/${CERT_BASENAME}-combined.pem"

echo "=== Creating Combined PEM File ==="
echo ""
echo "Input files:"
echo "  Private Key:  $PRIVATE_KEY"
echo "  Certificate:  $CERTIFICATE"
if [ -n "$CA_CERT" ]; then
    echo "  CA Cert:      $CA_CERT"
fi
echo ""
echo "Output file:  $OUTPUT_FILE"
echo ""

# Verify key and cert match first
echo "Verifying private key matches certificate..."
PRIVATE_MODULUS=$(openssl rsa -noout -modulus -in "$PRIVATE_KEY" 2>/dev/null | openssl md5)
CERT_MODULUS=$(openssl x509 -noout -modulus -in "$CERTIFICATE" 2>/dev/null | openssl md5)

if [ "$PRIVATE_MODULUS" != "$CERT_MODULUS" ]; then
    echo "✗ ERROR: Private key and certificate DO NOT MATCH!"
    echo "         Cannot create combined PEM file."
    exit 1
fi
echo "✓ Private key and certificate match"
echo ""

# Create combined file
echo "Creating combined PEM file..."

# Start with private key
cat "$PRIVATE_KEY" > "$OUTPUT_FILE"

# Add newline separator
echo "" >> "$OUTPUT_FILE"

# Add certificate
cat "$CERTIFICATE" >> "$OUTPUT_FILE"

# Add CA certificate if provided
if [ -n "$CA_CERT" ]; then
    echo "" >> "$OUTPUT_FILE"
    cat "$CA_CERT" >> "$OUTPUT_FILE"
fi

# Set appropriate permissions
chmod 400 "$OUTPUT_FILE"

echo ""
echo "=== Combined PEM File Created Successfully ==="
echo ""
echo "File: $OUTPUT_FILE"
echo "Permissions: 400 (read-only for owner)"
echo ""
echo "Contents:"
if grep -q "ENCRYPTED" "$OUTPUT_FILE"; then
    echo "  ✓ Encrypted private key (AES-256)"
else
    echo "  ✓ Private key (unencrypted)"
fi
echo "  ✓ Server/Client certificate"
if [ -n "$CA_CERT" ]; then
    echo "  ✓ CA certificate chain"
fi
echo ""
echo "Usage examples:"
echo ""
echo "Nginx (nginx.conf):"
echo "  ssl_certificate $OUTPUT_FILE;"
echo "  ssl_certificate_key $OUTPUT_FILE;"
echo ""
echo "Apache (httpd.conf):"
echo "  SSLCertificateFile $OUTPUT_FILE"
echo ""
echo "Node.js (HTTPS server):"
echo "  const options = {"
echo "    pfx: fs.readFileSync('$OUTPUT_FILE')"
echo "  };"
echo ""
