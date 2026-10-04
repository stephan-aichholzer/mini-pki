#!/bin/bash
# Script to create a self-signed Root CA certificate
#
# CA_BACKEND=file (default): key in private/ca-key.pem, passphrase protected
# CA_BACKEND=card:           key generated on a PKCS#11 smartcard (see pki.conf)

set -e

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
    # Replace, not add: a previous run may have stored an older CA certificate
    card_tool --login --delete-object --type cert --label "$CARD_KEY_LABEL" \
        > /dev/null 2>&1 || true
    card_tool --login --write-object certs/ca-cert.der --type cert \
        --id "$CARD_KEY_ID" --label "$CARD_KEY_LABEL" > /dev/null
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
