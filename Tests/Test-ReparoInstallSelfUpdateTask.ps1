Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$windowsSource = Get-Content -LiteralPath (Join-Path $repoRoot 'Reparo.ps1') -Raw
$linuxInstaller = Get-Content -LiteralPath (Join-Path $repoRoot 'deploy\install-reparo-linux.sh') -Raw

foreach ($required in @(
    'function Install-ReparoSelfUpdateTask',
    "`$taskName = 'Reparo-SelfUpdate-Tuesday-1000'",
    "New-ScheduledTaskTrigger -Weekly -DaysOfWeek Tuesday -At '10:00AM'",
    'schtasks.exe fallback',
    '/SC WEEKLY /D TUE /ST 10:00 /RU SYSTEM /RL HIGHEST /F',
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

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput(
    $windowsSource,
    [ref]$tokens,
    [ref]$parseErrors
)
if ($parseErrors.Count -gt 0) {
    throw "Windows Reparo source does not parse: $($parseErrors[0].Message)"
}

$selfUpdateFunction = $ast.Find(
    {
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'Install-ReparoSelfUpdateTask'
    },
    $true
)
if (-not $selfUpdateFunction) {
    throw 'Could not extract Install-ReparoSelfUpdateTask for fallback testing.'
}

Invoke-Expression $selfUpdateFunction.Extent.Text
$script:ReparoIsWindows = $true
$script:fallbackPreviewMessages = New-Object System.Collections.Generic.List[string]
function Write-Info { param([string]$Message) [void]$script:fallbackPreviewMessages.Add($Message) }
function Get-Command {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string[]]$Name,
        [System.Management.Automation.CommandTypes]$CommandType
    )
    return $null
}

Install-ReparoSelfUpdateTask -TargetRoot 'C:\ProgramData\Reparo' -WhatIfOnly
if (-not ($script:fallbackPreviewMessages -match 'schtasks\.exe fallback')) {
    throw 'Missing ScheduledTasks cmdlets did not select the schtasks.exe preview fallback.'
}

Write-Host 'Reparo install self-update scheduling contract passed.' -ForegroundColor Green
