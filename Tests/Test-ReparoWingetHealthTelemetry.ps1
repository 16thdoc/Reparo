Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$source = Get-Content -LiteralPath (Join-Path $repoRoot 'Reparo.ps1') -Raw

foreach ($required in @(
    'function Get-ReparoWingetHealth',
    'function Test-ReparoValidatedWingetOk',
    "Context    = if (Test-ReparoSystemIdentity) { 'SYSTEM' } else { 'User' }",
    "Validated  = (`$Status -eq 'OK')",
    '[NINJA] Publishing persisted WG:{0} without a health refresh.',
    "if (-not `$Preview -and -not `$SkipNinjaPublish)",
    "if (`$script:ReparoWingetHealthStatus -notin @('USER', 'OK'))"
)) {
    if (-not $source.Contains($required)) {
        throw "WinGet telemetry contract is absent: $required"
    }
}

$installBlock = [regex]::Match($source, '(?s)if \(\$Install -or \$New -or \$Latest\) \{.*?(?=if \(\$Msi -and -not \$Kill\))')
if (-not $installBlock.Success) { throw 'Could not locate the runtime install block.' }
if ($installBlock.Value.Contains("'-WingetDiscover'")) {
    throw 'Runtime updates must not start a post-install WinGet health refresh.'
}

Write-Host 'Reparo WinGet health telemetry contracts passed.' -ForegroundColor Green
