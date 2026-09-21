# Windows Defender exclusions for Android build performance.
#
# Real-time scanning of Gradle caches, the SDK and the emulator is one of the largest avoidable
# slowdowns for Android builds on Windows.
#
# Run from an ELEVATED PowerShell (Administrator):
#
#     powershell -ExecutionPolicy Bypass -File .\add-defender-exclusions.ps1
#
# To review or undo later:
#     Get-MpPreference | Select-Object -ExpandProperty ExclusionPath
#     Remove-MpPreference -ExclusionPath "<path>"

$ErrorActionPreference = "Continue"

# Safe, high-value exclusions: caches and toolchains, not your source code.
$paths = @(
    "$env:USERPROFILE\.gradle",
    "$env:USERPROFILE\.android",
    "$env:LOCALAPPDATA\Android\Sdk",
    "D:\toolchains"
)

# Optional and deliberately NOT enabled by default.
# Excluding your whole repository root also excludes your source from scanning. Only uncomment
# this if you accept that trade-off, for example on a dedicated build machine.
#
# $paths += "D:\repos"

foreach ($p in $paths) {
    if (Test-Path -LiteralPath $p) {
        Add-MpPreference -ExclusionPath $p -ErrorAction SilentlyContinue
        Write-Host "Excluded: $p"
    }
    else {
        Write-Host "Skipped (not found): $p"
    }
}

Write-Host ""
Write-Host "Current Defender exclusion paths:"
(Get-MpPreference).ExclusionPath | ForEach-Object { Write-Host "  $_" }
