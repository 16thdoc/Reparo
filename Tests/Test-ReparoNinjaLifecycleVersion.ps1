Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$source = Get-Content -LiteralPath (Join-Path $repoRoot 'Reparo.ps1') -Raw
$readme = Get-Content -LiteralPath (Join-Path $repoRoot 'README.md') -Raw
$ninjaUpdaterPath = Join-Path $repoRoot 'deploy\Ninja-Reparo-VersionCheck.ps1'
$ninjaUpdater = Get-Content -LiteralPath $ninjaUpdaterPath -Raw

foreach ($required in @(
    'function Publish-ReparoInstalledNinjaVersion',
    'param([string]$Version = $script:ReparoVersion)',
    'return Update-ReparoNinjaField -Version $matches.Version.Trim()',
    'Publish-ReparoInstalledNinjaVersion -TargetRoot $InstallRoot | Out-Null'
)) {
    if (-not $source.Contains($required)) {
        throw "Ninja lifecycle version publishing contract is absent: $required"
    }
}

foreach ($required in @(
    "Set-NinjaReparoField -Value 'Not Installed'",
    "Set-NinjaReparoField -Value 'Update Failed'",
    "'Cache-Control' = 'no-cache'",
    'Downloaded Reparo SHA-256 mismatch',
    'Reparo installation exited with code'
)) {
    if (-not $ninjaUpdater.Contains($required)) {
        throw "Ninja version updater contract is absent: $required"
    }
}

foreach ($retiredReference in @(
    'Ninja-Reparo-GitHub.ps1',
    'Ninja-GitHub.ps1',
    'Ninja-Embedded.ps1',
    'New-NinjaEmbeddedDeployment.ps1',
    'RMM-Operator-Guide.md',
    'deploy\ScreenConnect'
)) {
    if ($readme.Contains($retiredReference)) {
        throw "README still references retired deployment artifact: $retiredReference"
    }
}

Write-Host 'Reparo Ninja lifecycle version publishing and documentation contracts passed.' -ForegroundColor Green
