<#
.SYNOPSIS
Static NinjaOne Reparo Force runner using the manifest-backed release channel.

.DESCRIPTION
Import this parameter-free script once. Each run retrieves the reviewed release manifest
from main, validates its immutable Reparo commit URL and SHA-256, refreshes the installed
runtime transactionally, then runs Reparo -Force. Future Reparo releases advance only the
manifest; this Ninja script does not require re-importing for ordinary releases.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$installRoot = Join-Path $env:ProgramData 'Reparo'
$runtimePath = Join-Path $installRoot 'Reparo.ps1'
$bootstrapPath = Join-Path $installRoot 'Reparo.bootstrap.ps1'
$logRoot = Join-Path $installRoot 'Logs'
$releaseChannelUrl = 'https://raw.githubusercontent.com/16thdoc/Reparo/refs/heads/main/deploy/reparo-release.json'

function Get-DeploymentSha256 {
    param([Parameter(Mandatory)][string]$Path)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        return ([System.BitConverter]::ToString($sha256.ComputeHash($stream))).Replace('-', '')
    }
    finally {
        $stream.Dispose()
        $sha256.Dispose()
    }
}

function Get-ReparoReleaseManifest {
    param([Parameter(Mandatory)][string]$Uri)

    $manifest = (Invoke-WebRequest -Uri $Uri -UseBasicParsing).Content | ConvertFrom-Json -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($manifest.version) -or $manifest.version -notmatch '^\d+\.\d+\.\d+\.\d+$') {
        throw "Release manifest has an invalid version: $($manifest.version)"
    }
    if ([string]::IsNullOrWhiteSpace($manifest.commit) -or $manifest.commit -notmatch '^[0-9a-f]{40}$') {
        throw "Release manifest has an invalid commit: $($manifest.commit)"
    }
    if ([string]::IsNullOrWhiteSpace($manifest.sha256) -or $manifest.sha256 -notmatch '^[A-Fa-f0-9]{64}$') {
        throw "Release manifest has an invalid SHA-256: $($manifest.sha256)"
    }

    $expectedReparoUrl = 'https://raw.githubusercontent.com/16thdoc/Reparo/{0}/Reparo.ps1' -f $manifest.commit
    if ($manifest.reparoUrl -ne $expectedReparoUrl) {
        throw "Release manifest Reparo URL must be the immutable commit URL: $expectedReparoUrl"
    }

    return [pscustomobject]@{
        Version   = $manifest.version
        Commit    = $manifest.commit
        ReparoUrl = $manifest.reparoUrl
        Sha256    = $manifest.sha256.ToUpperInvariant()
    }
}

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

Write-Host '=== Ninja Reparo Force GitHub Release ==='
Write-Host "Computer: $env:COMPUTERNAME"
Write-Host "Release channel: $releaseChannelUrl"
Write-Host "Install root: $installRoot"

New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
Write-Host 'Resolving the reviewed Reparo release channel.'
$release = Get-ReparoReleaseManifest -Uri $releaseChannelUrl
Write-Host "Release: $($release.Version) ($($release.Commit))"
Write-Host "Source: $($release.ReparoUrl)"
Write-Host "Downloading Reparo bootstrap: $bootstrapPath"
Invoke-WebRequest -Uri $release.ReparoUrl -OutFile $bootstrapPath -UseBasicParsing

$actualSha256 = Get-DeploymentSha256 -Path $bootstrapPath
if ($actualSha256 -ne $release.Sha256) {
    throw "Reparo bootstrap SHA-256 mismatch. Expected $($release.Sha256); got $actualSha256."
}
Write-Host "Bootstrap SHA-256 verified: $actualSha256"

if (Get-Command Unblock-File -ErrorAction SilentlyContinue) {
    Unblock-File -Path $bootstrapPath
}

Write-Host 'Installing or refreshing the Reparo runtime.'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $bootstrapPath -New -InstallRoot $installRoot -LogRoot $logRoot -SourceUrl $release.ReparoUrl
if ($LASTEXITCODE -ne 0) {
    throw "Reparo GitHub install failed with exit code $LASTEXITCODE."
}
if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) {
    throw "Reparo installation reported success but the runtime was not found: $runtimePath"
}

Update-NinjaReparoCustomField -ReparoPath $runtimePath
Write-Host 'Running installed Reparo -Force from the verified release.'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runtimePath -Force -LogRoot $logRoot
$reparoExitCode = $LASTEXITCODE

Update-NinjaReparoCustomField -ReparoPath $runtimePath
if ($reparoExitCode -ne 0) {
    throw "Reparo -Force failed with exit code $reparoExitCode. The Ninja Reparo version field was still refreshed."
}

Write-Host 'Ninja Reparo Force GitHub release completed successfully.'
