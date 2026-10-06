#!/usr/bin/env bash
# WSL2 only: runs card-tools/Smartcard-Remote.ps1 on the Windows side, which
# hands the USB smartcard reader to WSL2 and back via usbipd-win.
# Run with --help for usage.

set -e

usage() {
    cat <<EOF
Usage: $0 [--detect | --attach | --detach] [NAME]

WSL2 only. Moves the USB smartcard reader between Windows and WSL2 with
usbipd-win, by running card-tools/Smartcard-Remote.ps1 on the Windows side:

  --detect   list the smartcard readers and who has them (default)
  --attach   hand the reader to WSL2 (shares it first if needed)
  --detach   give the reader back to Windows (detach + stop sharing)

  NAME       BUSID (12-4), VID:PID (076b:3031) or part of the reader name
             (omnikey). Optional when only one reader is connected.

Sharing and unsharing need administrator rights: Windows shows a UAC prompt
on the desktop. See docs/card-mode-wsl2.md.
EOF
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
esac
if ! command -v powershell.exe > /dev/null || ! command -v wslpath > /dev/null; then
    echo "powershell.exe not found - this helper is for WSL2 with Windows interop." >&2
    exit 1
fi
SCRIPT=$(wslpath -w "$(cd "$(dirname "$0")" && pwd)/Smartcard-Remote.ps1")
exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT" "$@"
