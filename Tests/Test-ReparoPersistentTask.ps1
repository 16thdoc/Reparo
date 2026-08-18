Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$windowsSource = Get-Content -LiteralPath (Join-Path $repoRoot 'Reparo.ps1') -Raw
$linuxSource = Get-Content -LiteralPath (Join-Path $repoRoot 'linux\reparo-linux') -Raw

foreach ($required in @(
    'function Invoke-ReparoPersistentTask',
    "-Task Daily 6am",
    "-Task Hourly 12hr -Force",
    "New-ScheduledTaskTrigger -Daily -At `$schedule.At",
    "New-ScheduledTaskTrigger -Daily -At (Get-Date).Date -RepetitionInterval ([TimeSpan]::FromHours(`$hours))",
    "New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest",
    "if (`$tokens.Count -eq 0) { `$tokens = @('-Update') }"
)) {
    if (-not $windowsSource.Contains($required)) {
        throw "Windows persistent task contract is absent: $required"
    }
}

foreach ($required in @(
    'configure_persistent_task() {',
    'command_exists crontab || die',
    'cron_schedule="$cron_minute $cron_hour * * *"',
    'cron_schedule="0 */$hours * * *"',
    "marker='# Reparo managed task'",
    'crontab "$temp_crontab"'
)) {
    if (-not $linuxSource.Contains($required)) {
        throw "Linux persistent task contract is absent: $required"
    }
}

Write-Host 'Reparo persistent task scheduling contract passed.' -ForegroundColor Green
