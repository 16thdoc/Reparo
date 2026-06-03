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
    [switch]$Winget,
    [switch]$WingetDiscover,
    [switch]$Force,
    [switch]$Status,
    [switch]$IgnoreTimeouts,
    [Alias('Log')]
    [switch]$Tail,
    [int]$WingetTimeoutSeconds,
    [int]$WingetDiscoveryTimeoutSeconds,
    [int]$WindowsUpdateTimeoutSeconds,
    [bool]$InstallNuGetProvider = $true,
    [string[]]$Include,
    [string]$LogRoot = "$env:ProgramData\Reparo\Logs"
)

$ErrorActionPreference = 'Stop'

if ([Net.ServicePointManager]::SecurityProtocol -notmatch 'Tls12') {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

function Format-NinjaLogValue {
    param(
        [Parameter(Mandatory)]
        [object]$Value
    )

    if ($null -eq $Value) {
        return '<null>'
    }

    if ($Value -is [bool]) {
        return $Value.ToString()
    }

    if ($Value -is [System.Array]) {
        if ($Value.Count -eq 0) {
            return '[]'
        }

        return ('[{0}]' -f ($Value -join ', '))
    }

    return [string]$Value
}

function Write-NinjaParameterBlock {
    $effectiveParameters = [ordered]@{
        ReparoUrl                    = $ReparoUrl
        InstallRoot                  = $InstallRoot
        Preview                      = $Preview
        Update                       = $Update
        Winget                       = $Winget
        WingetDiscover               = $WingetDiscover
        Force                        = $Force
        Status                       = $Status
        IgnoreTimeouts               = $IgnoreTimeouts
        Tail                         = $Tail
        Debug                        = [bool]($PSBoundParameters.ContainsKey('Debug'))
        WingetTimeoutSeconds         = $WingetTimeoutSeconds
        WingetDiscoveryTimeoutSeconds = $WingetDiscoveryTimeoutSeconds
        WindowsUpdateTimeoutSeconds   = $WindowsUpdateTimeoutSeconds
        InstallNuGetProvider         = $InstallNuGetProvider
        Include                      = $Include
        LogRoot                      = $LogRoot
    }

    Write-Host 'Parameter state:'
    foreach ($entry in $effectiveParameters.GetEnumerator()) {
        Write-Host ("  {0}={1}" -f $entry.Key, (Format-NinjaLogValue -Value $entry.Value))
    }
}

Write-Host '=== Ninja Reparo Bootstrap ==='
Write-Host "Computer: $env:COMPUTERNAME"
Write-Host "User: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Host "InstallRoot: $InstallRoot"
Write-Host "LogRoot: $LogRoot"
Write-Host "ReparoUrl: $ReparoUrl"
Write-NinjaParameterBlock
Write-Host ("Timeouts: Winget={0} WingetDiscovery={1} WindowsUpdate={2}" -f $WingetTimeoutSeconds, $WingetDiscoveryTimeoutSeconds, $WindowsUpdateTimeoutSeconds)
Write-Host ("NuGet provider bootstrap: {0}" -f $InstallNuGetProvider)
Write-Host 'Preflight:'
if ($Winget) {
    if ($Preview) {
        Write-Host '  - Winget discovery will run, but live winget upgrades will stay in preview mode.'
    }
    else {
        Write-Host '  - Winget discovery will run, then live winget upgrades will execute.'
    }
}
elseif ($WingetDiscover) {
    Write-Host '  - Winget discovery only; live winget upgrades will be skipped.'
}
elseif ($Preview) {
    Write-Host '  - Preview only; Reparo will log commands without running live package installs.'
}
elseif ($Update) {
    Write-Host '  - Managed-client update pass.'
}
elseif ($Force) {
    Write-Host '  - Full maintenance pass.'
}
else {
    Write-Host '  - Default Windows Update only.'
}
if ($IgnoreTimeouts) {
    Write-Host '  - Timeouts are disabled for the run.'
}

New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
$scriptPath = Join-Path $InstallRoot 'Reparo.ps1'
$bootstrapPath = Join-Path $InstallRoot 'Reparo.bootstrap.ps1'

Write-Host "Downloading bootstrap to: $bootstrapPath"
Invoke-WebRequest -Uri $ReparoUrl -OutFile $bootstrapPath -UseBasicParsing

if (Get-Command Unblock-File -ErrorAction SilentlyContinue) {
    Unblock-File -Path $bootstrapPath
    Write-Host 'Bootstrap unblocked'
}

Write-Host "Installing runtime copy: $scriptPath"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $bootstrapPath -New -InstallRoot $InstallRoot -SourceUrl $ReparoUrl
if ($LASTEXITCODE -ne 0) {
    Write-Host "Bootstrap install failed with code: $LASTEXITCODE"
    exit $LASTEXITCODE
}

$arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath, '-LogRoot', $LogRoot)

if ($Preview) { $arguments += '-Preview' }
if ($Winget) {
    $arguments += '-Winget'
}
if ($WingetDiscover) {
    $arguments += '-WingetDiscover'
}
if ($Force) {
    $arguments += '-Force'
}
elseif ($Status) {
    $arguments += '-Status'
}
elseif ($Include -and $Include.Count -gt 0) {
    $arguments += '-Include'
    $arguments += $Include
}
elseif ($Update) {
    $arguments += '-Update'
}

if ($PSBoundParameters.ContainsKey('Debug')) {
    $arguments += '-Debug'
}
if ($PSBoundParameters.ContainsKey('WingetTimeoutSeconds')) {
    $arguments += '-WingetTimeoutSeconds'
    $arguments += $WingetTimeoutSeconds
}
if ($PSBoundParameters.ContainsKey('WingetDiscoveryTimeoutSeconds')) {
    $arguments += '-WingetDiscoveryTimeoutSeconds'
    $arguments += $WingetDiscoveryTimeoutSeconds
}
if ($PSBoundParameters.ContainsKey('WindowsUpdateTimeoutSeconds')) {
    $arguments += '-WindowsUpdateTimeoutSeconds'
    $arguments += $WindowsUpdateTimeoutSeconds
}
if ($PSBoundParameters.ContainsKey('InstallNuGetProvider')) {
    $arguments += "-InstallNuGetProvider:$InstallNuGetProvider"
}
if ($IgnoreTimeouts) {
    $arguments += '-IgnoreTimeouts'
}

if ($Tail) {
    $arguments += '-Tail'
}

Write-Host ("Launching Reparo: powershell.exe {0}" -f ($arguments -join ' '))
Write-Host ("Forwarded to Reparo: {0}" -f ($arguments -join ' '))
if ($PSBoundParameters.ContainsKey('Debug')) {
    Write-Host 'Ninja debug: passing -Debug through to Reparo'
}
Write-Host 'Forwarded argument list:'
foreach ($argument in $arguments) {
    Write-Host "  $argument"
}

& powershell.exe @arguments
Write-Host "Reparo exit code: $LASTEXITCODE"
exit $LASTEXITCODE
