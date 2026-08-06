<#
.SYNOPSIS
Refreshes an existing Reparo runtime through its native -New command.

.DESCRIPTION
Parameter-free NinjaOne automation. It deliberately does not embed or install a
runtime: endpoints without Reparo fail clearly instead of receiving an unexpected
bootstrap. Run as SYSTEM with no Ninja options or arguments.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$runtimePath = Join-Path $env:ProgramData 'Reparo\Reparo.ps1'

function Set-NinjaReparoVersion {
    param([string]$Value)

    $setter = Get-Command -Name Ninja-Property-Set -ErrorAction SilentlyContinue
    if (-not $setter) {
        Write-Warning 'Ninja-Property-Set is unavailable; the Reparo custom field was not updated.'
        return
    }

    & $setter.Name -Name 'Reparo' -Value $Value
    if ($LASTEXITCODE -ne 0) {
        throw "Ninja-Property-Set failed with exit code $LASTEXITCODE."
    }
}

if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) {
    Set-NinjaReparoVersion -Value 'Not installed'
    throw "Reparo is not installed: $runtimePath. Use Ninja-Embedded.ps1 for a first install."
}

Write-Host "Refreshing installed Reparo runtime: $runtimePath"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runtimePath -New
if ($LASTEXITCODE -ne 0) {
    throw "Reparo -New failed with exit code $LASTEXITCODE."
}

$versionMatch = Select-String -LiteralPath $runtimePath -Pattern "ReparoVersion\s*=\s*'([^']+)'" | Select-Object -First 1
$version = if ($versionMatch) { $versionMatch.Matches[0].Groups[1].Value } else { 'Installed (version unreadable)' }
Set-NinjaReparoVersion -Value $version
Write-Host "Reparo native refresh complete. Version: $version"
