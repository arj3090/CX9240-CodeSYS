# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Manufacturing Automation, LLC
<#
  CX9240 one-shot setup, PC side.

  Copies the driver package, the CODESYS runtime packages and the setup script to the
  controller, then runs the setup there. Run it from a normal (not elevated) PowerShell:

      .\Install-CX9240.ps1 -Address 192.168.1.247

  or double-click Install-CX9240.cmd and type the address when asked.

  The controller password is preset to the one a newly imaged controller has
  (user Administrator, password 1), so you are only asked for:
    - your myBeckhoff e-mail and password (on a freshly flashed controller)
  Nothing you type is stored on the PC.

  If the controller's password has been changed, add -AskPassword to type it yourself,
  or -Password <value> to preset a different one.

  Optional parameters:
    -User        login name on the controller (default Administrator)
    -DriverDeb   path to ccat-cx9240-dkms_*_all.deb (default: newest in ..\packaging or here)
    -CodesysRoot CODESYS installation folder (default: newest C:\Program Files\CODESYS 3.5*\CODESYS
                 that contains the "CODESYS Control for Linux ARM64 SL" add-on)
    -KeyFile     SSH private key to use instead of the password
#>
param(
    [Parameter(Mandatory = $true)][string]$Address,
    [string]$User = 'Administrator',
    [string]$DriverDeb,
    [string]$CodesysRoot,
    [string]$KeyFile,
    [string]$Password = '1',     # password of a newly imaged controller
    [switch]$AskPassword         # prompt for the controller password instead of using -Password
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Stop-WithMessage([string]$msg) { Write-Host "`nSTOPPED: $msg" -ForegroundColor Red; exit 1 }
function Find-One([string]$pattern) {
    $f = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
    if ($f) { return $f.FullName }
    return $null
}

# --- driver package
if (-not $DriverDeb) {
    $DriverDeb = Find-One (Join-Path $here 'ccat-cx9240-dkms_*_all.deb')
    if (-not $DriverDeb) { $DriverDeb = Find-One (Join-Path $here '..\packaging\ccat-cx9240-dkms_*_all.deb') }
}
if (-not $DriverDeb -or -not (Test-Path $DriverDeb)) { Stop-WithMessage 'Driver package ccat-cx9240-dkms_*_all.deb not found. Put it next to this script or pass -DriverDeb.' }

# --- CODESYS runtime packages (the same files the IDE's Deploy tool installs)
$rtRel = 'CODESYS Control for Linux ARM64 SL\Delivery\linuxarm64\codesyscontrol_linuxarm64_*_arm64.deb'
if (-not $CodesysRoot) {
    $CodesysRoot = Get-ChildItem 'C:\Program Files\CODESYS 3.5*\CODESYS' -Directory -ErrorAction SilentlyContinue |
        Where-Object { Find-One (Join-Path $_.FullName $rtRel) } |
        Sort-Object FullName | Select-Object -Last 1 -ExpandProperty FullName
}
if (-not $CodesysRoot) { Stop-WithMessage 'No CODESYS installation with the "CODESYS Control for Linux ARM64 SL" add-on was found. Install the add-on, or pass -CodesysRoot.' }

$runtime = Find-One (Join-Path $CodesysRoot $rtRel)
$gateway = Find-One (Join-Path $CodesysRoot 'CODESYS Edge Gateway for Linux\Delivery\edgearm64\codesysedge_edgearm64_*_arm64.deb')
$proxy   = Find-One (Join-Path $CodesysRoot 'CODESYS PrivilegeProxy for Linux\Delivery\proxyarm64\codesysproxy_proxyarm64_*_arm64.deb')
$cm      = Find-One (Join-Path $CodesysRoot 'CODESYS CodeMeter for Linux SL\Delivery\codemeter-lite_*_arm64.deb')
if (-not $runtime) { Stop-WithMessage "CODESYS runtime package not found under $CodesysRoot" }

$script = Join-Path $here 'setup-controller.sh'
if (-not (Test-Path $script)) { Stop-WithMessage 'setup-controller.sh is missing; it must be next to this script.' }

$files = @($script, $DriverDeb, $runtime, $gateway, $proxy, $cm) | Where-Object { $_ }
Write-Host "Controller : $User@$Address"
Write-Host 'Files to copy:'
$files | ForEach-Object { Write-Host ('  ' + (Split-Path -Leaf $_)) }
if (-not $gateway) { Write-Host 'Note: gateway package not found, it will be skipped.' -ForegroundColor Yellow }
if (-not $proxy)   { Write-Host 'Note: privilege proxy package not found, it will be skipped.' -ForegroundColor Yellow }
if (-not $cm)      { Write-Host 'Note: CodeMeter package not found, it will be skipped.' -ForegroundColor Yellow }

$sshArgs = @('-o', 'StrictHostKeyChecking=accept-new')
if ($KeyFile) { $sshArgs += @('-i', $KeyFile) }
$target = "$User@$Address"

# Supply the controller password automatically unless a key or -AskPassword is used.
# OpenSSH has no password option; it can call a helper program instead (SSH_ASKPASS).
$usePreset = (-not $KeyFile) -and (-not $AskPassword)
$askpass = $null
$sudoPart = 'sudo sh ~/cx9240-setup/setup-controller.sh'
if ($usePreset) {
    if ($Password -notmatch '^[A-Za-z0-9._-]+$') { Stop-WithMessage 'The preset password contains characters this script cannot pass on safely. Use -AskPassword instead.' }
    $askpass = Join-Path $env:TEMP ("cx9240-askpass-{0}.cmd" -f $PID)
    Set-Content -Path $askpass -Value "@echo off`r`necho $Password" -Encoding Ascii
    $env:SSH_ASKPASS = $askpass
    $env:SSH_ASKPASS_REQUIRE = 'force'
    $env:DISPLAY = 'none'
    $sshArgs += @('-o', 'NumberOfPasswordPrompts=1', '-o', 'PreferredAuthentications=password,keyboard-interactive')
    # give sudo the password once, then run the setup in the same session
    $sudoPart = "printf '%s\n' '$Password' | sudo -S -p '' -v && " + $sudoPart
    Write-Host "Using the preset controller password. Use -AskPassword to type it instead."
}

try {
    Write-Host "`n--- Copying files" -ForegroundColor Cyan
    & scp @sshArgs @files "${target}:"
    if ($LASTEXITCODE -ne 0) { Stop-WithMessage 'Copy failed. Check the address and that the controller is switched on. If its password is no longer the preset one, run again with -AskPassword.' }

    Write-Host "`n--- Running the setup on the controller" -ForegroundColor Cyan
    $remote = 'rm -rf ~/cx9240-setup && mkdir ~/cx9240-setup && mv ~/setup-controller.sh ~/*.deb ~/cx9240-setup/ && sed -i ''s/\r$//'' ~/cx9240-setup/setup-controller.sh && ' + $sudoPart
    & ssh @sshArgs -t $target $remote
    if ($LASTEXITCODE -ne 0) { Stop-WithMessage 'The setup on the controller did not finish. Read the messages above.' }
}
finally {
    if ($askpass) {
        Remove-Item $askpass -ErrorAction SilentlyContinue
        Remove-Item Env:SSH_ASKPASS, Env:SSH_ASKPASS_REQUIRE, Env:DISPLAY -ErrorAction SilentlyContinue
    }
}

Write-Host "`nDone. Continue in CODESYS (Part 3 of the quick install guide)." -ForegroundColor Green
