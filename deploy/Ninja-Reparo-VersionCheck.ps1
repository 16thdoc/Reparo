<#
.SYNOPSIS
Checks and refreshes the ProgramData Reparo runtime from Ninja.

.DESCRIPTION
Publishes Not Installed when no runtime exists. Otherwise it downloads the reviewed,
SHA-256-pinned Reparo release, invokes its canonical offline installer, and records the
installed version in Ninja's Reparo device text field.
#>
[CmdletBinding()]
param(
    [string]$InstallRoot = "$env:ProgramData\Reparo"
)

$ErrorActionPreference = 'Stop'
$runtimePath = Join-Path $InstallRoot 'Reparo.ps1'
$manifestUrl = 'https://raw.githubusercontent.com/16thdoc/Reparo/refs/heads/main/deploy/reparo-release.json'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("NinjaReparo_{0}_{1}" -f $PID, (Get-Date -Format 'yyyyMMddHHmmss'))

function Set-NinjaReparoField {
    param([Parameter(Mandatory)][string]$Value)

    $setter = Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue
    if (-not $setter) { throw 'Ninja-Property-Set is unavailable. Run this only as a Ninja script.' }

    & $setter.Name -Name 'Reparo' -Value $Value
    Write-Host "Ninja Reparo field updated: $Value" -ForegroundColor Green
}

function Get-NinjaReparoWingetStatus {
    $healthPath = Join-Path $InstallRoot 'winget-health.json'
    if (-not (Test-Path -LiteralPath $healthPath -PathType Leaf)) { return 'UNKNOWN' }

    try {
        $health = Get-Content -LiteralPath $healthPath -Raw | ConvertFrom-Json -ErrorAction Stop
        if ($health.Status -in @('OK', 'USER', 'FAIL')) { return $health.Status }
    }
    catch { }

    return 'UNKNOWN'
}

if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) {
    Set-NinjaReparoField -Value 'Not Installed'
    Write-Host "Reparo is not installed at $runtimePath." -ForegroundColor Yellow
    exit 0
}

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $requestHeaders = @{ 'User-Agent' = 'Reparo-Ninja-VersionCheck'; 'Cache-Control' = 'no-cache'; 'Pragma' = 'no-cache' }
    $cacheBust = [Uri]::EscapeDataString((Get-Date -Format 'yyyyMMddHHmmss'))
    $manifest = Invoke-RestMethod -Uri ("{0}?x={1}" -f $manifestUrl, $cacheBust) -Headers $requestHeaders -UseBasicParsing -ErrorAction Stop

    if ($manifest.commit -notmatch '^[0-9a-f]{40}$' -or $manifest.sha256 -notmatch '^[A-F0-9]{64}$') {
        throw 'Release manifest does not contain a valid immutable commit and SHA-256.'
    }
    $expectedUrl = 'https://raw.githubusercontent.com/16thdoc/Reparo/{0}/Reparo.ps1' -f $manifest.commit
    if ($manifest.reparoUrl -ne $expectedUrl) { throw 'Release manifest Reparo URL is not pinned to its commit.' }

    $candidatePath = Join-Path $tempRoot 'Reparo.ps1'
    Invoke-WebRequest -Uri ("{0}?x={1}" -f $manifest.reparoUrl, $cacheBust) -Headers $requestHeaders -OutFile $candidatePath -UseBasicParsing -ErrorAction Stop
    $candidateHash = (Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash
    if ($candidateHash -ne $manifest.sha256) { throw "Downloaded Reparo SHA-256 mismatch. Expected $($manifest.sha256), got $candidateHash." }

    $tokens = $null
    $parseErrors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($candidatePath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw "Downloaded Reparo failed parse validation: $(($parseErrors | ForEach-Object Message) -join '; ')" }

    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $candidatePath -Install -InstallRoot $InstallRoot
    if ($LASTEXITCODE -ne 0) { throw "Reparo installation exited with code $LASTEXITCODE." }

    $versionOutput = & $runtimePath -Version *>&1 | Out-String
    if ($LASTEXITCODE -notin @(0, $null) -or $versionOutput -notmatch '(?m)^Reparo (?<Version>\d+\.\d+\.\d+\.\d+)\r?$') {
        throw "Installed Reparo did not return a valid version: $versionOutput"
    }

    Set-NinjaReparoField -Value ("{0} | WG:{1}" -f $matches.Version.Trim(), (Get-NinjaReparoWingetStatus))
}
catch {
    try { Set-NinjaReparoField -Value 'Update Failed' } catch { }
    throw
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
