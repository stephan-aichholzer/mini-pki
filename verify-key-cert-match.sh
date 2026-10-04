#!/bin/bash
# Script to verify that a private key matches its certificate
# This helps diagnose "key values mismatch" errors
# Run with --help for usage.

set -e

usage() {
    echo "Usage: $0 <private-key.pem> <certificate.pem>"
    echo ""
    echo "Example:"
    echo "  $0 private/server.example.com-key.pem certs/server.example.com-cert.pem"
    echo ""
    echo "This script will:"
    echo "  1. Extract the public key from the private key"
    echo "  2. Extract the public key from the certificate"
    echo "  3. Compare them to verify they match"
}

. "$(dirname "$0")/lib/cli.sh"
parse_cli "$@"
set -- "${ARGS[@]}"

if [ "$#" -ne 2 ]; then
    usage >&2
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

echo "=== Verifying Key/Certificate Match ==="
echo ""
echo "Private Key:  $PRIVATE_KEY"
echo "Certificate:  $CERTIFICATE"
echo ""

# Check if private key is encrypted
if grep -q "ENCRYPTED" "$PRIVATE_KEY"; then
    echo "Note: Private key is encrypted (you may be prompted for passphrase)"
    echo ""
fi

# Compare the raw moduli directly. Piping through `openssl md5` masked
# failures: if both openssl calls failed they each hashed empty input to the
# same digest, and the comparison reported a MATCH. Without the pipe, `set -e`
# aborts on a failed extraction, and the passphrase prompt stays visible.
# The `if [ $? -ne 0 ]` guards that used to follow these assignments were
# unreachable: `set -e` already aborts on a failed assignment.
echo "Extracting modulus from private key..."
if ! PRIVATE_MODULUS=$(openssl rsa -noout -modulus -in "$PRIVATE_KEY"); then
    echo "Error: Failed to extract modulus from private key"
    echo "       This could be due to:"
    echo "       - Incorrect passphrase"
    echo "       - Corrupted key file"
    echo "       - Wrong file format"
    exit 1
fi

echo "Extracting modulus from certificate..."
if ! CERT_MODULUS=$(openssl x509 -noout -modulus -in "$CERTIFICATE"); then
    echo "Error: Failed to extract modulus from certificate"
    echo "       The certificate file may be corrupted or invalid"
    exit 1
fi

# Compare (digests shown for readability; the comparison uses the full moduli)
echo ""
echo "Private Key Modulus:  $(printf '%s' "$PRIVATE_MODULUS" | openssl md5)"
echo "Certificate Modulus:  $(printf '%s' "$CERT_MODULUS" | openssl md5)"
echo ""

if [ "$PRIVATE_MODULUS" = "$CERT_MODULUS" ]; then
    echo "✓ SUCCESS: Private key and certificate MATCH!"
    echo ""
    echo "The key pair is valid and can be used together."
    exit 0
else
    echo "✗ FAILURE: Private key and certificate DO NOT MATCH!"
    echo ""
    echo "Possible causes:"
    echo "  1. You're using the wrong private key for this certificate"
    echo "  2. You're using the wrong certificate for this private key"
    echo "  3. The certificate was signed with a different key"
    echo "  4. One of the files is corrupted"
    echo ""
    echo "To fix:"
    echo "  - Verify you're using the correct key/cert pair"
    echo "  - Check the filenames match (same basename)"
    echo "  - Regenerate the certificate if needed"
    exit 1
fi
