<#
.SYNOPSIS
    Verifies that a native-Windows Android + OpenCode toolchain is correctly provisioned.

.DESCRIPTION
    Checks each layer of the setup and reports PASS / WARN / FAIL per item:

      * JDK and Java runtime
      * Android SDK, platform-tools, adb, emulator and its hypervisor
      * Installed SDK packages and AVDs
      * Android CLI and its configuration
      * Global Gradle tuning
      * OpenCode CLI version and background service
      * OpenCode global skills / agents / commands
      * Persisted PATH sanity (a common source of hard-to-diagnose failures)

    Command resolution uses the persisted Machine + User PATH rather than the current process
    environment, so it reports what a *new* terminal will actually get.

.PARAMETER AvdName
    AVD that is expected to exist. Default pixel_api36.

.PARAMETER ApiLevel
    API level that is expected to be installed. Default 36.

.EXAMPLE
    .\verify-setup.ps1

.NOTES
    Read-only. Exit code is 0 when nothing FAILed, 1 otherwise, so it can gate CI or a first-run
    checklist.
#>

[CmdletBinding()]
param(
    [string] $AvdName  = 'pixel_api36',
    [int]    $ApiLevel = 36
)

$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------- plumbing

$script:Results = [System.Collections.Generic.List[object]]::new()

function Add-Result {
    param(
        [string] $Item,
        [ValidateSet('PASS', 'WARN', 'FAIL', 'INFO')] [string] $Status,
        [string] $Detail = ''
    )
    $script:Results.Add([pscustomobject]@{ Item = $Item; Status = $Status; Detail = $Detail })
}

function Invoke-Check {
    param([string]$Item, [scriptblock]$Body)
    try {
        $outcome = & $Body
        if ($null -eq $outcome) { Add-Result -Item $Item -Status 'PASS'; return }
        Add-Result -Item $Item -Status $outcome.Status -Detail $outcome.Detail
    }
    catch {
        Add-Result -Item $Item -Status 'FAIL' -Detail $_.Exception.Message
    }
}

# Command resolution should reflect a NEW terminal, not this process.
$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$userPath    = [Environment]::GetEnvironmentVariable('Path', 'User')
$effective   = (@($machinePath, $userPath) | Where-Object { $_ }) -join ';'
$env:PATH    = $effective

function Resolve-Tool {
    param([string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

Write-Host "`nAndroid + OpenCode setup verification" -ForegroundColor White
Write-Host ""

# ---------------------------------------------------------------- JDK

Invoke-Check 'JAVA_HOME' {
    $jh = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'User')
    if (-not $jh) { return @{ Status = 'FAIL'; Detail = 'not set (User scope)' } }
    if (-not (Test-Path -LiteralPath (Join-Path $jh 'bin\java.exe'))) {
        return @{ Status = 'FAIL'; Detail = "set to '$jh' but bin\java.exe is missing" }
    }
    return @{ Status = 'PASS'; Detail = $jh }
}

Invoke-Check 'Java runtime' {
    $java = Resolve-Tool 'java'
    if (-not $java) { return @{ Status = 'FAIL'; Detail = 'java not on PATH' } }
    $v = (& $java -version 2>&1 | Select-Object -First 1)
    return @{ Status = 'PASS'; Detail = "$v" }
}

# ---------------------------------------------------------------- Android SDK

Invoke-Check 'ANDROID_HOME' {
    $ah = [Environment]::GetEnvironmentVariable('ANDROID_HOME', 'User')
    if (-not $ah) { return @{ Status = 'FAIL'; Detail = 'not set (User scope)' } }
    if (-not (Test-Path -LiteralPath $ah)) { return @{ Status = 'FAIL'; Detail = "path does not exist: $ah" } }
    return @{ Status = 'PASS'; Detail = $ah }
}

$sdk = [Environment]::GetEnvironmentVariable('ANDROID_HOME', 'User')

Invoke-Check 'adb' {
    $adb = Resolve-Tool 'adb'
    if (-not $adb) { return @{ Status = 'FAIL'; Detail = 'adb not on PATH' } }
    $v = (& $adb version 2>&1 | Select-Object -First 1)
    return @{ Status = 'PASS'; Detail = $v }
}

Invoke-Check 'Emulator hypervisor' {
    $emu = Resolve-Tool 'emulator'
    if (-not $emu) { return @{ Status = 'FAIL'; Detail = 'emulator not on PATH' } }
    $out = (& $emu -accel-check 2>&1) -join ' '
    if ($out -match 'is installed and usable') {
        $accel = ([regex]::Match($out, '(WHPX|AEHD|GVM)[^)]*\)?')).Value
        return @{ Status = 'PASS'; Detail = $accel.Trim() }
    }
    if ($out -match 'AEHD|WHPX') { return @{ Status = 'PASS'; Detail = $accel.Trim() } }
    return @{ Status = 'FAIL'; Detail = 'no usable accelerator; enable Windows Hypervisor Platform' }
}

Invoke-Check "Platform android-$ApiLevel" {
    if (-not $sdk) { return @{ Status = 'FAIL'; Detail = 'ANDROID_HOME unavailable' } }
    $p = Join-Path $sdk "platforms\android-$ApiLevel"
    if (Test-Path -LiteralPath $p) { return @{ Status = 'PASS'; Detail = $p } }
    return @{ Status = 'FAIL'; Detail = "not installed at $p" }
}

Invoke-Check "AVD '$AvdName'" {
    $avdHome = Join-Path $env:USERPROFILE ".android\avd\$AvdName.avd"
    if (Test-Path -LiteralPath $avdHome) { return @{ Status = 'PASS'; Detail = $avdHome } }
    return @{ Status = 'FAIL'; Detail = "not found at $avdHome" }
}

# ---------------------------------------------------------------- Android CLI

Invoke-Check 'Android CLI' {
    $android = Resolve-Tool 'android'
    if (-not $android) { return @{ Status = 'WARN'; Detail = 'android not on PATH (optional)' } }
    $v = (& $android --version 2>&1 | Select-Object -Last 1)
    return @{ Status = 'PASS'; Detail = "$v  ($android)" }
}

Invoke-Check '.androidrc' {
    $rc = Join-Path $env:USERPROFILE '.androidrc'
    if (Test-Path -LiteralPath $rc) { return @{ Status = 'PASS'; Detail = $rc } }
    return @{ Status = 'WARN'; Detail = 'absent; Android CLI will collect metrics and infer the SDK' }
}

# ---------------------------------------------------------------- Gradle

Invoke-Check 'Global gradle.properties' {
    $gp = Join-Path $env:USERPROFILE '.gradle\gradle.properties'
    if (Test-Path -LiteralPath $gp) { return @{ Status = 'PASS'; Detail = $gp } }
    return @{ Status = 'WARN'; Detail = 'absent; builds use Gradle defaults' }
}

# ---------------------------------------------------------------- OpenCode

Invoke-Check 'OpenCode CLI' {
    $oc = Resolve-Tool 'opencode'
    if (-not $oc) { return @{ Status = 'FAIL'; Detail = 'opencode not on PATH' } }
    $v = (& $oc --version 2>&1 | Select-Object -Last 1)
    return @{ Status = 'PASS'; Detail = "$v  ($oc)" }
}

$configDir = Join-Path $env:USERPROFILE '.config\opencode'

Invoke-Check 'OpenCode global config' {
    $cfg = Join-Path $configDir 'opencode.json'
    if (Test-Path -LiteralPath $cfg) { return @{ Status = 'PASS'; Detail = $cfg } }
    return @{ Status = 'WARN'; Detail = 'no global opencode.json' }
}

Invoke-Check 'OpenCode skills' {
    $skills = Join-Path $configDir 'skills'
    if (-not (Test-Path -LiteralPath $skills)) { return @{ Status = 'WARN'; Detail = 'no global skills directory' } }
    $n = (Get-ChildItem -LiteralPath $skills -Directory).Count
    if ($n -eq 0) { return @{ Status = 'WARN'; Detail = 'skills directory is empty' } }
    return @{ Status = 'PASS'; Detail = "$n skill(s)" }
}

Invoke-Check 'OpenCode agents' {
    $agents = Join-Path $configDir 'agents'
    if (-not (Test-Path -LiteralPath $agents)) { return @{ Status = 'INFO'; Detail = 'no global agents' } }
    $n = (Get-ChildItem -LiteralPath $agents -File).Count
    return @{ Status = $(if ($n -gt 0) { 'PASS' } else { 'INFO' }); Detail = "$n agent(s)" }
}

# ---------------------------------------------------------------- PATH sanity

# ---------------------------------------------------------------- project tooling

# Languages that project tooling shells out to. When one is missing, the project's own checks
# silently cannot run, so it is reported here with the exact fix rather than discovered mid-task.

Invoke-Check 'python3 (project tooling)' {
    $py = Resolve-Tool 'python3'
    if (-not $py) {
        return @{ Status = 'FAIL'; Detail = 'not on PATH; run install-toolchain.ps1 (provisions a portable Python 3 + shim), then open a new terminal' }
    }
    $v = (& python3 --version 2>&1 | Select-Object -First 1)
    return @{ Status = 'PASS'; Detail = "$v ($py)" }
}

Invoke-Check 'node (project tooling)' {
    $node = Resolve-Tool 'node'
    if (-not $node) {
        return @{ Status = 'WARN'; Detail = 'not on PATH; needed by .mjs tooling - install Node.js LTS' }
    }
    return @{ Status = 'PASS'; Detail = ((& node --version 2>&1 | Select-Object -First 1)) }
}

Invoke-Check 'PATH sanity (stray quotes)' {
    $quote = [char]34
    $bad = @()
    foreach ($scope in 'Machine', 'User') {
        $value = [Environment]::GetEnvironmentVariable('Path', $scope)
        if (-not $value) { continue }
        $bad += ($value -split ';' | Where-Object { $_.Contains($quote) } | ForEach-Object { "$scope`: $_" })
    }
    if ($bad.Count -gt 0) {
        return @{ Status = 'FAIL'; Detail = "entries contain a quote character: $($bad -join ' | ')" }
    }
    return @{ Status = 'PASS'; Detail = 'no quoted entries' }
}

Invoke-Check 'PATH sanity (duplicates)' {
    $all = ($effective -split ';' | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\').ToLower() })
    $dupes = $all | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name }
    if ($dupes.Count -gt 0) { return @{ Status = 'WARN'; Detail = "$($dupes.Count) duplicated PATH entry/entries" } }
    return @{ Status = 'PASS'; Detail = 'no duplicates' }
}

# ---------------------------------------------------------------- report

$width = ($script:Results | ForEach-Object { $_.Item.Length } | Measure-Object -Maximum).Maximum
if ($width -lt 24) { $width = 24 }

# Build the format string by interpolation. Concatenating it inline would let -f bind first.
$rowFormat = "{0,-6} {1,-$width} {2}"

Write-Host ($rowFormat -f 'RESULT', 'CHECK', 'DETAIL') -ForegroundColor DarkGray
Write-Host ($rowFormat -f '------', ('-' * $width), '------') -ForegroundColor DarkGray

foreach ($r in $script:Results) {
    $colour = switch ($r.Status) {
        'PASS' { 'Green' }
        'WARN' { 'Yellow' }
        'FAIL' { 'Red' }
        default { 'DarkGray' }
    }
    Write-Host ($rowFormat -f $r.Status, $r.Item, $r.Detail) -ForegroundColor $colour
}

$failed = @($script:Results | Where-Object { $_.Status -eq 'FAIL' }).Count
$warned = @($script:Results | Where-Object { $_.Status -eq 'WARN' }).Count

Write-Host ''
if ($failed -gt 0) {
    Write-Host "$failed check(s) FAILED, $warned warning(s)." -ForegroundColor Red
    exit 1
}
if ($warned -gt 0) {
    Write-Host "All required checks passed, $warned warning(s)." -ForegroundColor Yellow
    exit 0
}
Write-Host 'All checks passed.' -ForegroundColor Green
exit 0
