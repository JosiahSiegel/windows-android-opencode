<#
.SYNOPSIS
    Provisions a native-Windows Android development toolchain without needing administrator rights.

.DESCRIPTION
    Installs, into user-writable locations:

      * Temurin JDK (portable zip, no MSI and therefore no elevation)
      * Android SDK command-line tools
      * SDK packages: platform-tools, build-tools, a platform, the emulator, a system image
      * An Android Virtual Device
      * User-scoped JAVA_HOME / ANDROID_HOME / PATH entries
      * %USERPROFILE%\.androidrc so Android CLI runs with consistent flags

    The script is idempotent: already-present components are skipped, so it is safe to re-run and
    safe to use to repair a partially configured machine.

.PARAMETER ToolchainRoot
    Where the portable JDK is installed. Defaults to D:\toolchains when a D: drive exists,
    otherwise %USERPROFILE%\.toolchains.

.PARAMETER SdkPath
    Android SDK location. Defaults to %LOCALAPPDATA%\Android\Sdk (Android Studio's default).

.PARAMETER ApiLevel
    Android API level to install. Default 36.

.PARAMETER BuildTools
    build-tools version to install. Default 36.1.0.

.PARAMETER AvdName
    Name of the AVD to create. Default pixel_api36.

.PARAMETER Device
    avdmanager device profile for the AVD. Default pixel_7.

.PARAMETER SkipAvd
    Do not create an AVD.

.PARAMETER DryRun
    Print the actions that would be taken without downloading or changing anything.

.EXAMPLE
    .\install-toolchain.ps1

.EXAMPLE
    .\install-toolchain.ps1 -ApiLevel 35 -BuildTools 35.0.1 -AvdName pixel_api35

.EXAMPLE
    .\install-toolchain.ps1 -DryRun

.NOTES
    Runs in a normal user shell. Windows Hypervisor Platform (WHPX) is a separate, administrator-
    gated, machine-wide prerequisite for emulator acceleration; see docs/README for the check.
#>

[CmdletBinding()]
param(
    [string] $ToolchainRoot,
    [string] $SdkPath,
    [int]    $ApiLevel      = 36,
    [string] $BuildTools    = '36.1.0',
    [string] $AvdName       = 'pixel_api36',
    [string] $Device        = 'pixel_7',
    [switch] $SkipAvd,
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ---------------------------------------------------------------- helpers

function Write-Step  { param([string]$m) Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok    { param([string]$m) Write-Host "    [ok]   $m" -ForegroundColor Green }
function Write-Skip  { param([string]$m) Write-Host "    [skip] $m" -ForegroundColor DarkGray }
function Write-Note  { param([string]$m) Write-Host "    $m" }

function Get-RemoteFile {
    param([string]$Url, [string]$Destination)
    Write-Note "downloading $Url"
    # curl.exe ships with Windows 10+ and is far faster than Invoke-WebRequest for large files.
    & curl.exe -fSL --retry 3 --retry-delay 2 -o $Destination $Url
    if ($LASTEXITCODE -ne 0) {
        throw "Download failed with exit code $LASTEXITCODE`: $Url"
    }
}

function Expand-Zip {
    param([string]$Zip, [string]$Destination)
    if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Recurse -Force }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Expand-Archive -LiteralPath $Zip -DestinationPath $Destination -Force
}

function Set-UserPathVariable {
    param([string]$Name, [string]$Value)
    [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
    Set-Item -Path "Env:$Name" -Value $Value
}

function Add-UserPathEntry {
    param([string]$Entry)
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($null -eq $current) { $current = '' }
    $parts = $current -split ';' | Where-Object { $_ -ne '' }
    if ($parts -contains $Entry) {
        Write-Skip "PATH already contains $Entry"
    }
    else {
        $updated = (@($Entry) + $parts) -join ';'
        [Environment]::SetEnvironmentVariable('Path', $updated, 'User')
        $env:PATH = $Entry + ';' + $env:PATH
        Write-Ok "added to PATH: $Entry"
    }
}

# ---------------------------------------------------------------- defaults

if (-not $ToolchainRoot) {
    $ToolchainRoot = if (Test-Path 'D:\') { 'D:\toolchains' } else { Join-Path $env:USERPROFILE '.toolchains' }
}
if (-not $SdkPath) {
    $SdkPath = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
}

Write-Host "`nWindows Android toolchain provisioning" -ForegroundColor White
Write-Note "toolchain root : $ToolchainRoot"
Write-Note "Android SDK    : $SdkPath"
Write-Note "API level      : $ApiLevel  (build-tools $BuildTools)"
Write-Note "AVD            : $(if ($SkipAvd) { 'skipped' } else { $AvdName })"
if ($DryRun) { Write-Host "`nDRY RUN - nothing will be downloaded or changed.`n" -ForegroundColor Yellow }

# ---------------------------------------------------------------- 1. JDK

Write-Step 'JDK (Temurin, portable zip)'

$existingJdk = Get-ChildItem -Path $ToolchainRoot -Directory -Filter 'jdk-*' -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1

if ($existingJdk) {
    $jdkHome = $existingJdk.FullName
    Write-Skip "found $jdkHome"
}
elseif ($DryRun) {
    $jdkHome = Join-Path $ToolchainRoot 'jdk-<version>'
    Write-Note "would download the latest Temurin JDK 21 for windows x64 and extract to $ToolchainRoot"
}
else {
    $zip = Join-Path $env:TEMP 'temurin-jdk.zip'
    Get-RemoteFile -Url 'https://api.adoptium.net/v3/binary/latest/21/ga/windows/x64/jdk/hotspot/normal/eclipse' -Destination $zip
    New-Item -ItemType Directory -Path $ToolchainRoot -Force | Out-Null
    Expand-Archive -LiteralPath $zip -DestinationPath $ToolchainRoot -Force
    Remove-Item $zip -Force
    $existingJdk = Get-ChildItem -Path $ToolchainRoot -Directory -Filter 'jdk-*' | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $existingJdk) { throw 'JDK extraction produced no jdk-* directory.' }
    $jdkHome = $existingJdk.FullName
    Write-Ok "installed $jdkHome"
}

# ---------------------------------------------------------------- 2. cmdline-tools

Write-Step 'Android SDK command-line tools'

$cltBin = Join-Path $SdkPath 'cmdline-tools\latest\bin'

if (Test-Path -LiteralPath (Join-Path $cltBin 'sdkmanager.bat')) {
    Write-Skip "already present at $cltBin"
}
elseif ($DryRun) {
    Write-Note "would discover the current commandlinetools-win build and extract it to $cltBin"
}
else {
    Write-Note 'resolving the current command-line tools build from developer.android.com'
    $page = Invoke-WebRequest -Uri 'https://developer.android.com/studio/index.html' -UseBasicParsing
    $match = [regex]::Match($page.Content, 'commandlinetools-win-(\d+)_latest\.zip')
    if (-not $match.Success) { throw 'Could not determine the current command-line tools build number.' }
    $build = $match.Groups[1].Value
    $url   = "https://dl.google.com/android/repository/commandlinetools-win-${build}_latest.zip"
    Write-Note "build $build"

    $zip = Join-Path $env:TEMP 'cmdline-tools.zip'
    Get-RemoteFile -Url $url -Destination $zip

    $staging = Join-Path $env:TEMP 'clt-staging'
    Expand-Zip -Zip $zip -Destination $staging
    Remove-Item $zip -Force

    # The archive contains a top-level 'cmdline-tools' folder which must become 'latest'.
    $parent = Join-Path $SdkPath 'cmdline-tools'
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $target = Join-Path $parent 'latest'
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
    Move-Item -LiteralPath (Join-Path $staging 'cmdline-tools') -Destination $target
    Remove-Item -LiteralPath $staging -Recurse -Force
    Write-Ok "installed to $target"
}

# ---------------------------------------------------------------- 3. environment

Write-Step 'User environment variables'

if ($DryRun) {
    Write-Note "would set JAVA_HOME=$jdkHome"
    Write-Note "would set ANDROID_HOME=$SdkPath"
    Write-Note "would prepend %JAVA_HOME%\bin, $cltBin, $SdkPath\platform-tools and $SdkPath\emulator to PATH"
}
else {
    Set-UserPathVariable -Name 'JAVA_HOME'    -Value $jdkHome
    Write-Ok "JAVA_HOME=$jdkHome"
    Set-UserPathVariable -Name 'ANDROID_HOME' -Value $SdkPath
    Write-Ok "ANDROID_HOME=$SdkPath"

    Add-UserPathEntry (Join-Path $jdkHome 'bin')
    Add-UserPathEntry $cltBin
    Add-UserPathEntry (Join-Path $SdkPath 'platform-tools')
    Add-UserPathEntry (Join-Path $SdkPath 'emulator')
}

# ---------------------------------------------------------------- 4. SDK packages

Write-Step 'Android SDK packages'

$sdkManager = Join-Path $cltBin 'sdkmanager.bat'
$packages = @(
    'platform-tools',
    "build-tools;$BuildTools",
    "platforms;android-$ApiLevel",
    'emulator',
    "system-images;android-$ApiLevel;google_apis;x86_64"
)

if ($DryRun) {
    foreach ($p in $packages) { Write-Note "would install $p" }
}
elseif (-not (Test-Path -LiteralPath $sdkManager)) {
    throw "sdkmanager not found at $sdkManager"
}
else {
    # Licences must be accepted before packages can be installed.
    Write-Note 'accepting SDK licences'
    $yes = ('y' + [Environment]::NewLine) * 50
    $yes | & $sdkManager --licenses | Out-Null

    Write-Note ('installing: ' + ($packages -join ', '))
    $yes | & $sdkManager @packages | Out-Null
    Write-Ok 'packages installed'
}

# ---------------------------------------------------------------- 5. AVD

if (-not $SkipAvd) {
    Write-Step "Android Virtual Device '$AvdName'"

    $avdManager = Join-Path $cltBin 'avdmanager.bat'
    $imagePath  = Join-Path $SdkPath ("system-images\android-$ApiLevel\google_apis\x86_64")

    if ($DryRun) {
        Write-Note "would create AVD '$AvdName' from $Device using system-images;android-$ApiLevel;google_apis;x86_64"
    }
    elseif (-not (Test-Path -LiteralPath $imagePath)) {
        Write-Note "system image not found for API $ApiLevel; skipping AVD creation"
    }
    else {
        $existing = & $avdManager list avd 2>$null | Select-String -SimpleMatch "Name: $AvdName"
        if ($existing) {
            Write-Skip "AVD '$AvdName' already exists"
        }
        else {
            # avdmanager may warn about a missing devices.xml; that warning is harmless.
            'no' | & $avdManager create avd -n $AvdName -k "system-images;android-$ApiLevel;google_apis;x86_64" -d $Device --force | Out-Null
            Write-Ok "created AVD '$AvdName'"
        }
    }
}

# ---------------------------------------------------------------- 6. .androidrc

Write-Step 'Android CLI defaults (.androidrc)'

$androidRc = Join-Path $env:USERPROFILE '.androidrc'

if ($DryRun) {
    Write-Note "would write $androidRc with --no-metrics and --sdk=$SdkPath"
}
elseif (Test-Path -LiteralPath $androidRc) {
    Write-Skip "already exists at $androidRc"
}
else {
    @(
        '--no-metrics'
        "--sdk=$SdkPath"
    ) | Set-Content -LiteralPath $androidRc -Encoding ascii
    Write-Ok "wrote $androidRc"
}

# ---------------------------------------------------------------- summary

Write-Host "`nDone." -ForegroundColor White
if (-not $DryRun) {
    Write-Note 'Open a NEW terminal so the updated environment is inherited, then run:'
    Write-Note '    .\verify-setup.ps1'
    Write-Note ''
    Write-Note 'Emulator acceleration still needs Windows Hypervisor Platform enabled once,'
    Write-Note 'machine-wide and with administrator rights. See the README.'
}
