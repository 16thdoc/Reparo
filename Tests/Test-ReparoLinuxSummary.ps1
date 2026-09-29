Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$linuxPath = Join-Path $repoRoot 'linux\reparo-linux'
$source = Get-Content -LiteralPath $linuxPath -Raw

foreach ($required in @(
    'record_not_updated() {',
    'print_not_updated_report() {',
    'Not updated: reasons and actions',
    'Why: $reason',
    'Next: $action',
    'record_not_updated FAILED "$section" "command exited $status"',
    'record_not_updated SKIPPED "$section" ''preview only''',
    'print_not_updated_report'
)) {
    if (-not $source.Contains($required)) {
        throw "Native Linux actionable not-updated report contract is absent: $required"
    }
}

$sh = Get-Command sh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($sh) {
    & $sh.Source -n $linuxPath
    if ($LASTEXITCODE -ne 0) { throw "Native Linux runner failed POSIX shell syntax validation with exit code $LASTEXITCODE." }
}

Write-Host 'Reparo native Linux actionable not-updated report contract passed.' -ForegroundColor Green
