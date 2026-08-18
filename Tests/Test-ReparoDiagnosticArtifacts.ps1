Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot 'Reparo.ps1'
$ninjaRunnerPath = Join-Path $repoRoot 'deploy\Ninja-Reparo-Force-Debug-Installed.ps1'
$source = Get-Content -LiteralPath $sourcePath -Raw

$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw "Reparo.ps1 has PowerShell parse errors: $($parseErrors.Message -join '; ')" }

foreach ($required in @(
    '$script:ReparoDebug -or $process.ExitCode -ne 0',
    '[DIAGNOSTIC] Retained {0} artifacts:',
    '[DIAGNOSTIC] Retained {0} artifacts after timeout:'
)) {
    if (-not $source.Contains($required)) {
        throw "Reparo diagnostic-artifact retention contract is absent: $required"
    }
}

if (-not (Test-Path -LiteralPath $ninjaRunnerPath -PathType Leaf)) {
    throw "Ninja diagnostic Force runner is missing: $ninjaRunnerPath"
}
$ninjaRunner = Get-Content -LiteralPath $ninjaRunnerPath -Raw
if (-not $ninjaRunner.Contains('-Force -Debug -LogRoot $logRoot')) {
    throw 'Ninja diagnostic Force runner does not invoke the installed runtime with -Force -Debug.'
}

[void][System.Management.Automation.Language.Parser]::ParseFile($ninjaRunnerPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw "Ninja diagnostic Force runner has PowerShell parse errors: $($parseErrors.Message -join '; ')" }

Write-Host 'Reparo diagnostic artifact retention and Ninja debug runner passed.' -ForegroundColor Green
