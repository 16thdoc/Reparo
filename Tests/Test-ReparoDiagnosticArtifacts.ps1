Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot 'Reparo.ps1'
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

$timedCommand = [regex]::Match($source, '(?s)function Invoke-ReparoTimedCommand \{.*?(?=function Test-ReparoIgnorableCommandOutputLine \{)')
if (-not $timedCommand.Success) { throw 'Could not locate the timed command wrapper.' }

$retentionBranch = '(?s)if \(\$script:ReparoDebug -or \$process\.ExitCode -ne 0\) \{.*?\}\s*else \{\s*Remove-Item -LiteralPath \$commandOutputPath, \$commandScriptPath -Force -ErrorAction SilentlyContinue\s*\}'
if ($timedCommand.Value -notmatch $retentionBranch) {
    throw 'Timed-command diagnostic retention must keep its if/else branch contiguous.'
}

Write-Host 'Reparo diagnostic artifact retention contract passed.' -ForegroundColor Green
