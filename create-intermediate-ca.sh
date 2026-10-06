#!/bin/bash
# Create an intermediate CA in the current CA directory, in two steps:
#   request - key pair (file or card) and a certificate request (CSR)
#   install - take the certificate the parent CA issued (sign-intermediate-ca.sh)
# Run with --help for usage.

set -e

usage() {
    cat <<EOF
Usage: $0 request [--card | --file] [--subject DN] [-h | --help]
       $0 install CHAIN.pem [--card | --file]

Creates a CA below another CA (an intermediate or issuing CA). Each CA has a
directory of its own; run this script from inside the new CA's directory,
set up with init-ca-database.sh. Three steps, the middle one at the parent:

  1. here:          $0 request
                    key pair + certs/ca-csr.pem
  2. parent CA dir: sign-intermediate-ca.sh /path/to/certs/ca-csr.pem
                    issues the certificate, writes <name>-ca-chain.pem
  3. here:          $0 install /path/to/<name>-ca-chain.pem
                    checks and installs certs/ca-cert.pem and certs/ca-chain.pem

  request     file mode: a 4096-bit RSA key in private/ca-key.pem, protected
              with a passphrase; card mode: CARD_KEY_TYPE generated on the
              card under CARD_KEY_LABEL / CARD_KEY_ID (or a key with that
              label reused). Then the CSR, signed with that key.
  install     checks that the certificate belongs to this CA's key, is a CA
              certificate and chains up to a root; stores it (card mode: also
              on the card, and records the card in ca-card.manifest).

With the CA keys on different cards, swap cards between the steps - each
step checks that the right card is inserted. Card settings per CA go into a
pki.conf in the CA directory (CARD_TOKEN, CARD_KEY_LABEL, CARD_KEY_ID ...).

EOF
    backend_help
    subject_help
    cat <<EOF
Creates:
  certs/ca-csr.pem       certificate request          (request)
  private/ca-key.pem     CA private key               (request, file mode)
  certs/ca-cert.pem      this CA's certificate        (install)
  certs/ca-chain.pem     this CA up to the root       (install)
  ca-card.manifest       which card holds the key     (install, card mode)

Afterwards the issuing scripts (create-server-cert.sh ...) work in this
directory as in any CA directory.
EOF
}

. "$(dirname "$0")/lib/cli.sh"
CLI_BACKEND_OPTS=1
CLI_VALUE_OPTS="--subject"
parse_cli "$@"
set -- "${ARGS[@]}"
. "$(dirname "$0")/lib/ca-key.sh"
SCRIPTS=$(dirname "$0")

[ -f openssl.cnf ] || {
    echo "No openssl.cnf here - set up this CA directory first: $SCRIPTS/init-ca-database.sh"
    exit 1
}

# Guard against replacing a CA that may already have issued certificates
confirm_replace() {
    echo "WARNING: a CA already exists in this directory ($1)."
    echo "Replacing it invalidates every certificate already issued from it."
    read -r -p "Type 'replace' to overwrite, anything else to abort: " REPLY
    if [ "$REPLY" != "replace" ]; then
        echo "Aborted. The existing CA was left untouched."
        exit 1
    fi
    echo ""
}

# SHA-256 of the public key (DER SubjectPublicKeyInfo) in a certificate
cert_file_pubkey_sha256() {
    openssl x509 -in "$1" -pubkey -noout | openssl pkey -pubin -outform DER \
        | sha256sum | cut -d' ' -f1
}

do_request() {
    [ $# -eq 0 ] || cli_error "request takes no arguments"
    echo "=== Intermediate CA, step 1 of 3: key and certificate request (backend: $CA_BACKEND) ==="
    echo ""
    card_preflight init
    echo ""
    if [ -f certs/ca-cert.pem ]; then
        confirm_replace certs/ca-cert.pem
    elif [ -f private/ca-key.pem ] && [ "$CA_BACKEND" = file ]; then
        confirm_replace private/ca-key.pem
    fi

    echo "Generating the CA key..."
    ca_key_create
    echo ""

    echo "Creating the certificate request..."
    echo "You will be prompted for the $CA_SECRET_NAME"
    [ -n "${CLI_OPT[--subject]:-}" ] || echo "and the certificate details (Country, State, Organization, etc.)"
    local subject_args=()
    [ -n "${CLI_OPT[--subject]:-}" ] && subject_args=(-subj "${CLI_OPT[--subject]}")
    openssl req -config openssl.cnf -new -sha256 \
        "${CA_REQ_KEY_ARGS[@]}" "${subject_args[@]}" \
        -out certs/ca-csr.pem
    openssl req -verify -noout -in certs/ca-csr.pem 2>/dev/null \
        || { echo "✗ ERROR: the certificate request does not verify"; exit 1; }
    echo "✓ certs/ca-csr.pem: $(openssl req -noout -subject -in certs/ca-csr.pem)"

    echo ""
    echo "=== Next steps ==="
    echo "2. In the parent CA's directory (insert the parent's card first, if on a card):"
    echo "     $SCRIPTS/sign-intermediate-ca.sh $(pwd)/certs/ca-csr.pem"
    echo "3. Back here (with this CA's card inserted, if on a card):"
    echo "     $SCRIPTS/create-intermediate-ca.sh install <the -ca-chain.pem file from step 2>"
}

do_install() {
    [ $# -eq 1 ] || cli_error "install needs the chain file from sign-intermediate-ca.sh"
    local chain=$1 tmp first root n
    [ -f "$chain" ] || { echo "Not found: $chain"; exit 1; }
    echo "=== Intermediate CA, step 3 of 3: install the certificate (backend: $CA_BACKEND) ==="
    echo ""
    card_preflight init
    if [ "$CA_BACKEND" = card ] && ! card_has_ca_key; then
        preflight_fail "key '$CARD_KEY_LABEL' is not on this card" \
            "Insert this CA's card (not the parent's), or check CARD_KEY_LABEL in pki.conf"
    fi
    if [ "$CA_BACKEND" = file ] && [ ! -f private/ca-key.pem ]; then
        echo "No private/ca-key.pem here - run '$0 request' first, or use --card"
        exit 1
    fi
    echo ""

    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    n=$(grep -c -- '-----BEGIN CERTIFICATE-----' "$chain" || true)
    [ "$n" -ge 2 ] || { echo "✗ $chain must hold this CA's certificate and its parents up to the root"; exit 1; }
    first=$tmp/first.pem
    root=$tmp/root.pem
    openssl x509 -in "$chain" -out "$first"
    last_cert "$chain" > "$root"
    echo "Certificate: $(openssl x509 -noout -subject -in "$first")"
    echo "Issued by:   $(openssl x509 -noout -issuer -in "$first")"
    echo "Valid until: $(openssl x509 -noout -enddate -in "$first" | sed 's/^notAfter=//')"
    echo "Root:        $(openssl x509 -noout -subject -in "$root")"
    echo ""

    echo "Checking..."
    if [ "$(cert_file_pubkey_sha256 "$first")" != "$(ca_key_pubkey_sha256)" ]; then
        echo "✗ The certificate does not belong to this CA's key"
        [ "$CA_BACKEND" = card ] && echo "  (card key '$CARD_KEY_LABEL') - wrong card or wrong chain file?"
        exit 1
    fi
    echo "  ✓ certificate belongs to this CA's key"
    if ! openssl x509 -noout -ext basicConstraints -in "$first" 2>/dev/null | grep -q "CA:TRUE"; then
        echo "✗ The certificate is not a CA certificate (basicConstraints CA:TRUE missing)"
        exit 1
    fi
    echo "  ✓ CA certificate ($(openssl x509 -noout -ext basicConstraints -in "$first" | tail -1 | sed 's/^ *//'))"
    if [ "$(openssl x509 -noout -subject -in "$root")" != "$(openssl x509 -noout -issuer -in "$root" | sed 's/^issuer=/subject=/')" ]; then
        echo "✗ The last certificate in $chain is not a self-signed root"
        exit 1
    fi
    if ! openssl verify -CAfile "$root" -untrusted "$chain" "$first" > /dev/null; then
        echo "✗ The certificate does not verify up to the root in $chain"
        exit 1
    fi
    echo "  ✓ chain verifies up to the root"
    echo ""

    if [ -f certs/ca-cert.pem ] && ! cmp -s "$first" certs/ca-cert.pem; then
        confirm_replace certs/ca-cert.pem
    fi
    cp "$first" certs/ca-cert.pem
    cp "$chain" certs/ca-chain.pem
    chmod 644 certs/ca-cert.pem certs/ca-chain.pem
    echo "✓ Installed certs/ca-cert.pem and certs/ca-chain.pem"
    if [ "$CA_BACKEND" = card ]; then
        ca_cert_to_card
    fi

    echo ""
    echo "=== Intermediate CA ready ==="
    echo "Issue certificates from this directory, e.g. $SCRIPTS/create-server-cert.sh <hostname>"
    echo "Check the chain: openssl verify -CAfile certs/ca-chain.pem certs/ca-cert.pem"
}

case "${1:-}" in
    request) shift; do_request "$@" ;;
    install) shift; do_install "$@" ;;
    "")      cli_error "say 'request' or 'install'" ;;
    *)       cli_error "unknown step '$1' - 'request' or 'install'" ;;
esac
