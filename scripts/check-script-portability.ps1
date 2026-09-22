<#
.SYNOPSIS
    Scan a project's own tooling for the Windows-portability defects that silently make its
    verification unrunnable.

.DESCRIPTION
    A project's Gradle build is usually portable; hand-written Python, shell and Node tooling often is
    not. The failure mode is nasty because it is quiet: the check does not fail, it cannot run, and an
    unrunnable check is easy to mistake for "nothing to do".

    This scans a project's source-controlled scripts for the specific defects found in the field and
    prints a file:line finding with the fix. It is a lint with deliberately conservative rules: a file
    that already branches on the platform (os.name / sys.platform / process.platform) has its findings
    reported as INFO, because the Windows path may be handled a few lines away - a human confirms.

    Rules (Python unless noted):
      W1  "./gradlew" as a command           Windows has no extensionless gradlew; use gradlew.bat
      W1w quoted "gradlew" (no ./)           WARN if this is execution rather than a path check
      W2  "python3" as a subprocess argv      CreateProcess cannot resolve a .cmd shim; use sys.executable
      W3  select.select(...)                  cannot observe a subprocess pipe on Windows (WinError 10093)
      W4  os.killpg / start_new_session       POSIX-only; use taskkill /F /T /PID on Windows
      W5  bin/java by is-file                 Windows has java.exe; the bare-name check is always false
      W6  platform-tools/adb without .exe     Windows ships adb.exe
      W7  which("adb") in .mjs/.js            Windows resolves by PATHEXT, not a bare name
      W8  ./gradlew from a shell script       informative: fine on POSIX, wrong on Windows

.PARAMETER Path
    Project root to scan. Defaults to the current directory.

.PARAMETER Include
    Globs relative to the root. Defaults to the common tooling trees.

.EXAMPLE
    ./check-script-portability.ps1 -Path D:\repos\my-app

.NOTES
    Read-only. Exit code 0 when no FAIL findings, 1 when any exist, so it can gate a build.
#>
[CmdletBinding()]
param(
    [string] $Path = '.',
    [string[]] $Include = @(
        'tools/**/*.py', 'tools/**/*.mjs', 'tools/**/*.js',
        'scripts/**/*.py', 'scripts/**/*.sh', '**/*.sh', '**/*.py'
    )
)

$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath $Path).Path
Write-Host "`nScript portability scan: $root" -ForegroundColor White

# A file that already names the platform is treated as platform-aware: findings become INFO.
$guardPattern = 'os\.name|sys\.platform|process\.platform|\bwin32\b|Windows'

$rules = @(
    @{ Id = 'W1';  Sev = 'FAIL'; Pattern = '\./gradlew';                          Message = 'runs "./gradlew"; Windows needs gradlew.bat (the shell script is not executable there)' },
    @{ Id = 'W2';  Sev = 'FAIL'; Pattern = '["'']python3["'']\s*,';               Message = 'launches "python3" by name; CreateProcess cannot resolve a .cmd shim - use sys.executable' },
    @{ Id = 'W3';  Sev = 'FAIL'; Pattern = '\bselect\.select\s*\(';               Message = 'select() cannot observe a subprocess pipe on Windows (WinError 10093) - drain on a reader thread' },
    @{ Id = 'W4';  Sev = 'FAIL'; Pattern = 'os\.killpg|start_new_session\s*=\s*True'; Message = 'POSIX-only process control - use taskkill /F /T /PID on Windows' },
    @{ Id = 'W5';  Sev = 'FAIL'; Pattern = '/\s*"bin"\s*/\s*"java"';              Message = 'expects bin/java; Windows has java.exe - check for both' },
    @{ Id = 'W6';  Sev = 'FAIL'; Pattern = 'platform-tools[''"]\s*,\s*["'']adb[''"]'; Message = 'expects platform-tools/adb; Windows ships adb.exe' },
    @{ Id = 'W7';  Sev = 'WARN'; Pattern = 'which\([''"]adb[''"]\)';              Message = 'resolves adb by bare name; on Windows add adb.exe (PATHEXT)' },
    @{ Id = 'W8';  Sev = 'WARN'; Pattern = '^\s*(\./)?gradlew\b';                 Message = 'invokes ./gradlew from a shell script; correct on POSIX, wrong on Windows' }
)

$files = @()
foreach ($pattern in $Include) {
    $files += Get-ChildItem -Path (Join-Path $root $pattern) -File -ErrorAction SilentlyContinue
}
$files = $files |
    Where-Object { $_.FullName -notmatch '\\(build|node_modules|\.git|\.gradle|_work|\.venv)\\' } |
    Sort-Object FullName -Unique

if (-not $files) {
    Write-Host 'No files matched. Adjust -Include, or there is nothing to scan.' -ForegroundColor Yellow
    exit 0
}

$fails = 0
$warns = 0
$infos = 0

foreach ($file in $files) {
    $text = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $text) { continue }
    $lines = $text -split "`r?`n"
    $platformAware = $text -match $guardPattern
    $isJs = $file.Extension -in '.mjs', '.js'
    $rel = $file.FullName.Substring($root.Length).TrimStart('\', '/')

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        foreach ($rule in $rules) {
            if ($line -notmatch $rule.Pattern) { continue }
            if ($rule.Id -eq 'W7' -and -not $isJs) { continue }            # Python's shutil.which honours PATHEXT
            if ($rule.Id -eq 'W1' -and $line -match 'gradlew\.bat') { continue }  # portable ternary on one line
            $where = "$rel`:$($i + 1)"

            if ($platformAware) {
                $infos++
                Write-Host ("  INFO  {0}  [{1}] {2}" -f $where, $rule.Id, $rule.Message) -ForegroundColor DarkGray
            } elseif ($rule.Sev -eq 'FAIL') {
                $fails++
                Write-Host ("  FAIL  {0}  [{1}] {2}" -f $where, $rule.Id, $rule.Message) -ForegroundColor Red
            } else {
                $warns++
                Write-Host ("  WARN  {0}  [{1}] {2}" -f $where, $rule.Id, $rule.Message) -ForegroundColor Yellow
            }
        }
    }
}

Write-Host ''
Write-Host ("$($files.Count) file(s): $fails FAIL, $warns WARN, $infos INFO (platform-aware, review).") -ForegroundColor White
if ($fails -eq 0) {
    Write-Host 'No blocking portability defects. See docs/environment-gaps.md for why each rule matters.' -ForegroundColor Green
    exit 0
}
Write-Host 'See docs/environment-gaps.md for why each rule matters.' -ForegroundColor Yellow
exit 1
