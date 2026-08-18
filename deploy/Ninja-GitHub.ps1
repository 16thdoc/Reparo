<# 
.SYNOPSIS
NinjaOne-friendly bootstrapper for installing/updating and running Reparo from a GitHub raw URL.

.DESCRIPTION
Downloads a temporary Reparo bootstrap copy, uses Reparo -New to install or
update the ProgramData runtime copy with validation and backup handling, then
runs the installed copy with the requested mode. When run by NinjaOne, it also
updates the Reparo device text custom field with the installed runtime version.
Use a version tag or commit URL for broad production deployment.
#>
[CmdletBinding()]
param(
    [string]$ReparoUrl = 'https://raw.githubusercontent.com/16thdoc/Reparo/1fa3dd4eccc3cc7f7d7097db15d3084d1e3b2702/Reparo.ps1',
    [string]$InstallRoot = "$env:ProgramData\Reparo",
    [switch]$Preview,
    [switch]$Update = $true,
    [switch]$Winget,
    [switch]$WingetDiscover,
    [switch]$MigrateChocoToWinget,
    [switch]$ChocoDeregisterOnly,
    [switch]$ForceWingetReinstall,
    [switch]$AllowRuntimeDeregister,
    [switch]$AllowPortableDeregister,
    [switch]$FinalizeChocolateyRemoval,
    [switch]$AllowRemainingChocoPackages,
    [switch]$NoChocolateyBackup,
    [string]$MigrationReportPath,
    [string]$ChocoWingetMapPath,
    [string[]]$MigrateChocoExclude,
    [switch]$Force,
    [switch]$Kill,
    [switch]$Status,
    [switch]$IgnoreTimeouts,
    [string[]]$KillUpdaterNames,
    [Alias('Log')]
    [switch]$Tail,
    [ValidateRange(1, 10000)]
    [int]$TailLines,
    [ValidateRange(0, [int]::MaxValue)]
    [int]$WingetTimeoutSeconds,
    [ValidateRange(0, [int]::MaxValue)]
    [int]$WingetDiscoveryTimeoutSeconds,
    [ValidateRange(0, [int]::MaxValue)]
    [int]$WindowsUpdateTimeoutSeconds,
    [bool]$InstallNuGetProvider = $true,
    [Alias('AllowRestart', 'AR')]
    [switch]$AllowReboot,
    [Alias('Reboot', 'Restart', 'R', 'ForceRestart', 'FR', 'FS', 'FRST')]
    [switch]$ForceReboot,
    [Alias('Shutdown', 'PowerOff', 'ForcePowerOff', 'FSH')]
    [switch]$ForceShutdown,
    [string[]]$Include,
    [string]$LogRoot = "$env:ProgramData\Reparo\Logs",
    [string]$Syslog
)

$ErrorActionPreference = 'Stop'

if ($ForceReboot -and $ForceShutdown) {
    throw '-Reboot and -Shutdown cannot be used together. Choose one post-run power action.'
}

if ([Net.ServicePointManager]::SecurityProtocol -notmatch 'Tls12') {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

function Format-NinjaLogValue {
    param(
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
        MigrateChocoToWinget         = $MigrateChocoToWinget
        ChocoDeregisterOnly          = $ChocoDeregisterOnly
        ForceWingetReinstall         = $ForceWingetReinstall
        AllowRuntimeDeregister       = $AllowRuntimeDeregister
        AllowPortableDeregister      = $AllowPortableDeregister
        FinalizeChocolateyRemoval    = $FinalizeChocolateyRemoval
        AllowRemainingChocoPackages  = $AllowRemainingChocoPackages
        NoChocolateyBackup           = $NoChocolateyBackup
        MigrationReportPath          = $MigrationReportPath
        ChocoWingetMapPath           = $ChocoWingetMapPath
        MigrateChocoExclude          = $MigrateChocoExclude
        Force                        = $Force
        Kill                         = $Kill
        Status                       = $Status
        IgnoreTimeouts               = $IgnoreTimeouts
        KillUpdaterNames             = $KillUpdaterNames
        Tail                         = $Tail
        TailLines                    = $TailLines
        Debug                        = [bool]($PSBoundParameters.ContainsKey('Debug'))
        WingetTimeoutSeconds         = $WingetTimeoutSeconds
        WingetDiscoveryTimeoutSeconds = $WingetDiscoveryTimeoutSeconds
        WindowsUpdateTimeoutSeconds   = $WindowsUpdateTimeoutSeconds
        InstallNuGetProvider         = $InstallNuGetProvider
        AllowReboot                  = $AllowReboot
        ForceReboot                  = $ForceReboot
        ForceShutdown                = $ForceShutdown
        Include                      = $Include
        LogRoot                      = $LogRoot
        Syslog                       = $Syslog
    }

    Write-Host 'Parameter state:'
    foreach ($entry in $effectiveParameters.GetEnumerator()) {
        Write-Host ("  {0}={1}" -f $entry.Key, (Format-NinjaLogValue -Value $entry.Value))
    }
}

function Update-NinjaReparoCustomField {
    param(
        [Parameter(Mandatory)]
        [string]$ReparoPath
    )

    # This bootstrapper is also useful outside Ninja. Do nothing when Ninja's
    # device-property command is unavailable rather than making a successful
    # local install look like a failure.
    $propertySetter = Get-Command -Name Ninja-Property-Set -ErrorAction SilentlyContinue
    if (-not $propertySetter) {
        Write-Host 'Ninja custom field update skipped: Ninja-Property-Set is unavailable.'
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

Write-Host '=== Ninja Reparo Bootstrap ==='
Write-Host "Computer: $env:COMPUTERNAME"
Write-Host "User: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Host "InstallRoot: $InstallRoot"
Write-Host "LogRoot: $LogRoot"
Write-Host "ReparoUrl: $ReparoUrl"
Write-NinjaParameterBlock
Write-Host ("Timeouts: Winget={0} WingetDiscovery={1} WindowsUpdate={2}" -f $WingetTimeoutSeconds, $WingetDiscoveryTimeoutSeconds, $WindowsUpdateTimeoutSeconds)
Write-Host ("NuGet provider bootstrap: {0}" -f $InstallNuGetProvider)
Write-Host ("Windows Update reboot opt-in: {0}" -f $AllowReboot)
Write-Host ("Post-run reboot: {0}" -f $ForceReboot)
Write-Host ("Post-run shutdown: {0}" -f $ForceShutdown)
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
elseif ($MigrateChocoToWinget) {
    if ($Preview) {
        Write-Host '  - Chocolatey to winget migration preview; no packages will be installed or removed.'
    }
    else {
        Write-Host '  - Chocolatey to winget migration; matched packages install/verify with winget before optional safe Chocolatey deregistration.'
    }
}
elseif ($FinalizeChocolateyRemoval) {
    if ($Preview) {
        Write-Host '  - Chocolatey finalization preview; no files or environment variables will be removed.'
    }
    else {
        Write-Host '  - Chocolatey finalization requested; Reparo will enforce backup-first safety checks.'
    }
}
elseif ($Kill) {
    Write-Host '  - Kill pass; Reparo processes and known updater front ends will be stopped.'
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
if ($AllowReboot) {
    Write-Host '  - Windows Update is allowed to auto-reboot if PSWindowsUpdate requires it.'
}
if ($ForceReboot) {
    Write-Host '  - The computer will restart after Reparo completes.'
}
if ($ForceShutdown) {
    Write-Host '  - The computer will shut down after Reparo completes.'
}
if ($PSBoundParameters.ContainsKey('Syslog')) {
    Write-Host ("  - Reparo TCP syslog target will be configured/used: {0}" -f $Syslog)
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

if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw "Reparo installation reported success but the runtime was not found: $scriptPath"
}
Update-NinjaReparoCustomField -ReparoPath $scriptPath

$arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath, '-LogRoot', $LogRoot)

if ($Preview) { $arguments += '-Preview' }
if ($Winget) {
    $arguments += '-Winget'
}
if ($WingetDiscover) {
    $arguments += '-WingetDiscover'
}
if ($MigrateChocoToWinget) {
    $arguments += '-MigrateChocoToWinget'
}
if ($ChocoDeregisterOnly) {
    $arguments += '-ChocoDeregisterOnly'
}
if ($ForceWingetReinstall) {
    $arguments += '-ForceWingetReinstall'
}
if ($AllowRuntimeDeregister) {
    $arguments += '-AllowRuntimeDeregister'
}
if ($AllowPortableDeregister) {
    $arguments += '-AllowPortableDeregister'
}
if ($FinalizeChocolateyRemoval) {
    $arguments += '-FinalizeChocolateyRemoval'
}
if ($AllowRemainingChocoPackages) {
    $arguments += '-AllowRemainingChocoPackages'
}
if ($NoChocolateyBackup) {
    $arguments += '-NoChocolateyBackup'
}
if ($Force) {
    $arguments += '-Force'
}
elseif ($Kill) {
    $arguments += '-Kill'
}
elseif ($Status) {
    $arguments += '-Status'
}
elseif ($Include -and $Include.Count -gt 0) {
    $arguments += '-Include'
    $arguments += $Include
}
elseif ($Update -and -not ($MigrateChocoToWinget -or $FinalizeChocolateyRemoval)) {
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
if ($AllowReboot) {
    $arguments += '-AllowReboot'
}
if ($ForceReboot) {
    $arguments += '-ForceReboot'
}
if ($ForceShutdown) {
    $arguments += '-ForceShutdown'
}
if ($IgnoreTimeouts) {
    $arguments += '-IgnoreTimeouts'
}
if ($PSBoundParameters.ContainsKey('KillUpdaterNames')) {
    $arguments += '-KillUpdaterNames'
    $arguments += $KillUpdaterNames
}
if ($PSBoundParameters.ContainsKey('ChocoWingetMapPath')) {
    $arguments += '-ChocoWingetMapPath'
    $arguments += $ChocoWingetMapPath
}
if ($PSBoundParameters.ContainsKey('MigrationReportPath')) {
    $arguments += '-MigrationReportPath'
    $arguments += $MigrationReportPath
}
if ($PSBoundParameters.ContainsKey('MigrateChocoExclude')) {
    $arguments += '-MigrateChocoExclude'
    $arguments += $MigrateChocoExclude
}

if ($Tail) {
    $arguments += '-Tail'
}
if ($PSBoundParameters.ContainsKey('TailLines')) {
    $arguments += '-TailLines'
    $arguments += $TailLines
}
if ($PSBoundParameters.ContainsKey('Syslog')) {
    $arguments += '-Syslog'
    $arguments += $Syslog
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
