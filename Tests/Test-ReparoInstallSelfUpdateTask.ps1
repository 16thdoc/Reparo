Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$windowsSource = Get-Content -LiteralPath (Join-Path $repoRoot 'Reparo.ps1') -Raw
$linuxInstaller = Get-Content -LiteralPath (Join-Path $repoRoot 'deploy\install-reparo-linux.sh') -Raw

foreach ($required in @(
    'function Install-ReparoSelfUpdateTask',
    "`$taskName = 'Reparo-SelfUpdate-Tuesday-1000'",
    "New-ScheduledTaskTrigger -Weekly -DaysOfWeek Tuesday -At '10:00AM'",
    "& `$scriptPathLiteral -New",
    'if ($script:ReparoIsWindows -and $Install -and -not $Preview -and $isDefaultInstallRoot) {'
)) {
    if (-not $windowsSource.Contains($required)) {
        throw "Windows install self-update task contract is absent: $required"
    }
}

foreach ($required in @(
    "self_update_marker='# Reparo self-update task'",
    '0 10 * * 2 \"$shim_path\" --new $self_update_marker',
    'Created/updated weekly self-update cron task: Tuesday 10:00 AM (reparo --new).'
)) {
    if (-not $linuxInstaller.Contains($required)) {
        throw "Linux install self-update schedule contract is absent: $required"
    }
}

Write-Host 'Reparo install self-update scheduling contract passed.' -ForegroundColor Green
