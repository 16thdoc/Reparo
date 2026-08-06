Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot 'Reparo.ps1'
$source = Get-Content -LiteralPath $sourcePath -Raw

$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    throw "Reparo.ps1 has PowerShell parse errors: $($parseErrors.Message -join '; ')"
}

foreach ($required in @(
    'uninstall-no-record-file',
    'pip install\s+--ignore-installed\s+--no-deps\s+pip==',
    "`$repairArguments += '--user'",
    'reinstalling pip `$repairVersion in the same scope before retrying the upgrade',
    "Invoke-ReparoPipCommand -Arguments @('install', '--upgrade', 'pip')"
)) {
    if (-not $source.Contains($required)) {
        throw "Pip missing-RECORD recovery contract is absent: $required"
    }
}

$normalUpgradeCount = ([regex]::Matches(
    $source,
    [regex]::Escape("Invoke-ReparoPipCommand -Arguments @('install', '--upgrade', 'pip')")
)).Count
if ($normalUpgradeCount -lt 2) {
    throw 'Pip recovery must retry the normal upgrade after repairing the damaged version.'
}

Write-Host 'Reparo Pip missing-RECORD recovery contract passed.' -ForegroundColor Green
