<#
.SYNOPSIS
    Hands a USB smartcard reader from Windows to WSL2 and back (usbipd-win).

.DESCRIPTION
    One command instead of usbipd list / bind / attach / detach / unbind:

      -Detect   (default) list the smartcard readers and who has them
      -Attach   share the reader and attach it to WSL2 (bind is done
                automatically, with --force when a USB filter such as USBPcap
                requires it; Windows asks for administrator rights only then)
      -Detach   detach it from WSL2 and stop sharing it, so Windows can use
                the reader again (asks for administrator rights)

    NAME selects the reader: its BUSID (12-4), VID:PID (076b:3031) or part of
    its name (omnikey). Without NAME the only connected reader is used.

    -Attach, --attach and attach all work. From WSL use the wrapper
    card-tools/smartcard-remote.sh with the same arguments.
    See docs/card-mode-wsl2.md.

.EXAMPLE
    .\Smartcard-Remote.ps1
    Lists the smartcard readers.

.EXAMPLE
    .\Smartcard-Remote.ps1 -Attach
    Hands the only connected reader to WSL2.

.EXAMPLE
    .\Smartcard-Remote.ps1 -Detach omnikey
    Gives the OMNIKEY reader back to Windows.
#>

# No param() block on purpose: interactive PowerShell passes "--attach" as
# plain text, so the arguments are parsed here to accept every spelling.
$ErrorActionPreference = 'Continue'   # 'Stop' turns native stderr into errors in PS 5.1
Set-StrictMode -Version 2

function Fail([string]$message) {
    Write-Host "ERROR: $message" -ForegroundColor Red
    exit 1
}

function Show-Usage {
    Write-Host @"
Usage: Smartcard-Remote.ps1 [-Detect | -Attach | -Detach] [NAME]

  -Detect   list the smartcard readers and who has them (default)
  -Attach   hand the reader to WSL2 (shares it first if needed)
  -Detach   give the reader back to Windows (detach + stop sharing)

  NAME      BUSID (12-4), VID:PID (076b:3031) or part of the reader name
            (omnikey). Optional when only one reader is connected.

-Attach, --attach and attach all work. Details: docs/card-mode-wsl2.md
"@
}

# --- arguments --------------------------------------------------------------
$Action = $null
$Name = $null
foreach ($arg in $args) {
    $word = "$arg".TrimStart('-').ToLower()
    if ($word -in 'detect', 'attach', 'detach', 'help', 'h') {
        if ($Action) { Fail "use only one of -Detect, -Attach, -Detach" }
        $Action = $word
    } elseif ($Name) {
        Fail "unexpected argument '$arg' (see -Help)"
    } else {
        $Name = "$arg"
    }
}
if (-not $Action) { $Action = 'detect' }
if ($Action -in 'help', 'h') { Show-Usage; exit 0 }

# --- usbipd-win -------------------------------------------------------------
$Usbipd = $null
$cmd = Get-Command usbipd.exe -ErrorAction SilentlyContinue
if ($cmd) { $Usbipd = $cmd.Source }
elseif (Test-Path "$env:ProgramFiles\usbipd-win\usbipd.exe") { $Usbipd = "$env:ProgramFiles\usbipd-win\usbipd.exe" }
if (-not $Usbipd) {
    Write-Host "usbipd-win is not installed. It passes USB devices from Windows to WSL2."
    Write-Host "Install it (then open a new PowerShell):"
    Write-Host "  winget install --interactive --exact dorssel.usbipd-win"
    Write-Host "or the .msi from https://github.com/dorssel/usbipd-win/releases/latest"
    Write-Host "Guide: https://learn.microsoft.com/en-us/windows/wsl/connect-usb"
    exit 1
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Runs usbipd with administrator rights - directly when already elevated,
# otherwise through a UAC prompt. Returns the exit code.
function Invoke-UsbipdElevated([string[]]$usbipdArgs) {
    if (Test-Admin) {
        & $Usbipd @usbipdArgs
        return $LASTEXITCODE
    }
    Write-Host "  Windows asks for administrator rights (UAC) for: usbipd $usbipdArgs"
    try {
        $p = Start-Process -FilePath $Usbipd -ArgumentList $usbipdArgs -Verb RunAs `
            -WindowStyle Hidden -Wait -PassThru -ErrorAction Stop
    } catch {
        Fail "administrator rights were not granted - nothing changed"
    }
    return $p.ExitCode
}

# --- devices ----------------------------------------------------------------
function Get-VidPid($instanceId) {
    if ("$instanceId" -match 'VID_([0-9A-Fa-f]{4})&PID_([0-9A-Fa-f]{4})') {
        return ("{0}:{1}" -f $Matches[1], $Matches[2]).ToLower()
    }
    return ''
}

# Vendor and product names from the usb.ids list that ships with usbipd-win
# (Windows calls every CCID reader "Microsoft Usbccid Smartcard Reader").
function Get-UsbNames([string[]]$wanted) {
    $names = @{}
    $file = Join-Path (Split-Path $Usbipd) 'usb.ids'
    if (-not (Test-Path $file) -or -not $wanted) { return $names }
    $vid = $null; $vendor = $null
    foreach ($line in [IO.File]::ReadLines($file)) {
        if ($line -match '^([0-9a-f]{4})\s+(.+)$') {
            $vid = $Matches[1]; $vendor = $Matches[2]
        } elseif ($vid -and $line -match '^\t([0-9a-f]{4})\s+(.+)$') {
            $key = "${vid}:$($Matches[1])"
            if ($wanted -contains $key) {
                $names[$key] = "$vendor $($Matches[2])"
                if ($names.Count -eq $wanted.Count) { break }
            }
        }
    }
    return $names
}

# VID:PIDs Windows has ever installed as smartcard readers
function Get-KnownReaderIds {
    $ids = @()
    foreach ($dev in @(Get-PnpDevice -Class SmartCardReader -ErrorAction SilentlyContinue)) {
        $id = Get-VidPid $dev.InstanceId
        if ($id) { $ids += $id }
    }
    return $ids
}

function Get-Devices {
    $json = & $Usbipd state 2>$null | Out-String
    if ($LASTEXITCODE -ne 0 -or -not $json.Trim()) { Fail "'usbipd state' failed - is the usbipd service running?" }
    $raw = @(($json | ConvertFrom-Json).Devices)
    $ids = @($raw | ForEach-Object { Get-VidPid $_.InstanceId } | Where-Object { $_ } | Select-Object -Unique)
    $names = Get-UsbNames $ids
    $known = Get-KnownReaderIds
    foreach ($d in $raw) {
        $id = Get-VidPid $d.InstanceId
        $label = if ($id -and $names.ContainsKey($id)) { $names[$id] } else { "$($d.Description)" }
        $isReader = ($known -contains $id) -or ("$($d.Description) $label" -match 'smart ?card|ccid|card ?reader|cardman')
        $state =
            if (-not $d.BusId)            { 'not plugged in (still shared)' }
            elseif ($d.ClientIPAddress)   { 'attached to WSL' }
            elseif ($d.PersistedGuid -and $d.IsForced) { 'shared (forced) - Windows cannot use it' }
            elseif ($d.PersistedGuid)     { 'shared, not attached' }
            else                          { 'Windows' }
        [pscustomobject]@{
            BusId = $d.BusId; VidPid = $id; Name = $label; State = $state
            IsReader = $isReader; Attached = [bool]$d.ClientIPAddress
            Shared = [bool]$d.PersistedGuid; Guid = $d.PersistedGuid
        }
    }
}

function Show-Readers($readers) {
    foreach ($r in $readers) {
        $bus = if ($r.BusId) { $r.BusId } else { '-' }
        Write-Host ("  {0,-6} {1,-10} {2,-42} {3}" -f $bus, $r.VidPid, $r.Name, $r.State)
    }
}

# The reader NAME refers to, or the only reader when NAME is empty
function Select-Reader($devices) {
    if ($Name) {
        $n = $Name.ToLower()
        $found = @($devices | Where-Object {
            $_.BusId -eq $Name -or $_.VidPid -eq $n -or $_.Name.ToLower().Contains($n)
        })
        if ($found.Count -eq 0) { Fail "no USB device matches '$Name' - list the readers with -Detect" }
    } else {
        $found = @($devices | Where-Object { $_.IsReader })
        if ($found.Count -eq 0) { Fail "no smartcard reader found - is it plugged in? (all devices: usbipd list)" }
    }
    if ($found.Count -gt 1) {
        Write-Host "Several devices match - name one by BUSID or part of its name:"
        Show-Readers $found
        exit 1
    }
    return $found[0]
}

function Get-RunningWsl {
    $env:WSL_UTF8 = '1'
    $out = & wsl.exe --list --running --quiet 2>$null
    return @($out | ForEach-Object { "$_".Replace("`0", '').Trim() } | Where-Object { $_ })
}

# --- actions ----------------------------------------------------------------
switch ($Action) {
    'detect' {
        $version = (& $Usbipd --version | Select-Object -First 1) -replace '[-+].*$', ''
        $wsl = @(Get-RunningWsl)   # @() - a single result would be a plain string
        $wslText = if ($wsl.Count) { "running ($($wsl -join ', '))" } else { 'not running' }
        Write-Host "usbipd-win $version   WSL: $wslText"
        $readers = @(Get-Devices | Where-Object { $_.IsReader })
        if ($readers.Count -eq 0) {
            Write-Host "No smartcard reader found. Plug it in, or check: usbipd list"
            exit 1
        }
        Write-Host "Smartcard readers:"
        Show-Readers $readers
        if ($readers.Count -eq 1) {
            $hint = if ($readers[0].Attached) { '-Detach  (give it back to Windows)' } else { '-Attach  (hand it to WSL)' }
            Write-Host "Next: $hint"
        }
    }

    'attach' {
        $r = Select-Reader @(Get-Devices)
        if (-not $r.BusId) { Fail "$($r.Name) is not plugged in" }
        if ($r.Attached) { Write-Host "$($r.Name) ($($r.BusId)) is already attached to WSL."; exit 0 }
        if (@(Get-RunningWsl).Count -eq 0) {
            Fail "WSL is not running - open a WSL terminal (it keeps WSL running), then run this again"
        }
        if (-not $r.Shared) {
            Write-Host "Sharing $($r.Name) ($($r.BusId)) with WSL..."
            $bindArgs = @('bind', '--busid', $r.BusId)
            if ((& $Usbipd list 2>&1 | Out-String) -match 'bind --force') {
                $bindArgs += '--force'   # a USB filter such as USBPcap is installed
            }
            $code = Invoke-UsbipdElevated $bindArgs
            if ($code -ne 0) { Fail "usbipd bind failed (exit code $code)" }
        }
        Write-Host "Attaching $($r.Name) ($($r.BusId)) to WSL..."
        & $Usbipd attach --wsl --busid $r.BusId
        if ($LASTEXITCODE -ne 0) { Fail "usbipd attach failed" }
        Write-Host "Done - the reader now belongs to WSL. Check in WSL: card-tools/card-status.sh"
        Write-Host "Repeat -Attach after unplugging the reader or restarting WSL."
    }

    'detach' {
        $r = Select-Reader @(Get-Devices)
        if (-not $r.Attached -and -not $r.Shared) {
            Write-Host "$($r.Name) already belongs to Windows - nothing to do."
            exit 0
        }
        if ($r.Attached) {
            Write-Host "Detaching $($r.Name) ($($r.BusId)) from WSL..."
            & $Usbipd detach --busid $r.BusId
            if ($LASTEXITCODE -ne 0) { Fail "usbipd detach failed" }
        }
        Write-Host "Stop sharing $($r.Name)..."
        $unbindArgs = if ($r.BusId) { @('unbind', '--busid', $r.BusId) } else { @('unbind', '--guid', $r.Guid) }
        $code = Invoke-UsbipdElevated $unbindArgs
        if ($code -ne 0) { Fail "usbipd unbind failed (exit code $code)" }
        Write-Host "Done - Windows owns the reader again. If Windows does not see it, unplug and replug it."
    }
}
