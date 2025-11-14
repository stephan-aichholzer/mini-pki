#!/bin/bash
# Script to create a PKCS#12 bundle (.p12/.pfx) for cross-platform certificate distribution
# Bundles private key + certificate + CA chain into a single encrypted file

set -e

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "Usage: $0 <private-key.pem> <certificate.pem> [ca-cert.pem]"
    echo ""
    echo "Example:"
    echo "  $0 private/server-key.pem certs/server-cert.pem certs/ca-cert.pem"
    echo ""
    echo "This creates a PKCS#12 bundle containing:"
    echo "  1. Private key (encrypted)"
    echo "  2. Server/Client certificate"
    echo "  3. CA certificate chain (optional)"
    echo ""
    echo "Output: certs/<basename>.p12"
    echo ""
    echo "Use cases:"
    echo "  - Windows IIS server certificates"
    echo "  - Browser client certificate import"
    echo "  - Java keystore import"
    echo "  - Cross-platform certificate distribution"
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
OUTPUT_FILE="certs/${CERT_BASENAME}.p12"

echo "=== Creating PKCS#12 Bundle ==="
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
if [ $? -ne 0 ]; then
    echo "✗ ERROR: Failed to read private key"
    echo "         If the key is encrypted, you'll be prompted for the passphrase during bundle creation"
    # Don't exit, let openssl pkcs12 handle the passphrase prompt
else
    CERT_MODULUS=$(openssl x509 -noout -modulus -in "$CERTIFICATE" 2>/dev/null | openssl md5)
    if [ "$PRIVATE_MODULUS" != "$CERT_MODULUS" ]; then
        echo "✗ ERROR: Private key and certificate DO NOT MATCH!"
        echo "         Cannot create PKCS#12 bundle."
        exit 1
    fi
    echo "✓ Private key and certificate match"
fi
echo ""

# Get friendly name for the certificate
echo "Enter a friendly name for this certificate (e.g., 'My Server Cert'):"
read -r FRIENDLY_NAME

if [ -z "$FRIENDLY_NAME" ]; then
    FRIENDLY_NAME="$CERT_BASENAME"
fi

echo ""
echo "Creating PKCS#12 bundle..."
echo "You will be prompted to:"
if grep -q "ENCRYPTED" "$PRIVATE_KEY"; then
    echo "  1. Enter the private key passphrase (if encrypted)"
    echo "  2. Enter export password (protects the .p12 file)"
    echo "  3. Re-enter export password"
else
    echo "  1. Enter export password (protects the .p12 file)"
    echo "  2. Re-enter export password"
fi
echo ""
echo "Note: The export password is required and will be needed to import this bundle."
echo ""

# Build openssl pkcs12 command
PKCS12_CMD="openssl pkcs12 -export -out \"$OUTPUT_FILE\" -inkey \"$PRIVATE_KEY\" -in \"$CERTIFICATE\" -name \"$FRIENDLY_NAME\""

if [ -n "$CA_CERT" ]; then
    PKCS12_CMD="$PKCS12_CMD -certfile \"$CA_CERT\""
fi

# Execute the command
eval $PKCS12_CMD

if [ $? -ne 0 ]; then
    echo ""
    echo "✗ ERROR: Failed to create PKCS#12 bundle"
    exit 1
fi

# Set appropriate permissions
chmod 400 "$OUTPUT_FILE"

echo ""
echo "=== PKCS#12 Bundle Created Successfully ==="
echo ""
echo "File: $OUTPUT_FILE"
echo "Permissions: 400 (read-only for owner)"
echo "Friendly Name: $FRIENDLY_NAME"
echo ""
echo "To verify the bundle contents:"
echo "  openssl pkcs12 -info -in $OUTPUT_FILE"
echo ""
echo "To import into:"
echo ""
echo "Windows (IIS):"
echo "  1. Copy $OUTPUT_FILE to Windows server"
echo "  2. Double-click the .p12 file"
echo "  3. Follow Certificate Import Wizard"
echo "  4. Enter the export password"
echo ""
echo "macOS Keychain:"
echo "  1. Double-click $OUTPUT_FILE"
echo "  2. Enter export password"
echo "  3. Add to login or system keychain"
echo ""
echo "Firefox/Chrome:"
echo "  1. Settings → Privacy & Security → Certificates"
echo "  2. Import → Select $OUTPUT_FILE"
echo "  3. Enter export password"
echo ""
echo "Java Keytool:"
echo "  keytool -importkeystore \\"
echo "    -srckeystore $OUTPUT_FILE \\"
echo "    -srcstoretype PKCS12 \\"
echo "    -destkeystore keystore.jks \\"
echo "    -deststoretype JKS"
echo ""
echo "SECURITY WARNING:"
echo "  - Keep this file secure (contains private key)"
echo "  - Do NOT commit to version control"
echo "  - Use a strong export password"
echo "  - Delete after distribution if no longer needed"
echo ""
