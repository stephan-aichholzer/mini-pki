# Locate the OpenSSL pkcs11 provider (pkcs11.so), sourced by lib/ca-key.sh
# and card-tools/card-status.sh.
#
# Order:
#   1. PKCS11_PROVIDER_DIR from pki.conf / environment
#   2. card-tools/pkcs11-provider/ - built by card-tools/build-pkcs11-provider.sh
#   3. OpenSSL's system module directory (e.g. apt install pkcs11-provider)
#
# Sets PROVIDER_SO (the file, whether or not it exists) and PROVIDER_DIR
# (empty when the system directory is used, so no -provider-path is needed).

resolve_pkcs11_provider() {
    local local_dir="$PKI_DIR/card-tools/pkcs11-provider"
    if [ -n "$PKCS11_PROVIDER_DIR" ]; then
        PROVIDER_DIR=$PKCS11_PROVIDER_DIR
    elif [ -f "$local_dir/pkcs11.so" ]; then
        PROVIDER_DIR=$local_dir
    else
        PROVIDER_DIR=
    fi
    if [ -n "$PROVIDER_DIR" ]; then
        PROVIDER_SO="$PROVIDER_DIR/pkcs11.so"
    else
        PROVIDER_SO="$(openssl version -m | sed 's/^MODULESDIR: "\(.*\)"$/\1/')/pkcs11.so"
    fi
}
