# PC/SC access check, sourced by lib/ca-key.sh and card-tools/card-status.sh.
#
# pcscd built with polkit (Debian/Ubuntu) only serves clients in an active
# local login session. WSL2 shells, IDE terminals, ssh and cron are not, so
# pcscd rejects them - and every client (opensc-tool, pkcs11-tool, SAC) then
# reports "no reader" / "no token" instead of "access denied".

PCSC_POLKIT_ACTION=org.debian.pcsc-lite.access_pcsc

# True if polkit refuses this process access to pcscd. Asks polkit the same
# question pcscd asks (no root, no log access needed). False when pcscd runs
# with --disable-polkit, when polkit is not installed, or when it cannot tell.
pcsc_access_denied() {
    command -v pkcheck > /dev/null || return 1
    local pid
    pid=$(pgrep -x pcscd | head -1)
    if [ -n "$pid" ] && tr '\0' ' ' < "/proc/$pid/cmdline" 2> /dev/null | grep -q -- --disable-polkit; then
        return 1
    fi
    pkcheck --action-id "$PCSC_POLKIT_ACTION" --process $$ > /dev/null 2>&1
    case $? in
        1|2|3) return 0 ;;  # not authorized / would need authentication / dismissed
        *)     return 1 ;;  # authorized, or polkit/action unknown
    esac
}

# Explanation lines for a refused client, one per line
pcsc_access_denied_help() {
    echo "pcscd refuses user '$(id -un)' (polkit action $PCSC_POLKIT_ACTION):"
    echo "this shell is not an active local login session (WSL2, IDE terminal, ssh)."
    echo "Readers are hidden, not missing. Allow the user with a polkit rule:"
    echo "  sed \"s/USERNAME/\$USER/\" card-tools/pcscd-polkit.rules | sudo tee /etc/polkit-1/rules.d/49-pcscd-\$USER.rules && sudo systemctl restart polkit pcscd"
    echo "Confirm: journalctl -u pcscd | grep 'NOT authorized'  - see HOWTO_WSL2_SETUP.md"
}
