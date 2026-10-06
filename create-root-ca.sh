#!/bin/bash
# Script to create a self-signed Root CA certificate
#
# CA_BACKEND=file (default): key in private/ca-key.pem, passphrase protected
# CA_BACKEND=card:           key generated on a PKCS#11 smartcard (see pki.conf)
# Run with --help for usage.

set -e

usage() {
    cat <<EOF
Usage: $0 [--card | --file] [-h | --help]

Creates the self-signed root CA certificate (10 years, profile v3_ca).

  file mode   generates a 4096-bit RSA key in private/ca-key.pem, protected
              with a passphrase (AES-256) that you choose
  card mode   generates CARD_KEY_TYPE (default rsa:4096) on the smartcard under
              CARD_KEY_LABEL - or reuses a key with that label - and lets the
              card self-sign the certificate; the certificate is also stored on
              the card and the card is recorded in ca-card.manifest

Prompts for the CA passphrase or card PIN and the certificate subject
(Country ... Common Name). An existing CA is only replaced after typing
'replace'. Run ./init-ca-database.sh first.

EOF
    backend_help
    cat <<EOF
Creates:
  certs/ca-cert.pem      CA certificate (give this to clients)
  private/ca-key.pem     CA private key          (file mode)
  ca-card.manifest       which card holds the key (card mode)

Examples:
  $0             backend from pki.conf
  $0 --card      CA key on the smartcard
  $0 --file      CA key as passphrase-protected file
EOF
}

. "$(dirname "$0")/lib/cli.sh"
CLI_BACKEND_OPTS=1
parse_cli "$@"
set -- "${ARGS[@]}"
. "$(dirname "$0")/lib/ca-key.sh"

echo "=== Creating Root CA (backend: $CA_BACKEND) ==="
echo ""
echo "This script will:"
if [ "$CA_BACKEND" = card ]; then
    echo "1. Generate a $CARD_KEY_TYPE key pair on the card (label '$CARD_KEY_LABEL'),"
    echo "   or reuse it if it already exists. The private key never leaves the card."
else
    echo "1. Generate a 4096-bit RSA private key (password protected)"
fi
echo "2. Create a self-signed root CA certificate valid for 10 years"
echo ""

card_preflight init
echo ""

# Keys are created 0600 rather than 0400 so that a CA can be regenerated in
# place; the one case worth guarding is replacing a CA that has already issued
# certificates, because index.txt and serial still refer to the old one.
if [ -f private/ca-key.pem ] || [ -f certs/ca-cert.pem ]; then
    echo "WARNING: a CA already exists in this directory:"
    [ -f private/ca-key.pem ] && echo "  private/ca-key.pem"
    [ -f certs/ca-cert.pem ] && echo "  certs/ca-cert.pem"
    echo ""
    echo "Replacing it invalidates every certificate already issued from it."
    read -r -p "Type 'replace' to overwrite, anything else to abort: " REPLY
    if [ "$REPLY" != "replace" ]; then
        echo "Aborted. The existing CA was left untouched."
        exit 1
    fi
    echo ""
fi

echo "Step 1: Generating CA private key..."
if [ "$CA_BACKEND" = card ]; then
    [ -z "$CARD_PIN" ] && echo "You will be prompted for the card PIN (possibly more than once)"
    if card_has_ca_key; then
        echo "A key labelled '$CARD_KEY_LABEL' already exists on the card."
        read -r -p "Reuse it for the new CA certificate? (Y/n): " REPLY
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            echo "Aborted. Delete the key with pkcs11-tool or choose another CARD_KEY_LABEL."
            exit 1
        fi
    else
        case "$CARD_KEY_TYPE" in
            rsa:*|RSA:*) echo "Generating $CARD_KEY_TYPE on the card - RSA-4096 takes about 2 minutes..." ;;
            *)           echo "Generating $CARD_KEY_TYPE on the card..." ;;
        esac
        card_tool --login --keypairgen --key-type "$CARD_KEY_TYPE" \
            --id "$CARD_KEY_ID" --label "$CARD_KEY_LABEL"
    fi
    # A file key left over from file mode would be misleading
    rm -f private/ca-key.pem
else
    echo "You will be prompted to enter a passphrase (min 4 characters)"
    openssl genrsa -aes256 -out private/ca-key.pem 4096
    chmod 600 private/ca-key.pem
fi

echo ""
echo "Step 2: Creating self-signed root CA certificate..."
echo "You will be prompted for:"
echo "  - The $CA_SECRET_NAME"
echo "  - Certificate details (Country, State, Organization, etc.)"
echo ""

openssl req -config openssl.cnf \
      "${CA_REQ_KEY_ARGS[@]}" \
      -new -x509 -days 3650 -sha256 -extensions v3_ca \
      -out certs/ca-cert.pem

chmod 644 certs/ca-cert.pem

# Verify the certificate really was signed by the key we just generated.
# `openssl verify` checks the self-signature against the public key embedded
# in the certificate, so this needs no further passphrase prompt.
echo ""
echo "Verifying the CA certificate..."
if ! openssl verify -CAfile certs/ca-cert.pem certs/ca-cert.pem > /dev/null; then
    echo "✗ ERROR: The CA certificate failed self-verification!"
    echo ""
    echo "The certificate does not match the key it was supposedly signed with."
    exit 1
fi
echo "✓ Verification passed: CA certificate is valid and self-signed"

if [ "$CA_BACKEND" = card ]; then
    # Store the certificate next to its key so the card is self-contained
    echo ""
    echo "Writing the CA certificate to the card..."
    openssl x509 -in certs/ca-cert.pem -outform DER -out certs/ca-cert.der
    # pkcs11-tool prompts for the PIN on stdout and reads it with stdout's
    # terminal settings: redirecting stdout of a --login call fails with
    # "util_getpass error", so these calls keep stdout on the terminal.
    # Replace, not add: a previous run may have stored an older CA certificate.
    # Certificates are public objects, so the check itself needs no PIN.
    if card_tool --list-objects --type cert 2>/dev/null \
            | grep -q "label: *${CARD_KEY_LABEL}\$"; then
        echo "Removing the previous CA certificate from the card..."
        card_tool --login --delete-object --type cert --label "$CARD_KEY_LABEL"
    fi
    card_tool --login --write-object certs/ca-cert.der --type cert \
        --id "$CARD_KEY_ID" --label "$CARD_KEY_LABEL"
    rm -f certs/ca-cert.der
    echo "✓ CA certificate stored on the card"

    # Record which card this CA lives on, readable without the card
    write_card_manifest
    echo "✓ Card recorded in $CARD_MANIFEST (serial $(manifest_get token_serial))"
fi

echo ""
echo "=== Root CA Created Successfully ==="
echo ""
echo "Files created:"
if [ "$CA_BACKEND" = card ]; then
    echo "  Private Key: on the card ($CA_KEY_URI)"
    echo "  Card info:   $CARD_MANIFEST (which card holds the key - keep with the backup)"
else
    echo "  Private Key: private/ca-key.pem (KEEP THIS SECURE!)"
fi
echo "  Certificate: certs/ca-cert.pem"
echo ""
echo "To view the certificate:"
echo "  openssl x509 -noout -text -in certs/ca-cert.pem"
echo ""
