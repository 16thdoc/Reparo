<#
.SYNOPSIS
NinjaOne deployer that installs a bundled Reparo payload before optionally refreshing it from GitHub.

.DESCRIPTION
Upload this script and Reparo.ps1 together. The bundled payload is installed first,
so maintenance can run even when GitHub is blocked. A remote refresh is then attempted
without making a blocked GitHub connection fatal. Reparo -New validates a candidate
before replacing the installed runtime and keeps a backup of the prior copy.
#>
[CmdletBinding()]
param(
    [string]$BundledReparoPath,
    [string]$BundledSha256,
    [string]$InstallRoot = "$env:ProgramData\Reparo",
    [string]$LogRoot = "$env:ProgramData\Reparo\Logs",
    [switch]$RefreshFromGitHub = $true,
    [string]$RemoteReparoUrl = 'https://raw.githubusercontent.com/16thdoc/Reparo/main/Reparo.ps1',
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ReparoArguments
)

$ErrorActionPreference = 'Stop'

function Resolve-BundledReparoPath {
    param([string]$Path)

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        $candidates += $Path
    }
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $candidates += (Join-Path $PSScriptRoot 'Reparo.ps1')
    }
    $candidates += (Join-Path (Get-Location).Path 'Reparo.ps1')

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path
        }
    }

    throw 'Bundled Reparo.ps1 was not found. Upload it with this Ninja script, or pass -BundledReparoPath with its staged path.'
}

function Invoke-ReparoInstaller {
    param(
        [Parameter(Mandatory)]
        [string]$BootstrapPath,
        [Parameter(Mandatory)]
        [string]$SourceUrl
    )

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $BootstrapPath -New -InstallRoot $InstallRoot -LogRoot $LogRoot -SourceUrl $SourceUrl
    if ($LASTEXITCODE -ne 0) {
        throw "Reparo installer failed with exit code $LASTEXITCODE."
    }
}

$bundledPath = Resolve-BundledReparoPath -Path $BundledReparoPath
$bundledHash = (Get-FileHash -LiteralPath $bundledPath -Algorithm SHA256).Hash

if (-not [string]::IsNullOrWhiteSpace($BundledSha256) -and $bundledHash -ne $BundledSha256.Trim().ToUpperInvariant()) {
    throw "Bundled Reparo SHA-256 mismatch. Expected $BundledSha256; got $bundledHash."
}

Write-Host '=== Ninja Reparo Offline-First Deployer ==='
Write-Host "Computer: $env:COMPUTERNAME"
Write-Host "Bundled payload: $bundledPath"
Write-Host "Bundled SHA-256: $bundledHash"
Write-Host "Install root: $InstallRoot"
Write-Host "Remote refresh: $RefreshFromGitHub"
if ($RefreshFromGitHub) {
    Write-Host "Remote source: $RemoteReparoUrl"
}

Write-Host 'Installing the bundled Reparo payload.'
Invoke-ReparoInstaller -BootstrapPath $bundledPath -SourceUrl $bundledPath

$installedPath = Join-Path $InstallRoot 'Reparo.ps1'
if (-not (Test-Path -LiteralPath $installedPath -PathType Leaf)) {
    throw "Bundled installation reported success but runtime was not found: $installedPath"
}

if ($RefreshFromGitHub) {
    try {
        Write-Host 'Checking GitHub for a newer Reparo runtime.'
        Invoke-ReparoInstaller -BootstrapPath $installedPath -SourceUrl $RemoteReparoUrl
        Write-Host 'GitHub refresh completed.'
    }
    catch {
        Write-Warning "GitHub refresh failed; continuing with the bundled runtime. $($_.Exception.Message)"
    }
}

$arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installedPath, '-LogRoot', $LogRoot)
if ($ReparoArguments -and $ReparoArguments.Count -gt 0) {
    $arguments += $ReparoArguments
}
else {
    $arguments += '-Update'
}

Write-Host ("Launching installed Reparo: powershell.exe {0}" -f ($arguments -join ' '))
& powershell.exe @arguments
$exitCode = $LASTEXITCODE
Write-Host "Reparo exit code: $exitCode"
exit $exitCode
