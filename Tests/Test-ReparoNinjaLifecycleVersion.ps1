Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$source = Get-Content -LiteralPath (Join-Path $repoRoot 'Reparo.ps1') -Raw
$readme = Get-Content -LiteralPath (Join-Path $repoRoot 'README.md') -Raw

foreach ($required in @(
    'function Publish-ReparoInstalledNinjaVersion',
    'param([string]$Version = $script:ReparoVersion)',
    'return Update-ReparoNinjaField -Version $matches.Version.Trim()',
    'Publish-ReparoInstalledNinjaVersion -TargetRoot $InstallRoot | Out-Null',
    "[Alias('WG')]`n    [switch]`$WingetHealth",
    '$WingetDiscover = $true',
    "if (`$Ninja) {",
    "'-New', '-InstallRoot', `$InstallRoot",
    "& powershell.exe @ninjaInstallArguments",
    "& `$setter.Name -Name 'Reparo' -Value 'Update Failed'"
)) {
    if (-not $source.Contains($required)) {
        throw "Ninja lifecycle version publishing contract is absent: $required"
    }
}

if (Test-Path -LiteralPath (Join-Path $repoRoot 'deploy\Ninja-Reparo-VersionCheck.ps1')) {
    throw 'Standalone Ninja version-check payload was not retired.'
}

if (-not $readme.Contains('`-Ninja` replaces the former standalone Ninja version-check payload')) {
    throw 'README does not document -Ninja as the unified Ninja lifecycle mode.'
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
