<#
.SYNOPSIS
Installs or refreshes Reparo from GitHub for NinjaOne and updates the device version field.

.DESCRIPTION
Parameter-free NinjaOne automation. Downloads Reparo from the configured public GitHub
source, runs its transactional -New installer, and writes the installed version to the
Ninja device text custom field named Reparo. It performs no machine maintenance.

The source URL is pinned to the reviewed Reparo 1.2.6.2 release commit. Update it only
when promoting a reviewed replacement release for the fleet.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$installRoot = Join-Path $env:ProgramData 'Reparo'
$runtimePath = Join-Path $installRoot 'Reparo.ps1'
$bootstrapPath = Join-Path $installRoot 'Reparo.bootstrap.ps1'
$reparoUrl = 'https://raw.githubusercontent.com/16thdoc/Reparo/c5ac40cce0deab76441cca204f3f43104c4de07a/Reparo.ps1'

function Update-NinjaReparoCustomField {
    param([Parameter(Mandatory)][string]$ReparoPath)

    $propertySetter = Get-Command -Name Ninja-Property-Set -ErrorAction SilentlyContinue
    if (-not $propertySetter) {
        Write-Warning 'Ninja-Property-Set is unavailable; the Reparo custom field was not updated.'
        return
    }

    $version = 'Installed (version unreadable)'
    $match = Select-String -LiteralPath $ReparoPath -Pattern "ReparoVersion\s*=\s*'([^']+)'" | Select-Object -First 1
    if ($match -and $match.Matches[0].Groups[1].Value) {
        $version = $match.Matches[0].Groups[1].Value
    }

    & $propertySetter.Name -Name 'Reparo' -Value $version
    if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        throw "Ninja-Property-Set failed with exit code $LASTEXITCODE."
    }
    Write-Host "Ninja custom field 'Reparo' set to: $version"
}

if ([Net.ServicePointManager]::SecurityProtocol -notmatch 'Tls12') {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

Write-Host '=== Ninja Reparo GitHub Deploy ==='
Write-Host "Computer: $env:COMPUTERNAME"
Write-Host "Source: $reparoUrl"
Write-Host "Install root: $installRoot"

New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
Write-Host "Downloading Reparo bootstrap: $bootstrapPath"
Invoke-WebRequest -Uri $reparoUrl -OutFile $bootstrapPath -UseBasicParsing

if (Get-Command Unblock-File -ErrorAction SilentlyContinue) {
    Unblock-File -Path $bootstrapPath
}

Write-Host 'Installing or refreshing the Reparo runtime.'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $bootstrapPath -New -InstallRoot $installRoot -SourceUrl $reparoUrl
if ($LASTEXITCODE -ne 0) {
    throw "Reparo GitHub install failed with exit code $LASTEXITCODE."
}
if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) {
    throw "Reparo installation reported success but the runtime was not found: $runtimePath"
}

Update-NinjaReparoCustomField -ReparoPath $runtimePath
Write-Host 'Reparo GitHub deploy complete; maintenance was not run.'
