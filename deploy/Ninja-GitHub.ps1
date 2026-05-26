<# 
.SYNOPSIS
NinjaOne-friendly bootstrapper for installing/updating and running Reparo from a GitHub raw URL.

.DESCRIPTION
Downloads a temporary Reparo bootstrap copy, uses Reparo -New to install or
update the ProgramData runtime copy with validation and backup handling, then
runs the installed copy with the requested mode. Use a version tag or commit URL
for broad production deployment.
#>
[CmdletBinding()]
param(
    [string]$ReparoUrl = 'https://raw.githubusercontent.com/16thdoc/Reparo/main/Reparo.ps1',
    [string]$InstallRoot = "$env:ProgramData\Reparo",
    [switch]$Preview,
    [switch]$Update = $true,
    [switch]$Force,
    [string[]]$Include,
    [string]$LogRoot = "$env:ProgramData\Reparo\Logs"
)

$ErrorActionPreference = 'Stop'

if ([Net.ServicePointManager]::SecurityProtocol -notmatch 'Tls12') {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
$scriptPath = Join-Path $InstallRoot 'Reparo.ps1'
$bootstrapPath = Join-Path $InstallRoot 'Reparo.bootstrap.ps1'

Invoke-WebRequest -Uri $ReparoUrl -OutFile $bootstrapPath -UseBasicParsing

if (Get-Command Unblock-File -ErrorAction SilentlyContinue) {
    Unblock-File -Path $bootstrapPath
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $bootstrapPath -New -InstallRoot $InstallRoot -SourceUrl $ReparoUrl
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath, '-LogRoot', $LogRoot)

if ($Preview) { $arguments += '-Preview' }
if ($Force) {
    $arguments += '-Force'
}
elseif ($Include -and $Include.Count -gt 0) {
    $arguments += '-Include'
    $arguments += $Include
}
elseif ($Update) {
    $arguments += '-Update'
}

& powershell.exe @arguments
exit $LASTEXITCODE
