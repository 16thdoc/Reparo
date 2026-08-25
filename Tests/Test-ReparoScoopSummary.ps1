Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot 'Reparo.ps1'
$source = Get-Content -LiteralPath $sourcePath -Raw

foreach ($required in @(
    "`$item.PSObject.Properties['Installed Version']",
    "`$item.PSObject.Properties['Latest Version']",
    'Software       = $name',
    'CurrentVersion = $installed',
    'Version        = $available',
    "[regex]::Match(`$line, '^(?<name>\S+)\s+(?<installed>\S+)\s+(?<available>\S+)')",
    "Resolve-ReparoScoopRecoveryShell",
    "term 'Get-FileHash' is not recognized",
    "Import-Module Microsoft.PowerShell.Utility -Force -ErrorAction Stop; scoop update",
    "-Section 'Scoop(retry)'"
)) {
    if (-not $source.Contains($required)) {
        throw "Scoop structured-status summary contract is absent: $required"
    }
}

Write-Host 'Reparo Scoop structured-status summary contract passed.' -ForegroundColor Green
