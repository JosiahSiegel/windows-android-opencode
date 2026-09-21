<#
.SYNOPSIS
    Stops the emulator session opened by start-manual-test.ps1.

.DESCRIPTION
    Finds running emulators through adb and tells them to shut down. By default it only stops
    emulators whose AVD name matches -AvdName, so opening a validation window never shuts down an
    unrelated emulator someone else started.

.PARAMETER AvdName
    AVD name to stop. Default pixel_api36, matching start-manual-test.ps1. Use -All to stop every
    running emulator instead.

.PARAMETER All
    Stop every running emulator, regardless of AVD.

.PARAMETER DryRun
    List what would be stopped without stopping anything.

.EXAMPLE
    .\stop-manual-test.ps1

.EXAMPLE
    .\stop-manual-test.ps1 -All
#>

[CmdletBinding()]
param(
    [string] $AvdName = 'pixel_api36',
    [switch] $All,
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'

function Resolve-AndroidHome {
    if ($env:ANDROID_HOME -and (Test-Path -LiteralPath $env:ANDROID_HOME)) { return $env:ANDROID_HOME }
    $user = [Environment]::GetEnvironmentVariable('ANDROID_HOME', 'User')
    if ($user -and (Test-Path -LiteralPath $user)) { return $user }
    throw 'ANDROID_HOME is not set or does not exist. Run verify-setup.ps1 to see which layer is missing.'
}

function Get-EmulatorSerial {
    param([string] $AdbPath)
    $serials = @()
    $lines = & $AdbPath devices 2>$null
    foreach ($line in $lines) {
        if ($line -match '^(emulator-\d+)\s+device') { $serials += $Matches[1] }
    }
    return $serials
}

function Get-EmulatorAvd {
    param([string] $AdbPath, [string] $Serial)
    $out = (& $AdbPath -s $Serial emu avd name 2>$null) -join ' '
    if ($out -match '([A-Za-z0-9_.-]+)') { return $Matches[1] }
    return ''
}

$AndroidHome = Resolve-AndroidHome
$adb = Join-Path $AndroidHome 'platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $adb)) { throw "adb not found at '$adb'. Run verify-setup.ps1." }

$serials = Get-EmulatorSerial -AdbPath $adb
if (-not $serials -or $serials.Count -eq 0) {
    Write-Host 'No emulator is running.' -ForegroundColor Yellow
    exit 0
}

$stopped = 0
foreach ($serial in $serials) {
    $avd = Get-EmulatorAvd -AdbPath $adb -Serial $serial
    if (-not $All -and $AvdName -and $avd -ne $AvdName) {
        Write-Host "Skipping $serial (AVD '$avd' is not '$AvdName'; use -All to stop it)" -ForegroundColor DarkGray
        continue
    }
    if ($DryRun) {
        Write-Host "Would stop $serial (AVD '$avd')" -ForegroundColor Cyan
        continue
    }
    Write-Host "Stopping $serial (AVD '$avd')" -ForegroundColor Cyan
    & $adb -s $serial emu kill | Out-Null
    $stopped++
}

if ($DryRun) { exit 0 }
Write-Host "Stopped $stopped emulator(s)." -ForegroundColor Green
