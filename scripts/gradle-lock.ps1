<#
.SYNOPSIS
    Run a command while holding a per-project build lock, so concurrent agents cannot corrupt a
    shared Gradle output tree.

.DESCRIPTION
    Two Gradle invocations against the same project share app/build/... . When their tasks
    interleave - or one is killed mid-write - they leave truncated shared artifacts (a corrupt
    test-results binary, a half-written jar). Those then look like code failures and send the agent
    chasing a bug that does not exist. That is an environment defect: the fix is to serialise
    builds, and it applies whenever more than one agent or session may build the same checkout.

    A named system Mutex provides a lock across processes, so it holds between separate agent
    sessions on the same machine. The name is derived from the project directory, so different
    projects still build in parallel; only builds of the *same* checkout serialise.

.PARAMETER Command
    Command line to run under the lock, e.g. '.\gradlew.bat :app:testDebugUnitTest --rerun-tasks'.

.PARAMETER TimeoutSeconds
    How long to wait for the lock before failing. Default 1800.

.EXAMPLE
    ./gradle-lock.ps1 -Command '.\gradlew.bat :app:testDebugUnitTest --console=plain'

.EXAMPLE
    ./gradle-lock.ps1 '.\gradlew.bat :app:lintDebug'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string] $Command,

    [int] $TimeoutSeconds = 1800
)

$ErrorActionPreference = 'Stop'

# Stable per-project name: .NET string hashing is randomised per process, so it cannot be used here.
$directory = (Get-Location).Path.ToLowerInvariant()
$sha = [System.Security.Cryptography.SHA256]::Create()
try {
    $digest = [BitConverter]::ToString(
        $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($directory))
    ).Replace('-', '')
} finally {
    $sha.Dispose()
}
$mutexName = "Global\android-gradle-$digest"

$mutex = [System.Threading.Mutex]::new($false, $mutexName)
$acquired = $false
$exitCode = 1
try {
    try {
        $acquired = $mutex.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))
    } catch [System.Threading.AbandonedMutexException] {
        # The previous holder died without releasing; the lock is ours now.
        $acquired = $true
    }
    if (-not $acquired) {
        throw "Timed out after ${TimeoutSeconds}s waiting for the build lock for '$directory'. Another build is still running."
    }
    Write-Host "[gradle-lock] lock held for $directory" -ForegroundColor DarkCyan
    # Run in-process: shelling out to cmd.exe corrupts redirected output (and emits a spurious
    # "memory-mapped stream" error when stdout is a file), which is worse than useless for a tool
    # whose whole job is to make build output trustworthy.
    & ([scriptblock]::Create($Command))
    $exitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
} finally {
    if ($acquired) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
exit $exitCode
