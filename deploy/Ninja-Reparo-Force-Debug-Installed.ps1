<#
.SYNOPSIS
Runs Reparo -Force -Debug from an existing runtime and refreshes the Ninja version field.

.DESCRIPTION
Parameter-free NinjaOne automation for endpoints where Reparo is already installed.
It does not download, install, or refresh the runtime. It runs the installed runtime
with -Force -Debug, retaining child command/output artifacts in the ProgramData Reparo
log directory, then updates Ninja's Reparo device text custom field even if maintenance fails.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$runtimePath = Join-Path $env:ProgramData 'Reparo\Reparo.ps1'
$logRoot = Join-Path $env:ProgramData 'Reparo\Logs'

function Update-NinjaReparoCustomField {
    param([Parameter(Mandatory)][string]$ReparoPath)

    $propertySetter = Get-Command -Name Ninja-Property-Set -ErrorAction SilentlyContinue
    if (-not $propertySetter) {
        throw 'Ninja-Property-Set is unavailable; cannot update the Reparo custom field.'
    }

    $version = 'Not installed'
    if (Test-Path -LiteralPath $ReparoPath -PathType Leaf) {
        $match = Select-String -LiteralPath $ReparoPath -Pattern "ReparoVersion\s*=\s*'([^']+)'" | Select-Object -First 1
        $version = if ($match -and $match.Matches[0].Groups[1].Value) { $match.Matches[0].Groups[1].Value } else { 'Installed (version unreadable)' }
    }

    & $propertySetter.Name -Name 'Reparo' -Value $version
    if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        throw "Ninja-Property-Set failed with exit code $LASTEXITCODE."
    }
    Write-Host "Ninja custom field 'Reparo' set to: $version"
}

Write-Host '=== Ninja Reparo Force Debug (Installed Runtime) ==='
Write-Host "Computer: $env:COMPUTERNAME"
Write-Host "Runtime: $runtimePath"
Write-Host "Log root: $logRoot"

if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) {
    Update-NinjaReparoCustomField -ReparoPath $runtimePath
    throw "Reparo is not installed: $runtimePath. Deploy Reparo before running this automation."
}

Write-Host 'Running installed Reparo with -Force -Debug; child diagnostic artifacts will be retained.'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runtimePath -Force -Debug -LogRoot $logRoot
$reparoExitCode = $LASTEXITCODE

Update-NinjaReparoCustomField -ReparoPath $runtimePath
if ($reparoExitCode -ne 0) {
    throw "Reparo -Force -Debug failed with exit code $reparoExitCode. The Ninja Reparo version field was still refreshed."
}

Write-Host 'Installed Reparo -Force -Debug completed successfully.'
