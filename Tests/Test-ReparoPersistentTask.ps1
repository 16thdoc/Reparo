Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$windowsSource = Get-Content -LiteralPath (Join-Path $repoRoot 'Reparo.ps1') -Raw
$linuxSource = Get-Content -LiteralPath (Join-Path $repoRoot 'linux\reparo-linux') -Raw

foreach ($required in @(
    'function Invoke-ReparoPersistentTask',
    "-Task Daily 6am",
    "-Task Hourly 12hr -Force",
    'function Resolve-ReparoRecurrence',
    'function New-ReparoTaskXml',
    '<UserId>S-1-5-18</UserId>',
    "if (`$run.Count -eq 0) { `$run['Update']=`$true }"
)) {
    if (-not $windowsSource.Contains($required)) {
        throw "Windows persistent task contract is absent: $required"
    }
}

foreach ($required in @(
    'configure_persistent_task() {',
    'crontab is required for task management',
    'resolve_cron_recurrence() {',
    'marker="# Reparo managed task v2:$TASK_NAME"',
    'Preview only; no crontab changed',
    'crontab "$temp_crontab"'
)) {
    if (-not $linuxSource.Contains($required)) {
        throw "Linux persistent task contract is absent: $required"
    }
}

Write-Host 'Reparo persistent task scheduling contract passed.' -ForegroundColor Green
