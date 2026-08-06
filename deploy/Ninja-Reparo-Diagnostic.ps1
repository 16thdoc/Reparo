<#
.SYNOPSIS
Read-only NinjaOne diagnostic for Reparo runtime deployment.

.DESCRIPTION
Run as SYSTEM with no arguments. Reports the actual ProgramData runtime, logs,
PATH entries, process context, and Ninja custom-field setter availability. It makes
no changes and returns nonzero only when the expected runtime is missing.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Write-DiagnosticValue {
    param(
        [string]$Name,
        [object]$Value
    )

    $text = if ($null -eq $Value) { '<null>' } else { [string]$Value }
    Write-Host ("{0}: {1}" -f $Name, $text)
}

$installRoot = Join-Path $env:ProgramData 'Reparo'
$runtimePath = Join-Path $installRoot 'Reparo.ps1'
$logRoot = Join-Path $installRoot 'Logs'
$shimPath = Join-Path $installRoot 'bin\reparo.cmd'

Write-Host '=== Ninja Reparo Runtime Diagnostic ==='
Write-DiagnosticValue -Name 'Computer' -Value $env:COMPUTERNAME
Write-DiagnosticValue -Name 'Identity' -Value ([Security.Principal.WindowsIdentity]::GetCurrent().Name)
Write-DiagnosticValue -Name 'Working directory' -Value (Get-Location).Path
Write-DiagnosticValue -Name 'ProgramData' -Value $env:ProgramData
Write-DiagnosticValue -Name 'Install root' -Value $installRoot
Write-DiagnosticValue -Name 'Install root exists' -Value (Test-Path -LiteralPath $installRoot -PathType Container)
Write-DiagnosticValue -Name 'Runtime exists' -Value (Test-Path -LiteralPath $runtimePath -PathType Leaf)
Write-DiagnosticValue -Name 'Shim exists' -Value (Test-Path -LiteralPath $shimPath -PathType Leaf)
Write-DiagnosticValue -Name 'Log directory exists' -Value (Test-Path -LiteralPath $logRoot -PathType Container)

if (Test-Path -LiteralPath $runtimePath -PathType Leaf) {
    $versionMatch = Select-String -LiteralPath $runtimePath -Pattern "ReparoVersion\s*=\s*'([^']+)'" | Select-Object -First 1
    $version = if ($versionMatch) { $versionMatch.Matches[0].Groups[1].Value } else { 'Installed (version unreadable)' }
    Write-DiagnosticValue -Name 'Runtime version' -Value $version
    Write-DiagnosticValue -Name 'Runtime SHA-256' -Value ((Get-FileHash -LiteralPath $runtimePath -Algorithm SHA256).Hash)
}

if (Test-Path -LiteralPath $logRoot -PathType Container) {
    $logs = @(Get-ChildItem -LiteralPath $logRoot -File -Filter 'reparo_*.log' -ErrorAction Stop | Sort-Object LastWriteTime -Descending)
    Write-DiagnosticValue -Name 'Reparo log count' -Value $logs.Count
    foreach ($log in @($logs | Select-Object -First 5)) {
        Write-Host ("Recent log: {0} ({1:u})" -f $log.FullName, $log.LastWriteTime)
    }
}

foreach ($scope in @('Machine', 'User', 'Process')) {
    $path = if ($scope -eq 'Process') { $env:Path } else { [Environment]::GetEnvironmentVariable('Path', $scope) }
    $hasReparoBin = [bool](@($path -split ';' | Where-Object { $_ -ieq (Join-Path $installRoot 'bin') }))
    Write-DiagnosticValue -Name "$scope PATH contains Reparo bin" -Value $hasReparoBin
}

$propertySetter = Get-Command -Name Ninja-Property-Set -ErrorAction SilentlyContinue
Write-DiagnosticValue -Name 'Ninja-Property-Set available' -Value ([bool]$propertySetter)
if ($propertySetter) {
    Write-DiagnosticValue -Name 'Ninja-Property-Set command type' -Value $propertySetter.CommandType
    Write-DiagnosticValue -Name 'Ninja-Property-Set source' -Value $propertySetter.Source
}

if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) {
    Write-Error "Reparo runtime is missing: $runtimePath"
    exit 1
}

Write-Host 'Diagnostic complete: Reparo runtime is present.'
exit 0
