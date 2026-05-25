<# 
.SYNOPSIS
NinjaOne-friendly bootstrapper for running Reparo from a GitHub raw URL.

.DESCRIPTION
Downloads Reparo.ps1 to ProgramData and runs it with the requested mode.
Use a version tag or commit URL for broad production deployment.
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

Invoke-WebRequest -Uri $ReparoUrl -OutFile $scriptPath -UseBasicParsing

if (Get-Command Unblock-File -ErrorAction SilentlyContinue) {
    Unblock-File -Path $scriptPath
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
