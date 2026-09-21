<#
.SYNOPSIS
    Installs the agent work-queue files into a project and the ux-issue command globally.

.DESCRIPTION
    Scaffolds the durable work queue described in docs/agent-work-queue.md:

      <project>\agent\next-issue.mjs        queue driver
      <project>\agent\backlog.schema.json   item shape
      <project>\agent\backlog.json          starting queue (created only when absent)
      ~\.config\opencode\commands\ux-issue.md   the /ux-issue command

    Idempotent: existing files are kept unless -Force is given, so re-running never clobbers a
    backlog you are working through.

.PARAMETER ProjectPath
    Project to scaffold. Defaults to the current directory.

.PARAMETER Force
    Overwrite files that already exist. The backlog is still written only when absent or forced.

.PARAMETER DryRun
    Print what would happen without writing anything.

.EXAMPLE
    .\install-agent-work-queue.ps1 -ProjectPath D:\repos\my-app -DryRun

.EXAMPLE
    .\install-agent-work-queue.ps1 -ProjectPath D:\repos\my-app
#>

[CmdletBinding()]
param(
    [string] $ProjectPath = (Get-Location).Path,
    [switch] $Force,
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string] $Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

$source = Join-Path $PSScriptRoot '..\templates\agent-work-queue'
if (-not (Test-Path -LiteralPath $source)) { throw "Template not found at '$source'." }
if (-not (Test-Path -LiteralPath $ProjectPath)) { throw "Project path not found: $ProjectPath" }

$agentDir = Join-Path $ProjectPath 'agent'
$commandDir = Join-Path $env:USERPROFILE '.config\opencode\commands'

$copies = @(
    @{ From = (Join-Path $source 'next-issue.mjs');       To = (Join-Path $agentDir 'next-issue.mjs');       Required = $true },
    @{ From = (Join-Path $source 'backlog.schema.json');  To = (Join-Path $agentDir 'backlog.schema.json');  Required = $true },
    @{ From = (Join-Path $source 'backlog.example.json'); To = (Join-Path $agentDir 'backlog.json');         Required = $true },
    @{ From = (Join-Path $source 'gradle-lock.ps1');      To = (Join-Path $agentDir 'gradle-lock.ps1');      Required = $true },
    @{ From = (Join-Path $source 'commands\ux-issue.md'); To = (Join-Path $commandDir 'ux-issue.md');        Required = $true }
)

Write-Host "`nAgent work queue -> $ProjectPath" -ForegroundColor White

if ($DryRun) {
    Write-Step 'Dry run - nothing will be written'
    foreach ($c in $copies) {
        $state = if (Test-Path -LiteralPath $c.To) { 'exists' } else { 'create' }
        Write-Host ("    {0,-6} {1}" -f $state, $c.To)
    }
    exit 0
}

New-Item -ItemType Directory -Force -Path $agentDir | Out-Null
New-Item -ItemType Directory -Force -Path $commandDir | Out-Null

foreach ($c in $copies) {
    $exists = Test-Path -LiteralPath $c.To
    # Keep existing files (including the backlog, which is private working state) unless -Force.
    if ($exists -and (-not $Force)) {
        Write-Host "    keep   $($c.To)" -ForegroundColor DarkGray
        continue
    }
    Copy-Item -LiteralPath $c.From -Destination $c.To -Force
    Write-Host "    wrote  $($c.To)" -ForegroundColor Green
}

Write-Host ''
Write-Step 'Next'
Write-Host '    node agent/next-issue.mjs --brief'
Write-Host '    (or run /ux-issue in OpenCode)'
