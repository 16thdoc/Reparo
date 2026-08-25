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
    "'-New', '-SkipNinjaPublish', '-InstallRoot', `$InstallRoot",
    "& powershell.exe @ninjaInstallArguments",
    'Publish-ReparoInstalledNinjaVersion -TargetRoot $InstallRoot | Out-Null',
    "& `$setter.Name -Name 'Reparo' -Value 'Update Failed'",
    "Runtime update preserves persisted WinGet health; use -WG to refresh it."
)) {
    if (-not $source.Contains($required)) {
        throw "Ninja lifecycle version publishing contract is absent: $required"
    }
}

$ninjaBlock = [regex]::Match($source, '(?s)if \(\$Ninja\) \{.*?(?=if \(\$Install -or \$New -or \$Latest\))')
if (-not $ninjaBlock.Success -or $ninjaBlock.Value.Contains('Update-ReparoNinjaField | Out-Null')) {
    throw '-Ninja must publish exactly once through Publish-ReparoInstalledNinjaVersion after its child update.'
}

if (Test-Path -LiteralPath (Join-Path $repoRoot 'deploy\Ninja-Reparo-VersionCheck.ps1')) {
    throw 'Standalone Ninja version-check payload was not retired.'
}

$systemIdentityFunction = $source.IndexOf('function Test-ReparoSystemIdentity')
$installLifecycle = $source.IndexOf('if ($Install -or $New -or $Latest)')
if ($systemIdentityFunction -lt 0 -or $installLifecycle -lt 0 -or $systemIdentityFunction -gt $installLifecycle) {
    throw 'Test-ReparoSystemIdentity must be declared before the install lifecycle can invoke it.'
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
