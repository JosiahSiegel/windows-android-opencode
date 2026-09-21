<#
.SYNOPSIS
    Finds (and optionally repairs) PATH entries that contain a double-quote character.

.DESCRIPTION
    A stray double quote inside a PATH entry is a subtle and painful Windows defect. Because
    Windows builds many command lines as space-separated strings, a path such as

        C:\Program Files\Some Tool"

    ends the quoting early. When Java tools build a classpath or library path from PATH, the path
    is split and the remainder is parsed as a program argument. The classic symptom is:

        Error: Could not find or load main class Files\Some
        Caused by: java.lang.ClassNotFoundException: Files\Some

    Gradle unit tests, javac, and other forked-JVM tooling then fail for reasons that look
    unrelated to PATH at all.

    This script reports every affected entry in the Machine and User PATH. With -Fix it removes the
    quote characters, backing up the original value first.

.PARAMETER Fix
    Apply the repair. Without it the script only reports.

.PARAMETER Scope
    Which PATH to inspect: Machine, User, or Both. Default Both. Repairing Machine requires an
    elevated shell.

.PARAMETER BackupDirectory
    Where to write the pre-repair values. Defaults to the script directory.

.EXAMPLE
    .\repair-path-quotes.ps1

.EXAMPLE
    # elevated
    .\repair-path-quotes.ps1 -Fix
#>

[CmdletBinding()]
param(
    [switch] $Fix,
    [ValidateSet('Machine', 'User', 'Both')] [string] $Scope = 'Both',
    [string] $BackupDirectory
)

$ErrorActionPreference = 'Stop'

if (-not $BackupDirectory) { $BackupDirectory = $PSScriptRoot }

$quote  = [char]34
$scopes = switch ($Scope) {
    'Both'    { @('Machine', 'User') }
    default   { @($Scope) }
}

$found = 0
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Host ''
Write-Host 'PATH quote audit' -ForegroundColor White
Write-Host ("  elevated: {0}" -f $isAdmin)

foreach ($s in $scopes) {
    $value = [Environment]::GetEnvironmentVariable('Path', $s)

    if (-not $value) {
        Write-Host "  $s`: (not set)"
        continue
    }

    $bad = @($value -split ';' | Where-Object { $_.Contains($quote) })

    if ($bad.Count -eq 0) {
        Write-Host "  $s`: clean" -ForegroundColor Green
        continue
    }

    $found += $bad.Count
    Write-Host "  $s`: $($bad.Count) entry/entries contain a quote" -ForegroundColor Yellow
    foreach ($b in $bad) { Write-Host "      [$b]" }

    if (-not $Fix) { continue }

    if ($s -eq 'Machine' -and -not $isAdmin) {
        Write-Host "      cannot repair Machine scope without an elevated shell" -ForegroundColor Red
        continue
    }

    New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null
    $backup = Join-Path $BackupDirectory ("path-$($s.ToLower())-backup.txt")
    Set-Content -LiteralPath $backup -Value $value -NoNewline

    $repaired = $value.Replace($quote, '')
    [Environment]::SetEnvironmentVariable('Path', $repaired, $s)
    Write-Host "      repaired; original saved to $backup" -ForegroundColor Green
}

Write-Host ''
if ($found -eq 0) {
    Write-Host 'No quoted PATH entries found. Nothing to do.' -ForegroundColor Green
    exit 0
}

if (-not $Fix) {
    Write-Host "Found $found affected entry/entries. Re-run with -Fix to repair." -ForegroundColor Yellow
    Write-Host 'Restart terminals and Gradle daemons afterwards.' -ForegroundColor Yellow
    exit 0
}

Write-Host 'Repair complete. Restart terminals and Gradle daemons.' -ForegroundColor Green
exit 0
