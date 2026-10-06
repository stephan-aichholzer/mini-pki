# HOWTO: Card mode under WSL2

How to use a USB smartcard reader with a Thales IDPrime 940 and the SafeNet
Authentication Client (SAC) from mini-pki running in WSL2. The general card
mode setup is in [card-mode.md](card-mode.md); this
document covers what is different on WSL2.

**Short version:** set up once (steps 1-8), then moving the reader between
Windows and WSL is one command -
`card-tools/smartcard-remote.sh --attach` / `--detach`, see
[Moving the reader between Windows and WSL](#moving-the-reader-between-windows-and-wsl).

Tested 2026-10-06: Windows 11, usbipd-win 5.3, WSL2 kernel 6.18, Ubuntu 24.04,
pcscd 2.0.3, OpenSC 0.25, SAC 10.9 R1 (core), HID OMNIKEY 3021 reader,
IDPrime 940.

## Why it does not just work

WSL2 is a virtual machine. Two things stand between the card and mini-pki:

1. **USB is not passed through.** Windows owns the reader. It has to be
   handed to the WSL2 VM over USB/IP with
   [usbipd-win](https://github.com/dorssel/usbipd-win), which is not part of
   Windows or WSL and must be installed separately.
2. **pcscd refuses the client.** On Ubuntu, pcscd asks polkit whether the
   caller may use the card, and polkit only says yes to an *active local
   login session*. WSL shells, IDE terminals (VS Code), ssh and cron are not
   one. pcscd silently rejects them, and every tool then claims **"No smart
   card readers found"** - even with the reader attached. The pcscd log shows
   the real reason: `journalctl -u pcscd | grep 'NOT authorized'`.

The chain, from the card to mini-pki:

| Layer | Where | Provided by |
|---|---|---|
| Reader + card | Windows USB | hardware |
| USB/IP server | Windows | usbipd-win (`usbipd bind`, `usbipd attach`) |
| USB/IP client | WSL2 kernel | `vhci_hcd` module (loaded by `usbipd attach`) |
| PC/SC daemon | WSL2 | `pcscd` + `libccid`, access controlled by **polkit** |
| PKCS#11 module | WSL2 | SAC `/usr/lib/libeTPkcs11.so` (OpenSC optional) |
| OpenSSL provider | mini-pki | `card-tools/pkcs11-provider/pkcs11.so` |

## Step 1 - Check the prerequisites

| Requirement | Check | Fix |
|---|---|---|
| Windows 11 (or Windows 10 with WSL from the Microsoft Store) | `winver` | Windows Update |
| Distribution runs as WSL **2** | PowerShell: `wsl -l -v` | `wsl --set-version Ubuntu 2` |
| WSL kernel 5.10.60.1 or newer | WSL: `uname -r` | PowerShell: `wsl --shutdown`, then `wsl --update` |
| systemd enabled in WSL | WSL: `ps -p 1 -o comm=` prints `systemd` | see below |

pcscd and the SAC service are started by systemd. If `ps -p 1 -o comm=`
prints `init` instead of `systemd`, enable it and restart WSL:

```bash
sudo sh -c 'printf "[boot]\nsystemd=true\n" >> /etc/wsl.conf'
```
```powershell
wsl --shutdown
```

## Step 2 - Windows: install usbipd-win

Check first - in PowerShell:

```powershell
usbipd --version
```

If the command is not found, install it, either with winget:

```powershell
winget install --interactive --exact dorssel.usbipd-win
```

or with the `.msi` installer from the
[usbipd-win releases page](https://github.com/dorssel/usbipd-win/releases/latest).
Use `--interactive`: otherwise winget may restart Windows without asking if
the driver installation needs it. Open a **new** PowerShell afterwards so
`usbipd` is on the PATH.

References:
- Microsoft: [Connect USB devices to WSL](https://learn.microsoft.com/en-us/windows/wsl/connect-usb)
  (official guide, includes the steps below)
- [usbipd-win README](https://github.com/dorssel/usbipd-win) and its
  [WSL support wiki](https://github.com/dorssel/usbipd-win/wiki/WSL-support)

From inside WSL the tool is reachable as
`"/mnt/c/Program Files/usbipd-win/usbipd.exe"`.

## Step 3 - Windows: share the reader (once, as administrator)

> **Shortcut:** `card-tools/smartcard-remote.sh --attach` does steps 3 and 7
> in one go, including `--force` and the administrator prompt - see
> [Moving the reader](#moving-the-reader-between-windows-and-wsl). The manual
> commands below show what it does; skip to step 4 if you use it.

Open PowerShell **as administrator** (Start menu, right-click *Windows
PowerShell* -> *Run as administrator*) and list the USB devices:

```powershell
usbipd list
```

The reader shows up as a smartcard reader, e.g.:

```
BUSID  VID:PID    DEVICE                                        STATE
12-4   076b:3031  Microsoft Usbccid Smartcard Reader (WUDF)     Not shared
```

Note its **BUSID** (`12-4` here; yours will differ) and share it:

```powershell
usbipd bind --busid 12-4
```

If `usbipd list` printed a warning like *"USB filter 'USBPcap' is known to be
incompatible with this software; 'bind --force' will be required"* (USBPcap
comes with Wireshark), use:

```powershell
usbipd bind --busid 12-4 --force
```

`usbipd list` now shows the state `Shared` (or `Shared (forced)`). Binding is
remembered across reboots. The BUSID belongs to the USB port: plug the reader
into another port and it gets a new BUSID that must be bound again.

**Windows loses the reader.** While attached to WSL, Windows cannot use it
(no Windows smartcard login, no SAC on Windows). With `--force`, Windows
cannot use it until you undo the binding:

```powershell
usbipd unbind --busid 12-4
```

## Step 4 - WSL: smartcard stack

```bash
sudo apt install pcscd libccid opensc
```

Optional, for debugging: `pcsc-tools` (`pcsc_scan`) and `usbutils` (`lsusb`).

## Step 5 - WSL: SafeNet Authentication Client

SAC comes from Thales or the card supplier as a zip (e.g.
`SAC_10.9._R1_GA_Linux.zip`). It is licensed for use with the purchased
cards and **must not be redistributed** - keep it outside this repository
(mini-pki ignores `*.deb`, `*.rpm` and `SAC_*.zip` as a safety net), do not
commit it and do not put it into a Docker image. On WSL use the **core** package from
`Ubuntu/Installation/withoutUI/` - it has no graphical tools and only needs
`libssl3`, `libpcsclite1` and `pcscd`. Extract it (no `unzip` needed):

```bash
mkdir -p ~/sac && python3 -m zipfile -e SAC_10.9._R1_GA_Linux.zip ~/sac/
```

Compare the package checksum with the one Thales ships next to it - the two
hashes must be identical:

```bash
cd ~/sac/"SAC 10.9. R1 GA Linux/Ubuntu/Installation/withoutUI/Ubuntu" && sha256sum *core*.deb && cat *core*.sha256sum.txt
```

Install it (`./` makes apt treat it as a file):

```bash
sudo apt install ./610-013349-004_RevB_safenetauthenticationclient-core_10.9.6885_amd64.deb
```

A final note *"Download is performed unsandboxed as root ... couldn't be
accessed by user '_apt'"* is harmless. The package installs
`/usr/lib/libeTPkcs11.so` and starts the `SACSrv` service:

```bash
systemctl is-active SACSrv
```

The SAC Linux manuals (release notes, user and administrator guide) are in
the zip under `Documentation/`.

## Step 6 - WSL: let your user talk to pcscd (polkit)

`card-tools/pcscd-polkit.rules` allows exactly one user to use pcscd without
a login session. Install it for your user and restart polkit and pcscd - one
line, run from the mini-pki directory:

```bash
sed "s/USERNAME/$USER/" card-tools/pcscd-polkit.rules | sudo tee /etc/polkit-1/rules.d/49-pcscd-$USER.rules && sudo systemctl restart polkit pcscd
```

Check - this asks polkit the same question pcscd asks:

```bash
pkcheck --action-id org.debian.pcsc-lite.access_pcsc --process $$ && echo allowed
```

Alternative: start pcscd with `--disable-polkit` (`PCSCD_ARGS=--disable-polkit`
in `/etc/default/pcscd`). That opens pcscd to **every** local user and
process; the rule above is narrower.

## Step 7 - Attach the reader to WSL

Easiest: `card-tools/smartcard-remote.sh --attach` - see
[Moving the reader](#moving-the-reader-between-windows-and-wsl). By hand, no
administrator needed. From PowerShell:

```powershell
usbipd attach --wsl --busid 12-4
```

or the same from inside WSL:

```bash
"/mnt/c/Program Files/usbipd-win/usbipd.exe" attach --wsl --busid 12-4
```

`usbipd list` now shows `Attached`, and in WSL:

```bash
opensc-tool -l
```

lists the reader, with `Yes` in the *Card* column when a card is inserted.

**The attachment does not survive** unplugging the reader, `wsl --shutdown`
or a Windows restart - run `attach` again. To re-attach automatically while
a PowerShell window stays open:

```powershell
usbipd attach --wsl --busid 12-4 --auto-attach
```

Give the reader back to Windows without unplugging it:

```powershell
usbipd detach --busid 12-4
```

## Step 8 - Set up mini-pki card mode

From here on everything is as on native Linux - continue with the
[card-mode.md](card-mode.md):

```bash
card-tools/setup.sh
```

It builds the OpenSSL pkcs11 provider and the Python card tools inside the
project and ends with `card-tools/card-status.sh`, which must report
*All checks passed*.

## Moving the reader between Windows and WSL

`card-tools/Smartcard-Remote.ps1` wraps the usbipd commands of steps 3 and 7.
It finds the reader by itself, shares it with `--force` when a USB filter
requires it, and asks for administrator rights (a UAC prompt on the desktop)
only for sharing and unsharing.

From WSL, through the wrapper:

```bash
card-tools/smartcard-remote.sh             # which readers, and who has them
card-tools/smartcard-remote.sh --attach    # hand the reader to WSL
card-tools/smartcard-remote.sh --detach    # give it back to Windows
```

From PowerShell (no administrator window needed), with the project path as
Windows sees it - for `~/mini-pki` in the distribution `Ubuntu`:

```powershell
powershell -ExecutionPolicy Bypass -File \\wsl.localhost\Ubuntu\home\<you>\mini-pki\card-tools\Smartcard-Remote.ps1 -Attach
```

`-ExecutionPolicy Bypass` is only needed when Windows blocks scripts
(*"running scripts is disabled on this system"*). `-Attach`, `--attach` and
`attach` all work.

| Action | What it does |
|---|---|
| `--detect` (default) | Lists the smartcard readers with BUSID, VID:PID, name and state: `Windows`, `shared, not attached`, `shared (forced) - Windows cannot use it`, `attached to WSL` |
| `--attach [NAME]` | Shares the reader if needed (UAC prompt), then attaches it to WSL. WSL must be running - run it from a WSL terminal or keep one open |
| `--detach [NAME]` | Detaches it from WSL and stops sharing it (UAC prompt), so Windows can use it again |

`NAME` is the BUSID (`12-4`), the VID:PID (`076b:3031`) or part of the reader
name (`omnikey`); without it the only connected reader is used. Reader names
come from the USB ID list that ships with usbipd-win, because Windows calls
every reader *"Microsoft Usbccid Smartcard Reader"*:

```
usbipd-win 5.3.0   WSL: running (Ubuntu)
Smartcard readers:
  12-4   076b:3031  OmniKey AG 3x21 Smart Card Reader          attached to WSL
Next: -Detach  (give it back to Windows)
```

After unplugging the reader or restarting WSL, run `--attach` again.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Smartcard-Remote.ps1`: *administrator rights were not granted* | The UAC prompt was declined or not answered - run it again and confirm the prompt |
| *running scripts is disabled on this system* | Windows execution policy - run it as `powershell -ExecutionPolicy Bypass -File ...Smartcard-Remote.ps1`, or use the WSL wrapper `card-tools/smartcard-remote.sh` |
| `usbipd: command not found` / not recognized | usbipd-win not installed (step 2), or PowerShell opened before the installation - open a new one |
| `usbipd list` warns about `USBPcap` or another filter | `usbipd bind --busid <BUSID> --force` (step 3) |
| `attach` fails because the device is not shared | Run `usbipd bind` as administrator first (step 3); after moving the reader to another USB port its BUSID changed |
| `attach` fails because no WSL 2 distribution is running | Open a WSL terminal first, then attach |
| `card-status.sh`: *pcscd refuses access - readers are hidden, not missing* | polkit rule missing (step 6) |
| *No smart card readers found* / *no reader found* | Reader not attached (step 7) - or pcscd refuses access: `journalctl -u pcscd \| grep 'NOT authorized'` (step 6) |
| Reader worked, then gone | Reader unplugged, WSL restarted or Windows rebooted - attach again (step 7) |
| `pcscd is not running` | systemd not enabled in WSL (step 1); `sudo systemctl start pcscd.socket` |
| `pkcs11-tool --module /usr/lib/libeTPkcs11.so -L` shows only `(empty)` slots | SAC works, but no reader reached pcscd - steps 6 and 7 |
| `/usr/lib/libeTPkcs11.so not found` | SAC not installed (step 5) |
| Windows smartcard login or Windows SAC stopped working | The reader belongs to WSL: `usbipd detach`, or `usbipd unbind` after `--force` (step 3) |

For card problems that are not WSL specific (expired factory PIN, key types,
wrong card) see [card-mode.md](card-mode.md#troubleshooting).
