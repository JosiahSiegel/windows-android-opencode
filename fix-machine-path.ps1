# Repairs a malformed machine-level PATH entry:
#
#     C:\Program Files\GitHub CLI"
#
# The trailing double-quote breaks any Java tooling that builds a space-separated command line.
# The concrete symptom is a Gradle unit-test failure such as:
#
#     Error: Could not find or load main class Files\GitHub
#     Caused by: java.lang.ClassNotFoundException: Files\GitHub
#
# because Java splits the unquoted path and treats "Files\GitHub" as the main class.
#
# Run from an ELEVATED PowerShell (Administrator):
#
#     powershell -ExecutionPolicy Bypass -File .\fix-machine-path.ps1
#
# The script backs up the current machine PATH next to itself before changing anything.

$ErrorActionPreference = "Stop"

$quote   = [char]34
$before  = [Environment]::GetEnvironmentVariable("Path", "Machine")
$bad     = "GitHub CLI" + $quote

if (-not $before.Contains($bad)) {
    Write-Host "No malformed PATH entry found. Nothing to do."
    exit 0
}

$backup = Join-Path $PSScriptRoot "machine-path-backup.txt"
Set-Content -Path $backup -Value $before -NoNewline
Write-Host "Backed up the current machine PATH to: $backup"

$after = $before.Replace($bad, "GitHub CLI")

if ($after -eq $before) {
    Write-Host "Replacement produced no change. Aborting."
    exit 1
}

[Environment]::SetEnvironmentVariable("Path", $after, "Machine")

Write-Host ""
Write-Host "Machine PATH repaired."
Write-Host "Entries containing a quote are now:"
($after -split ";" | Where-Object { $_.Contains($quote) } | ForEach-Object { "  [$_]" }) |
    ForEach-Object { Write-Host $_ }
Write-Host ""
Write-Host "Restart any open terminals and Gradle daemons for the change to take effect."
Write-Host "To undo: restore the contents of $backup into the machine Path variable."
