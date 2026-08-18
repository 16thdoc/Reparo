<#
.SYNOPSIS
Updates Ninja's Reparo version custom field from the existing installed runtime.

.DESCRIPTION
Parameter-free, read-only NinjaOne automation. It does not download, install, refresh,
or run Reparo. It reads the version from C:\ProgramData\Reparo\Reparo.ps1 and writes
that value to Ninja's Reparo device text custom field. Missing runtimes are reported as
Not installed.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$runtimePath = Join-Path $env:ProgramData 'Reparo\Reparo.ps1'

$propertySetter = Get-Command -Name Ninja-Property-Set -ErrorAction SilentlyContinue
if (-not $propertySetter) {
    throw 'Ninja-Property-Set is unavailable; cannot update the Reparo custom field.'
}

$version = 'Not installed'
if (Test-Path -LiteralPath $runtimePath -PathType Leaf) {
    $match = Select-String -LiteralPath $runtimePath -Pattern "ReparoVersion\s*=\s*'([^']+)'" | Select-Object -First 1
    $version = if ($match -and $match.Matches[0].Groups[1].Value) { $match.Matches[0].Groups[1].Value } else { 'Installed (version unreadable)' }
}

Write-Host '=== Ninja Reparo Report Only ==='
Write-Host "Computer: $env:COMPUTERNAME"
Write-Host "Runtime: $runtimePath"
Write-Host "Reported version: $version"

& $propertySetter.Name -Name 'Reparo' -Value $version
if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    throw "Ninja-Property-Set failed with exit code $LASTEXITCODE."
}

Write-Host "Ninja custom field 'Reparo' set to: $version"
