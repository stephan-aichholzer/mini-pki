#!/bin/bash
# Script to create a code signing certificate

set -e

usage() {
    cat <<EOF
Usage: $0 [--card | --file] <signer-name>

Creates a code signing certificate signed by the CA: profile v3_code_signing
(codeSigning; digitalSignature), valid 375 days, with a new 2048-bit RSA key
that is always passphrase-protected.

  <signer-name>   person, team or build system - also used for the file names

Prompts for the key passphrase, the subject (enter <signer-name> as Common
Name) and the CA passphrase or card PIN. In card mode a pre-flight check
verifies card and CA key first.

EOF
    backend_help
    cat <<EOF
Creates:
  private/<name>-key.pem   signing key (passphrase-protected)
  certs/<name>.csr         signing request (can be deleted afterwards)
  certs/<name>-cert.pem    code signing certificate

Examples:
  $0 "Jane Developer"
  $0 --card build-bot
EOF
}

. "$(dirname "$0")/lib/cli.sh"
CLI_BACKEND_OPTS=1
parse_cli "$@"
set -- "${ARGS[@]}"
. "$(dirname "$0")/lib/ca-key.sh"

if [ "$#" -ne 1 ]; then
    usage >&2
    exit 1
fi

card_preflight issue

SIGNER_NAME=$1
BASENAME=$(echo $SIGNER_NAME | sed 's/[^a-zA-Z0-9._-]/_/g')

echo "=== Creating Code Signing Certificate ==="
echo "Signer Name: $SIGNER_NAME"
echo ""

# Generate private key (should be password protected)
echo "Step 1: Generating private key..."
echo "You will be prompted to enter a passphrase (recommended for code signing)"
openssl genrsa -aes256 -out private/${BASENAME}-key.pem 2048
chmod 600 private/${BASENAME}-key.pem

# Generate CSR
echo "Step 2: Generating Certificate Signing Request..."
echo "You will be prompted for certificate details (Country, State, Organization, etc.)"
echo "Enter this as the Common Name: $SIGNER_NAME"
echo "(the Common Name is not filled in automatically)"
echo ""
openssl req -config openssl.cnf -key private/${BASENAME}-key.pem \
    -new -sha256 -out certs/${BASENAME}.csr

# Sign with CA
echo "Step 3: Signing certificate with CA..."
echo "You will be prompted for the $CA_SECRET_NAME"
openssl ca -config openssl.cnf -extensions v3_code_signing \
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
echo "(enter the private key passphrase once more to verify the pair)"
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
echo "=== Code Signing Certificate Created Successfully ==="
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
echo "Usage examples:"
echo "  # Sign a file"
echo "  openssl dgst -sha256 -sign private/${BASENAME}-key.pem -out file.sig file.txt"
echo ""
echo "  # Verify signature"
echo "  openssl dgst -sha256 -verify <(openssl x509 -in certs/${BASENAME}-cert.pem -pubkey -noout) -signature file.sig file.txt"
echo ""
