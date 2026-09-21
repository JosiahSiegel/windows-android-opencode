<#
.SYNOPSIS
    Opens an interactive emulator session running your current build, for manual validation.

.DESCRIPTION
    The human counterpart to the automated checks. A test run proves behaviour; this proves
    *feel* - thumb reach, wording, whether the flow is obvious after repetition. It boots the
    emulator as a normal window on the desktop, installs the current APK, launches the app and
    prints exactly which build is on screen.

    Click through it like a phone. The window accepts mouse clicks, drags, the scroll wheel and
    the keyboard. Nothing here produces a PASS/FAIL - the verdict is yours.

    Safe to re-run: an already-running emulator is reused, the APK is reinstalled and the app is
    relaunched. The emulator is left running on purpose; stop it with stop-manual-test.ps1.

.PARAMETER ProjectPath
    Android project root. Defaults to the current directory.

.PARAMETER AvdName
    AVD to boot when no emulator is running. Default pixel_api36.

.PARAMETER Apk
    APK to install. Defaults to app\build\outputs\apk\debug\app-debug.apk (or the newest debug APK
    if that exact name is absent) under the project.

.PARAMETER Build
    Run gradlew.bat :app:assembleDebug first, then install the result. Builds before booting the
    emulator, because a full Gradle build and the emulator compete for the CPU.

.PARAMETER Package
    Application id to launch. Normally read from the APK itself; supply it only if aapt is
    unavailable and auto-detection fails.

.PARAMETER Activity
    Activity to launch. Normally read from the APK; defaults to .MainActivity when auto-detection
    cannot find a launcher activity.

.PARAMETER LaunchArgs
    Extra arguments appended to the am start command, for app-specific launch flags such as debug
    scenario extras. Pass one array element per token.

.PARAMETER NoWindow
    Boot headless instead of showing the emulator window. Useful for pre-loading a state before a
    human looks at it, but for manual validation you want the window.

.PARAMETER ColdBoot
    Boot without loading a snapshot, for a deterministic starting state.

.PARAMETER DryRun
    Print what would happen and exit without building, booting, installing or changing anything.

.EXAMPLE
    .\start-manual-test.ps1 -ProjectPath D:\repos\my-app -Build

    Build the current project, install it and open the emulator window.

.EXAMPLE
    .\start-manual-test.ps1 -ProjectPath D:\repos\my-app -LaunchArgs '--es','photo_print_scenario','editor'

    Launch straight into a debug scenario, then hand the window to the person validating.

.NOTES
    Requires the toolchain from install-toolchain.ps1 (JAVA_HOME, ANDROID_HOME, an AVD). If a
    layer is missing, run verify-setup.ps1 to see which one.
#>

[CmdletBinding()]
param(
    [string]   $ProjectPath = (Get-Location).Path,
    [string]   $AvdName     = 'pixel_api36',
    [string]   $Apk,
    [switch]   $Build,
    [string]   $Package,
    [string]   $Activity,
    [string[]] $LaunchArgs  = @(),
    [switch]   $NoWindow,
    [switch]   $ColdBoot,
    [switch]   $DryRun
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- plumbing

function Write-Step {
    param([string] $Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Note {
    param([string] $Message)
    Write-Host "    $Message" -ForegroundColor DarkGray
}

function Resolve-AndroidHome {
    if ($env:ANDROID_HOME -and (Test-Path -LiteralPath $env:ANDROID_HOME)) { return $env:ANDROID_HOME }
    $user = [Environment]::GetEnvironmentVariable('ANDROID_HOME', 'User')
    if ($user -and (Test-Path -LiteralPath $user)) { return $user }
    throw 'ANDROID_HOME is not set or does not exist. Run verify-setup.ps1 to see which layer is missing.'
}

function Resolve-Aapt {
    param([string] $AndroidHome)
    $buildTools = Join-Path $AndroidHome 'build-tools'
    if (-not (Test-Path -LiteralPath $buildTools)) { return $null }
    $versions = Get-ChildItem -LiteralPath $buildTools -Directory | Sort-Object Name -Descending
    foreach ($version in $versions) {
        foreach ($exe in @('aapt2.exe', 'aapt.exe')) {
            $path = Join-Path $version.FullName $exe
            if (Test-Path -LiteralPath $path) { return $path }
        }
    }
    return $null
}

function Resolve-ApkFile {
    param([string] $Root, [string] $Explicit)
    if ($Explicit) {
        if (-not (Test-Path -LiteralPath $Explicit)) { throw "APK not found: $Explicit" }
        return (Resolve-Path -LiteralPath $Explicit).Path
    }
    $debugDir = Join-Path $Root 'app\build\outputs\apk\debug'
    if (-not (Test-Path -LiteralPath $debugDir)) {
        throw "No debug APK directory at '$debugDir'. Run with -Build, or build once first."
    }
    $preferred = Join-Path $debugDir 'app-debug.apk'
    if (Test-Path -LiteralPath $preferred) { return $preferred }
    $newest = Get-ChildItem -LiteralPath $debugDir -Filter '*.apk' |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $newest) { throw "No .apk found under '$debugDir'. Run with -Build." }
    return $newest.FullName
}

function Read-ApkIdentity {
    param([string] $ApkPath, [string] $AaptPath)
    $identity = [pscustomobject]@{ Package = $null; Activity = $null }
    if (-not $AaptPath) { return $identity }
    $badging = (& $AaptPath dump badging $ApkPath 2>$null) -join "`n"
    $pkgMatch = [regex]::Match($badging, "package: name='([^']+)'")
    if ($pkgMatch.Success) { $identity.Package = $pkgMatch.Groups[1].Value }
    $actMatch = [regex]::Match($badging, "launchable-activity: name='([^']+)'")
    if ($actMatch.Success) { $identity.Activity = $actMatch.Groups[1].Value }
    return $identity
}

function Get-EmulatorSerial {
    param([string] $AdbPath)
    $lines = & $AdbPath devices 2>$null
    foreach ($line in $lines) {
        if ($line -match '^(emulator-\d+)\s+device') { return $Matches[1] }
    }
    return $null
}

function Wait-ForBoot {
    param([string] $AdbPath, [string] $Serial, [int] $TimeoutSeconds = 180)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $state = (& $AdbPath -s $Serial shell getprop sys.boot_completed 2>$null) -join ''
        if ($state.Trim() -eq '1') { return $true }
        Start-Sleep -Seconds 3
    }
    return $false
}

# ---------------------------------------------------------------- resolve

$AndroidHome = Resolve-AndroidHome
$adb         = Join-Path $AndroidHome 'platform-tools\adb.exe'
$emulator    = Join-Path $AndroidHome 'emulator\emulator.exe'

if (-not (Test-Path -LiteralPath $adb)) { throw "adb not found at '$adb'. Run verify-setup.ps1." }
if (-not (Test-Path -LiteralPath $emulator)) { throw "emulator not found at '$emulator'. Run verify-setup.ps1." }
if (-not (Test-Path -LiteralPath $ProjectPath)) { throw "Project path not found: $ProjectPath" }

Write-Host "`nManual validation session" -ForegroundColor White
Write-Note "Project: $ProjectPath"
Write-Note "AVD:     $AvdName"

if ($DryRun) {
    Write-Step 'Dry run - nothing will be built, booted, installed or changed'
    $dryApk = Resolve-ApkFile -Root $ProjectPath -Explicit $Apk
    $dryIdentity = Read-ApkIdentity -ApkPath $dryApk -AaptPath (Resolve-Aapt -AndroidHome $AndroidHome)
    Write-Note "Would install: $dryApk"
    Write-Note "Would launch:  $($dryIdentity.Package)/$($dryIdentity.Activity)"
    exit 0
}

# ---------------------------------------------------------------- build first

if ($Build) {
    $running = Get-EmulatorSerial -AdbPath $adb
    if ($running) {
        Write-Host "    warning: an emulator ($running) is already running; a full build competes with it for CPU" -ForegroundColor Yellow
    }
    Write-Step 'Building :app:assembleDebug'
    Push-Location $ProjectPath
    try {
        & (Join-Path $ProjectPath 'gradlew.bat') ':app:assembleDebug' --console=plain
        if ($LASTEXITCODE -ne 0) { throw "Gradle build failed with exit code $LASTEXITCODE" }
    }
    finally {
        Pop-Location
    }
}

$apkPath = Resolve-ApkFile -Root $ProjectPath -Explicit $Apk
$apkHash = (Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash.ToLowerInvariant()

# ---------------------------------------------------------------- boot

$serial = Get-EmulatorSerial -AdbPath $adb
if (-not $serial) {
    if ($NoWindow) { Write-Step "Booting $AvdName (headless)" } else { Write-Step "Booting $AvdName (window)" }
    $emulatorArgs = @('-avd', $AvdName, '-no-boot-anim', '-no-audio')
    if ($NoWindow) { $emulatorArgs += '-no-window' }
    else           { $emulatorArgs += '-gpu'; $emulatorArgs += 'auto' }
    if ($ColdBoot) { $emulatorArgs += '-no-snapshot-load' }
    Start-Process -FilePath $emulator -ArgumentList $emulatorArgs -WindowStyle Normal | Out-Null

    & $adb wait-for-device | Out-Null
    $serial = Get-EmulatorSerial -AdbPath $adb
    if (-not $serial) { throw 'Emulator did not attach to adb.' }
    if (-not (Wait-ForBoot -AdbPath $adb -Serial $serial)) {
        throw "Emulator $serial did not finish booting within the timeout."
    }
}
else {
    Write-Step "Reusing running emulator $serial"
}

# ---------------------------------------------------------------- install + launch

$identity = Read-ApkIdentity -ApkPath $apkPath -AaptPath (Resolve-Aapt -AndroidHome $AndroidHome)
$launchPackage  = if ($Package)  { $Package }  else { $identity.Package }
$launchActivity = if ($Activity) { $Activity } else { $identity.Activity }
if (-not $launchPackage) {
    throw 'Could not read the application id from the APK (aapt not found?). Pass -Package.'
}
if (-not $launchActivity) { $launchActivity = '.MainActivity' }

Write-Step "Installing $(Split-Path -Leaf $apkPath)"
& $adb -s $serial install -r $apkPath
if ($LASTEXITCODE -ne 0) { throw "adb install failed with exit code $LASTEXITCODE" }

Write-Step "Launching $launchPackage/$launchActivity"
$startArgs = @('shell', 'am', 'start', '-n', "$launchPackage/$launchActivity") + $LaunchArgs
& $adb -s $serial @startArgs | Out-Null

# ---------------------------------------------------------------- hand-off

$commit = ''
if (Test-Path -LiteralPath (Join-Path $ProjectPath '.git')) {
    Push-Location $ProjectPath
    try { $commit = (& git rev-parse --short HEAD 2>$null) } finally { Pop-Location }
}

Write-Host "`nReady for manual validation" -ForegroundColor Green
Write-Host "  Serial:  $serial"
Write-Host "  APK:     $apkPath"
Write-Host "  SHA-256: $apkHash"
if ($commit) { Write-Host "  Commit:  $commit" }
Write-Host "  Launched: $launchPackage/$launchActivity"
Write-Host ''
Write-Host '  Click through the emulator window like a phone. Suggested checks:' -ForegroundColor White
Write-Host '    - Can you reach the goal without guessing which control does what?'
Write-Host '    - Is anything clipped, overlapping or unreachable?'
Write-Host '    - After the action, is it obvious what changed?'
Write-Host '    - Does an error or cancellation preserve what it should?'
Write-Host '    - Repeat the main action a few times: is it still pleasant?'
Write-Host ''
Write-Note 'This is a human judgement, not a machine result. Record what you saw, not a PASS/FAIL.'
Write-Note "Stop the session with: .\stop-manual-test.ps1 -AvdName $AvdName"
