#!/bin/bash
# Script to test server certificate with OpenSSL before using in application
# This helps verify the certificate is properly configured for TLS/SSL

set -e

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <private-key.pem> <certificate.pem>"
    echo ""
    echo "Example:"
    echo "  $0 private/server-key.pem certs/server-cert.pem"
    echo ""
    echo "This script will:"
    echo "  1. Verify key and certificate match"
    echo "  2. Display certificate details"
    echo "  3. Test with OpenSSL s_server"
    exit 1
fi

PRIVATE_KEY=$1
CERTIFICATE=$2

# Check files exist
if [ ! -f "$PRIVATE_KEY" ]; then
    echo "Error: Private key file not found: $PRIVATE_KEY"
    exit 1
fi

if [ ! -f "$CERTIFICATE" ]; then
    echo "Error: Certificate file not found: $CERTIFICATE"
    exit 1
fi

echo "=== Testing Server Certificate for TLS/SSL Usage ==="
echo ""
echo "Private Key:  $PRIVATE_KEY"
echo "Certificate:  $CERTIFICATE"
echo ""

# Step 1: Verify key and certificate match
echo "Step 1: Verifying private key matches certificate..."
PRIVATE_MODULUS=$(openssl rsa -noout -modulus -in "$PRIVATE_KEY" 2>/dev/null | openssl md5)
CERT_MODULUS=$(openssl x509 -noout -modulus -in "$CERTIFICATE" 2>/dev/null | openssl md5)

if [ "$PRIVATE_MODULUS" != "$CERT_MODULUS" ]; then
    echo "✗ FAILED: Private key and certificate DO NOT MATCH!"
    echo ""
    echo "This is the root cause of your X509_check_private_key error."
    exit 1
fi
echo "✓ PASSED: Private key and certificate match"
echo ""

# Step 2: Display certificate details
echo "Step 2: Certificate Details"
echo "----------------------------"
echo ""
echo "Subject:"
openssl x509 -noout -subject -in "$CERTIFICATE"
echo ""
echo "Issuer:"
openssl x509 -noout -issuer -in "$CERTIFICATE"
echo ""
echo "Validity:"
openssl x509 -noout -dates -in "$CERTIFICATE"
echo ""
echo "Key Usage:"
openssl x509 -noout -ext keyUsage -in "$CERTIFICATE" 2>/dev/null || echo "  (not set)"
echo ""
echo "Extended Key Usage:"
openssl x509 -noout -ext extendedKeyUsage -in "$CERTIFICATE" 2>/dev/null || echo "  (not set)"
echo ""
echo "Subject Alternative Names:"
openssl x509 -noout -ext subjectAltName -in "$CERTIFICATE" 2>/dev/null || echo "  (not set)"
echo ""

# Step 3: Test with OpenSSL
echo "Step 3: Testing with OpenSSL s_server"
echo "--------------------------------------"
echo ""
echo "Starting OpenSSL test server on port 4433..."
echo "Press Ctrl+C to stop the server after verification"
echo ""
echo "In another terminal, test with:"
echo "  openssl s_client -connect localhost:4433 -showcerts"
echo ""
echo "Or test with curl:"
echo "  curl -k https://localhost:4433"
echo ""

# Check if port is already in use
if lsof -Pi :4433 -sTCP:LISTEN -t >/dev/null 2>&1 ; then
    echo "Warning: Port 4433 is already in use. Trying port 4434..."
    PORT=4434
else
    PORT=4433
fi

echo "Starting server on port $PORT..."
echo ""

# Start OpenSSL server
if [ -f "certs/ca-cert.pem" ]; then
    openssl s_server -accept $PORT \
        -cert "$CERTIFICATE" \
        -key "$PRIVATE_KEY" \
        -CAfile certs/ca-cert.pem \
        -www
else
    openssl s_server -accept $PORT \
        -cert "$CERTIFICATE" \
        -key "$PRIVATE_KEY" \
        -www
fi
