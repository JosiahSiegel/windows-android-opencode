<#
.SYNOPSIS
    Adds Windows Defender exclusions that materially speed up Android builds.

.DESCRIPTION
    Real-time scanning of Gradle caches, the Android SDK, the emulator and downloaded toolchains is
    one of the largest avoidable slowdowns for Android builds on Windows. Because these locations
    contain only caches and toolchain binaries, excluding them is low risk: your source code is
    still scanned.

    The script derives the usual locations from JAVA_HOME, ANDROID_HOME and the user profile, so it
    works on any machine without editing. Exclusions are additive and idempotent.

    Requires an elevated PowerShell.

.PARAMETER Paths
    Extra paths to exclude. Defaults are derived automatically and do not need to be supplied.

.PARAMETER IncludeRepositoryRoot
    Also exclude a repository root such as D:\repos. Off by default: it would exclude your own
    source from scanning. Only appropriate on a dedicated build machine.

.PARAMETER RepositoryRoot
    The repository root to exclude when -IncludeRepositoryRoot is used. Default D:\repos.

.PARAMETER Remove
    Remove the exclusions this script adds, instead of adding them.

.EXAMPLE
    # elevated
    .\add-defender-exclusions.ps1

.EXAMPLE
    # elevated
    .\add-defender-exclusions.ps1 -IncludeRepositoryRoot -RepositoryRoot 'C:\code'

.EXAMPLE
    # elevated
    .\add-defender-exclusions.ps1 -Remove

.NOTES
    Review current exclusions at any time with:
        Get-MpPreference | Select-Object -ExpandProperty ExclusionPath
#>

[CmdletBinding()]
param(
    [string[]] $Paths = @(),
    [switch]   $IncludeRepositoryRoot,
    [string]   $RepositoryRoot = 'D:\repos',
    [switch]   $Remove
)

$ErrorActionPreference = 'Stop'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host ''
    Write-Host 'This script must run in an elevated PowerShell (Administrator).' -ForegroundColor Red
    Write-Host 'Defender preference changes are machine-wide.' -ForegroundColor Red
    exit 1
}

if (-not (Get-Command Get-MpPreference -ErrorAction SilentlyContinue)) {
    Write-Host 'Windows Defender cmdlets are unavailable on this system.' -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------- candidate paths

$candidates = [System.Collections.Generic.List[string]]::new()

# User-scoped caches.
$candidates.Add((Join-Path $env:USERPROFILE '.gradle'))
$candidates.Add((Join-Path $env:USERPROFILE '.android'))

# Android SDK, wherever it lives.
$sdk = [Environment]::GetEnvironmentVariable('ANDROID_HOME', 'User')
if (-not $sdk) { $sdk = [Environment]::GetEnvironmentVariable('ANDROID_HOME', 'Machine') }
if (-not $sdk) { $sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
$candidates.Add($sdk)

# Portable toolchain root, derived from JAVA_HOME when it is set.
$jdk = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'User')
if (-not $jdk) { $jdk = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'Machine') }
if ($jdk) {
    $toolchainRoot = Split-Path -Parent $jdk
    if ($toolchainRoot) { $candidates.Add($toolchainRoot) }
}

foreach ($p in $Paths) { $candidates.Add($p) }

if ($IncludeRepositoryRoot) {
    $candidates.Add($RepositoryRoot)
    Write-Host ''
    Write-Host "WARNING: excluding '$RepositoryRoot' also excludes your source code from scanning." -ForegroundColor Yellow
}

# De-duplicate, keeping order, and drop blanks.
$seen    = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$targets = foreach ($p in $candidates) {
    if ([string]::IsNullOrWhiteSpace($p)) { continue }
    $normalised = $p.TrimEnd('\')
    if ($seen.Add($normalised)) { $normalised }
}

# ---------------------------------------------------------------- apply

$current = @((Get-MpPreference).ExclusionPath)

Write-Host ''
Write-Host $(if ($Remove) { 'Removing Defender exclusions' } else { 'Adding Defender exclusions' }) -ForegroundColor White

foreach ($t in $targets) {
    $exists = $current -contains $t

    if ($Remove) {
        if (-not $exists) {
            Write-Host "  [skip]  not excluded: $t"
            continue
        }
        Remove-MpPreference -ExclusionPath $t -ErrorAction SilentlyContinue
        Write-Host "  [ok]    removed: $t" -ForegroundColor Green
        continue
    }

    if (-not (Test-Path -LiteralPath $t)) {
        Write-Host "  [skip]  does not exist: $t"
        continue
    }
    if ($exists) {
        Write-Host "  [skip]  already excluded: $t"
        continue
    }

    Add-MpPreference -ExclusionPath $t -ErrorAction SilentlyContinue
    Write-Host "  [ok]    excluded: $t" -ForegroundColor Green
}

# ---------------------------------------------------------------- verify

Write-Host ''
Write-Host 'Current Defender exclusion paths:' -ForegroundColor White
(Get-MpPreference).ExclusionPath | ForEach-Object { Write-Host "  $_" }
