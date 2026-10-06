# Common command-line handling, sourced by the scripts before lib/ca-key.sh.
#
# A script defines usage() (printing its help text), sources this file and
# calls parse_cli "$@". parse_cli
#   - prints usage() and exits for -h / --help,
#   - handles --card / --file when the script set CLI_BACKEND_OPTS=1,
#   - takes value options listed in CLI_VALUE_OPTS (e.g. "--subject --days"),
#     as "--days 30" or "--days=30", into the CLI_OPT array (CLI_OPT[--days]),
#   - rejects unknown options,
#   - leaves the positional arguments in the ARGS array.
# Options may appear anywhere; "--" ends option parsing.
#
# --card / --file set CLI_CA_BACKEND, which lib/ca-key.sh applies after
# reading pki.conf, so the command line wins over pki.conf and environment.

parse_cli() {
    ARGS=()
    declare -gA CLI_OPT=()
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            --card|--file)
                [ "${CLI_BACKEND_OPTS:-0}" = 1 ] || cli_error "unknown option $1"
                CLI_CA_BACKEND=${1#--}
                ;;
            --)
                shift
                ARGS+=("$@")
                break
                ;;
            --?*)
                local name=${1%%=*}
                [[ " ${CLI_VALUE_OPTS:-} " == *" $name "* ]] || cli_error "unknown option $1"
                if [[ $1 == *=* ]]; then
                    CLI_OPT[$name]=${1#*=}
                else
                    [ $# -gt 1 ] || cli_error "$1 needs a value"
                    CLI_OPT[$name]=$2
                    shift
                fi
                ;;
            -?*)
                cli_error "unknown option $1"
                ;;
            *)
                ARGS+=("$1")
                ;;
        esac
        shift
    done
}

cli_error() {
    echo "Error: $1" >&2
    echo "Run '$0 --help' for usage." >&2
    exit 2
}

# Help section for scripts that use the CA key
backend_help() {
    local current
    current=$(CA_BACKEND=${CA_BACKEND:-} && . "$(dirname "${BASH_SOURCE[0]}")/../pki.conf" \
        2>/dev/null && { [ ! -f pki.conf ] || . ./pki.conf 2>/dev/null; } && echo "$CA_BACKEND")
    cat <<EOF
CA key backend:
  --card        use the CA key on the smartcard (card mode)
  --file        use the passphrase-protected private/ca-key.pem (file mode)
                Default: CA_BACKEND from pki.conf or the environment
                (currently: ${current:-file}). Card settings live in pki.conf -
                the repository's, plus a pki.conf in this CA directory if any.

EOF
}

# Help section for scripts that take --subject
subject_help() {
    cat <<EOF
  --subject DN  the certificate subject, e.g. "/C=AT/O=Example/CN=Example CA",
                instead of the interactive prompts

EOF
}
