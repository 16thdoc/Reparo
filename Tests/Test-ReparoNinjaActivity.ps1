Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$source = Get-Content -LiteralPath (Join-Path $repoRoot 'Reparo.ps1') -Raw
$readme = Get-Content -LiteralPath (Join-Path $repoRoot 'README.md') -Raw

foreach ($required in @(
    'function Test-ReparoNinjaContext',
    'function Get-ReparoInstalledVersion',
    'function Write-ReparoNinjaActivityLine',
    'function Write-ReparoNinjaSelfUpdateActivity',
    'function Write-ReparoNinjaMaintenanceActivity',
    'REPARO SELF-UPDATE ACTIVITY',
    'REPARO MAINTENANCE ACTIVITY',
    'Updated software',
    'Skipped items',
    'Failed items',
    'MaximumRowsPerBucket = 25',
    'Write-ReparoNinjaMaintenanceActivity -Mode $mode -Status $script:ReparoFinalStatus',
    'Write-ReparoNinjaMaintenanceActivity -Mode $appMode -Status $script:ReparoFinalStatus'
)) {
    if (-not $source.Contains($required)) {
        throw "Ninja activity contract is absent: $required"
    }
}

$maintenanceWriter = [regex]::Match($source, '(?s)function Write-ReparoNinjaMaintenanceActivity \{.*?(?=function Invoke-ReparoTimedCommand)')
if (-not $maintenanceWriter.Success) { throw 'Could not locate the Ninja maintenance activity writer.' }
foreach ($required in @(
    'if (-not (Test-ReparoNinjaContext)) { return }',
    '$script:ReparoVersion',
    '$script:ReparoLogPath',
    '$script:ReparoSummary[''Updated'']',
    '$script:ReparoSummary[''Skipped'']',
    '$script:ReparoSummary[''Failed'']'
)) {
    if (-not $maintenanceWriter.Value.Contains($required)) {
        throw "Ninja maintenance activity detail is absent: $required"
    }
}

$finalizeThenPublish = 'Finalize-ReparoLogFile -Status \$script:ReparoFinalStatus\r?\n\s*Write-ReparoNinjaMaintenanceActivity -Mode \$mode -Status \$script:ReparoFinalStatus'
if ($source -notmatch $finalizeThenPublish) {
    throw 'The Ninja maintenance activity must report the finalized log path.'
}

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw "Could not parse Reparo.ps1 for Ninja activity behavior tests: $($parseErrors[0].Message)" }
$functionNames = @(
    'Test-ReparoNinjaContext',
    'Write-ReparoNinjaActivityLine',
    'Write-ReparoNinjaSelfUpdateActivity',
    'ConvertTo-ReparoNinjaActivityRow',
    'Write-ReparoNinjaMaintenanceActivity'
)
$functionDefinitions = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $functionNames
}, $true))
if ($functionDefinitions.Count -ne $functionNames.Count) { throw 'Could not extract all Ninja activity functions for behavior tests.' }

& {
    Invoke-Expression (($functionDefinitions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n")
    function Ninja-Property-Set { param([string]$Name, [string]$Value) }
    function Write-ReparoLog { param([string]$Message) }
    $script:ReparoVersion = '9.8.7.6'
    $script:ReparoLogPath = 'C:\ProgramData\Reparo\Logs\test_COMPLETE.log'
    $script:ReparoSummary = [ordered]@{
        Updated = New-Object System.Collections.Generic.List[object]
        Skipped = New-Object System.Collections.Generic.List[object]
        Failed  = New-Object System.Collections.Generic.List[object]
        Notes   = New-Object System.Collections.Generic.List[string]
    }
    [void]$script:ReparoSummary.Updated.Add([pscustomobject]@{ Software = 'Git'; CurrentVersion = '1.0'; Version = '2.0'; Method = 'winget'; Reason = 'updated' })
    [void]$script:ReparoSummary.Skipped.Add([pscustomobject]@{ Software = 'Locked App'; CurrentVersion = '3.0'; Version = '3.0'; Method = 'winget'; Reason = 'version locked' })
    [void]$script:ReparoSummary.Failed.Add([pscustomobject]@{ Software = 'Broken App'; CurrentVersion = '4.0'; Version = '5.0'; Method = 'choco'; Reason = "exit`r`ncode 1" })

    $maintenanceOutput = Write-ReparoNinjaMaintenanceActivity -Mode 'UPDATE' -Status 'FAILED' 6>&1 | Out-String
    foreach ($expected in @(
        'REPARO MAINTENANCE ACTIVITY',
        'Status: FAILED',
        'Version: 9.8.7.6',
        'Updated: 1 | Skipped: 1 | Failed: 1',
        '- Git 1.0 -> 2.0 [winget]: updated',
        '- Broken App 4.0 -> 5.0 [choco]: exit code 1',
        'test_COMPLETE.log'
    )) {
        if (-not $maintenanceOutput.Contains($expected)) { throw "Ninja maintenance behavior output is absent: $expected" }
    }

    $selfUpdateOutput = Write-ReparoNinjaSelfUpdateActivity -Status 'COMPLETE' -PreviousVersion '1.0.0.0' -InstalledVersion '1.0.0.1' 6>&1 | Out-String
    foreach ($expected in @('REPARO SELF-UPDATE ACTIVITY', 'Previous version: 1.0.0.0', 'Installed version: 1.0.0.1')) {
        if (-not $selfUpdateOutput.Contains($expected)) { throw "Ninja self-update behavior output is absent: $expected" }
    }
}

foreach ($required in @(
    'Ninja captures the concise Reparo activity receipt from standard output',
    'Application / Reparo',
    '1001',
    '1002',
    '1003'
)) {
    if (-not $readme.Contains($required)) {
        throw "README Ninja activity guidance is absent: $required"
    }
}

Write-Host 'Reparo Ninja maintenance and self-update activity contracts passed.' -ForegroundColor Green
