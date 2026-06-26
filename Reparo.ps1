<# 
.SYNOPSIS
Client-safe maintenance runner for RMM/Ninja deployment.

.DESCRIPTION
Reparo upgrades common package/tool ecosystems when they are present.
It is intentionally standalone and does not depend on profile modules,
cloud-synced helper paths, editor sync state, or local automation commands.

Default mode runs Windows Update only. Use -Install or -New to install or update the
ProgramData runtime copy from GitHub, -Update for a conservative managed-client
maintenance pass, -Force for the full gauntlet, or -Include for specific
sections.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [Alias('H')]
    [switch]$Help,
    [Alias('V')]
    [switch]$Version,
    [Alias('Install', 'N')]
    [switch]$New,
    [Alias('P')]
    [switch]$Preview,
    [Alias('WU')]
    [switch]$WindowsUpdate,
    [Alias('WSL')]
    [switch]$WslApt,
    [Alias('U')]
    [switch]$Update,
    [Alias('WG')]
    [switch]$Winget,
    [Alias('WD')]
    [switch]$WingetDiscover,
    [Alias('S', 'List', 'L')]
    [switch]$Search,
    [Alias('VL')]
    [string[]]$VersionLock,
    [Alias('SaveVersionLock', 'AVL')]
    [string[]]$AddVersionLock,
    [Alias('VLP')]
    [string]$VersionLockPath = "$env:ProgramData\Reparo\version-locks.json",
    [Alias('LVL')]
    [switch]$ListVersionLocks,
    [Alias('MCW')]
    [switch]$MigrateChocoToWinget,
    [Alias('CDO')]
    [switch]$ChocoDeregisterOnly,
    [Alias('FWR')]
    [switch]$ForceWingetReinstall,
    [Alias('ARD')]
    [switch]$AllowRuntimeDeregister,
    [Alias('APD')]
    [switch]$AllowPortableDeregister,
    [Alias('FCR')]
    [switch]$FinalizeChocolateyRemoval,
    [switch]$AllowRemainingChocoPackages,
    [switch]$NoChocolateyBackup,
    [string]$MigrationReportPath,
    [Alias('CWM')]
    [string]$ChocoWingetMapPath,
    [Alias('MCE')]
    [string[]]$MigrateChocoExclude,
    [string]$CheckApp,
    [string]$LockApp,
    [string]$LockVersion,
    [ValidateSet('Auto', 'Winget', 'Choco')]
    [string]$PackageManager = 'Auto',
    [Alias('IS')]
    [switch]$InstallSpicetify,
    [Alias('F')]
    [switch]$Force,
    [Alias('K')]
    [switch]$Kill,
    [Alias('KUN')]
    [string[]]$KillUpdaterNames,
    [Alias('IT')]
    [switch]$IgnoreTimeouts,
    [ValidateRange(0, [int]::MaxValue)]
    [Alias('WTS')]
    [int]$WingetTimeoutSeconds = 0,
    [ValidateRange(0, [int]::MaxValue)]
    [Alias('WDTS')]
    [int]$WingetDiscoveryTimeoutSeconds = 0,
    [ValidateRange(0, [int]::MaxValue)]
    [Alias('WUTS')]
    [int]$WindowsUpdateTimeoutSeconds = 0,
    [ValidateRange(0, [int]::MaxValue)]
    [Alias('WATS')]
    [int]$WslAptTimeoutSeconds = 1800,
    [Alias('INP')]
    [bool]$InstallNuGetProvider = $true,
    [Alias('Reboot', 'R')]
    [switch]$AllowReboot,
    [Alias('LR')]
    [string]$LogRoot = "$env:ProgramData\Reparo\Logs",
    [Alias('IR')]
    [string]$InstallRoot = "$env:ProgramData\Reparo",
    [Alias('SU')]
    [string]$SourceUrl = 'https://raw.githubusercontent.com/16thdoc/Reparo/main/Reparo.ps1',
    [Alias('NB')]
    [switch]$NoBackup,
    [Alias('ST')]
    [switch]$Status,
    [Alias('SweepStale', 'Clean', 'Prune', 'SW')]
    [switch]$Sweep,
    [Alias('DS')]
    [switch]$DeleteStale,
    [Alias('Log', 'T')]
    [switch]$Tail,
    [ValidateRange(1, 10000)]
    [Alias('TL')]
    [int]$TailLines = 400,
    [Alias('I')]
    [string[]]$Include,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingInclude
)

$ErrorActionPreference = 'Stop'
$script:ReparoVersion = '1.0.8.3'

function Get-ReparoVersionFlavor {
    param([string]$Version = $script:ReparoVersion)

    $versionFlavors = @{
        '1.0.8.1' = [pscustomobject]@{ Quote = 'Hotfix applied. The goblin has been relocated.'; Art = '  GOBLIN: evicted from version output' }
        '1.0.8.2' = [pscustomobject]@{ Quote = 'New quote online. Old ghosts denied boarding.'; Art = '  QUOTE BAY: temporal lint removed' }
        '1.0.8.3' = [pscustomobject]@{ Quote = 'I cast Magic Missile at the darkness.'; Art = '  D20: quote gremlin takes 1d4+1 force damage' }
    }

    if ($versionFlavors.ContainsKey($Version)) {
        return $versionFlavors[$Version]
    }

    $flavors = @(
        [pscustomobject]@{ Quote = 'Hold on to your butts.'; Art = '  /\\_ Jurassic patch detected _/\\' },
        [pscustomobject]@{ Quote = 'Hack the planet!'; Art = '  [*] crash_override.exe loaded' },
        [pscustomobject]@{ Quote = 'Shall we play a game?'; Art = '  .-- WOPR warming the tea --.' },
        [pscustomobject]@{ Quote = 'The only winning move is not to play.'; Art = '  tic-tac-toe: avoided successfully' },
        [pscustomobject]@{ Quote = 'There is no spoon.'; Art = '  ( spoon.exe has exited with code 0 )' },
        [pscustomobject]@{ Quote = 'Do or do not. There is no try.'; Art = '  JEDI: try/catch block removed' },
        [pscustomobject]@{ Quote = 'Open the pod bay doors.'; Art = '  HAL says: maintenance acknowledged' },
        [pscustomobject]@{ Quote = 'Never tell me the odds.'; Art = '  <KesselRun parsecs="12" />' },
        [pscustomobject]@{ Quote = 'Would you like to know more?'; Art = '  SERVICE GUARANTEES CITIZENSHIP' },
        [pscustomobject]@{ Quote = 'By Grabthar''s hammer, what a savings.'; Art = '  GALAXY QUEST: thermian patch ritual complete' },
        [pscustomobject]@{ Quote = 'I cast Magic Missile at the darkness.'; Art = '  D20: quote gremlin takes 1d4+1 force damage' },
        [pscustomobject]@{ Quote = 'The spice must flow.'; Art = '  ARRAKIS: maintenance harvester deployed' },
        [pscustomobject]@{ Quote = 'So say we all.'; Art = '  BSG: jump drive cooled, logs synced' },
        [pscustomobject]@{ Quote = 'Roll for initiative.'; Art = '  D20: service encounter begins' },
        [pscustomobject]@{ Quote = 'The cake is a lie.'; Art = '  APERTURE: morally dubious maintenance complete' },
        [pscustomobject]@{ Quote = 'It is pitch black. You are likely to be eaten by a grue.'; Art = '  ZORK: lantern battery critically petty' }
    )

    $hash = [long]5381
    foreach ($char in ([string]$Version).ToCharArray()) {
        $hash = (($hash * 33) + [int][char]$char) % 2147483647
    }

    $flavors[[int]($hash % $flavors.Count)]
}

function Get-ReparoVersionQuote {
    param([string]$Version = $script:ReparoVersion)

    (Get-ReparoVersionFlavor -Version $Version).Quote
}

function Get-ReparoVersionArt {
    param([string]$Version = $script:ReparoVersion)

    (Get-ReparoVersionFlavor -Version $Version).Art
}

if ($RemainingInclude -and $RemainingInclude.Count -gt 0 -and -not $Search) {
    $Include = @($Include) + @($RemainingInclude)
}

function Format-ReparoLogValue {
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

function Write-ReparoParameterBlock {
    $effectiveParameters = [ordered]@{
        Help                         = $Help
        Version                      = $Version
        New                          = $New
        Preview                      = $Preview
        WindowsUpdate                = $WindowsUpdate
        WslApt                       = $WslApt
        Update                       = $Update
        Winget                       = $Winget
        WingetDiscover               = $WingetDiscover
        Search                       = $Search
        VersionLock                  = $VersionLock
        AddVersionLock               = $AddVersionLock
        VersionLockPath              = $VersionLockPath
        ListVersionLocks             = $ListVersionLocks
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
        CheckApp                     = $CheckApp
        LockApp                      = $LockApp
        LockVersion                  = $LockVersion
        PackageManager               = $PackageManager
        InstallSpicetify             = $InstallSpicetify
        Force                        = $Force
        Kill                         = $Kill
        KillUpdaterNames             = $KillUpdaterNames
        IgnoreTimeouts               = $IgnoreTimeouts
        WingetTimeoutSeconds         = $WingetTimeoutSeconds
        WingetDiscoveryTimeoutSeconds = $WingetDiscoveryTimeoutSeconds
        WindowsUpdateTimeoutSeconds   = $WindowsUpdateTimeoutSeconds
        WslAptTimeoutSeconds          = $WslAptTimeoutSeconds
        InstallNuGetProvider         = $InstallNuGetProvider
        AllowReboot                  = $AllowReboot
        LogRoot                      = $LogRoot
        InstallRoot                  = $InstallRoot
        SourceUrl                    = $SourceUrl
        NoBackup                     = $NoBackup
        Status                       = $Status
        Sweep                        = $Sweep
        DeleteStale                  = $DeleteStale
        Tail                         = $Tail
        TailLines                    = $TailLines
        Include                      = $Include
        RemainingInclude             = $RemainingInclude
        Debug                        = [bool]($PSBoundParameters.ContainsKey('Debug'))
    }

    Write-ReparoLog '[FLAGS] Effective parameters:'
    foreach ($entry in $effectiveParameters.GetEnumerator()) {
        Write-ReparoLog ("[FLAGS]   {0}={1}" -f $entry.Key, (Format-ReparoLogValue -Value $entry.Value))
    }
}

function Ensure-ReparoNuGetProvider {
    if (-not $InstallNuGetProvider) {
        Write-ReparoDebug 'NuGet provider bootstrap disabled by configuration.'
        return $false
    }

    $minimumVersion = [Version]'2.8.5.201'

    try {
        $provider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        if ($provider -and $provider.Version -and ([Version]$provider.Version -ge $minimumVersion)) {
            Write-ReparoDebug ("NuGet provider already available: {0}" -f $provider.Version)

            try {
                Import-PackageProvider -Name NuGet -MinimumVersion $minimumVersion -Force -ErrorAction SilentlyContinue | Out-Null
            }
            catch {
                Write-ReparoDebug ("NuGet provider import warning: {0}" -f $_.Exception.Message)
            }

            return $true
        }

        Write-ReparoLog '[INFO] NuGet provider missing or outdated; attempting bootstrap from PSGallery.'
        Write-ReparoDebug 'Starting NuGet provider bootstrap path.'
        Write-ReparoEventLog -EventId 1500 -EntryType Information -Message @"
Reparo bootstrap requested: NuGet provider.

Computer: $env:COMPUTERNAME
PID: $PID
MinimumVersion: $minimumVersion
Log: $script:ReparoLogPath
"@

        if (Get-Command Set-PSRepository -ErrorAction SilentlyContinue) {
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue | Out-Null
        }

        Install-PackageProvider -Name NuGet -MinimumVersion $minimumVersion -Force -ForceBootstrap -Scope AllUsers -Confirm:$false -ErrorAction Stop | Out-Null
        Import-PackageProvider -Name NuGet -MinimumVersion $minimumVersion -Force -ErrorAction Stop | Out-Null

        Write-ReparoLog '[DONE] NuGet provider installed successfully.'
        Write-ReparoDebug 'NuGet provider bootstrap completed successfully.'
        Write-ReparoEventLog -EventId 1501 -EntryType Information -Message @"
Reparo bootstrap completed: NuGet provider.

Computer: $env:COMPUTERNAME
PID: $PID
MinimumVersion: $minimumVersion
Log: $script:ReparoLogPath
"@
        return $true
    }
    catch {
        Write-ReparoLog ("[WARN] NuGet provider install failed: {0}" -f $_.Exception.Message)
        Write-ReparoDebug ("NuGet provider bootstrap failed: {0}" -f $_.Exception.Message)
        Write-ReparoEventLog -EventId 1502 -EntryType Warning -Message @"
Reparo bootstrap failed: NuGet provider.

Computer: $env:COMPUTERNAME
PID: $PID
MinimumVersion: $minimumVersion
Error: $($_.Exception.Message)
Log: $script:ReparoLogPath
"@
        return $false
    }
}

function Show-ReparoHelp {
    $versionQuote = Get-ReparoVersionQuote
    $versionArt = Get-ReparoVersionArt
    $helpText = @"
Reparo $script:ReparoVersion
$versionArt
$versionQuote

Usage:
  reparo
  reparo -Version
  reparo -CheckApp Git.Git -PackageManager Winget
  reparo -LockApp Git.Git -LockVersion 2.51.0 -PackageManager Winget
  reparo -Kill
  reparo -Kill -KillUpdaterNames winget msiexec
  reparo -Update
  reparo -Install
  reparo -Preview -Update
  reparo -Winget
  reparo -WingetDiscover
  reparo -List
  reparo -Search git
  reparo -List git
  reparo -Search git | Where-Object Method -eq winget
  reparo -AddVersionLock winget:ScanSnap.PackageId=1.2.3
  reparo -ListVersionLocks
  reparo -Preview -MigrateChocoToWinget -MigrationReportPath "$env:USERPROFILE\Desktop\reparo-choco-winget-preview"
  reparo -MigrateChocoToWinget -ChocoDeregisterOnly
  reparo -FinalizeChocolateyRemoval
  reparo -Tail
  reparo -Status
  reparo -Status -Sweep
  reparo -Include Winget Choco

Modes:
  Default              Run Windows Update only.
  -Update              Run the managed-client pass: Winget, Winget(msstore), Choco, PowerShell7, WindowsUpdate.
                        Updated package rows show current version -> target version when available.
  -Winget              Run a winget-focused pass. Reparo attempts to repair/register App Installer,
                       logs discovery output, then runs the Winget sections. In preview mode,
                       discovery still runs so you can refresh the visible upgrade list.
  -WingetDiscover      Repair/register winget if needed, then run only winget discovery commands.
                       This refreshes the visible upgrade list without starting live installs.
  -Search,-List,-S,-L  Inventory software Reparo -Force can update, with installed versions.
                       Optional terms filter by name, id, method, source, or version.
  -VersionLock         Inline lock specs: method:id=version. Example: winget:Git.Git=2.51.0.
                       Locks are matched case-insensitively by method and package id/name.
  -AddVersionLock      Persist lock specs to the local workstation lock file, then exit.
                       Use this for client/workstation-specific exclusions like ScanSnap.
  -VersionLockPath     JSON lock file. Default: C:\ProgramData\Reparo\version-locks.json.
                       Supports [{"Method":"winget","Id":"Git.Git","Version":"2.51.0"}]
                       or {"winget:Git.Git":"2.51.0"}.
  -ListVersionLocks    Print resolved version locks and exit.
  -MigrateChocoToWinget
                       Build a plan from Chocolatey inventory, winget availability,
                       duplicate groups, Chocolatey ProgramData payloads, and PATH shims.
                       Live mode installs/verifies winget replacements. Chocolatey cleanup is
                       safe deregistration with skip flags, not app uninstall.
                       Use -Preview first and review the CSV/JSON report.
  -ChocoDeregisterOnly After winget verification, deregister safe Chocolatey records with
                       --skip-autouninstaller and --skip-powershell.
  -ForceWingetReinstall
                       Allow winget install --force during migration. Off by default.
  -AllowRuntimeDeregister
                       Allow runtime package Chocolatey records to be deregistered.
  -AllowPortableDeregister
                       Allow portable/CLI payload records after non-Chocolatey command verification.
  -FinalizeChocolateyRemoval
                       Separate explicit Chocolatey removal phase. Backs up first and blocks
                       if non-excluded packages or Chocolatey-only commands remain.
  -MigrationReportPath Export migration plan/results. A bare path writes .csv and .json.
  -CheckApp <id/name>  Show the installed version of one app through winget/choco.
  -LockApp <id/name>   Pin one app so package-manager update passes do not move it.
  -LockVersion <ver>   Version to pin. If omitted, Reparo tries to pin the currently installed version.
  -PackageManager      App lookup/lock backend: Auto, Winget, or Choco. Default: Auto.
  -InstallSpicetify    Install or reinstall Spicetify Marketplace in the logged-on user's context,
                       then run Spicetify update and restore/backup/apply.
  -ChocoWingetMapPath  Optional JSON or CSV map for site-specific package IDs.
                       JSON can be an object like {"git":"Git.Git"} or an array with
                       ChocoId/WingetId/Source fields. CSV uses ChocoId,WingetId,Source.
  -MigrateChocoExclude Extra Chocolatey package IDs to skip during migration.
  -IgnoreTimeouts      Disable command-step timeout enforcement even when timeout parameters are supplied.
  -AllowReboot,-Reboot Allow Windows Update to auto-reboot if PSWindowsUpdate requires it.
                       Default behavior still uses -IgnoreReboot.
  -Install, -New       Install/update C:\ProgramData\Reparo\Reparo.ps1 from GitHub.
  -Force               Run all sections, including developer toolchains and WSL apt handling.
  -Kill                Stop running Reparo PowerShell processes and known updater front ends.
  -KillUpdaterNames    Additional process base names swept by -Kill after Reparo process trees stop.
                       Default: winget, choco, chocolatey, scoop, pip, pipx, npm, pnpm,
                       yarn, dotnet, rustup, cargo, conda, mamba, gem, composer.
  -Preview             Show what would run without executing update commands.
  -Tail, -Log          Follow the active log when used alone, or print this run's log tail at the end.
  -TailLines           Number of log lines to show when tailing. Default: 400.
  -Status              Show running state, pending reboot state, stale logs, and last completed run.
  -Sweep,-Clean,-Prune Rename stale _RUNNING logs to _STALE logs. Use with -Status or alone.
  -DeleteStale         With -Sweep, delete stale _RUNNING logs instead of renaming them.
  -Include <sections>  Run only selected sections, for example: -Include Winget Choco.
  -Debug               Emit extra trace logging into the Reparo log file.
  -Version,-V          Show the Reparo version.
  -Help,-H             Show this help.

Timeouts:
  Most command timeouts are disabled by default. WSL apt has a default timeout
  because unattended sudo/apt sessions can otherwise wait forever.
  -WingetTimeoutSeconds          Optional live Winget upgrade timeout.
  -WingetDiscoveryTimeoutSeconds Optional discovery timeout used by -Winget.
  -WindowsUpdateTimeoutSeconds   Optional Windows Update timeout.
  -WslAptTimeoutSeconds          WSL apt timeout. Default: 1800 seconds.
  -InstallNuGetProvider         When true (default), bootstrap the NuGet provider before PSGallery installs.
  -AllowReboot                  Let the Windows Update section pass -AutoReboot instead of -IgnoreReboot.

Windows Update:
  Reparo will try to install PSWindowsUpdate from PSGallery if the module is missing
  and the session has the rights and network access to do so.

Install/update:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -Install

After install, new PowerShell sessions can usually run:
  reparo -Update
  reparo -Install

Common sections:
  Winget, Winget(msstore), Choco, PowerShell7, WindowsUpdate, Scoop, Pip, Pipx, Npm,
  Pnpm, Yarn, DotNet, Rust, CargoBins, Conda, Gem, Composer, Spicetify,
  Wsl, WslApt.

Logs:
  C:\ProgramData\Reparo\Logs
"@

    Write-Host $helpText
}

if ($Help) {
    Show-ReparoHelp
    return
}

if ($Version) {
    Write-Host "Reparo $script:ReparoVersion"
    Write-Host "Source: $PSCommandPath"
    Write-Host (Get-ReparoVersionQuote)
    return
}

$updateSections = @(
    'WindowsUpdate'
    'Winget'
    'Winget(msstore)'
    'Choco'
    'PowerShell7'
)

if ($Winget) {
    $Include = @(
        'Winget'
        'Winget(msstore)'
        'Winget(source list)'
        'Winget(list upgrades)'
    )
}
elseif ($WingetDiscover) {
    $Include = @(
        'Winget(source list)'
        'Winget(list upgrades)'
        'Winget(upgrade list)'
    )
}
if ($Force) {
    $Preview = $false
    $WindowsUpdate = $true
    $WslApt = $true
    $IgnoreTimeouts = $true
    $Include = $null
}
elseif ($Update) {
    $WindowsUpdate = $true
    $Include = $updateSections
}
elseif ($InstallSpicetify) {
    $Include = @('Spicetify')
}

if (-not (Test-Path -LiteralPath $LogRoot)) {
    New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
}

$script:ReparoLogBaseName = "reparo_{0}_{1}_{2}" -f $env:COMPUTERNAME, $PID, (Get-Date -Format 'yyyy-MM-dd_HHmmss')
$script:ReparoLogPath = Join-Path $LogRoot ($script:ReparoLogBaseName + '_RUNNING.log')
$script:ReparoDebug = $PSBoundParameters.ContainsKey('Debug') -or ($DebugPreference -ne 'SilentlyContinue' -and $DebugPreference -ne 'Ignore')
# Event IDs are scoped by LogName + Source. Reparo uses Application/Reparo with local ranges:
# 1000-1099 run lifecycle, 1100-1199 install/update, 1200-1299 command/section,
# 1300-1399 reboot handling, 1400-1499 kill operations, 1500-1599 bootstrap/repair.
$script:ReparoEventLogSource = 'Reparo'
$script:ReparoEventLogReady = $null
$script:ReparoPendingRebootDetected = $false

function Write-ReparoDebug {
    param([string]$Message)

    if ($script:ReparoDebug -and -not [string]::IsNullOrWhiteSpace($Message)) {
        Write-ReparoLog ("[DEBUG] {0}" -f $Message)
    }
}

function Write-Info($Message) { Write-Host "INFO  $Message" -ForegroundColor Cyan }
function Write-Step($Message) { Write-Host "STEP  $Message" -ForegroundColor Yellow }
function Write-Skip($Message) { Write-Host "SKIP  $Message" -ForegroundColor DarkGray }
function Write-Done($Message) { Write-Host "DONE  $Message" -ForegroundColor Green }
function Write-Fail($Message) { Write-Host "FAIL  $Message" -ForegroundColor Red }

function ConvertTo-ReparoPowerShellLiteral {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) {
        return '$null'
    }

    return ("'{0}'" -f ($Value -replace "'", "''"))
}

function ConvertTo-ReparoSafeFileName {
    param([string]$Value)

    $safe = ([string]$Value) -replace '[^A-Za-z0-9_.-]+', '_'
    $safe = $safe.Trim('_')
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return 'command'
    }

    return $safe
}

function Get-ReparoChildProcessIds {
    param([Parameter(Mandatory)][int]$ParentProcessId)

    $children = @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { [int]$_.ParentProcessId -eq $ParentProcessId }
    )

    foreach ($child in $children) {
        Get-ReparoChildProcessIds -ParentProcessId ([int]$child.ProcessId)
        [int]$child.ProcessId
    }
}

function Stop-ReparoProcessTree {
    param([Parameter(Mandatory)][int]$ProcessId)

    $processIds = @(
        Get-ReparoChildProcessIds -ParentProcessId $ProcessId
        $ProcessId
    ) | Select-Object -Unique

    foreach ($processId in $processIds) {
        try {
            Stop-Process -Id ([int]$processId) -Force -ErrorAction Stop
        }
        catch {
            Write-ReparoDebug ("Process-tree stop warning for PID {0}: {1}" -f $processId, $_.Exception.Message)
        }
    }
}

function Get-ReparoProtectedProcessIds {
    param([int]$ProcessId = $PID)

    $ids = New-Object System.Collections.Generic.List[int]
    [void]$ids.Add([int]$ProcessId)

    $ancestor = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue
    while ($ancestor -and $ancestor.ParentProcessId) {
        $ancestorId = [int]$ancestor.ParentProcessId
        if ($ids.Contains($ancestorId)) {
            break
        }

        [void]$ids.Add($ancestorId)
        $ancestor = Get-CimInstance Win32_Process -Filter "ProcessId = $ancestorId" -ErrorAction SilentlyContinue
    }

    $ids.ToArray()
}

function ConvertTo-ReparoProcessBaseName {
    param([AllowNull()][string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $null
    }

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($Name.Trim())
    if ([string]::IsNullOrWhiteSpace($baseName)) {
        return $null
    }

    $baseName.ToLowerInvariant()
}

function Get-ReparoDefaultKillUpdaterNames {
    @(
        'winget',
        'choco',
        'chocolatey',
        'scoop',
        'pip',
        'pipx',
        'npm',
        'pnpm',
        'yarn',
        'dotnet',
        'rustup',
        'cargo',
        'conda',
        'mamba',
        'gem',
        'composer'
    )
}

function Invoke-ReparoKillUpdaterProcesses {
    [CmdletBinding()]
    param([string[]]$ProcessNames = $KillUpdaterNames)

    $allProcessNames = @(Get-ReparoDefaultKillUpdaterNames) + @($ProcessNames)
    $targetNames = @(
        foreach ($name in $allProcessNames) {
            $baseName = ConvertTo-ReparoProcessBaseName -Name $name
            if ($baseName) { $baseName }
        }
    ) | Sort-Object -Unique

    if (-not $targetNames -or $targetNames.Count -eq 0) {
        Write-Warning 'No updater process names were provided for the -Kill sweep.'
        return
    }

    Write-Info ("Sweeping updater processes: {0}" -f ($targetNames -join ', '))
    $protectedPids = @(Get-ReparoProtectedProcessIds -ProcessId $PID)

    $processes = @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                -not ($protectedPids -contains [int]$_.ProcessId) -and
                $targetNames -contains (ConvertTo-ReparoProcessBaseName -Name $_.Name)
            }
    )

    if (-not $processes -or $processes.Count -eq 0) {
        Write-Info 'No updater processes found.'
        return
    }

    $results = foreach ($process in $processes) {
        $status = 'Forced'
        $errorText = $null

        try {
            Stop-ReparoProcessTree -ProcessId ([int]$process.ProcessId)
            $waitUntil = [DateTime]::UtcNow.AddSeconds(3)
            do {
                Start-Sleep -Milliseconds 100
                $stillRunning = Get-Process -Id ([int]$process.ProcessId) -ErrorAction SilentlyContinue
            } while ($stillRunning -and [DateTime]::UtcNow -lt $waitUntil)

            if ($stillRunning) {
                $status = 'Still running'
            }
        }
        catch {
            $status = 'Failed'
            $errorText = $_.Exception.Message
        }

        [pscustomobject]@{
            PID       = [int]$process.ProcessId
            Name      = $process.Name
            ParentPID = [int]$process.ParentProcessId
            Status    = $status
            Error     = $errorText
        }
    }

    $results | Format-Table -AutoSize
    Write-ReparoEventLog -EventId 1401 -EntryType Warning -Message @"
Reparo updater process kill sweep completed.

Computer: $env:COMPUTERNAME
PID: $PID
Targets: $($targetNames -join ', ')
Results:
$(($results | Format-Table -AutoSize | Out-String).Trim())
Log: $script:ReparoLogPath
"@
}

function Invoke-ReparoKill {
    [CmdletBinding()]
    param()

    $excludedPids = @(Get-ReparoProtectedProcessIds -ProcessId $PID)

    $processes = @(
        Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction SilentlyContinue |
            Where-Object {
                -not ($excludedPids -contains [int]$_.ProcessId) -and
                $_.CommandLine -and
                $_.CommandLine -notmatch '(?i)(^|\s)-Command(\s|$)' -and
                $_.CommandLine -match '(?i)(^|\s)-File\s+["'']?[^"'']*Reparo\.ps1(["''\s]|$)' -and
                $_.CommandLine -notmatch '(?i)(^|\s)-Kill(\s|$)'
            }
    )

    if (-not $processes -or $processes.Count -eq 0) {
        Write-Info 'No running Reparo PowerShell processes found.'
    }
    else {
        $results = foreach ($process in $processes) {
            $status = 'Stopped'
            $errorText = $null

            try {
                $liveProcess = Get-Process -Id ([int]$process.ProcessId) -ErrorAction Stop
                $closedGracefully = $false

                if ($liveProcess.MainWindowHandle -ne 0) {
                    $closedGracefully = $liveProcess.CloseMainWindow()
                    if ($closedGracefully) {
                        $liveProcess.WaitForExit(5000)
                    }
                }

                $stillRunning = Get-Process -Id ([int]$process.ProcessId) -ErrorAction SilentlyContinue
                if ($stillRunning) {
                    Stop-ReparoProcessTree -ProcessId ([int]$process.ProcessId)
                    $status = if ($closedGracefully) { 'Forced after graceful timeout' } else { 'Forced' }
                }
                elseif ($closedGracefully) {
                    $status = 'Gracefully stopped'
                }
            }
            catch {
                $status = 'Failed'
                $errorText = $_.Exception.Message
            }

            [pscustomobject]@{
                PID    = [int]$process.ProcessId
                Name   = $process.Name
                Status = $status
                Error  = $errorText
            }
        }

        $results | Format-Table -AutoSize
        Write-ReparoEventLog -EventId 1400 -EntryType Warning -Message @"
Reparo process kill completed.

Computer: $env:COMPUTERNAME
PID: $PID
Results:
$(($results | Format-Table -AutoSize | Out-String).Trim())
Log: $script:ReparoLogPath
"@
    }

    Invoke-ReparoKillUpdaterProcesses -ProcessNames $KillUpdaterNames
}

function Test-ReparoScriptParse {
    param([Parameter(Mandatory)][string]$Path)

    $tokens = $null
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)

    if ($errors -and $errors.Count -gt 0) {
        $message = ($errors | ForEach-Object { $_.Message }) -join '; '
        throw "Reparo.ps1 failed PowerShell parse validation: $message"
    }
}

function Get-ReparoFileHash {
    param([Parameter(Mandatory)][string]$Path)

    if (Get-Command Get-FileHash -ErrorAction SilentlyContinue) {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    }

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $bytes = $sha256.ComputeHash($stream)
            return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '').ToUpperInvariant()
        }
        finally {
            $sha256.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Install-ReparoCommandShim {
    param(
        [Parameter(Mandatory)][string]$TargetRoot,
        [switch]$WhatIfOnly
    )

    $binRoot = Join-Path $TargetRoot 'bin'
    $shimPath = Join-Path $binRoot 'reparo.cmd'
    $scriptPath = Join-Path $TargetRoot 'Reparo.ps1'
    $shimContent = @"
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$scriptPath" %*
exit /b %ERRORLEVEL%
"@

    if ($WhatIfOnly) {
        Write-Info "Would create command shim: $shimPath"
    }
    else {
        New-Item -ItemType Directory -Force -Path $binRoot | Out-Null
        Set-Content -LiteralPath $shimPath -Value $shimContent -Encoding ASCII
        Write-Info "Command shim installed: $shimPath"
    }

    $pathSeparator = [System.IO.Path]::PathSeparator
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $machineParts = @($machinePath -split [regex]::Escape([string]$pathSeparator) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $machineHasShim = $machineParts -contains $binRoot

    if ($machineHasShim) {
        Write-Info "Machine PATH already includes: $binRoot"
    }
    elseif ($WhatIfOnly) {
        Write-Info "Would add to machine PATH: $binRoot"
    }
    else {
        try {
            $newMachinePath = (@($machineParts) + $binRoot) -join $pathSeparator
            [Environment]::SetEnvironmentVariable('Path', $newMachinePath, 'Machine')
            Write-Info "Added to machine PATH: $binRoot"
        }
        catch {
            Write-Skip "Unable to update machine PATH: $($_.Exception.Message)"
            try {
                $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
                $userParts = @($userPath -split [regex]::Escape([string]$pathSeparator) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                if ($userParts -notcontains $binRoot) {
                    $newUserPath = (@($userParts) + $binRoot) -join $pathSeparator
                    [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
                    Write-Info "Added to user PATH instead: $binRoot"
                }
            }
            catch {
                Write-Skip "Unable to update user PATH: $($_.Exception.Message)"
            }
        }
    }

    $processParts = @($env:Path -split [regex]::Escape([string]$pathSeparator) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($processParts -notcontains $binRoot) {
        $env:Path = (@($processParts) + $binRoot) -join $pathSeparator
    }
}

function Invoke-ReparoNew {
    param(
        [Parameter(Mandatory)][string]$TargetRoot,
        [Parameter(Mandatory)][string]$Url,
        [switch]$SkipBackup,
        [switch]$WhatIfOnly
    )

    $scriptPath = Join-Path $TargetRoot 'Reparo.ps1'
    $targetLogRoot = Join-Path $TargetRoot 'Logs'
    $backupRoot = Join-Path $TargetRoot 'Backups'
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ReparoNew_{0}_{1}" -f $PID, (Get-Date -Format 'yyyyMMddHHmmss'))
    $tempScript = Join-Path $tempRoot 'Reparo.ps1'

    Write-Info "Install root: $TargetRoot"
    Write-Info "Source: $Url"
    Write-ReparoEventLog -EventId 1100 -EntryType Information -Message @"
Reparo install/update requested.

Computer: $env:COMPUTERNAME
PID: $PID
Version: $script:ReparoVersion
TargetRoot: $TargetRoot
Source: $Url
Preview: $WhatIfOnly
SkipBackup: $SkipBackup
Log: $script:ReparoLogPath
"@

    if ($WhatIfOnly) {
        Write-Info 'Preview only. No files will be replaced.'
    }

    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $Url -OutFile $tempScript -UseBasicParsing
        Unblock-File -LiteralPath $tempScript -ErrorAction SilentlyContinue
        Test-ReparoScriptParse -Path $tempScript

        $newHash = Get-ReparoFileHash -Path $tempScript
        if (Test-Path -LiteralPath $scriptPath) {
            $currentHash = Get-ReparoFileHash -Path $scriptPath
            if ($currentHash -eq $newHash) {
                Write-Skip "Installed Reparo.ps1 is already current ($newHash)."
                Install-ReparoCommandShim -TargetRoot $TargetRoot -WhatIfOnly:$WhatIfOnly
                Write-ReparoEventLog -EventId 1101 -EntryType Information -Message @"
Reparo install/update skipped; installed script is already current.

Computer: $env:COMPUTERNAME
PID: $PID
TargetRoot: $TargetRoot
SHA256: $newHash
Log: $script:ReparoLogPath
"@
                return
            }
        }

        if ($WhatIfOnly) {
            Write-Info "Would replace: $scriptPath"
            Write-Info "New SHA256: $newHash"
            Install-ReparoCommandShim -TargetRoot $TargetRoot -WhatIfOnly
            Write-ReparoEventLog -EventId 1103 -EntryType Warning -Message @"
Reparo install/update preview completed; no files were replaced.

Computer: $env:COMPUTERNAME
PID: $PID
TargetRoot: $TargetRoot
TargetScript: $scriptPath
NewSHA256: $newHash
Log: $script:ReparoLogPath
"@
            return
        }

        New-Item -ItemType Directory -Force -Path $TargetRoot, $targetLogRoot | Out-Null

        if ((Test-Path -LiteralPath $scriptPath) -and -not $SkipBackup) {
            New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
            $backupPath = Join-Path $backupRoot ("Reparo_{0}.ps1" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
            Copy-Item -LiteralPath $scriptPath -Destination $backupPath -Force
            Write-Info "Backup saved: $backupPath"
        }

        Copy-Item -LiteralPath $tempScript -Destination $scriptPath -Force
        Write-Done "Installed Reparo.ps1 updated ($newHash)."
        Write-Info "Live script: $scriptPath"
        Install-ReparoCommandShim -TargetRoot $TargetRoot
        Write-ReparoEventLog -EventId 1102 -EntryType Information -Message @"
Reparo install/update completed.

Computer: $env:COMPUTERNAME
PID: $PID
TargetRoot: $TargetRoot
TargetScript: $scriptPath
SHA256: $newHash
Log: $script:ReparoLogPath
"@
    }
    catch {
        Write-ReparoEventLog -EventId 1104 -EntryType Error -Message @"
Reparo install/update failed.

Computer: $env:COMPUTERNAME
PID: $PID
TargetRoot: $TargetRoot
Source: $Url
Error: $($_.Exception.Message)
Log: $script:ReparoLogPath
"@
        throw
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Write-ReparoLog {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Message,
        [int]$Retries = 6,
        [int]$DelayMs = 200
    )

    if ($null -eq $Message) {
        $Message = ''
    }

    for ($i = 1; $i -le $Retries; $i++) {
        try {
            $fs = [System.IO.File]::Open(
                $script:ReparoLogPath,
                [System.IO.FileMode]::Append,
                [System.IO.FileAccess]::Write,
                [System.IO.FileShare]::ReadWrite
            )

            try {
                $sw = New-Object System.IO.StreamWriter($fs)
                $sw.WriteLine([string]$Message)
                $sw.Flush()
            }
            finally {
                if ($sw) { $sw.Dispose() }
                $fs.Dispose()
            }

            return
        }
        catch {
            if ($i -lt $Retries) {
                Start-Sleep -Milliseconds $DelayMs
                continue
            }

            Write-Warning "Failed to write to log file '$script:ReparoLogPath': $($_.Exception.Message)"
        }
    }
}

function Test-ReparoCurrentProcessElevated {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        Write-ReparoLog ("[EVENTLOG] Unable to determine elevation state: {0}" -f $_.Exception.Message)
        return $false
    }
}

function Ensure-ReparoEventLogSource {
    if ($null -ne $script:ReparoEventLogReady) {
        return [bool]$script:ReparoEventLogReady
    }

    $script:ReparoEventLogReady = $false

    try {
        if (-not (Get-Command Write-EventLog -ErrorAction SilentlyContinue)) {
            Write-ReparoLog '[EVENTLOG] Write-EventLog is unavailable in this PowerShell host; skipping Windows Event Log output.'
            return $false
        }

        if (-not [System.Diagnostics.EventLog]::SourceExists($script:ReparoEventLogSource)) {
            if (-not (Test-ReparoCurrentProcessElevated)) {
                Write-ReparoLog ("[EVENTLOG] Source {0} does not exist and shell is not elevated; skipping Windows Event Log registration." -f $script:ReparoEventLogSource)
                return $false
            }

            New-EventLog -LogName Application -Source $script:ReparoEventLogSource
            Write-ReparoLog ("[EVENTLOG] Registered Application event source: {0}" -f $script:ReparoEventLogSource)
        }

        $script:ReparoEventLogReady = $true
        return $true
    }
    catch {
        Write-ReparoLog ("[EVENTLOG] Unable to register/check event source: {0}" -f $_.Exception.Message)
        return $false
    }
}

function Write-ReparoEventLog {
    param(
        [Parameter(Mandatory)][int]$EventId,
        [ValidateSet('Information', 'Warning', 'Error')]
        [string]$EntryType = 'Information',
        [Parameter(Mandatory)][string]$Message
    )

    try {
        if (-not (Ensure-ReparoEventLogSource)) {
            return
        }

        $eventMessage = [string]$Message
        if ($eventMessage.Length -gt 30000) {
            $eventMessage = $eventMessage.Substring(0, 30000) + "`r`n...[truncated]"
        }

        Write-EventLog -LogName Application -Source $script:ReparoEventLogSource -EventId $EventId -EntryType $EntryType -Message $eventMessage
        Write-ReparoLog ("[EVENTLOG] Wrote Application/{0} event {1}." -f $script:ReparoEventLogSource, $EventId)
    }
    catch {
        Write-ReparoLog ("[EVENTLOG] Failed writing event {0}: {1}" -f $EventId, $_.Exception.Message)
    }
}

function Get-ReparoPendingRebootEvidence {
    $checks = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
        'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    )

    try {
        if (Test-Path -LiteralPath $checks[0]) {
            [pscustomobject]@{
                Source = 'Component Based Servicing'
                Path   = $checks[0]
                Detail = 'Registry key exists'
            }
        }

        if (Test-Path -LiteralPath $checks[1]) {
            [pscustomobject]@{
                Source = 'Windows Update'
                Path   = $checks[1]
                Detail = 'Registry key exists'
            }
        }

        $sessionManager = Get-ItemProperty -LiteralPath $checks[2] -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
        if ($sessionManager -and $sessionManager.PendingFileRenameOperations) {
            $operations = @($sessionManager.PendingFileRenameOperations)
            for ($i = 0; $i -lt $operations.Count; $i += 2) {
                $source = [string]$operations[$i]
                $target = if (($i + 1) -lt $operations.Count) { [string]$operations[$i + 1] } else { '' }

                if ([string]::IsNullOrWhiteSpace($source) -and [string]::IsNullOrWhiteSpace($target)) {
                    continue
                }

                $detail = if ([string]::IsNullOrWhiteSpace($target)) {
                    "Pending delete: $source"
                }
                else {
                    "Pending rename: $source -> $target"
                }

                [pscustomobject]@{
                    Source = 'PendingFileRenameOperations'
                    Path   = $checks[2]
                    Detail = $detail
                }
            }
        }
    }
    catch {
        Write-ReparoLog ("[WARN] Pending reboot check failed: {0}" -f $_.Exception.Message)
    }
}

function Test-ReparoPendingReboot {
    $evidence = @(Get-ReparoPendingRebootEvidence)

    return ($evidence.Count -gt 0)
}

function Finalize-ReparoLogFile {
    param(
        [Parameter(Mandatory)][string]$Status
    )

    if ([string]::IsNullOrWhiteSpace($Status)) {
        $Status = 'COMPLETE'
    }

    $finalPath = Join-Path $LogRoot ($script:ReparoLogBaseName + "_{0}.log" -f $Status)

    try {
        if ((Test-Path -LiteralPath $script:ReparoLogPath) -and ($script:ReparoLogPath -ne $finalPath)) {
            Move-Item -LiteralPath $script:ReparoLogPath -Destination $finalPath -Force
            $script:ReparoLogPath = $finalPath
        }
    }
    catch {
        Write-Warning "Failed to finalize log file name: $($_.Exception.Message)"
        return
    }

    Write-Host ("Final log: {0}" -f $script:ReparoLogPath) -ForegroundColor Cyan
    Write-ReparoLog ("[SUMMARY] Final log renamed to: {0}" -f $script:ReparoLogPath)
}

function Get-ReparoRunningProcessInfo {
    param(
        [int[]]$ExcludeProcessIds = @()
    )

    $excludeSet = New-Object System.Collections.Generic.HashSet[int]
    foreach ($processId in $ExcludeProcessIds) {
        $null = $excludeSet.Add([int]$processId)
    }

    $processes = @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -in @('powershell.exe', 'pwsh.exe') -and
                -not $excludeSet.Contains([int]$_.ProcessId) -and
                $_.CommandLine -and
                $_.CommandLine -notmatch '(?i)(^|\s)-Command(\s|$)' -and
                $_.CommandLine -match '(?i)(^|\s)-File\s+["'']?[^"'']*Reparo\.ps1(["''\s]|$)' -and
                $_.CommandLine -notmatch '(?i)(^|\s)-Kill(\s|$)'
            }
    )

    foreach ($process in $processes) {
        [pscustomobject]@{
            PID         = [int]$process.ProcessId
            Name        = $process.Name
            CommandLine = [string]$process.CommandLine
            LogPath     = (Get-ReparoLogPathForPid -ProcessId ([int]$process.ProcessId))
            Running     = [bool](Get-Process -Id ([int]$process.ProcessId) -ErrorAction SilentlyContinue)
        }
    }
}

function Get-ReparoLogPathForPid {
    param(
        [Parameter(Mandatory)][int]$ProcessId
    )

    $patterns = @(
        "reparo_*_${ProcessId}_*_RUNNING.log"
        "reparo_*_${ProcessId}_*.log"
    )

    foreach ($pattern in $patterns) {
        $match = Get-ChildItem -LiteralPath $LogRoot -File -Filter $pattern -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($match) { return $match.FullName }
    }

    return $null
}

function Get-ReparoLatestCompletedLog {
    Get-ChildItem -LiteralPath $LogRoot -File -Filter 'reparo_*.log' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike '*_RUNNING.log' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Get-ReparoStaleRunningLog {
    param([object[]]$RunningProcessInfo = $null)

    if ($null -eq $RunningProcessInfo) {
        $RunningProcessInfo = @(Get-ReparoRunningProcessInfo -ExcludeProcessIds @($PID))
    }

    $runningLogPaths = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($process in $RunningProcessInfo) {
        if ($process.LogPath) {
            $null = $runningLogPaths.Add($process.LogPath)
        }
    }

    Get-ChildItem -LiteralPath $LogRoot -File -Filter 'reparo_*_*_RUNNING.log' -ErrorAction SilentlyContinue |
        Where-Object {
            if ($runningLogPaths.Contains($_.FullName)) { return $false }
            if ($_.Name -match '_(\d+)_\d{4}-\d{2}-\d{2}_\d{6}_RUNNING\.log$') {
                return -not [bool](Get-Process -Id ([int]$matches[1]) -ErrorAction SilentlyContinue)
            }

            return $true
        }
}

function Invoke-ReparoStaleLogSweep {
    param([switch]$Delete)

    $staleLogs = @(Get-ReparoStaleRunningLog)
    if ($staleLogs.Count -eq 0) {
        Write-Info 'No stale running logs found.'
        return
    }

    $results = foreach ($log in ($staleLogs | Sort-Object LastWriteTime -Descending)) {
        $status = if ($Delete) { 'Deleted' } else { 'Renamed' }
        $targetPath = $null
        $errorText = $null

        try {
            if ($Delete) {
                Remove-Item -LiteralPath $log.FullName -Force -ErrorAction Stop
            }
            else {
                $targetPath = $log.FullName -replace '_RUNNING\.log$', '_STALE.log'
                Move-Item -LiteralPath $log.FullName -Destination $targetPath -Force -ErrorAction Stop
            }
        }
        catch {
            $status = 'Failed'
            $errorText = $_.Exception.Message
        }

        [pscustomobject]@{
            Status = $status
            Source = $log.FullName
            Target = $targetPath
            Error  = $errorText
        }
    }

    $results | Format-Table -AutoSize

    $failedCount = @($results | Where-Object { $_.Status -eq 'Failed' }).Count
    $eventId = if ($failedCount -gt 0) { 1404 } elseif ($Delete) { 1403 } else { 1402 }
    $entryType = if ($failedCount -gt 0) { 'Warning' } else { 'Information' }
    $action = if ($Delete) { 'deleted' } else { 'renamed' }

    Write-ReparoEventLog -EventId $eventId -EntryType $entryType -Message @"
Reparo stale running log sweep completed.

Computer: $env:COMPUTERNAME
PID: $PID
Action: $action
Found: $($staleLogs.Count)
Failed: $failedCount
Results:
$(($results | Format-Table -AutoSize | Out-String).Trim())
LogRoot: $LogRoot
"@
}

function Get-ReparoLogMetadata {
    param([Parameter(Mandatory)]$LogFile)

    $name = if ($LogFile -is [System.IO.FileInfo]) { $LogFile.Name } else { [System.IO.Path]::GetFileName([string]$LogFile) }
    if ($name -notmatch '^reparo_(?<Computer>.+)_(?<PID>\d+)_(?<Timestamp>\d{4}-\d{2}-\d{2}_\d{6})_(?<Status>RUNNING|COMPLETE|FAILED|PREVIEW)\.log$') {
        return $null
    }

    $started = $null
    try {
        $started = [DateTime]::ParseExact($matches['Timestamp'], 'yyyy-MM-dd_HHmmss', [Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        $started = $null
    }

    [pscustomobject]@{
        Computer = $matches['Computer']
        PID      = [int]$matches['PID']
        Started  = $started
        Status   = $matches['Status']
    }
}

function Format-ReparoAge {
    param([AllowNull()][DateTime]$Timestamp)

    if (-not $Timestamp) { return 'unknown' }

    $age = New-TimeSpan -Start $Timestamp -End (Get-Date)
    if ($age.TotalDays -ge 1) { return ('{0}d {1}h ago' -f [int][Math]::Floor($age.TotalDays), $age.Hours) }
    if ($age.TotalHours -ge 1) { return ('{0}h {1}m ago' -f [int][Math]::Floor($age.TotalHours), $age.Minutes) }
    if ($age.TotalMinutes -ge 1) { return ('{0}m {1}s ago' -f [int][Math]::Floor($age.TotalMinutes), $age.Seconds) }

    return ('{0}s ago' -f [int][Math]::Max(0, [Math]::Floor($age.TotalSeconds)))
}

function Get-ReparoActiveLogPath {
    param(
        [int[]]$ExcludeProcessIds = @()
    )

    $running = @(Get-ReparoRunningProcessInfo -ExcludeProcessIds $ExcludeProcessIds)
    if ($running.Count -gt 0) {
        $candidate = $running |
            Where-Object { $_.LogPath } |
            Sort-Object PID -Descending |
            Select-Object -First 1
        if ($candidate.LogPath) { return $candidate.LogPath }
    }

    $latest = Get-ReparoLatestCompletedLog
    if ($latest) { return $latest.FullName }

    return $null
}

function Show-ReparoStatus {
    $running = @(Get-ReparoRunningProcessInfo -ExcludeProcessIds @($PID))
    Write-Host 'REPARO status' -ForegroundColor Magenta
    Write-Host "Version: $script:ReparoVersion"
    Write-Host "Computer: $env:COMPUTERNAME"
    Write-Host "Log root: $LogRoot"

    $pendingRebootEvidence = @(Get-ReparoPendingRebootEvidence)
    if ($pendingRebootEvidence.Count -gt 0) {
        Write-Host 'Pending reboot: yes' -ForegroundColor Yellow
        Write-Host 'Pending reboot evidence:'
        $pendingRebootEvidence |
            Select-Object Source, Detail |
            Format-Table -AutoSize
    }
    else {
        Write-Host 'Pending reboot: no'
    }

    if ($running.Count -gt 0) {
        Write-Host "Running: $($running.Count)"
        $running |
            Select-Object PID, Name, LogPath, CommandLine |
            Format-Table -AutoSize
    }
    else {
        Write-Host 'Running: none'
    }

    $activeLog = $running |
        Where-Object { $_.LogPath } |
        Sort-Object PID -Descending |
        Select-Object -ExpandProperty LogPath -First 1
    if ($activeLog) {
        Write-Host "Active log: $activeLog"
    }
    else {
        Write-Host 'Active log: none'
    }

    $staleRunningLogs = @(Get-ReparoStaleRunningLog -RunningProcessInfo $running)
    if ($staleRunningLogs.Count -gt 0) {
        $recentCutoff = (Get-Date).AddHours(-24)
        $recentStaleLogs = @($staleRunningLogs | Where-Object { $_.LastWriteTime -ge $recentCutoff })
        $olderStaleCount = $staleRunningLogs.Count - $recentStaleLogs.Count

        Write-Host "Stale running logs: $($staleRunningLogs.Count)"
        if ($recentStaleLogs.Count -gt 0) {
            Write-Host 'Recent stale running logs (<24h):'
            $recentStaleLogs |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 5 |
            ForEach-Object {
                Write-Host "  $($_.FullName)"
            }
        }

        if ($olderStaleCount -gt 0) {
            Write-Host "Older stale running logs hidden: $olderStaleCount (use -Sweep to rename them _STALE)"
        }
    }

    $latest = Get-ReparoLatestCompletedLog
    if ($latest) {
        $metadata = Get-ReparoLogMetadata -LogFile $latest
        Write-Host ''
        Write-Host 'Last completed run:' -ForegroundColor Magenta
        if ($metadata) {
            Write-Host "  Status: $($metadata.Status)"
            Write-Host "  Started: $($metadata.Started) ($(Format-ReparoAge -Timestamp $metadata.Started))"
            Write-Host "  PID: $($metadata.PID)"
            Write-Host "  Computer: $($metadata.Computer)"
        }
        else {
            Write-Host '  Metadata: unavailable'
        }

        Write-Host "  Last write: $($latest.LastWriteTime) ($(Format-ReparoAge -Timestamp $latest.LastWriteTime))"
        Write-Host "  Log: $($latest.FullName)"
    }
    else {
        Write-Host 'Latest completed log: none'
    }
}

function Invoke-ReparoTailLog {
    param(
        [string]$LogPath,
        [int]$TailLines = 200,
        [switch]$Follow,
        [int]$PollSeconds = 2,
        [int]$QuietPollsAfterExit = 2
    )

    if (-not $LogPath) {
        Write-Warning 'No Reparo log file was found to tail.'
        return
    }

    $targetPid = $null
    if ($LogPath -match '_(\d+)_\d{4}-\d{2}-\d{2}_\d{6}_(?:RUNNING|COMPLETE|FAILED|PREVIEW)\.log$') {
        $targetPid = [int]$matches[1]
    }

    $printedLines = 0

    try {
        $allInitialLines = @(Get-Content -LiteralPath $LogPath)
        if ($allInitialLines.Count -gt $TailLines) {
            $initial = @($allInitialLines[($allInitialLines.Count - $TailLines)..($allInitialLines.Count - 1)])
        }
        else {
            $initial = $allInitialLines
        }

        $printedLines = $initial.Count
        foreach ($line in $initial) {
            Write-Host $line
        }

        $printedLines = $allInitialLines.Count
    }
    catch {
        Write-Warning "Unable to read log file '$LogPath': $($_.Exception.Message)"
        return
    }

    if (-not $Follow) {
        return
    }

    $quietPolls = 0
    while ($true) {
        Start-Sleep -Seconds $PollSeconds

        if ($targetPid) {
            $currentLog = Get-ReparoLogPathForPid -ProcessId $targetPid
            if ($currentLog) {
                $LogPath = $currentLog
            }
        }

        if (-not (Test-Path -LiteralPath $LogPath)) {
            $quietPolls++
        }
        else {
            try {
                $allLines = @(Get-Content -LiteralPath $LogPath)
                if ($allLines.Count -gt $printedLines) {
                    foreach ($line in $allLines[$printedLines..($allLines.Count - 1)]) {
                        Write-Host $line
                    }
                    $printedLines = $allLines.Count
                    $quietPolls = 0
                }
                else {
                    $quietPolls++
                }
            }
            catch {
                $quietPolls++
            }
        }

        if ($targetPid) {
            $stillRunning = [bool](Get-Process -Id $targetPid -ErrorAction SilentlyContinue)
            if (-not $stillRunning -and $quietPolls -ge $QuietPollsAfterExit) {
                break
            }
        }
        elseif ($quietPolls -ge $QuietPollsAfterExit) {
            break
        }
    }
}

if ($New) {
    Invoke-ReparoNew -TargetRoot $InstallRoot -Url $SourceUrl -SkipBackup:$NoBackup -WhatIfOnly:$Preview
    return
}

if ($Kill) {
    Invoke-ReparoKill
    return
}

if ($Status) {
    Show-ReparoStatus
    if ($Sweep) {
        Write-Host ''
        Write-Host 'Sweeping stale running logs' -ForegroundColor Magenta
        Invoke-ReparoStaleLogSweep -Delete:$DeleteStale
    }

    return
}

if ($Sweep) {
    Invoke-ReparoStaleLogSweep -Delete:$DeleteStale
    return
}

if ($DeleteStale) {
    Write-Warning '-DeleteStale only has an effect when used with -Sweep.'
    return
}

if ($Tail -and -not ($Update -or $Winget -or $WingetDiscover -or $Search -or $AddVersionLock -or $ListVersionLocks -or $MigrateChocoToWinget -or $FinalizeChocolateyRemoval -or $InstallSpicetify -or $Force -or $Preview -or $WindowsUpdate -or $WslApt -or $Include -or $New -or $Kill -or $Sweep -or $DeleteStale -or $CheckApp -or $LockApp)) {
    $tailTarget = Get-ReparoActiveLogPath -ExcludeProcessIds @($PID)
    if ($tailTarget) {
        Write-Host ("Following log: {0}" -f $tailTarget) -ForegroundColor Cyan
        Invoke-ReparoTailLog -LogPath $tailTarget -TailLines $TailLines -Follow
    }
    else {
        Write-Warning 'No active or completed Reparo log was found to tail.'
    }
    return
}

function Resolve-ReparoCommand {
    param([Parameter(Mandatory)][string]$Name)

    try {
        return (Get-Command $Name -CommandType Application -ErrorAction Stop)
    }
    catch {
        return $null
    }
}

function Test-Cmd($Name) {
    [bool](Resolve-ReparoCommand -Name $Name)
}

function Test-ReparoExecutable {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string[]]$Arguments = @('--version')
    )

    $command = Resolve-ReparoCommand -Name $Name
    if (-not $command) { return $false }

    try {
        $output = @(& $command.Source @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
        foreach ($item in $output) {
            $line = [string]$item
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                Write-ReparoLog ("[CHECK] {0}: {1}" -f $Name, $line)
            }
        }

        return ($exitCode -eq 0 -or $null -eq $exitCode)
    }
    catch {
        Write-ReparoLog ("[CHECK] {0} is present but cannot run: {1}" -f $Name, $_.Exception.Message)
        return $false
    }
}

function Test-Admin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($id)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Test-ReparoSystemIdentity {
    try {
        return ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-18')
    }
    catch {
        return $false
    }
}

function Get-ReparoInteractiveUserName {
    try {
        $explorers = @(Get-CimInstance Win32_Process -Filter "Name = 'explorer.exe'" -ErrorAction SilentlyContinue)
        foreach ($explorer in $explorers | Sort-Object CreationDate -Descending) {
            try {
                $owner = Invoke-CimMethod -InputObject $explorer -MethodName GetOwner -ErrorAction Stop
                if ($owner -and -not [string]::IsNullOrWhiteSpace($owner.User)) {
                    if ([string]::IsNullOrWhiteSpace($owner.Domain)) {
                        return $owner.User
                    }

                    return ('{0}\{1}' -f $owner.Domain, $owner.User)
                }
            }
            catch {
                Write-ReparoDebug ("Unable to inspect explorer.exe owner for PID {0}: {1}" -f $explorer.ProcessId, $_.Exception.Message)
            }
        }
    }
    catch {
        Write-ReparoDebug ("Unable to enumerate explorer.exe for interactive user detection: {0}" -f $_.Exception.Message)
    }

    return $null
}

function Test-ReparoSectionSelected($Section) {
    $includeText = ''
    if ($Include -and $Include.Count -gt 0) {
        $includeText = $Include -join ','
    }

    Write-ReparoDebug ("Test-ReparoSectionSelected({0}) Force={1} Update={2} WindowsUpdate={3} MigrateChocoToWinget={4} FinalizeChocolateyRemoval={5} Include={6}" -f $Section, $Force, $Update, $WindowsUpdate, $MigrateChocoToWinget, $FinalizeChocolateyRemoval, $includeText)
    if ($Force) { return $true }
    if ($Include -and $Include.Count -gt 0) {
        return ($Include -contains $Section)
    }
    if (($MigrateChocoToWinget -or $FinalizeChocolateyRemoval) -and -not ($Update -or $WindowsUpdate -or $Winget -or $WingetDiscover -or $WslApt)) {
        return $false
    }

    return ($Section -eq 'WindowsUpdate')
}

function Ensure-ReparoPSWindowsUpdate {
    if (Get-Command Get-WindowsUpdate -ErrorAction SilentlyContinue) {
        Write-ReparoDebug 'Get-WindowsUpdate already available.'
        return $true
    }

    try {
        Write-ReparoLog '[INFO] PSWindowsUpdate not found; attempting install from PSGallery.'
        Write-ReparoDebug 'Starting PSWindowsUpdate bootstrap path.'
        Write-ReparoEventLog -EventId 1510 -EntryType Information -Message @"
Reparo bootstrap requested: PSWindowsUpdate.

Computer: $env:COMPUTERNAME
PID: $PID
Repository: PSGallery
Scope: AllUsers
Log: $script:ReparoLogPath
"@
        if (Get-Command Set-PSRepository -ErrorAction SilentlyContinue) {
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue | Out-Null
        }
        
        if (Get-Command Set-PSRepository -ErrorAction SilentlyContinue) {
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue | Out-Null
        }

        if (-not (Ensure-ReparoNuGetProvider)) {
            Write-ReparoLog '[WARN] NuGet provider unavailable; skipping PSWindowsUpdate bootstrap.'
            return $false
        }

        Install-Module -Name 'PSWindowsUpdate' -Force -AllowClobber -Scope AllUsers -Repository 'PSGallery' -ErrorAction Stop | Out-Null
        Import-Module PSWindowsUpdate -Force -ErrorAction Stop

        if (Get-Command Get-WindowsUpdate -ErrorAction SilentlyContinue) {
            Write-ReparoLog '[DONE] PSWindowsUpdate installed successfully.'
            Write-ReparoDebug 'PSWindowsUpdate bootstrap completed and Get-WindowsUpdate is now available.'
            Write-ReparoEventLog -EventId 1511 -EntryType Information -Message @"
Reparo bootstrap completed: PSWindowsUpdate.

Computer: $env:COMPUTERNAME
PID: $PID
Repository: PSGallery
Scope: AllUsers
Log: $script:ReparoLogPath
"@
            return $true
        }

        throw 'PSWindowsUpdate installed, but Get-WindowsUpdate is still unavailable.'
    }
    catch {
        Write-ReparoLog ("[WARN] PSWindowsUpdate install failed: {0}" -f $_.Exception.Message)
        Write-ReparoDebug ("PSWindowsUpdate bootstrap failed: {0}" -f $_.Exception.Message)
        Write-ReparoEventLog -EventId 1512 -EntryType Warning -Message @"
Reparo bootstrap failed: PSWindowsUpdate.

Computer: $env:COMPUTERNAME
PID: $PID
Error: $($_.Exception.Message)
Log: $script:ReparoLogPath
"@
        return $false
    }
}

function Ensure-ReparoWinget {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-ReparoDebug 'winget already available.'
        return $true
    }

    Write-ReparoLog '[ACTION] winget not found; attempting repair/registration.'
    Write-ReparoDebug 'Starting winget repair path.'
    Write-ReparoEventLog -EventId 1520 -EntryType Information -Message @"
Reparo repair requested: winget.

Computer: $env:COMPUTERNAME
PID: $PID
Log: $script:ReparoLogPath
"@

    try {
        if (-not (Get-Command Repair-WinGetPackageManager -ErrorAction SilentlyContinue)) {
            if (Get-Command Install-Module -ErrorAction SilentlyContinue) {
                Write-ReparoLog '[INFO] Microsoft.WinGet.Client not found; attempting install from PSGallery.'
                if (Get-Command Set-PSRepository -ErrorAction SilentlyContinue) {
                    Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue | Out-Null
                }

                if (-not (Ensure-ReparoNuGetProvider)) {
                    Write-ReparoLog '[WARN] NuGet provider unavailable; skipping Microsoft.WinGet.Client bootstrap.'
                    return $false
                }

                Install-Module -Name 'Microsoft.WinGet.Client' -Force -AllowClobber -Scope AllUsers -Repository 'PSGallery' -ErrorAction Stop | Out-Null
                Import-Module 'Microsoft.WinGet.Client' -Force -ErrorAction Stop
            }
        }

        if (Get-Command Repair-WinGetPackageManager -ErrorAction SilentlyContinue) {
            Write-ReparoLog '[ACTION] Repair-WinGetPackageManager -Force -Latest'
            Repair-WinGetPackageManager -Force -Latest -ErrorAction Stop | Out-Null
        }
        elseif (Get-Command Add-AppxPackage -ErrorAction SilentlyContinue) {
            Write-ReparoLog '[ACTION] Re-registering Microsoft.DesktopAppInstaller.'
            Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop | Out-Null
        }
        else {
            throw 'Neither Repair-WinGetPackageManager nor Add-AppxPackage is available.'
        }

        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-ReparoLog '[DONE] winget repair/registration completed successfully.'
            Write-ReparoDebug 'winget is now available after repair/registration.'
            Write-ReparoEventLog -EventId 1521 -EntryType Information -Message @"
Reparo repair completed: winget.

Computer: $env:COMPUTERNAME
PID: $PID
Log: $script:ReparoLogPath
"@
            return $true
        }

        throw 'winget is still unavailable after repair/registration.'
    }
    catch {
        Write-ReparoLog ("[WARN] winget repair/registration failed: {0}" -f $_.Exception.Message)
        Write-ReparoDebug ("winget repair path failed: {0}" -f $_.Exception.Message)
        Write-ReparoEventLog -EventId 1522 -EntryType Warning -Message @"
Reparo repair failed: winget.

Computer: $env:COMPUTERNAME
PID: $PID
Error: $($_.Exception.Message)
Log: $script:ReparoLogPath
"@
        return $false
    }
}

function Invoke-ReparoWingetDiscovery {
    param(
        [switch]$PreviewOnly
    )

    if (-not (Test-ReparoSectionSelected 'Winget') -and -not $Winget -and -not $WingetDiscover) {
        return
    }

    foreach ($step in @(
        @{ Section = 'Winget(source list)'; Command = 'winget source list' }
        @{ Section = 'Winget(list upgrades)'; Command = 'winget list --upgrade-available' }
        @{ Section = 'Winget(upgrade list)'; Command = 'winget upgrade' }
    )) {
        if (-not (Test-ReparoSectionTool -Section 'Winget' -PresenceCmd 'winget')) {
            return
        }

        Write-ReparoLog ("[DISCOVERY] {0}" -f $step.Section)
        Write-ReparoLog ("[CMD] {0}" -f $step.Command)
        if ($PreviewOnly) {
            Write-ReparoDebug ("Preview-only winget discovery will still execute: {0}" -f $step.Command)
        }

        try {
            $shell = Resolve-ReparoShell
            $result = Invoke-ReparoTimedCommand -ShellPath $shell -Command $step.Command -Section $step.Section -TimeoutSeconds $WingetDiscoveryTimeoutSeconds -IgnoreTimeouts:$IgnoreTimeouts

            if ($result.TimedOut) {
                Write-ReparoLog ("[WARN] {0} discovery timed out after {1}" -f $step.Section, $result.Elapsed)
            }
            elseif ($result.ExitCode -ne 0) {
                Write-ReparoLog ("[WARN] {0} discovery exit code {1}" -f $step.Section, $result.ExitCode)
            }
            else {
                Write-ReparoLog ("[DONE] {0} discovery complete" -f $step.Section)
            }
        }
        catch {
            Write-ReparoLog ("[WARN] {0} discovery failed: {1}" -f $step.Section, $_.Exception.Message)
        }
    }
}

function Resolve-ReparoShell {
    Write-ReparoDebug 'Resolving runnable PowerShell host.'
    foreach ($shellName in @('pwsh', 'powershell')) {
        $command = Resolve-ReparoCommand -Name $shellName
        if (-not $command) { continue }

        try {
            $output = @(& $command.Source -NoProfile -ExecutionPolicy Bypass -Command '$PSVersionTable.PSVersion.ToString()' 2>&1)
            $exitCode = $LASTEXITCODE
            Write-ReparoDebug ("Shell probe {0} returned exit code {1}" -f $shellName, $exitCode)
            foreach ($item in $output) {
                $line = [string]$item
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    Write-ReparoLog ("[CHECK] {0}: {1}" -f $shellName, $line)
                }
            }

            if ($exitCode -eq 0 -or $null -eq $exitCode) {
                return $command.Source
            }
        }
        catch {
            Write-ReparoLog ("[CHECK] {0} is present but cannot run: {1}" -f $shellName, $_.Exception.Message)
        }
    }

    throw 'No runnable PowerShell host was found. Tried pwsh and powershell.'
}

function Test-ReparoBenignExit {
    param(
        [string]$Section,
        [int]$ExitCode,
        [object[]]$Output
    )

    if ($ExitCode -eq 0 -or $Section -notlike 'Winget*') {
        return $false
    }

    $text = ($Output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
    return ($text -match 'No installed package found matching input criteria|No applicable update found|No available upgrade found|No packages found')
}

function Get-ReparoWingetManualInterventionReason {
    param(
        [object[]]$Output
    )

    $text = ($Output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    if ($text -match 'install technology is different from the current version installed') {
        return 'Winget found a newer version, but that package requires uninstall/reinstall because the installer technology changed.'
    }

    return $null
}

function Invoke-ReparoWingetRepair {
    if (Test-ReparoExecutable -Name 'winget' -Arguments @('--version')) {
        return $true
    }

    if ($Preview) {
        Write-ReparoLog '[CHECK] winget is not runnable; preview mode will not attempt repair'
        return $false
    }

    Write-Step 'Winget repair'
    Write-ReparoLog '[STEP] Winget repair'

    try {
        Write-ReparoLog '[CMD] Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe'
        Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop
        if (Test-ReparoExecutable -Name 'winget' -Arguments @('--version')) {
            Write-Done 'Winget registered successfully'
            Write-ReparoLog '[DONE] Winget registered successfully'
            return $true
        }
    }
    catch {
        Write-ReparoLog ("[WARN] Winget App Installer registration failed: {0}" -f $_.Exception.Message)
    }

    if (Get-Command Repair-WinGetPackageManager -ErrorAction SilentlyContinue) {
        try {
            Write-ReparoLog '[CMD] Repair-WinGetPackageManager -AllUsers'
            Repair-WinGetPackageManager -AllUsers -ErrorAction Stop
            if (Test-ReparoExecutable -Name 'winget' -Arguments @('--version')) {
                Write-Done 'Winget repaired successfully'
                Write-ReparoLog '[DONE] Winget repaired successfully'
                return $true
            }
        }
        catch {
            Write-ReparoLog ("[WARN] Repair-WinGetPackageManager failed: {0}" -f $_.Exception.Message)
        }
    }

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ReparoWinget_{0}_{1}" -f $PID, (Get-Date -Format 'yyyyMMddHHmmss'))
    $bundlePath = Join-Path $tempRoot 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'

    try {
        New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

        Write-ReparoLog '[CMD] Invoke-RestMethod https://api.github.com/repos/microsoft/winget-cli/releases/latest'
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest' -Headers @{ 'User-Agent' = 'Reparo' } -UseBasicParsing
        $asset = @($release.assets | Where-Object { $_.browser_download_url -like '*Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle' } | Select-Object -First 1)
        if (-not $asset) {
            throw 'Unable to locate the latest Microsoft.DesktopAppInstaller msixbundle asset.'
        }

        Write-ReparoLog ("[CMD] Invoke-WebRequest {0}" -f $asset.browser_download_url)
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $bundlePath -UseBasicParsing
        Unblock-File -LiteralPath $bundlePath -ErrorAction SilentlyContinue

        Write-ReparoLog ("[CMD] Add-AppxPackage -Path {0}" -f $bundlePath)
        Add-AppxPackage -Path $bundlePath -ErrorAction Stop

        if (Test-ReparoExecutable -Name 'winget' -Arguments @('--version')) {
            Write-Done 'Winget installed successfully'
            Write-ReparoLog '[DONE] Winget installed successfully'
            return $true
        }
    }
    catch {
        Write-ReparoLog ("[WARN] Winget GitHub install failed: {0}" -f $_.Exception.Message)
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Skip 'Winget is not available in this context after repair attempts'
    Write-ReparoLog '[SKIP] Winget is not available in this context after repair attempts'
    return $false
}

function Test-ReparoSectionTool {
    param(
        [string]$Section,
        [string]$PresenceCmd
    )

    if ([string]::IsNullOrWhiteSpace($PresenceCmd)) {
        return $true
    }

    switch ($PresenceCmd) {
        'winget' { return (Invoke-ReparoWingetRepair) }
        'choco' { return (Test-ReparoExecutable -Name $PresenceCmd -Arguments @('--version')) }
        'scoop' { return (Test-ReparoExecutable -Name $PresenceCmd -Arguments @('--version')) }
        'pipx' { return (Test-ReparoExecutable -Name $PresenceCmd -Arguments @('--version')) }
        'npm' { return (Test-ReparoExecutable -Name $PresenceCmd -Arguments @('--version')) }
        'pnpm' { return (Test-ReparoExecutable -Name $PresenceCmd -Arguments @('--version')) }
        'yarn' { return (Test-ReparoExecutable -Name $PresenceCmd -Arguments @('--version')) }
        'dotnet' { return (Test-ReparoExecutable -Name $PresenceCmd -Arguments @('--version')) }
        'rustup' { return (Test-ReparoExecutable -Name $PresenceCmd -Arguments @('--version')) }
        'cargo-install-update' { return (Test-ReparoExecutable -Name $PresenceCmd -Arguments @('--version')) }
        'conda' { return (Test-ReparoExecutable -Name $PresenceCmd -Arguments @('--version')) }
        'gem' { return (Test-ReparoExecutable -Name $PresenceCmd -Arguments @('--version')) }
        'composer' { return (Test-ReparoExecutable -Name $PresenceCmd -Arguments @('--version')) }
        'spicetify' { return (Test-ReparoExecutable -Name $PresenceCmd -Arguments @('--version')) }
        'wsl' { return (Test-ReparoExecutable -Name $PresenceCmd -Arguments @('--status')) }
        default { return (Test-Cmd $PresenceCmd) }
    }
}

$script:ReparoSummary = [ordered]@{
    Updated = New-Object System.Collections.Generic.List[object]
    Skipped = New-Object System.Collections.Generic.List[object]
    Failed  = New-Object System.Collections.Generic.List[object]
    Notes   = New-Object System.Collections.Generic.List[string]
}

function Add-ReparoSummaryRecord {
    param(
        [ValidateSet('Updated', 'Skipped', 'Failed')]
        [string]$Bucket,
        [string]$Software,
        [string]$CurrentVersion,
        [string]$Version,
        [string]$Method,
        [string]$Reason
    )

    if ([string]::IsNullOrWhiteSpace($Software)) { $Software = 'Unknown' }
    if ([string]::IsNullOrWhiteSpace($CurrentVersion)) { $CurrentVersion = '-' }
    if ([string]::IsNullOrWhiteSpace($Version)) { $Version = '-' }
    if ([string]::IsNullOrWhiteSpace($Method)) { $Method = '-' }
    if ([string]::IsNullOrWhiteSpace($Reason)) { $Reason = '-' }

    [void]$script:ReparoSummary[$Bucket].Add([pscustomobject]@{
        Software       = $Software
        CurrentVersion = $CurrentVersion
        Version        = $Version
        Method         = $Method
        Reason         = $Reason
    })

    if ($Bucket -eq 'Failed') {
        Write-ReparoEventLog -EventId 1202 -EntryType Error -Message @"
Reparo section/package failed.

Computer: $env:COMPUTERNAME
PID: $PID
Software: $Software
CurrentVersion: $CurrentVersion
Version: $Version
Method: $Method
Reason: $Reason
Log: $script:ReparoLogPath
"@
    }
}

function Add-ReparoSummaryNote {
    param([string]$Message)

    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        [void]$script:ReparoSummary['Notes'].Add($Message)
    }
}

function ConvertFrom-ReparoWingetTable {
    param(
        [object[]]$Output,
        [string]$Method
    )

    $updates = New-Object System.Collections.Generic.List[object]
    foreach ($item in $Output) {
        $line = ([string]$item).TrimEnd()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^(Name|[-]+)\s+') { continue }
        if ($line -match '^\d+\s+upgrades?\s+available\.?$') { continue }
        if ($line -match '^(No installed package found|No available upgrade found|No packages found|The following packages have an upgrade)') { continue }

        $match = [regex]::Match($line, '^(?<name>.+?)\s{2,}(?<id>\S+)\s{2,}(?<version>\S+)\s{2,}(?<available>\S+)(?:\s{2,}(?<source>\S+))?\s*$')
        if (-not $match.Success) { continue }

        $name = $match.Groups['name'].Value.Trim()
        $available = $match.Groups['available'].Value.Trim()
        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($available)) { continue }

        [void]$updates.Add([pscustomobject]@{
            Software       = $name
            CurrentVersion = $match.Groups['version'].Value.Trim()
            Version        = $available
            Method         = $Method
        })
    }

    return $updates.ToArray()
}

function Get-ReparoPendingUpdates {
    param([string]$Section)

    try {
        switch ($Section) {
            'Winget' {
                if (-not (Test-ReparoExecutable -Name 'winget' -Arguments @('--version'))) { return @() }
                $output = @(winget upgrade --include-unknown --accept-source-agreements 2>&1)
                return @(ConvertFrom-ReparoWingetTable -Output $output -Method 'winget')
            }
            'Winget(msstore)' {
                if (-not (Test-ReparoExecutable -Name 'winget' -Arguments @('--version'))) { return @() }
                $output = @(winget upgrade --source msstore --include-unknown --accept-source-agreements 2>&1)
                return @(ConvertFrom-ReparoWingetTable -Output $output -Method 'winget/msstore')
            }
            'Choco' {
                if (-not (Test-ReparoExecutable -Name 'choco' -Arguments @('--version'))) { return @() }
                $output = @(choco outdated --limit-output --no-color 2>&1)
                $updates = New-Object System.Collections.Generic.List[object]
                foreach ($item in $output) {
                    $line = ([string]$item).Trim()
                    if ([string]::IsNullOrWhiteSpace($line) -or $line -notmatch '\|') { continue }

                    $parts = $line -split '\|'
                    if ($parts.Count -lt 3) { continue }

                    [void]$updates.Add([pscustomobject]@{
                        Software       = $parts[0].Trim()
                        CurrentVersion = $parts[1].Trim()
                        Version        = $parts[2].Trim()
                        Method         = 'choco'
                    })
                }
                return $updates.ToArray()
            }
            'Scoop' {
                if (-not (Test-ReparoExecutable -Name 'scoop' -Arguments @('--version'))) { return @() }
                $output = @(scoop status 2>&1)
                $updates = New-Object System.Collections.Generic.List[object]
                foreach ($item in $output) {
                    $line = ([string]$item).Trim()
                    if ([string]::IsNullOrWhiteSpace($line)) { continue }
                    if ($line -match '^(Name|[-]+)\s+') { continue }

                    $match = [regex]::Match($line, '^(?<name>\S+)\s+(?<installed>\S+)\s+(?<available>\S+)')
                    if (-not $match.Success) { continue }

                    [void]$updates.Add([pscustomobject]@{
                        Software       = $match.Groups['name'].Value.Trim()
                        CurrentVersion = $match.Groups['installed'].Value.Trim()
                        Version        = $match.Groups['available'].Value.Trim()
                        Method         = 'scoop'
                    })
                }
                return $updates.ToArray()
            }
        }
    }
    catch {
        Add-ReparoSummaryNote ("Unable to collect package-level update list for {0}: {1}" -f $Section, $_.Exception.Message)
    }

    return @()
}

function New-ReparoVersionLockRecord {
    param(
        [string]$Method,
        [string]$Id,
        [string]$Software,
        [string]$Version,
        [string]$Source = 'configured'
    )

    if ([string]::IsNullOrWhiteSpace($Id) -and -not [string]::IsNullOrWhiteSpace($Software)) {
        $Id = $Software
    }

    if ([string]::IsNullOrWhiteSpace($Software)) {
        $Software = $Id
    }

    if ([string]::IsNullOrWhiteSpace($Method) -or [string]::IsNullOrWhiteSpace($Id)) {
        return $null
    }

    [pscustomobject]@{
        Method   = $Method.Trim().ToLowerInvariant()
        Id       = $Id.Trim()
        Software = $Software.Trim()
        Version  = if ([string]::IsNullOrWhiteSpace($Version)) { '*' } else { $Version.Trim() }
        Source   = $Source
    }
}

function ConvertFrom-ReparoVersionLockSpec {
    param(
        [Parameter(Mandatory)][string]$Spec,
        [string]$Source = 'parameter'
    )

    $text = $Spec.Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }

    $match = [regex]::Match($text, '^(?<method>[^:=\s]+)[:=](?<id>[^=]+?)(?:=(?<version>.+))?$')
    if (-not $match.Success) {
        throw "Invalid version lock spec '$Spec'. Use method:id=version, for example winget:Git.Git=2.51.0."
    }

    return (New-ReparoVersionLockRecord -Method $match.Groups['method'].Value -Id $match.Groups['id'].Value -Version $match.Groups['version'].Value -Source $Source)
}

function Get-ReparoVersionLocks {
    $locks = New-Object System.Collections.Generic.List[object]

    if (-not [string]::IsNullOrWhiteSpace($VersionLockPath) -and (Test-Path -LiteralPath $VersionLockPath)) {
        try {
            $json = Get-Content -LiteralPath $VersionLockPath -Raw | ConvertFrom-Json
            if ($json -is [System.Array]) {
                foreach ($row in $json) {
                    $record = New-ReparoVersionLockRecord -Method $row.Method -Id $row.Id -Software $row.Software -Version $row.Version -Source $VersionLockPath
                    if ($record) { [void]$locks.Add($record) }
                }
            }
            elseif ($json.PSObject.Properties.Name -contains 'Method' -and $json.PSObject.Properties.Name -contains 'Id') {
                $record = New-ReparoVersionLockRecord -Method $json.Method -Id $json.Id -Software $json.Software -Version $json.Version -Source $VersionLockPath
                if ($record) { [void]$locks.Add($record) }
            }
            else {
                foreach ($property in $json.PSObject.Properties) {
                    $record = ConvertFrom-ReparoVersionLockSpec -Spec ("{0}={1}" -f $property.Name, $property.Value) -Source $VersionLockPath
                    if ($record) { [void]$locks.Add($record) }
                }
            }
        }
        catch {
            throw "Unable to read version lock file '$VersionLockPath': $($_.Exception.Message)"
        }
    }

    foreach ($spec in @($VersionLock)) {
        if ([string]::IsNullOrWhiteSpace($spec)) { continue }
        $record = ConvertFrom-ReparoVersionLockSpec -Spec $spec -Source 'parameter'
        if ($record) { [void]$locks.Add($record) }
    }

    return $locks.ToArray()
}

function Test-ReparoPackageVersionLocked {
    param(
        [Parameter(Mandatory)][string]$Method,
        [AllowNull()][string]$Id,
        [AllowNull()][string]$Software,
        [AllowNull()][string]$CurrentVersion
    )

    foreach ($lock in @(Get-ReparoVersionLocks)) {
        if ($lock.Method -ne $Method.ToLowerInvariant()) { continue }
        $packageMatches = ($Id -and $lock.Id -ieq $Id) -or ($Software -and (($lock.Id -ieq $Software) -or ($lock.Software -ieq $Software)))
        if (-not $packageMatches) { continue }

        return $lock
    }

    return $null
}

function Get-ReparoLockedPackageIds {
    param([Parameter(Mandatory)][string]$Method)

    @(Get-ReparoVersionLocks) |
        Where-Object { $_.Method -eq $Method.ToLowerInvariant() } |
        ForEach-Object { $_.Id } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique
}

function New-ReparoInventoryRecord {
    param(
        [string]$Software,
        [string]$Id,
        [string]$Version,
        [string]$AvailableVersion,
        [string]$Method,
        [string]$Source
    )

    $lock = Test-ReparoPackageVersionLocked -Method $Method -Id $Id -Software $Software -CurrentVersion $Version
    $lockSpec = if ($Method -and $Id -and $Version) { "{0}:{1}={2}" -f $Method, $Id, $Version } else { '-' }

    [pscustomobject]@{
        Software         = if ([string]::IsNullOrWhiteSpace($Software)) { $Id } else { $Software }
        Id               = if ([string]::IsNullOrWhiteSpace($Id)) { $Software } else { $Id }
        Version          = if ([string]::IsNullOrWhiteSpace($Version)) { '-' } else { $Version }
        AvailableVersion = if ([string]::IsNullOrWhiteSpace($AvailableVersion)) { '-' } else { $AvailableVersion }
        Method           = $Method
        Source           = if ([string]::IsNullOrWhiteSpace($Source)) { '-' } else { $Source }
        Locked           = [bool]$lock
        LockVersion      = if ($lock) { $lock.Version } else { '-' }
        LockSpec         = $lockSpec
    }
}

function ConvertFrom-ReparoWingetInventoryTable {
    param([object[]]$Output)

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($item in $Output) {
        $line = ([string]$item).TrimEnd()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^(Name|[-]+)\s+') { continue }
        if ($line -match '^(No installed package found|No packages found)') { continue }

        $match = [regex]::Match($line, '^(?<name>.+?)\s{2,}(?<id>\S+)\s{2,}(?<version>\S+)(?:\s{2,}(?<available>\S+))?(?:\s{2,}(?<source>\S+))?\s*$')
        if (-not $match.Success) { continue }

        $available = $match.Groups['available'].Value.Trim()
        $source = $match.Groups['source'].Value.Trim()
        if ([string]::IsNullOrWhiteSpace($source) -and $available -match '^(winget|msstore)$') {
            $source = $available
            $available = $null
        }

        [void]$rows.Add((New-ReparoInventoryRecord -Software $match.Groups['name'].Value.Trim() -Id $match.Groups['id'].Value.Trim() -Version $match.Groups['version'].Value.Trim() -AvailableVersion $available -Method 'winget' -Source $source))
    }

    return $rows.ToArray()
}

function Get-ReparoForceInventory {
    $items = New-Object System.Collections.Generic.List[object]

    if (Test-ReparoExecutable -Name 'winget' -Arguments @('--version')) {
        foreach ($row in @(ConvertFrom-ReparoWingetInventoryTable -Output @(winget list --accept-source-agreements --disable-interactivity 2>&1))) { [void]$items.Add($row) }
    }

    if (Test-ReparoExecutable -Name 'choco' -Arguments @('--version')) {
        foreach ($package in @(Get-ReparoChocoPackages)) {
            [void]$items.Add((New-ReparoInventoryRecord -Software $package.ChocoId -Id $package.ChocoId -Version $package.Version -Method 'choco' -Source 'choco'))
        }
    }

    if (Test-ReparoExecutable -Name 'scoop' -Arguments @('--version')) {
        $output = @(scoop list 2>&1)
        foreach ($line in $output) {
            $text = ([string]$line).Trim()
            if ([string]::IsNullOrWhiteSpace($text) -or $text -match '^(Installed apps|Name\s+Version|[-]+)') { continue }
            $match = [regex]::Match($text, '^(?<name>\S+)\s+(?<version>\S+)(?:\s+(?<source>\S+))?')
            if ($match.Success) {
                [void]$items.Add((New-ReparoInventoryRecord -Software $match.Groups['name'].Value -Id $match.Groups['name'].Value -Version $match.Groups['version'].Value -Method 'scoop' -Source $match.Groups['source'].Value))
            }
        }
    }

    if (Test-ReparoExecutable -Name 'dotnet' -Arguments @('--version')) {
        $output = @(dotnet tool list --global 2>&1)
        foreach ($line in $output) {
            $text = ([string]$line).Trim()
            if ($text -match '^\s*(\S+)\s+(\S+)\s+(\S+)\s*$' -and $text -notmatch 'Package Id' -and $text -notmatch '^-+$') {
                [void]$items.Add((New-ReparoInventoryRecord -Software $matches[1] -Id $matches[1] -Version $matches[2] -Method 'dotnet' -Source 'dotnet-tool'))
            }
        }
    }

    if (Test-ReparoExecutable -Name 'npm' -Arguments @('--version')) {
        $output = @(npm list -g --depth=0 --json 2>&1)
        try {
            $json = ($output -join [Environment]::NewLine) | ConvertFrom-Json
            foreach ($property in $json.dependencies.PSObject.Properties) {
                [void]$items.Add((New-ReparoInventoryRecord -Software $property.Name -Id $property.Name -Version $property.Value.version -Method 'npm' -Source 'npm-global'))
            }
        }
        catch { }
    }

    if (Test-ReparoExecutable -Name 'pipx' -Arguments @('--version')) {
        $output = @(cmd.exe /c 'pipx list --json 2>nul')
        try {
            $json = ($output -join [Environment]::NewLine) | ConvertFrom-Json
            foreach ($property in $json.venvs.PSObject.Properties) {
                [void]$items.Add((New-ReparoInventoryRecord -Software $property.Name -Id $property.Name -Version $property.Value.metadata.main_package.package_version -Method 'pipx' -Source 'pipx'))
            }
        }
        catch { }
    }

    return $items.ToArray()
}

function Show-ReparoSearchResults {
    param([string[]]$Terms)

    $rows = @(Get-ReparoForceInventory)
    foreach ($term in @($Terms)) {
        if ([string]::IsNullOrWhiteSpace($term)) { continue }
        $needle = [regex]::Escape($term.Trim())
        $rows = @($rows | Where-Object { $_.Software -match $needle -or $_.Id -match $needle -or $_.Method -match $needle -or $_.Source -match $needle -or $_.Version -match $needle })
    }

    if (-not $rows -or $rows.Count -eq 0) {
        Write-Warning 'No Reparo-managed applications matched the search.'
        return
    }

    $rows | Sort-Object Method, Software | Select-Object Software, Id, Version, AvailableVersion, Method, Source, Locked, LockVersion, LockSpec
}

function Show-ReparoVersionLocks {
    $locks = @(Get-ReparoVersionLocks)
    if (-not $locks -or $locks.Count -eq 0) {
        Write-Host 'No Reparo version locks are configured.'
        Write-Host "Default lock file: $VersionLockPath"
        return
    }

    $locks | Sort-Object Method, Id | Select-Object Method, Id, Version, Software, Source
}

function Add-ReparoVersionLocksToFile {
    param([Parameter(Mandatory)][string[]]$Specs)

    if ([string]::IsNullOrWhiteSpace($VersionLockPath)) {
        throw 'VersionLockPath cannot be blank when adding persistent locks.'
    }

    $existing = New-Object 'System.Collections.Generic.List[object]'
    if (Test-Path -LiteralPath $VersionLockPath) {
        try {
            $json = Get-Content -LiteralPath $VersionLockPath -Raw | ConvertFrom-Json
            if ($json -is [System.Array]) {
                foreach ($row in $json) {
                    $record = New-ReparoVersionLockRecord -Method $row.Method -Id $row.Id -Software $row.Software -Version $row.Version -Source $VersionLockPath
                    if ($record) { [void]$existing.Add($record) }
                }
            }
            elseif ($json.PSObject.Properties.Name -contains 'Method' -and $json.PSObject.Properties.Name -contains 'Id') {
                $record = New-ReparoVersionLockRecord -Method $json.Method -Id $json.Id -Software $json.Software -Version $json.Version -Source $VersionLockPath
                if ($record) { [void]$existing.Add($record) }
            }
            else {
                foreach ($property in $json.PSObject.Properties) {
                    $record = ConvertFrom-ReparoVersionLockSpec -Spec ("{0}={1}" -f $property.Name, $property.Value) -Source $VersionLockPath
                    if ($record) { [void]$existing.Add($record) }
                }
            }
        }
        catch {
            throw "Unable to read existing version lock file '$VersionLockPath': $($_.Exception.Message)"
        }
    }

    foreach ($spec in @($Specs)) {
        if ([string]::IsNullOrWhiteSpace($spec)) { continue }
        $record = ConvertFrom-ReparoVersionLockSpec -Spec $spec -Source $VersionLockPath
        if (-not $record) { continue }

        $merged = New-Object 'System.Collections.Generic.List[object]'
        foreach ($item in @($existing.ToArray())) {
            if ($item.Method -ieq $record.Method -and $item.Id -ieq $record.Id) { continue }
            [void]$merged.Add($item)
        }
        $existing = $merged
        [void]$existing.Add($record)
    }

    $rows = @(
        $existing |
            Sort-Object Method, Id |
            ForEach-Object {
                [pscustomobject]@{
                    Method   = $_.Method
                    Id       = $_.Id
                    Software = $_.Software
                    Version  = $_.Version
                }
            }
    )

    if ($Preview) {
        Write-Host "Preview: would write $($rows.Count) lock(s) to $VersionLockPath"
        $rows | Select-Object Method, Id, Version, Software
        return
    }

    $parent = Split-Path -Parent $VersionLockPath
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    ConvertTo-Json -InputObject @($rows) -Depth 4 | Set-Content -LiteralPath $VersionLockPath -Encoding UTF8
    Write-Host "Saved $($rows.Count) Reparo version lock(s) to $VersionLockPath"
    $rows | Select-Object Method, Id, Version, Software
}

function Add-ReparoSectionUpdates {
    param(
        [string]$Section,
        [object[]]$PendingUpdates
    )

    if ($PendingUpdates -and $PendingUpdates.Count -gt 0) {
        foreach ($update in $PendingUpdates) {
            if ($update.CurrentVersion -and $update.CurrentVersion -ne '-') {
                Write-ReparoLog ("[UPDATED] {0}: {1} -> {2} via {3}" -f $update.Software, $update.CurrentVersion, $update.Version, $update.Method)
            }
            else {
                Write-ReparoLog ("[UPDATED] {0}: -> {1} via {2}" -f $update.Software, $update.Version, $update.Method)
            }

            Add-ReparoSummaryRecord -Bucket Updated -Software $update.Software -CurrentVersion $update.CurrentVersion -Version $update.Version -Method $update.Method -Reason 'updated'
        }
        return
    }

    Add-ReparoSummaryNote ("{0} completed, but no package-level update list was available." -f $Section)
}

function Get-ReparoChocoWingetBuiltinMap {
    $map = [ordered]@{
        '7zip'                         = '7zip.7zip'
        '7zip.install'                 = '7zip.7zip'
        'adobereader'                  = 'Adobe.Acrobat.Reader.64-bit'
        'audacity'                     = 'Audacity.Audacity'
        'autohotkey'                   = 'AutoHotkey.AutoHotkey'
        'awscli'                       = 'Amazon.AWSCLI'
        'azure-cli'                    = 'Microsoft.AzureCLI'
        'bitwarden'                    = 'Bitwarden.Bitwarden'
        'brave'                        = 'Brave.Brave'
        'calibre'                      = 'calibre.calibre'
        'bulkrenameutility'            = 'TGRMNSoftware.BulkRenameUtility'
        'discord'                      = 'Discord.Discord'
        'dosbox'                       = 'DOSBox.DOSBox'
        'docker-desktop'               = 'Docker.DockerDesktop'
        'dotnet'                       = 'Microsoft.DotNet.SDK.8'
        'dotnet-10.0-desktopruntime'   = 'Microsoft.DotNet.DesktopRuntime.10'
        'dotnet-5.0-desktopruntime'    = 'Microsoft.DotNet.DesktopRuntime.5'
        'dotnet-8.0-desktopruntime'    = 'Microsoft.DotNet.DesktopRuntime.8'
        'dotnet-desktopruntime'        = 'Microsoft.DotNet.DesktopRuntime.10'
        'dotnet-8.0-sdk'               = 'Microsoft.DotNet.SDK.8'
        'dotnet-9.0-sdk'               = 'Microsoft.DotNet.SDK.9'
        'dropbox'                      = 'Dropbox.Dropbox'
        'dupeguru'                     = 'DupeGuru.DupeGuru'
        'epicgameslauncher'            = 'EpicGames.EpicGamesLauncher'
        'everything'                   = 'voidtools.Everything'
        'firefox'                      = 'Mozilla.Firefox'
        'ffmpeg'                       = 'Gyan.FFmpeg'
        'freecad'                      = 'FreeCAD.FreeCAD'
        'git'                          = 'Git.Git'
        'git.install'                  = 'Git.Git'
        'github-desktop'               = 'GitHub.GitHubDesktop'
        'googlechrome'                 = 'Google.Chrome'
        'googledrive'                  = 'Google.GoogleDrive'
        'googleearthpro'               = 'Google.EarthPro'
        'greenshot'                    = 'Greenshot.Greenshot'
        'handbrake'                    = 'HandBrake.HandBrake'
        'handbrake.install'            = 'HandBrake.HandBrake'
        'httpie'                       = 'HTTPie.HTTPie'
        'itunes'                       = 'Apple.iTunes'
        'javaruntime'                  = 'Oracle.JavaRuntimeEnvironment'
        'jdk8'                         = 'EclipseAdoptium.Temurin.8.JDK'
        'jdk11'                        = 'EclipseAdoptium.Temurin.11.JDK'
        'jdk17'                        = 'EclipseAdoptium.Temurin.17.JDK'
        'jdk21'                        = 'EclipseAdoptium.Temurin.21.JDK'
        'jq'                           = 'jqlang.jq'
        'keepassxc'                    = 'KeePassXCTeam.KeePassXC'
        'krita'                        = 'KDE.Krita'
        'libreoffice-fresh'            = 'TheDocumentFoundation.LibreOffice'
        'microsoft-teams'              = 'Microsoft.Teams'
        'microsoft-windows-terminal'   = 'Microsoft.WindowsTerminal'
        'microsoftazurestorageexplorer' = 'Microsoft.Azure.StorageExplorer'
        'micro'                        = 'zyedidia.micro'
        'mkvtoolnix'                   = 'MoritzBunkus.MKVToolNix'
        'moonlight'                    = 'MoonlightGameStreamingProject.Moonlight'
        'moonlight-qt'                 = 'MoonlightGameStreamingProject.Moonlight'
        'moonlight-qt.install'         = 'MoonlightGameStreamingProject.Moonlight'
        'mouse-jiggler'                = 'ArkaneSystems.MouseJiggler'
        'mp3tag'                       = 'FlorianHeidenreich.Mp3tag'
        'nano'                         = 'okibcn.nano'
        'nano-win'                     = 'okibcn.nano'
        'nodejs'                       = 'OpenJS.NodeJS'
        'nodejs.install'               = 'OpenJS.NodeJS'
        'notepadplusplus'              = 'Notepad++.Notepad++'
        'notepadplusplus.install'      = 'Notepad++.Notepad++'
        'obsidian'                     = 'Obsidian.Obsidian'
        'obs-studio'                   = 'OBSProject.OBSStudio'
        'paint.net'                    = 'dotPDN.PaintDotNet'
        'plex'                         = 'Plex.Plex'
        'plexamp'                      = 'Plex.Plexamp'
        'postman'                      = 'Postman.Postman'
        'powertoys'                    = 'Microsoft.PowerToys'
        'protonvpn'                    = 'Proton.ProtonVPN'
        'python'                       = 'Python.Python.3.14'
        'python3'                      = 'Python.Python.3.14'
        'python313'                    = 'Python.Python.3.13'
        'python314'                    = 'Python.Python.3.14'
        'putty'                        = 'PuTTY.PuTTY'
        'putty.portable'               = 'PuTTY.PuTTY'
        'qflipper'                     = 'FlipperDevicesInc.qFlipper'
        'rufus'                        = 'Rufus.Rufus'
        'signal'                       = 'OpenWhisperSystems.Signal'
        'slack'                        = 'SlackTechnologies.Slack'
        'spotify'                      = 'Spotify.Spotify'
        'steam'                        = 'Valve.Steam'
        'sunshine'                     = 'LizardByte.Sunshine'
        'sysmon'                       = 'Microsoft.Sysinternals.Sysmon'
        'sysinternals'                 = 'Microsoft.Sysinternals'
        'teamviewer'                   = 'TeamViewer.TeamViewer'
        'terraform'                    = 'Hashicorp.Terraform'
        'thunderbird'                  = 'Mozilla.Thunderbird'
        'vivaldi'                      = 'Vivaldi.Vivaldi'
        'vcredist140'                  = 'Microsoft.VCRedist.2015+.x64'
        'vcredist2015'                 = 'Microsoft.VCRedist.2015+.x64'
        'vcredist2017'                 = 'Microsoft.VCRedist.2015+.x64'
        'vlc'                          = 'VideoLAN.VLC'
        'vlc.install'                  = 'VideoLAN.VLC'
        'vscode'                       = 'Microsoft.VisualStudioCode'
        'vscode.install'               = 'Microsoft.VisualStudioCode'
        'vigembus'                     = 'ViGEm.ViGEmBus'
        'whois'                        = 'Microsoft.Sysinternals.Whois'
        'winscp'                       = 'WinSCP.WinSCP'
        'winscp.install'               = 'WinSCP.WinSCP'
        'windirstat'                   = 'WinDirStat.WinDirStat'
        'wireshark'                    = 'WiresharkFoundation.Wireshark'
        'wiztree'                      = 'AntibodySoftware.WizTree'
        'vortex'                       = 'NexusMods.Vortex'
        'zoom'                         = 'Zoom.Zoom'
    }

    return $map
}

function Add-ReparoChocoWingetMapEntry {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Map,
        [Parameter(Mandatory)][string]$ChocoId,
        [Parameter(Mandatory)][string]$WingetId,
        [string]$Source
    )

    if ([string]::IsNullOrWhiteSpace($ChocoId) -or [string]::IsNullOrWhiteSpace($WingetId)) {
        return
    }

    $key = $ChocoId.Trim().ToLowerInvariant()
    $Map[$key] = [pscustomobject]@{
        WingetId = $WingetId.Trim()
        Source   = if ([string]::IsNullOrWhiteSpace($Source)) { 'winget' } else { $Source.Trim() }
    }
}

function Get-ReparoChocoWingetMap {
    $map = @{}

    foreach ($entry in (Get-ReparoChocoWingetBuiltinMap).GetEnumerator()) {
        Add-ReparoChocoWingetMapEntry -Map $map -ChocoId $entry.Key -WingetId $entry.Value -Source 'winget'
    }

    if ([string]::IsNullOrWhiteSpace($ChocoWingetMapPath)) {
        return $map
    }

    if (-not (Test-Path -LiteralPath $ChocoWingetMapPath)) {
        throw "Choco winget map path not found: $ChocoWingetMapPath"
    }

    $extension = [System.IO.Path]::GetExtension($ChocoWingetMapPath)
    if ($extension -eq '.json') {
        $json = Get-Content -LiteralPath $ChocoWingetMapPath -Raw | ConvertFrom-Json
        if ($json -is [System.Array]) {
            foreach ($row in $json) {
                Add-ReparoChocoWingetMapEntry -Map $map -ChocoId $row.ChocoId -WingetId $row.WingetId -Source $row.Source
            }
        }
        else {
            foreach ($property in $json.PSObject.Properties) {
                if ($property.Value -is [string]) {
                    Add-ReparoChocoWingetMapEntry -Map $map -ChocoId $property.Name -WingetId $property.Value -Source 'winget'
                }
                else {
                    Add-ReparoChocoWingetMapEntry -Map $map -ChocoId $property.Name -WingetId $property.Value.WingetId -Source $property.Value.Source
                }
            }
        }

        return $map
    }

    $rows = Import-Csv -LiteralPath $ChocoWingetMapPath
    foreach ($row in $rows) {
        Add-ReparoChocoWingetMapEntry -Map $map -ChocoId $row.ChocoId -WingetId $row.WingetId -Source $row.Source
    }

    return $map
}

function Get-ReparoChocoPackages {
    if (-not (Test-ReparoExecutable -Name 'choco' -Arguments @('--version'))) {
        throw 'Chocolatey is not available in this context.'
    }

    $output = @(choco list --local-only --limit-output --no-color 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "choco list failed with exit code $LASTEXITCODE"
    }

    $packages = New-Object System.Collections.Generic.List[object]
    foreach ($item in $output) {
        $line = ([string]$item).Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line -notmatch '\|') { continue }

        $parts = $line -split '\|'
        if ($parts.Count -lt 2) { continue }

        [void]$packages.Add([pscustomobject]@{
            ChocoId = $parts[0].Trim()
            Version = $parts[1].Trim()
        })
    }

    return $packages.ToArray()
}

function Test-ReparoWingetPackageAvailable {
    param(
        [Parameter(Mandatory)][string]$WingetId,
        [string]$Source = 'winget'
    )

    $arguments = @('search', '--id', $WingetId, '--exact', '--accept-source-agreements', '--disable-interactivity')
    if (-not [string]::IsNullOrWhiteSpace($Source)) {
        $arguments += @('--source', $Source)
    }

    $output = @(& winget @arguments 2>&1)
    foreach ($line in $output) {
        Write-ReparoLog ("[MIGRATE] winget search: {0}" -f ([string]$line))
    }

    return ($LASTEXITCODE -eq 0 -and (($output -join "`n") -match [regex]::Escape($WingetId)))
}

function Get-ReparoChocolateyRoot {
    if (-not [string]::IsNullOrWhiteSpace($env:ChocolateyInstall)) {
        return $env:ChocolateyInstall
    }

    if ((Test-Path -LiteralPath 'C:\ProgramData\choco') -and -not (Test-Path -LiteralPath 'C:\ProgramData\chocolatey')) {
        return 'C:\ProgramData\choco'
    }

    return 'C:\ProgramData\chocolatey'
}

function Get-ReparoChocoMigrationDefaultExcludes {
    return @(
        'chocolatey',
        'chocolatey-agent',
        'chocolatey-compatibility.extension',
        'chocolatey-core.extension',
        'chocolatey-dotnetfx.extension',
        'chocolatey-fastanswers.extension',
        'chocolatey-font-helpers.extension',
        'chocolatey-misc-helpers.extension',
        'chocolatey-visualstudio.extension',
        'chocolatey-windowsupdate.extension',
        'KB2919355',
        'KB2919442',
        'KB2999226',
        'KB3033929',
        'KB3035131',
        'KB3063858',
        'DotNet4.5',
        'dotnetfx',
        'netfx-4.7.2'
    )
}

function Get-ReparoChocoFinalizeAllowedPackageIds {
    return @(
        @(Get-ReparoChocoMigrationDefaultExcludes) +
        @(
            # Trenton is fine with CyberChef being discarded with Chocolatey instead of preserved.
            'cyberchef'
        )
    )
}

function Get-ReparoChocoRuntimePackageIds {
    return @(
        'dotnet-10.0-desktopruntime',
        'dotnet-5.0-desktopruntime',
        'dotnet-8.0-desktopruntime',
        'dotnet-desktopruntime',
        'vcredist140',
        'vcredist2015',
        'vcredist2017'
    )
}

function Get-ReparoChocoPortableCommandMap {
    return @{
        'micro'          = @('micro')
        'nano'           = @('nano')
        'nano-win'       = @('nano')
        'putty.portable' = @('putty', 'plink', 'pscp', 'psftp', 'puttygen', 'pageant')
        'sysmon'         = @('sysmon', 'sysmon64')
        'whois'          = @('whois')
    }
}

function Test-ReparoChocoPayloadIsSignificant {
    param([Parameter(Mandatory)][System.IO.FileInfo]$File)

    $name = $File.Name
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($name)
    $extension = $File.Extension.ToLowerInvariant()

    if ($name -match '^chocolatey(install|uninstall|beforemodify)\.ps1$') { return $false }
    if ($name -match '^(helper|helpers|data|update|install|uninstall|beforemodify)\.ps1$') { return $false }
    if ($extension -in '.html', '.htm') { return $false }
    if ($extension -eq '.ps1' -and $baseName -match '(helper|data|install|uninstall|beforemodify)') { return $false }
    if ($extension -eq '.exe' -and $baseName -match '(setup|installer|install|unins|uninstall)') { return $false }

    return ($extension -in '.exe', '.cmd', '.bat', '.ps1', '.psm1', '.js')
}

function Get-ReparoChocoProgramDataAudit {
    $chocoRoot = Get-ReparoChocolateyRoot
    $libPath = Join-Path $chocoRoot 'lib'
    if (-not (Test-Path -LiteralPath $libPath)) { return @() }

    Get-ChildItem -LiteralPath $libPath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $packageDir = $_
        $files = @(Get-ChildItem -LiteralPath $packageDir.FullName -Recurse -File -ErrorAction SilentlyContinue)
        $toolPayloads = @($files | Where-Object {
            $_.Extension -in '.exe', '.cmd', '.bat', '.ps1', '.psm1', '.html', '.htm', '.js' -and
            $_.FullName -match '\\tools\\|\\bin\\'
        })
        $nonChocoPayloads = @($toolPayloads | Where-Object { Test-ReparoChocoPayloadIsSignificant -File $_ })

        [pscustomobject]@{
            Package              = $packageDir.Name
            Path                 = $packageDir.FullName
            SizeMB               = [math]::Round((($files | Measure-Object Length -Sum).Sum / 1MB), 2)
            FileCount            = $files.Count
            ToolPayloadCount     = $toolPayloads.Count
            NonChocoPayloadCount = $nonChocoPayloads.Count
            HasNonChocoPayload   = [bool]$nonChocoPayloads
            SamplePayload        = ($nonChocoPayloads | Select-Object -First 5 -ExpandProperty FullName) -join '; '
        }
    }
}

function Get-ReparoChocoPackageDirs {
    $chocoRoot = Get-ReparoChocolateyRoot
    $libPath = Join-Path $chocoRoot 'lib'
    if (-not (Test-Path -LiteralPath $libPath)) { return @() }

    Get-ChildItem -LiteralPath $libPath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        [pscustomobject]@{
            ChocoId = $_.Name
            Version = '(disk)'
            Path    = $_.FullName
        }
    }
}

function Test-ReparoPathIsUnderRoot {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root
    )

    $normalizedPath = $Path.Trim().TrimEnd('\')
    $normalizedRoot = $Root.Trim().TrimEnd('\')
    return ($normalizedPath -ieq $normalizedRoot -or $normalizedPath.StartsWith($normalizedRoot + '\', [System.StringComparison]::OrdinalIgnoreCase))
}

function Get-ReparoChocoPathShimAudit {
    $chocoRoot = Get-ReparoChocolateyRoot
    $seen = @{}
    $rows = New-Object System.Collections.Generic.List[object]

    @(Get-Command * -CommandType Application -ErrorAction SilentlyContinue | Where-Object {
        Test-ReparoPathIsUnderRoot -Path $_.Source -Root $chocoRoot
    } | ForEach-Object {
        $key = $_.Source.ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            [void]$rows.Add([pscustomobject]@{
                Name    = $_.Name
                Source  = $_.Source
                Package = $null
            })
        }
    })

    $binPath = Join-Path $chocoRoot 'bin'
    if (Test-Path -LiteralPath $binPath) {
        Get-ChildItem -LiteralPath $binPath -File -ErrorAction SilentlyContinue | Where-Object {
            $_.Extension -in '.exe', '.cmd', '.bat', '.ps1'
        } | ForEach-Object {
            $key = $_.FullName.ToLowerInvariant()
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                [void]$rows.Add([pscustomobject]@{
                    Name    = $_.Name
                    Source  = $_.FullName
                    Package = $null
                })
            }
        }
    }

    return @($rows.ToArray() | Sort-Object Name)
}

function Test-ReparoCommandHasNonChocoSource {
    param([Parameter(Mandatory)][string]$CommandName)

    $chocoRoot = Get-ReparoChocolateyRoot
    $hits = @(Get-Command $CommandName -All -ErrorAction SilentlyContinue)
    if ($hits.Count -eq 0) {
        return [pscustomobject]@{
            Command            = $CommandName
            Found              = $false
            HasNonChocoSource  = $false
            Sources            = @()
        }
    }

    return [pscustomobject]@{
        Command            = $CommandName
        Found              = $true
        HasNonChocoSource  = [bool]($hits | Where-Object { -not (Test-ReparoPathIsUnderRoot -Path $_.Source -Root $chocoRoot) })
        Sources            = @($hits.Source)
    }
}

function Get-ReparoWingetInstalledPackage {
    param(
        [Parameter(Mandatory)][string]$WingetId,
        [string]$Source = 'winget'
    )

    $arguments = @('list', '--id', $WingetId, '--exact', '--accept-source-agreements', '--disable-interactivity')
    if (-not [string]::IsNullOrWhiteSpace($Source)) {
        $arguments += @('--source', $Source)
    }

    $output = @(& winget @arguments 2>&1)
    foreach ($line in $output) {
        Write-ReparoLog ("[MIGRATE] winget list: {0}" -f ([string]$line))
    }

    if ($LASTEXITCODE -ne 0) { return $null }
    $packages = @(ConvertFrom-ReparoWingetListTable -Output $output)
    return @($packages | Where-Object { $_.Id -ieq $WingetId } | Select-Object -First 1)[0]
}

function Ensure-ReparoWingetPackageInstalled {
    param(
        [Parameter(Mandatory)][string]$WingetId,
        [string]$Source = 'winget'
    )

    $installed = Get-ReparoWingetInstalledPackage -WingetId $WingetId -Source $Source
    if ($installed -and -not $ForceWingetReinstall) {
        Write-Info "winget target already installed: $WingetId $($installed.Version)"
        Write-ReparoLog ("[MIGRATE] winget target already installed: {0} {1}" -f $WingetId, $installed.Version)
        return [pscustomobject]@{ ExitCode = 0; Action = 'AlreadyInstalled'; Installed = $true; Version = $installed.Version }
    }

    $arguments = @(
        'install',
        '--id', $WingetId,
        '--exact',
        '--source', $Source,
        '--accept-source-agreements',
        '--accept-package-agreements',
        '--disable-interactivity',
        '--silent'
    )
    if ($ForceWingetReinstall) { $arguments += '--force' }

    if ($Preview) {
        Write-Info "Preview: would run winget $($arguments -join ' ')"
        Write-ReparoLog ("[PREVIEW] Would run winget {0}" -f ($arguments -join ' '))
        return [pscustomobject]@{ ExitCode = 0; Action = 'PreviewInstall'; Installed = $false; Version = $null }
    }

    $result = Invoke-ReparoLoggedNativeCommand -FilePath 'winget' -Arguments $arguments -Label 'WINGET-MIGRATE'
    $result | Add-Member -NotePropertyName Action -NotePropertyValue 'Install' -Force
    return $result
}

function Invoke-ReparoChocoDeregisterPackage {
    param([Parameter(Mandatory)][string]$ChocoId)

    $arguments = @('uninstall', $ChocoId, '-y', '--no-progress', '--skip-autouninstaller', '--skip-powershell')
    if ($Preview) {
        Write-Info "Preview: would deregister Chocolatey package record $ChocoId using safe skip flags"
        Write-ReparoLog ("[PREVIEW] Would deregister Chocolatey package record {0} with safe skip flags" -f $ChocoId)
        return [pscustomobject]@{ ExitCode = 0; Preview = $true }
    }

    Invoke-ReparoLoggedNativeCommand -FilePath 'choco' -Arguments $arguments -Label 'CHOCO-DEREGISTER'
}

function Get-ReparoChocoMigrationClass {
    param(
        [Parameter(Mandatory)][string]$ChocoId,
        [bool]$HasMap,
        [bool]$HasProgramDataPayload,
        [int]$DuplicateCount
    )

    $key = $ChocoId.ToLowerInvariant()
    if ($key -eq 'chocolatey' -or $key -like 'chocolatey-*') { return 'ChocolateyInfrastructure' }
    if ((Get-ReparoChocoMigrationDefaultExcludes | ForEach-Object { $_.ToLowerInvariant() }) -contains $key) { return 'WindowsPrerequisite' }
    if ((Get-ReparoChocoRuntimePackageIds | ForEach-Object { $_.ToLowerInvariant() }) -contains $key) { return 'RuntimeDependency' }
    if ($key -eq 'sysmon') { return 'PortablePayload' }
    if ($key -eq 'cyberchef') { return 'ManualReview' }
    if ((Get-ReparoChocoPortableCommandMap).ContainsKey($key) -or $HasProgramDataPayload) { return 'PortablePayload' }
    if (-not $HasMap) { return 'Unsupported' }
    if ($DuplicateCount -gt 1) { return 'DuplicateCluster' }
    return 'GuiApp'
}

function Get-ReparoChocoMigrationRiskLevel {
    param([Parameter(Mandatory)][string]$MigrationClass)

    switch ($MigrationClass) {
        'ChocolateyInfrastructure' { 'Critical' }
        'WindowsPrerequisite'      { 'Critical' }
        'RuntimeDependency'        { 'High' }
        'PortablePayload'          { 'High' }
        'ManualReview'             { 'High' }
        'Unsupported'              { 'High' }
        'DuplicateCluster'         { 'Medium' }
        default                    { 'Low' }
    }
}

function Get-ReparoChocoMigrationPlan {
    param(
        [Parameter(Mandatory)][object[]]$Packages,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Map,
        [Parameter(Mandatory)][System.Collections.IDictionary]$ExcludeSet
    )

    $payloadAudit = @(Get-ReparoChocoProgramDataAudit)
    $shimAudit = @(Get-ReparoChocoPathShimAudit)
    $portableCommandMap = Get-ReparoChocoPortableCommandMap
    $duplicateCounts = @{}

    foreach ($package in $Packages) {
        $key = ([string]$package.ChocoId).ToLowerInvariant()
        if ($Map.ContainsKey($key)) {
            $target = $Map[$key]
            $groupKey = ("{0}|{1}" -f $target.Source, $target.WingetId).ToLowerInvariant()
            if (-not $duplicateCounts.ContainsKey($groupKey)) { $duplicateCounts[$groupKey] = 0 }
            $duplicateCounts[$groupKey]++
        }
    }

    $plan = New-Object System.Collections.Generic.List[object]
    foreach ($package in ($Packages | Sort-Object ChocoId)) {
        $chocoId = [string]$package.ChocoId
        $key = $chocoId.ToLowerInvariant()
        $target = if ($Map.ContainsKey($key)) { $Map[$key] } else { $null }
        $groupKey = if ($target) { ("{0}|{1}" -f $target.Source, $target.WingetId).ToLowerInvariant() } else { $null }
        $payload = @($payloadAudit | Where-Object { $_.Package -ieq $chocoId } | Select-Object -First 1)[0]
        $commands = if ($portableCommandMap.ContainsKey($key)) { @($portableCommandMap[$key]) } else { @() }
        $chocoShimCommands = @($shimAudit | Where-Object {
            $shimName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            $commands -contains $shimName -or $_.Name -ieq $chocoId -or $shimName -ieq $chocoId
        } | Select-Object -ExpandProperty Name)
        $commandChecks = @($commands | ForEach-Object { Test-ReparoCommandHasNonChocoSource -CommandName $_ })
        $hasChocolateyOnlyCommand = [bool]($commandChecks | Where-Object { -not $_.HasNonChocoSource })
        $wingetAvailable = $false
        $wingetInstalled = $false
        $wingetInstalledVersion = $null

        if ($target) {
            $wingetAvailable = Test-ReparoWingetPackageAvailable -WingetId $target.WingetId -Source $target.Source
            $installed = Get-ReparoWingetInstalledPackage -WingetId $target.WingetId -Source $target.Source
            if ($installed) {
                $wingetInstalled = $true
                $wingetInstalledVersion = $installed.Version
            }
        }

        $duplicateCount = if ($groupKey -and $duplicateCounts.ContainsKey($groupKey)) { $duplicateCounts[$groupKey] } else { 1 }
        $migrationClass = Get-ReparoChocoMigrationClass -ChocoId $chocoId -HasMap ([bool]$target) -HasProgramDataPayload ([bool]($payload -and $payload.HasNonChocoPayload)) -DuplicateCount $duplicateCount
        $riskLevel = Get-ReparoChocoMigrationRiskLevel -MigrationClass $migrationClass
        $safeToDeregister = $false
        $reason = $null

        if ($ExcludeSet.ContainsKey($key)) {
            $reason = 'excluded from normal migration'
        }
        elseif (-not $target) {
            $reason = 'no winget map'
        }
        elseif (-not $wingetAvailable) {
            $reason = 'winget package not found'
        }
        elseif ($migrationClass -eq 'RuntimeDependency' -and -not $AllowRuntimeDeregister) {
            $reason = 'runtime package requires -AllowRuntimeDeregister'
        }
        elseif ($migrationClass -eq 'PortablePayload' -and -not $AllowPortableDeregister) {
            $reason = 'portable/CLI payload requires -AllowPortableDeregister and command verification'
        }
        elseif ($migrationClass -eq 'PortablePayload' -and $hasChocolateyOnlyCommand) {
            $reason = 'portable/CLI payload requires post-winget non-Chocolatey command verification'
            $safeToDeregister = $true
        }
        elseif ($migrationClass -in @('ChocolateyInfrastructure', 'WindowsPrerequisite', 'Unsupported', 'ManualReview')) {
            $reason = "class $migrationClass requires manual review"
        }
        else {
            $safeToDeregister = $true
            $reason = 'safe after winget verification'
        }

        [void]$plan.Add([pscustomobject]@{
            ChocoId                  = $chocoId
            ChocoVersion             = $package.Version
            WingetId                 = if ($target) { $target.WingetId } else { $null }
            Source                   = if ($target) { $target.Source } else { $null }
            WingetAvailable          = $wingetAvailable
            WingetInstalled          = $wingetInstalled
            WingetInstalledVersion   = $wingetInstalledVersion
            MigrationClass           = $migrationClass
            RiskLevel                = $riskLevel
            DuplicateGroupKey        = $groupKey
            DuplicateCount           = $duplicateCount
            ProgramDataPayload       = [bool]($payload -and $payload.HasNonChocoPayload)
            ProgramDataSizeMB        = if ($payload) { $payload.SizeMB } else { 0 }
            ProgramDataSamplePayload = if ($payload) { $payload.SamplePayload } else { '' }
            ChocoShimCommands        = ($chocoShimCommands -join ';')
            RequiredCommands         = ($commands -join ';')
            ChocolateyOnlyCommands   = (($commandChecks | Where-Object { -not $_.HasNonChocoSource } | Select-Object -ExpandProperty Command) -join ';')
            SafeToDeregister         = $safeToDeregister
            ProposedAction           = if ($target) { if ($safeToDeregister) { 'InstallOrVerifyWingetThenDeregister' } else { 'InstallOrVerifyWingetOnly' } } else { 'ReportOnly' }
            Reason                   = $reason
        })
    }

    return $plan.ToArray()
}

function Export-ReparoChocoMigrationPlan {
    param([Parameter(Mandatory)][object[]]$Plan)

    if ([string]::IsNullOrWhiteSpace($MigrationReportPath)) { return }

    $basePath = $MigrationReportPath
    $extension = [System.IO.Path]::GetExtension($basePath)
    if ($extension -ieq '.csv') {
        $csvPath = $basePath
        $jsonPath = [System.IO.Path]::ChangeExtension($basePath, '.json')
    }
    elseif ($extension -ieq '.json') {
        $jsonPath = $basePath
        $csvPath = [System.IO.Path]::ChangeExtension($basePath, '.csv')
    }
    else {
        $csvPath = "$basePath.csv"
        $jsonPath = "$basePath.json"
    }

    $csvParent = Split-Path -Parent $csvPath
    if (-not [string]::IsNullOrWhiteSpace($csvParent)) {
        New-Item -ItemType Directory -Force -Path $csvParent | Out-Null
    }

    $Plan | Export-Csv -LiteralPath $csvPath -NoTypeInformation
    $Plan | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    Write-Done "Exported Chocolatey migration reports: $csvPath and $jsonPath"
    Write-ReparoLog ("[MIGRATE] Exported reports: {0}; {1}" -f $csvPath, $jsonPath)
    Add-ReparoSummaryNote ("Chocolatey migration report exported to $csvPath and $jsonPath")
}

function Get-ReparoChocolateyBackupPath {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $desktopPath = [Environment]::GetFolderPath('DesktopDirectory')
    if ([string]::IsNullOrWhiteSpace($desktopPath)) {
        $desktopPath = Join-Path $env:USERPROFILE 'Desktop'
    }
    if ([string]::IsNullOrWhiteSpace($desktopPath) -or -not (Test-Path -LiteralPath $desktopPath)) {
        $desktopPath = Join-Path ([System.IO.Path]::GetTempPath()) 'Reparo'
    }

    return (Join-Path $desktopPath ("chocolatey-backup-{0}" -f $timestamp))
}

function Invoke-ReparoFinalizeChocolateyRemoval {
    Write-Step 'Finalize Chocolatey removal'
    Write-ReparoLog '[STEP] Finalize Chocolatey removal'

    $chocoRoot = Get-ReparoChocolateyRoot
    if (-not (Test-Path -LiteralPath $chocoRoot)) {
        Write-Skip "Chocolatey root not found: $chocoRoot"
        Add-ReparoSummaryNote "Chocolatey removal skipped; root not found: $chocoRoot"
        return
    }

    $remainingPackages = New-Object System.Collections.Generic.List[object]
    try {
        @(Get-ReparoChocoPackages) | ForEach-Object { [void]$remainingPackages.Add($_) }
    }
    catch {
        Write-Info "Unable to query Chocolatey package records; falling back to $chocoRoot\lib inventory: $($_.Exception.Message)"
        Write-ReparoLog ("[WARN] choco list unavailable during finalization; using lib inventory: {0}" -f $_.Exception.Message)
    }

    $knownIds = @{}
    foreach ($package in @($remainingPackages.ToArray())) {
        $knownIds[([string]$package.ChocoId).ToLowerInvariant()] = $true
    }
    foreach ($package in @(Get-ReparoChocoPackageDirs)) {
        $key = ([string]$package.ChocoId).ToLowerInvariant()
        if (-not $knownIds.ContainsKey($key)) {
            [void]$remainingPackages.Add($package)
            $knownIds[$key] = $true
        }
    }

    $allowedFinalizePackages = @(Get-ReparoChocoFinalizeAllowedPackageIds | ForEach-Object { $_.ToLowerInvariant() })
    $nonExcludedPackages = @($remainingPackages.ToArray() | Where-Object { $allowedFinalizePackages -notcontains ([string]$_.ChocoId).ToLowerInvariant() })
    if ($nonExcludedPackages.Count -gt 0 -and -not $AllowRemainingChocoPackages) {
        $reason = "remaining non-excluded Chocolatey packages: $($nonExcludedPackages.ChocoId -join ', ')"
        Write-Fail "Blocked Chocolatey removal: $reason"
        Add-ReparoSummaryRecord -Bucket Failed -Software 'Chocolatey' -Version '-' -Method 'choco-finalize' -Reason $reason
        return
    }

    $shimAudit = @(Get-ReparoChocoPathShimAudit | Where-Object { $_.Name -notin @('choco.exe', 'RefreshEnv.cmd') })
    if ($shimAudit.Count -gt 0) {
        $reason = "Chocolatey-only commands remain: $($shimAudit.Name -join ', ')"
        Write-Fail "Blocked Chocolatey removal: $reason"
        Add-ReparoSummaryRecord -Bucket Failed -Software 'Chocolatey' -Version '-' -Method 'choco-finalize' -Reason $reason
        return
    }

    $backupPath = $null
    if (-not $NoChocolateyBackup) {
        $backupPath = Get-ReparoChocolateyBackupPath
        if ($Preview) {
            Write-Info "Preview: would back up $chocoRoot to $backupPath"
            Write-ReparoLog ("[PREVIEW] Would back up {0} to {1}" -f $chocoRoot, $backupPath)
        }
        else {
            $backupParent = Split-Path -Parent $backupPath
            if (-not [string]::IsNullOrWhiteSpace($backupParent)) {
                New-Item -ItemType Directory -Force -Path $backupParent | Out-Null
            }
            Copy-Item -LiteralPath $chocoRoot -Destination $backupPath -Recurse -Force
            Write-Done "Backed up Chocolatey to $backupPath"
            Write-ReparoLog ("[DONE] Backed up Chocolatey to {0}" -f $backupPath)
        }
    }

    if ($Preview) {
        Write-Info "Preview: would remove $chocoRoot, ChocolateyInstall, and Chocolatey PATH entries"
        Add-ReparoSummaryRecord -Bucket Skipped -Software 'Chocolatey' -Version '-' -Method 'choco-finalize' -Reason 'preview only'
        return
    }

    Remove-Item -LiteralPath $chocoRoot -Recurse -Force
    [Environment]::SetEnvironmentVariable('ChocolateyInstall', $null, 'Machine')
    [Environment]::SetEnvironmentVariable('ChocolateyInstall', $null, 'User')

    foreach ($target in @('Machine', 'User')) {
        $pathValue = [Environment]::GetEnvironmentVariable('Path', $target)
        if ([string]::IsNullOrWhiteSpace($pathValue)) { continue }
        $newPath = (($pathValue -split ';') | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_) -and -not (Test-ReparoPathIsUnderRoot -Path $_ -Root $chocoRoot)
        }) -join ';'
        [Environment]::SetEnvironmentVariable('Path', $newPath, $target)
    }

    Write-Done 'Chocolatey finalized/removed after safety checks.'
    Add-ReparoSummaryRecord -Bucket Updated -Software 'Chocolatey' -Version '-' -Method 'choco-finalize' -Reason 'removed after backup and safety checks'
}

function Invoke-ReparoLoggedNativeCommand {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$Label
    )

    Write-ReparoLog ("[CMD] {0} {1}" -f $FilePath, ($Arguments -join ' '))
    $output = @(& $FilePath @Arguments 2>&1)
    $exitCode = $LASTEXITCODE

    foreach ($line in $output) {
        Write-ReparoLog ("[{0}] {1}" -f $Label, ([string]$line))
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output   = $output
    }
}

function ConvertFrom-ReparoWingetListTable {
    param([object[]]$Output)

    $packages = New-Object System.Collections.Generic.List[object]
    $columns = $null
    foreach ($item in $Output) {
        $line = ([string]$item).TrimEnd()
        $trimmedLine = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($trimmedLine -match '^[\\|/-]$') { continue }
        if ($line -match '^Name\s+Id\s+Version') {
            $columns = @{
                Name      = $line.IndexOf('Name')
                Id        = $line.IndexOf('Id')
                Version   = $line.IndexOf('Version')
                Available = $line.IndexOf('Available')
                Source    = $line.IndexOf('Source')
            }
            continue
        }

        if ($trimmedLine -match '^[-\s]+$') { continue }
        if ($trimmedLine -match '^(No installed package found|No packages found)') { continue }

        $name = $null
        $id = $null
        $version = $null
        $source = $null

        if ($columns -and $columns.Name -ge 0 -and $columns.Id -gt $columns.Name -and $columns.Version -gt $columns.Id) {
            $positions = @($columns.Name, $columns.Id, $columns.Version, $columns.Available, $columns.Source) |
                Where-Object { $_ -ge 0 } |
                Sort-Object -Unique

            $getColumn = {
                param([int]$Start)

                if ($Start -lt 0 -or $Start -ge $line.Length) { return $null }

                $end = $line.Length
                foreach ($position in $positions) {
                    if ($position -gt $Start) {
                        $end = [Math]::Min($position, $line.Length)
                        break
                    }
                }

                return $line.Substring($Start, ($end - $Start)).Trim()
            }

            $name = & $getColumn $columns.Name
            $id = & $getColumn $columns.Id
            $version = & $getColumn $columns.Version
            $source = & $getColumn $columns.Source
        }
        else {
            $match = [regex]::Match($line, '^(?<name>.+?)\s{2,}(?<id>\S+)\s{2,}(?<version>\S+)(?:\s{2,}(?<source>\S+))?\s*$')
            if ($match.Success) {
                $name = $match.Groups['name'].Value.Trim()
                $id = $match.Groups['id'].Value.Trim()
                $version = $match.Groups['version'].Value.Trim()
                $source = $match.Groups['source'].Value.Trim()
            }
            else {
                $tokens = @($line -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                if ($columns -and $columns.Available -ge 0 -and $tokens.Count -ge 5) {
                    $source = $tokens[-1]
                    $version = $tokens[-3]
                    $id = $tokens[-4]
                    $name = ($tokens[0..($tokens.Count - 5)] -join ' ')
                }
                elseif ($tokens.Count -ge 4) {
                    $source = $tokens[-1]
                    $version = $tokens[-2]
                    $id = $tokens[-3]
                    $name = ($tokens[0..($tokens.Count - 4)] -join ' ')
                }
                elseif ($tokens.Count -ge 3) {
                    $version = $tokens[-1]
                    $id = $tokens[-2]
                    $name = ($tokens[0..($tokens.Count - 3)] -join ' ')
                }
                else {
                    continue
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($version)) { continue }

        [void]$packages.Add([pscustomobject]@{
            Name    = $name
            Id      = $id
            Version = $version
            Source  = $source
            Method  = 'winget'
        })
    }

    return $packages.ToArray()
}

function Get-ReparoWingetAppVersion {
    param([Parameter(Mandatory)][string]$App)

    if (-not (Test-ReparoExecutable -Name 'winget' -Arguments @('--version'))) {
        return $null
    }

    $queries = @(
        @('list', '--id', $App, '--exact', '--accept-source-agreements', '--disable-interactivity'),
        @('list', $App, '--accept-source-agreements', '--disable-interactivity')
    )

    foreach ($arguments in $queries) {
        $output = @(& winget @arguments 2>&1)
        foreach ($line in $output) {
            Write-ReparoLog ("[APP] winget {0}: {1}" -f ($arguments -join ' '), ([string]$line))
        }

        if ($LASTEXITCODE -ne 0) { continue }

        $packages = @(ConvertFrom-ReparoWingetListTable -Output $output)
        if ($packages.Count -gt 0) {
            return $packages[0]
        }
    }

    return $null
}

function Get-ReparoChocoAppVersion {
    param([Parameter(Mandatory)][string]$App)

    if (-not (Test-ReparoExecutable -Name 'choco' -Arguments @('--version'))) {
        return $null
    }

    $output = @(choco list --local-only --exact $App --limit-output --no-color 2>&1)
    foreach ($line in $output) {
        Write-ReparoLog ("[APP] choco list: {0}" -f ([string]$line))
    }

    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    foreach ($item in $output) {
        $line = ([string]$item).Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line -notmatch '\|') { continue }
        $parts = $line -split '\|'
        if ($parts.Count -lt 2) { continue }

        return [pscustomobject]@{
            Name    = $parts[0].Trim()
            Id      = $parts[0].Trim()
            Version = $parts[1].Trim()
            Source  = 'chocolatey'
            Method  = 'choco'
        }
    }

    return $null
}

function Get-ReparoAppVersion {
    param(
        [Parameter(Mandatory)][string]$App,
        [ValidateSet('Auto', 'Winget', 'Choco')]
        [string]$Manager = 'Auto'
    )

    $managers = if ($Manager -eq 'Auto') { @('Winget', 'Choco') } else { @($Manager) }
    foreach ($candidate in $managers) {
        $result = switch ($candidate) {
            'Winget' { Get-ReparoWingetAppVersion -App $App }
            'Choco' { Get-ReparoChocoAppVersion -App $App }
        }

        if ($result) {
            return $result
        }
    }

    return $null
}

function Invoke-ReparoCheckAppVersion {
    param(
        [Parameter(Mandatory)][string]$App,
        [ValidateSet('Auto', 'Winget', 'Choco')]
        [string]$Manager = 'Auto'
    )

    Write-Step "Check app version: $App"
    Write-ReparoLog ("[STEP] Check app version: {0} via {1}" -f $App, $Manager)

    $result = Get-ReparoAppVersion -App $App -Manager $Manager
    if (-not $result) {
        Write-Skip "App not found through ${Manager}: $App"
        Write-ReparoLog ("[SKIP] App not found through {0}: {1}" -f $Manager, $App)
        Add-ReparoSummaryRecord -Bucket Skipped -Software $App -Version '-' -Method $Manager -Reason 'app not found'
        return $false
    }

    Write-Done ("{0} ({1}) is installed at {2} via {3}" -f $result.Name, $result.Id, $result.Version, $result.Method)
    Write-ReparoLog ("[APP] {0}|{1}|{2}|{3}" -f $result.Name, $result.Id, $result.Version, $result.Method)
    Add-ReparoSummaryNote ("{0} ({1}) is installed at {2} via {3}." -f $result.Name, $result.Id, $result.Version, $result.Method)
    return $true
}

function Invoke-ReparoLockAppVersion {
    param(
        [Parameter(Mandatory)][string]$App,
        [string]$Version,
        [ValidateSet('Auto', 'Winget', 'Choco')]
        [string]$Manager = 'Auto'
    )

    Write-Step "Lock app version: $App"
    Write-ReparoLog ("[STEP] Lock app version: {0} via {1}" -f $App, $Manager)

    $result = Get-ReparoAppVersion -App $App -Manager $Manager
    if (-not $result) {
        Write-Skip "App not found through ${Manager}: $App"
        Write-ReparoLog ("[SKIP] App not found through {0}: {1}" -f $Manager, $App)
        Add-ReparoSummaryRecord -Bucket Skipped -Software $App -Version '-' -Method $Manager -Reason 'app not found'
        return $false
    }

    $pinVersion = $Version
    if ([string]::IsNullOrWhiteSpace($pinVersion)) {
        $pinVersion = $result.Version
        if ([string]::IsNullOrWhiteSpace($pinVersion) -or $pinVersion -eq 'Unknown') {
            $pinVersion = $null
        }
    }

    $pinDescription = if ([string]::IsNullOrWhiteSpace($pinVersion)) { 'a blocking pin' } else { $pinVersion }

    if ($Preview) {
        Write-Info ("Preview: would lock {0} ({1}) to {2} via {3}" -f $result.Name, $result.Id, $pinDescription, $result.Method)
        Write-ReparoLog ("[PREVIEW] Would lock {0} ({1}) to {2} via {3}" -f $result.Name, $result.Id, $pinDescription, $result.Method)
        Add-ReparoSummaryRecord -Bucket Skipped -Software $result.Name -CurrentVersion $result.Version -Version $pinDescription -Method $result.Method -Reason 'preview only'
        return $true
    }

    switch ($result.Method) {
        'winget' {
            $arguments = @('pin', 'add', '--id', $result.Id, '--exact')
            if (-not [string]::IsNullOrWhiteSpace($result.Source)) {
                $arguments += @('--source', $result.Source)
            }

            if (-not [string]::IsNullOrWhiteSpace($pinVersion)) {
                $arguments += @('--version', $pinVersion)
            }
            else {
                $arguments += '--blocking'
            }

            $pinResult = Invoke-ReparoLoggedNativeCommand -FilePath 'winget' -Arguments $arguments -Label 'WINGET-PIN'
        }
        'choco' {
            $arguments = @('pin', 'add', '--name', $result.Id)
            if (-not [string]::IsNullOrWhiteSpace($pinVersion)) {
                $arguments += @('--version', $pinVersion)
            }

            $pinResult = Invoke-ReparoLoggedNativeCommand -FilePath 'choco' -Arguments $arguments -Label 'CHOCO-PIN'
        }
        default {
            throw "Unsupported package manager for locking: $($result.Method)"
        }
    }

    if ($pinResult.ExitCode -ne 0) {
        Write-Fail ("Failed to lock {0}: exit code {1}" -f $result.Name, $pinResult.ExitCode)
        Add-ReparoSummaryRecord -Bucket Failed -Software $result.Name -CurrentVersion $result.Version -Version $pinVersion -Method $result.Method -Reason "pin exit code $($pinResult.ExitCode)"
        return $false
    }

    Write-Done ("Locked {0} ({1}) to {2} via {3}" -f $result.Name, $result.Id, $pinDescription, $result.Method)
    Write-ReparoLog ("[DONE] Locked {0} ({1}) to {2} via {3}" -f $result.Name, $result.Id, $pinDescription, $result.Method)
    Add-ReparoSummaryRecord -Bucket Updated -Software $result.Name -CurrentVersion $result.Version -Version $pinDescription -Method $result.Method -Reason 'locked'
    return $true
}

function Invoke-ReparoChocoToWingetMigration {
    Write-Step 'Chocolatey to winget migration'
    Write-ReparoLog '[STEP] Chocolatey to winget migration'

    $hasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
    if (-not $hasWinget) {
        $hasWinget = Ensure-ReparoWinget
    }

    if (-not $hasWinget) {
        Write-Skip 'winget not found or could not be repaired; skipping migration'
        Write-ReparoLog '[SKIP] winget not found or could not be repaired; skipping migration'
        Add-ReparoSummaryRecord -Bucket Skipped -Software 'ChocoToWinget' -Version '-' -Method 'choco->winget' -Reason 'winget not found or could not be repaired'
        return
    }

    try {
        $packages = @(Get-ReparoChocoPackages)
    }
    catch {
        Write-Fail $_.Exception.Message
        Write-ReparoLog ("[ERROR] {0}" -f $_.Exception.Message)
        Add-ReparoSummaryRecord -Bucket Failed -Software 'ChocoToWinget' -Version '-' -Method 'choco->winget' -Reason $_.Exception.Message
        return
    }

    if (-not $packages -or $packages.Count -eq 0) {
        Write-Skip 'No Chocolatey packages found.'
        Write-ReparoLog '[SKIP] No Chocolatey packages found'
        Add-ReparoSummaryNote 'Chocolatey migration found no local Chocolatey packages.'
        return
    }

    try {
        $map = Get-ReparoChocoWingetMap
    }
    catch {
        Write-Fail $_.Exception.Message
        Write-ReparoLog ("[ERROR] {0}" -f $_.Exception.Message)
        Add-ReparoSummaryRecord -Bucket Failed -Software 'ChocoToWinget' -Version '-' -Method 'choco->winget' -Reason $_.Exception.Message
        return
    }

    $defaultExclude = @(Get-ReparoChocoMigrationDefaultExcludes)
    $excludeSet = @{}
    foreach ($exclude in (@($defaultExclude) + @($MigrateChocoExclude))) {
        if (-not [string]::IsNullOrWhiteSpace($exclude)) {
            $excludeSet[$exclude.Trim().ToLowerInvariant()] = $true
        }
    }

    $plan = @(Get-ReparoChocoMigrationPlan -Packages $packages -Map $map -ExcludeSet $excludeSet)
    Export-ReparoChocoMigrationPlan -Plan $plan

    foreach ($row in $plan) {
        Write-ReparoLog ("[MIGRATE-PLAN] {0}|{1}|{2}|{3}|{4}|Safe={5}|{6}" -f $row.ChocoId, $row.ChocoVersion, $row.WingetId, $row.MigrationClass, $row.RiskLevel, $row.SafeToDeregister, $row.Reason)
    }

    if ($Preview) {
        Write-Info ("Preview: built Chocolatey migration plan for {0} package(s)." -f $plan.Count)
        foreach ($row in $plan) {
            $bucket = if ($row.WingetId -and $row.WingetAvailable -and $row.SafeToDeregister) { 'Updated' } else { 'Skipped' }
            Add-ReparoSummaryRecord -Bucket $bucket -Software $row.ChocoId -CurrentVersion $row.ChocoVersion -Version $row.WingetId -Method 'choco->winget' -Reason ("preview: {0}; {1}" -f $row.MigrationClass, $row.Reason)
        }
        return
    }

    $candidateRows = @($plan | Where-Object { $_.WingetId -and $_.WingetAvailable })
    $groups = @($candidateRows | Group-Object DuplicateGroupKey)
    foreach ($group in $groups) {
        $groupRows = @($group.Group)
        $target = $groupRows[0]
        Write-ReparoLog ("[MIGRATE] Winget group {0}: {1}" -f $target.DuplicateGroupKey, (($groupRows | Select-Object -ExpandProperty ChocoId) -join ', '))

        $wingetResult = Ensure-ReparoWingetPackageInstalled -WingetId $target.WingetId -Source $target.Source
        if ($wingetResult.ExitCode -ne 0) {
            $reason = "winget install/verify exit code $($wingetResult.ExitCode)"
            foreach ($row in $groupRows) {
                Write-Fail "$($row.ChocoId) migration failed: $reason"
                Add-ReparoSummaryRecord -Bucket Failed -Software $row.ChocoId -CurrentVersion $row.ChocoVersion -Version $row.WingetId -Method 'choco->winget' -Reason $reason
            }
            continue
        }

        foreach ($row in $groupRows) {
            if (-not $row.SafeToDeregister) {
                Write-Skip "Verified winget target for $($row.ChocoId), but not deregistering: $($row.Reason)"
                Add-ReparoSummaryRecord -Bucket Skipped -Software $row.ChocoId -CurrentVersion $row.ChocoVersion -Version $row.WingetId -Method 'choco->winget' -Reason $row.Reason
                continue
            }

            if (-not $ChocoDeregisterOnly) {
                Write-Done "Verified winget target for $($row.ChocoId) -> $($row.WingetId); Chocolatey record left registered."
                Add-ReparoSummaryRecord -Bucket Updated -Software $row.ChocoId -CurrentVersion $row.ChocoVersion -Version $row.WingetId -Method 'choco->winget' -Reason 'winget verified; deregistration not requested'
                continue
            }

            if ($row.MigrationClass -eq 'PortablePayload' -and -not [string]::IsNullOrWhiteSpace($row.RequiredCommands)) {
                $requiredCommands = @($row.RequiredCommands -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                $postInstallCommandChecks = @($requiredCommands | ForEach-Object { Test-ReparoCommandHasNonChocoSource -CommandName $_ })
                $chocoOnlyCommands = @($postInstallCommandChecks | Where-Object { -not $_.HasNonChocoSource } | Select-Object -ExpandProperty Command)
                if ($chocoOnlyCommands.Count -gt 0) {
                    $reason = "portable/CLI commands still resolve only through Chocolatey: $($chocoOnlyCommands -join ', ')"
                    Write-Skip "Verified winget target for $($row.ChocoId), but not deregistering: $reason"
                    Add-ReparoSummaryRecord -Bucket Skipped -Software $row.ChocoId -CurrentVersion $row.ChocoVersion -Version $row.WingetId -Method 'choco->winget' -Reason $reason
                    continue
                }
            }

            $chocoResult = Invoke-ReparoChocoDeregisterPackage -ChocoId $row.ChocoId
            if ($chocoResult.ExitCode -ne 0) {
                $reason = "choco deregister exit code $($chocoResult.ExitCode)"
                Write-Fail "$($row.ChocoId) winget verified but Chocolatey deregistration failed: $reason"
                Add-ReparoSummaryRecord -Bucket Failed -Software $row.ChocoId -CurrentVersion $row.ChocoVersion -Version $row.WingetId -Method 'choco->winget' -Reason $reason
                continue
            }

            Write-Done "Migrated $($row.ChocoId) -> $($row.WingetId); deregistered Chocolatey package record."
            Add-ReparoSummaryRecord -Bucket Updated -Software $row.ChocoId -CurrentVersion $row.ChocoVersion -Version $row.WingetId -Method 'choco->winget' -Reason 'winget verified; Chocolatey record deregistered'
        }
    }

    foreach ($row in @($plan | Where-Object { -not ($_.WingetId -and $_.WingetAvailable) })) {
        Write-Skip "Skipping $($row.ChocoId): $($row.Reason)"
        Add-ReparoSummaryRecord -Bucket Skipped -Software $row.ChocoId -CurrentVersion $row.ChocoVersion -Version $row.WingetId -Method 'choco->winget' -Reason $row.Reason
    }
}

function Write-ReparoSummaryTable {
    param(
        [string]$Title,
        [object[]]$Rows,
        [switch]$IncludeReason
    )

    Write-Host ''
    Write-Host $Title -ForegroundColor Magenta

    if (-not $Rows -or $Rows.Count -eq 0) {
        Write-Host '  None'
        Write-ReparoLog ("[SUMMARY] {0}: none" -f $Title)
        return
    }

    if ($IncludeReason) {
        $table = $Rows | Select-Object Software, CurrentVersion, Version, Method, Reason | Format-Table -AutoSize | Out-String
    }
    else {
        $table = $Rows | Select-Object Software, CurrentVersion, Version, Method | Format-Table -AutoSize | Out-String
    }

    $table = $table.TrimEnd()
    Write-Host $table
    foreach ($line in ($table -split [Environment]::NewLine)) {
        Write-ReparoLog ("[SUMMARY] {0}" -f $line)
    }
}

function Write-ReparoSummary {
    Write-Host ''
    Write-Host 'REPARO summary' -ForegroundColor Magenta
    Write-ReparoLog '[SUMMARY] REPARO summary'

    Write-ReparoSummaryTable -Title 'Updated software' -Rows $script:ReparoSummary['Updated'].ToArray()
    Write-ReparoSummaryTable -Title 'Skipped sections' -Rows $script:ReparoSummary['Skipped'].ToArray() -IncludeReason
    Write-ReparoSummaryTable -Title 'Failed sections' -Rows $script:ReparoSummary['Failed'].ToArray() -IncludeReason

    if ($script:ReparoSummary['Notes'].Count -gt 0) {
        Write-Host ''
        Write-Host 'Notes' -ForegroundColor Magenta
        foreach ($note in $script:ReparoSummary['Notes']) {
            Write-Host ("  - {0}" -f $note)
            Write-ReparoLog ("[SUMMARY] NOTE {0}" -f $note)
        }
    }

    Write-Host ''
    Write-Host ("Working log: {0}" -f $script:ReparoLogPath) -ForegroundColor Cyan
    Write-ReparoLog ("[SUMMARY] Working log: {0}" -f $script:ReparoLogPath)
}

function Invoke-ReparoTimedCommand {
    param(
        [Parameter(Mandatory)][string]$ShellPath,
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string]$Section,
        [int]$TimeoutSeconds = 0,
        [switch]$IgnoreTimeouts
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $heartbeatSeconds = 60
    $nextHeartbeat = [DateTime]::UtcNow.AddSeconds($heartbeatSeconds)
    $timeoutEnabled = (-not $IgnoreTimeouts -and $TimeoutSeconds -gt 0)
    $safeSection = ConvertTo-ReparoSafeFileName -Value $Section
    $commandOutputPath = Join-Path $LogRoot ("{0}_{1}.out.log" -f $script:ReparoLogBaseName, $safeSection)
    $commandScriptPath = Join-Path $LogRoot ("{0}_{1}.command.ps1" -f $script:ReparoLogBaseName, $safeSection)

    Remove-Item -LiteralPath $commandOutputPath, $commandScriptPath -Force -ErrorAction SilentlyContinue

    $commandScript = @(
        '$ErrorActionPreference = ''Continue'''
        '[Console]::OutputEncoding = [System.Text.Encoding]::UTF8'
        '$OutputEncoding = [System.Text.Encoding]::UTF8'
        ('$outputPath = {0}' -f (ConvertTo-ReparoPowerShellLiteral -Value $commandOutputPath))
        'function Write-ReparoChildOutput {'
        '    param([object]$Value)'
        '    $line = [string]$Value'
        '    Add-Content -LiteralPath $outputPath -Value $line -Encoding UTF8'
        '}'
        'try {'
        '    & {'
        $Command
        '    } 2>&1 | ForEach-Object { Write-ReparoChildOutput -Value $_ }'
        '    if ($null -ne $global:LASTEXITCODE) { exit $global:LASTEXITCODE }'
        '    exit 0'
        '}'
        'catch {'
        '    $message = ($_ | Out-String).Trim()'
        '    if (-not [string]::IsNullOrWhiteSpace($message)) {'
        '        Write-ReparoChildOutput -Value $message'
        '    }'
        '    exit 1'
        '}'
    )
    Set-Content -LiteralPath $commandScriptPath -Value $commandScript -Encoding UTF8

    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$commandScriptPath`""

    if (-not $timeoutEnabled) {
        Write-ReparoLog ("[CMD-START] {0} | timeout=disabled" -f $Section)
    }
    else {
        Write-ReparoLog ("[CMD-START] {0} | timeout={1}s" -f $Section, $TimeoutSeconds)
    }
    Write-ReparoDebug ("Launching {0} via {1} with arguments: {2}" -f $Section, $ShellPath, $arguments)

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $ShellPath
    $psi.Arguments = $arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError = $false
    $psi.CreateNoWindow = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    $null = $process.Start()
    Write-ReparoDebug ("Started PID {0} for section {1}" -f $process.Id, $Section)

    $timedOut = $false
    $output = New-Object System.Collections.Generic.List[string]
    $loggedLineCount = 0
    while (-not $process.HasExited) {
        Start-Sleep -Milliseconds 500

        Sync-ReparoCommandOutputLog -Path $commandOutputPath -LineCount ([ref]$loggedLineCount) -Output $output -Section $Section

        if ([DateTime]::UtcNow -ge $nextHeartbeat) {
            Write-ReparoLog ("[CMD-WAIT] {0} still running elapsed={1} pid={2}" -f $Section, $stopwatch.Elapsed, $process.Id)
            $nextHeartbeat = [DateTime]::UtcNow.AddSeconds($heartbeatSeconds)
        }

        if ($timeoutEnabled -and $stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
            $timedOut = $true
            Stop-ReparoProcessTree -ProcessId $process.Id
            break
        }
    }

    $process.WaitForExit()
    Sync-ReparoCommandOutputLog -Path $commandOutputPath -LineCount ([ref]$loggedLineCount) -Output $output -Section $Section
    $stopwatch.Stop()

    if ($timedOut) {
        Write-ReparoLog ("[CMD-TIMEOUT] {0} timed out after {1}s elapsed={2}" -f $Section, $TimeoutSeconds, $stopwatch.Elapsed)
        Write-ReparoEventLog -EventId 1201 -EntryType Warning -Message @"
Reparo command timed out.

Computer: $env:COMPUTERNAME
PID: $PID
Section: $Section
TimeoutSeconds: $TimeoutSeconds
Elapsed: $($stopwatch.Elapsed)
CommandOutputLog: $commandOutputPath
Log: $script:ReparoLogPath
"@
        return [pscustomobject]@{
            TimedOut = $true
            ExitCode = 124
            Output   = @($output.ToArray()) + @("[TIMEOUT] $Section exceeded ${TimeoutSeconds}s")
            Elapsed  = $stopwatch.Elapsed
        }
    }

    Write-ReparoLog ("[CMD-END] {0} exit={1} elapsed={2}" -f $Section, $process.ExitCode, $stopwatch.Elapsed)
    Write-ReparoDebug ("{0} completed with exit={1} elapsed={2} outputLines={3}" -f $Section, $process.ExitCode, $stopwatch.Elapsed, $output.Count)
    Remove-Item -LiteralPath $commandOutputPath, $commandScriptPath -Force -ErrorAction SilentlyContinue

    [pscustomobject]@{
        TimedOut = $false
        ExitCode = $process.ExitCode
        Output   = $output.ToArray()
        Elapsed  = $stopwatch.Elapsed
    }
}

function Test-ReparoIgnorableCommandOutputLine {
    param(
        [Parameter(Mandatory)][string]$Section,
        [AllowNull()][string]$Line
    )

    $text = ([string]$Line)
    $text = $text -replace '\x1B\[[0-?]*[ -/]*[@-~]', ''
    $text = $text -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', ''
    $text = $text.Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $true
    }

    if ($text -match '^[\|/\\\-]+$') {
        return $true
    }

    if ($Section -eq 'Spicetify') {
        if ($text -match '^[\|/\\\-]\s+.+') {
            return $true
        }

        if ($text -match '^Patching files\s+\[\d+/\d+\].*\b\d{1,3}%\s*\|\s*\d+s\s*$') {
            return $true
        }
    }

    return $false
}

function Sync-ReparoCommandOutputLog {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ref]$LineCount,
        [Parameter(Mandatory)]$Output,
        [Parameter(Mandatory)][string]$Section
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    try {
        $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop)
    }
    catch {
        return
    }

    if ($lines.Count -le $LineCount.Value) {
        return
    }

    if ($LineCount.Value -le 0) {
        $newLines = $lines
    }
    else {
        $newLines = $lines[$LineCount.Value..($lines.Count - 1)]
    }

    foreach ($line in $newLines) {
        if (-not (Test-ReparoIgnorableCommandOutputLine -Section $Section -Line ([string]$line))) {
            [void]$Output.Add([string]$line)
            Write-Host ([string]$line)
            Write-ReparoLog ("[CMD-OUT] {0}: {1}" -f $Section, [string]$line)
        }
    }

    $LineCount.Value = $lines.Count
}

function Invoke-ReparoCommandStep {
    param(
        [string]$Section,
        [string]$PresenceCmd,
        [string]$Command,
        [int]$TimeoutSeconds = 0
    )

    if (-not (Test-ReparoSectionSelected $Section)) { return }
    Write-ReparoDebug ("Invoke-ReparoCommandStep: {0} timeout={1} preview={2} debug={3}" -f $Section, $TimeoutSeconds, $Preview, $script:ReparoDebug)

    if ($PresenceCmd -and -not (Test-ReparoSectionTool -Section $Section -PresenceCmd $PresenceCmd)) {
        Write-Skip "$Section not found or cannot run in this context; skipping"
        Write-ReparoLog "[SKIP] $Section not found or cannot run in this context; skipping"
        Add-ReparoSummaryRecord -Bucket Skipped -Software $Section -Version '-' -Method $Section -Reason "$PresenceCmd not found or cannot run"
        return
    }

    Write-Step $Section
    Write-ReparoLog "[STEP] $Section"
    Write-ReparoLog ("[CMD] {0}" -f $Command)
    $pendingUpdates = @(Get-ReparoPendingUpdates -Section $Section)

    if ($Preview) {
        Write-ReparoLog ("[DRY-RUN] {0}" -f $Command)
        Write-Skip "$Section (preview only)"
        Add-ReparoSummaryRecord -Bucket Skipped -Software $Section -Version '-' -Method $Section -Reason 'preview only'
        return
    }

    try {
        $shell = Resolve-ReparoShell
        $result = Invoke-ReparoTimedCommand -ShellPath $shell -Command $Command -Section $Section -TimeoutSeconds $TimeoutSeconds -IgnoreTimeouts:$IgnoreTimeouts
        $output = @($result.Output)
        $exitCode = $result.ExitCode
        Write-ReparoDebug ("{0} output lines captured: {1}" -f $Section, $output.Count)

        $manualWingetReason = Get-ReparoWingetManualInterventionReason -Output $output
        if ($manualWingetReason) {
            Write-Warning $manualWingetReason
            Write-ReparoLog ("[WARN] {0}" -f $manualWingetReason)
            Add-ReparoSummaryNote $manualWingetReason
        }

        if ($result.TimedOut) {
            Write-Fail "$Section timed out after $($result.Elapsed)"
            Write-ReparoLog ("[ERROR] {0} timed out after {1}" -f $Section, $result.Elapsed)
            Add-ReparoSummaryRecord -Bucket Failed -Software $Section -Version '-' -Method $Section -Reason "timeout after $($result.Elapsed)"
            return
        }

        if ($exitCode -ne 0) {
            if (Test-ReparoBenignExit -Section $Section -ExitCode $exitCode -Output $output) {
                Write-Done "$Section complete (nothing to update)"
                Write-ReparoLog ("[DONE] {0} complete (benign winget exit code {1}; nothing to update)" -f $Section, $exitCode)
                Add-ReparoSummaryNote ("{0} completed with nothing to update." -f $Section)
                return
            }

            Write-Fail "$Section failed with exit code $exitCode"
            Write-ReparoLog ("[ERROR] {0} failed with exit code {1}" -f $Section, $exitCode)
            Add-ReparoSummaryRecord -Bucket Failed -Software $Section -Version '-' -Method $Section -Reason "exit code $exitCode"
            return
        }

        Write-Done "$Section complete"
        Write-ReparoLog "[DONE] $Section complete"
        Add-ReparoSectionUpdates -Section $Section -PendingUpdates $pendingUpdates
    }
    catch {
        $message = $_.Exception.Message
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = ($_ | Out-String).Trim()
        }
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = 'No exception message was provided.'
        }

        Write-Fail "$Section failed: $message"
        Write-ReparoLog ("[ERROR] {0}: {1}" -f $Section, $message)
        Add-ReparoSummaryRecord -Bucket Failed -Software $Section -Version '-' -Method $Section -Reason $message
    }
}

function New-ReparoSpicetifyWorkerScript {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)][string]$StatusPath,
        [switch]$PreviewOnly,
        [switch]$InstallRequested
    )

    $script = @"
`$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
`$OutputEncoding = [System.Text.Encoding]::UTF8
`$outputPath = $(ConvertTo-ReparoPowerShellLiteral -Value $OutputPath)
`$statusPath = $(ConvertTo-ReparoPowerShellLiteral -Value $StatusPath)
`$previewOnly = `$$($PreviewOnly.IsPresent.ToString().ToLowerInvariant())
`$installRequested = `$$($InstallRequested.IsPresent.ToString().ToLowerInvariant())

function Write-ReparoSpicetifyOutput {
    param([object]`$Value)
    `$line = [string]`$Value
    Add-Content -LiteralPath `$outputPath -Value `$line -Encoding UTF8
}

function Resolve-ReparoSpicetifyCommand {
    `$command = Get-Command spicetify -CommandType Application -ErrorAction SilentlyContinue
    if (`$command) { return `$command.Source }

    `$candidates = @(
        (Join-Path `$env:APPDATA 'spicetify\spicetify.exe'),
        (Join-Path `$env:LOCALAPPDATA 'spicetify\spicetify.exe'),
        (Join-Path `$env:USERPROFILE '.spicetify\spicetify.exe')
    )

    foreach (`$candidate in `$candidates) {
        if (-not [string]::IsNullOrWhiteSpace(`$candidate) -and (Test-Path -LiteralPath `$candidate)) {
            return `$candidate
        }
    }

    return `$null
}

try {
    Write-ReparoSpicetifyOutput ("[INFO] Spicetify worker identity: {0}" -f [Security.Principal.WindowsIdentity]::GetCurrent().Name)
    `$spicetify = Resolve-ReparoSpicetifyCommand
    if (`$installRequested) {
        Write-ReparoSpicetifyOutput '[STEP] Spicetify install/reinstall'
        if (`$previewOnly) {
            Write-ReparoSpicetifyOutput '[DRY-RUN] Invoke-WebRequest https://raw.githubusercontent.com/spicetify/marketplace/main/resources/install.ps1'
            Write-ReparoSpicetifyOutput '[DRY-RUN] powershell -File install.ps1 -BypassAdmin'
        }
        else {
            `$installerPath = Join-Path ([System.IO.Path]::GetTempPath()) ("spicetify-install-{0}.ps1" -f [guid]::NewGuid())
            Write-ReparoSpicetifyOutput ("[CMD] Download Spicetify installer to {0}" -f `$installerPath)
            Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/spicetify/marketplace/main/resources/install.ps1' -OutFile `$installerPath
            Unblock-File -LiteralPath `$installerPath -ErrorAction SilentlyContinue
            `$installOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File `$installerPath -BypassAdmin 2>&1)
            `$installExit = `$LASTEXITCODE
            foreach (`$line in `$installOutput) { Write-ReparoSpicetifyOutput ([string]`$line) }
            Remove-Item -LiteralPath `$installerPath -Force -ErrorAction SilentlyContinue
            if (`$installExit -ne 0) {
                Write-ReparoSpicetifyOutput ("[ERROR] Spicetify installer failed with exit code {0}" -f `$installExit)
                Set-Content -LiteralPath `$statusPath -Value ([string]`$installExit) -Encoding ASCII
                exit `$installExit
            }

            `$spicetify = Resolve-ReparoSpicetifyCommand
        }
    }

    if (-not `$spicetify) {
        Write-ReparoSpicetifyOutput '[SKIP] spicetify was not found in the interactive user context.'
        Set-Content -LiteralPath `$statusPath -Value '42' -Encoding ASCII
        exit 42
    }

    Write-ReparoSpicetifyOutput ("[CHECK] spicetify path: {0}" -f `$spicetify)
    `$versionOutput = @(& `$spicetify --version 2>&1)
    foreach (`$line in `$versionOutput) { Write-ReparoSpicetifyOutput ("[CHECK] {0}" -f [string]`$line) }

    if (`$previewOnly) {
        Write-ReparoSpicetifyOutput '[DRY-RUN] spicetify update'
        Write-ReparoSpicetifyOutput '[DRY-RUN] spicetify restore backup apply'
        Set-Content -LiteralPath `$statusPath -Value '0' -Encoding ASCII
        exit 0
    }

    foreach (`$step in @(
        @{ Label = 'Spicetify update'; Args = @('update') },
        @{ Label = 'Spicetify restore backup apply'; Args = @('restore', 'backup', 'apply') }
    )) {
        Write-ReparoSpicetifyOutput ("[STEP] {0}" -f `$step.Label)
        `$output = @(& `$spicetify @(`$step.Args) 2>&1)
        `$exit = `$LASTEXITCODE
        foreach (`$line in `$output) { Write-ReparoSpicetifyOutput ([string]`$line) }
        if (`$exit -ne 0) {
            Write-ReparoSpicetifyOutput ("[ERROR] {0} failed with exit code {1}" -f `$step.Label, `$exit)
            Set-Content -LiteralPath `$statusPath -Value ([string]`$exit) -Encoding ASCII
            exit `$exit
        }
    }

    Write-ReparoSpicetifyOutput '[DONE] Spicetify update and restore/backup/apply completed.'
    Set-Content -LiteralPath `$statusPath -Value '0' -Encoding ASCII
    exit 0
}
catch {
    `$message = (`$_ | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace(`$message)) { `$message = `$_.Exception.Message }
    Write-ReparoSpicetifyOutput ("[ERROR] {0}" -f `$message)
    Set-Content -LiteralPath `$statusPath -Value '1' -Encoding ASCII
    exit 1
}
"@

    Set-Content -LiteralPath $Path -Value $script -Encoding UTF8
}

function Sync-ReparoSpicetifyOutput {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ref]$LineCount
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    try {
        $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop)
    }
    catch {
        return
    }

    if ($lines.Count -le $LineCount.Value) {
        return
    }

    if ($LineCount.Value -le 0) {
        $newLines = $lines
    }
    else {
        $newLines = $lines[$LineCount.Value..($lines.Count - 1)]
    }

    foreach ($line in $newLines) {
        if (-not (Test-ReparoIgnorableCommandOutputLine -Section 'Spicetify' -Line ([string]$line))) {
            Write-Host ([string]$line)
            Write-ReparoLog ("[CMD-OUT] Spicetify: {0}" -f [string]$line)
        }
    }

    $LineCount.Value = $lines.Count
}

function Invoke-ReparoSpicetify {
    if (-not (Test-ReparoSectionSelected 'Spicetify')) { return }

    Write-Step 'Spicetify'
    Write-ReparoLog '[STEP] Spicetify'
    Write-ReparoLog '[INFO] Spicetify runs in the interactive user context because Spotify and Spicetify state are per-user.'

    $safeSection = ConvertTo-ReparoSafeFileName -Value 'Spicetify'
    $workerScriptPath = Join-Path $LogRoot ("{0}_{1}.command.ps1" -f $script:ReparoLogBaseName, $safeSection)
    $workerOutputPath = Join-Path $LogRoot ("{0}_{1}.out.log" -f $script:ReparoLogBaseName, $safeSection)
    $workerStatusPath = Join-Path $LogRoot ("{0}_{1}.exit" -f $script:ReparoLogBaseName, $safeSection)
    Remove-Item -LiteralPath $workerScriptPath, $workerOutputPath, $workerStatusPath -Force -ErrorAction SilentlyContinue
    New-ReparoSpicetifyWorkerScript -Path $workerScriptPath -OutputPath $workerOutputPath -StatusPath $workerStatusPath -PreviewOnly:$Preview -InstallRequested:$InstallSpicetify

    $lineCount = 0
    $timeoutSeconds = 600
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        if ((Test-Admin) -or (Test-ReparoSystemIdentity)) {
            $interactiveUser = Get-ReparoInteractiveUserName
            if ([string]::IsNullOrWhiteSpace($interactiveUser)) {
                Write-Skip 'Spicetify requested, but no logged-on Explorer user was found.'
                Write-ReparoLog '[SKIP] Spicetify requested, but no logged-on Explorer user was found'
                Add-ReparoSummaryRecord -Bucket Skipped -Software 'Spicetify' -Version '-' -Method 'spicetify' -Reason 'no logged-on Explorer user found'
                return
            }

            $shell = Resolve-ReparoShell
            $taskName = ('Reparo-Spicetify-{0}-{1}' -f $env:COMPUTERNAME, $PID)
            $taskArguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $workerScriptPath
            Write-ReparoLog ("[CMD] Register-ScheduledTask -TaskName {0} -UserId {1} -Execute {2} -Argument {3}" -f $taskName, $interactiveUser, $shell, $taskArguments)

            try {
                $action = New-ScheduledTaskAction -Execute $shell -Argument $taskArguments
                $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1)
                $principal = New-ScheduledTaskPrincipal -UserId $interactiveUser -LogonType Interactive -RunLevel Limited
                Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force -ErrorAction Stop | Out-Null
            }
            catch {
                throw "Unable to create Spicetify user-context scheduled task. $($_.Exception.Message)"
            }

            try {
                Write-ReparoLog ("[CMD] Start-ScheduledTask -TaskName {0}" -f $taskName)
                Start-ScheduledTask -TaskName $taskName -ErrorAction Stop
            }
            catch {
                throw "Unable to start Spicetify user-context scheduled task. $($_.Exception.Message)"
            }
        }
        else {
            $shell = Resolve-ReparoShell
            Write-ReparoLog ("[CMD] {0} -NoProfile -ExecutionPolicy Bypass -File {1}" -f $shell, $workerScriptPath)
            $process = Start-Process -FilePath $shell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $workerScriptPath) -WindowStyle Hidden -PassThru
            Write-ReparoDebug ("Started Spicetify worker PID {0}" -f $process.Id)
        }

        while (-not (Test-Path -LiteralPath $workerStatusPath)) {
            Start-Sleep -Milliseconds 500
            Sync-ReparoSpicetifyOutput -Path $workerOutputPath -LineCount ([ref]$lineCount)

            if ($stopwatch.Elapsed.TotalSeconds -ge $timeoutSeconds) {
                throw "Spicetify worker did not finish within ${timeoutSeconds}s."
            }
        }

        Sync-ReparoSpicetifyOutput -Path $workerOutputPath -LineCount ([ref]$lineCount)
        $exitText = (Get-Content -LiteralPath $workerStatusPath -ErrorAction SilentlyContinue | Select-Object -First 1)
        $exitCode = 1
        if (-not [int]::TryParse([string]$exitText, [ref]$exitCode)) {
            $exitCode = 1
        }

        if ($exitCode -eq 0) {
            if ($Preview) {
                Write-Skip 'Spicetify (preview only)'
                Add-ReparoSummaryRecord -Bucket Skipped -Software 'Spicetify' -Version '-' -Method 'spicetify' -Reason 'preview only'
            }
            else {
                Write-Done 'Spicetify complete'
                if ($InstallSpicetify) {
                    Add-ReparoSummaryNote 'Spicetify completed install/reinstall, update, and restore/backup/apply in the interactive user context.'
                }
                else {
                    Add-ReparoSummaryNote 'Spicetify completed update and restore/backup/apply in the interactive user context.'
                }
            }
        }
        elseif ($exitCode -eq 42) {
            Write-Skip 'spicetify not found in the interactive user context; skipping'
            Add-ReparoSummaryRecord -Bucket Skipped -Software 'Spicetify' -Version '-' -Method 'spicetify' -Reason 'spicetify not found in interactive user context'
        }
        else {
            Write-Fail "Spicetify failed with exit code $exitCode"
            Add-ReparoSummaryRecord -Bucket Failed -Software 'Spicetify' -Version '-' -Method 'spicetify' -Reason "exit code $exitCode"
        }
    }
    catch {
        Write-Fail "Spicetify failed: $($_.Exception.Message)"
        Write-ReparoLog ("[ERROR] Spicetify: {0}" -f $_.Exception.Message)
        Add-ReparoSummaryRecord -Bucket Failed -Software 'Spicetify' -Version '-' -Method 'spicetify' -Reason $_.Exception.Message
    }
    finally {
        if ($taskName) {
            try {
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
                Write-ReparoDebug ("Spicetify task cleanup: deleted {0}" -f $taskName)
            }
            catch {
                Write-ReparoDebug ("Spicetify task cleanup failed for {0}: {1}" -f $taskName, $_.Exception.Message)
            }
        }

        Remove-Item -LiteralPath $workerScriptPath, $workerStatusPath -Force -ErrorAction SilentlyContinue
    }
}

if ($ListVersionLocks) {
    Show-ReparoVersionLocks
    return
}

if ($AddVersionLock) {
    Add-ReparoVersionLocksToFile -Specs $AddVersionLock
    return
}

if ($Search) {
    Show-ReparoSearchResults -Terms $RemainingInclude
    return
}

if ($CheckApp -or $LockApp) {
    $appMode = if ($LockApp) { 'LOCK APP' } else { 'CHECK APP' }
    if ($Preview) { $appMode = "$appMode + PREVIEW" }

    Write-Host ("REPARO starting on {0} [{1}]" -f $env:COMPUTERNAME, $appMode) -ForegroundColor Magenta
    Write-ReparoLog ("=== reparo start: {0} on {1} (PID {2}) ===" -f (Get-Date), $env:COMPUTERNAME, $PID)
    Write-ReparoLog ("[FLAGS] Bound parameters: {0}" -f ((($PSBoundParameters.Keys | Sort-Object) -join ', ')))
    Write-ReparoParameterBlock

    $appSucceeded = $true
    if ($CheckApp) {
        $appSucceeded = (Invoke-ReparoCheckAppVersion -App $CheckApp -Manager $PackageManager) -and $appSucceeded
    }

    if ($LockApp) {
        $appSucceeded = (Invoke-ReparoLockAppVersion -App $LockApp -Version $LockVersion -Manager $PackageManager) -and $appSucceeded
    }

    Write-ReparoSummary
    Write-ReparoLog ("=== reparo end: {0} ===" -f (Get-Date))
    if ($script:ReparoSummary['Failed'].Count -gt 0 -or -not $appSucceeded) {
        $script:ReparoFinalStatus = 'FAILED'
    }
    elseif ($Preview) {
        $script:ReparoFinalStatus = 'PREVIEW'
    }
    else {
        $script:ReparoFinalStatus = 'COMPLETE'
    }

    Finalize-ReparoLogFile -Status $script:ReparoFinalStatus
    return
}

if ($MigrateChocoToWinget -and $FinalizeChocolateyRemoval) {
    $mode = 'MIGRATE CHOCO TO WINGET + FINALIZE CHOCOLATEY REMOVAL'
}
elseif ($Force) {
    $mode = 'FORCE'
}
elseif ($Update) {
    $mode = 'UPDATE'
}
elseif ($MigrateChocoToWinget) {
    $mode = 'MIGRATE CHOCO TO WINGET'
}
elseif ($FinalizeChocolateyRemoval) {
    $mode = 'FINALIZE CHOCOLATEY REMOVAL'
}
elseif ($InstallSpicetify) {
    $mode = 'INSTALL SPICETIFY'
}
elseif ($Include) {
    $mode = "INCLUDE: {0}" -f ($Include -join ',')
}
else {
    $mode = 'WINDOWSUPDATE'
}

if ($Preview) { $mode = "$mode + PREVIEW" }

Write-Host ("REPARO starting on {0} [{1}]" -f $env:COMPUTERNAME, $mode) -ForegroundColor Magenta
Write-ReparoLog ("=== reparo start: {0} on {1} (PID {2}) ===" -f (Get-Date), $env:COMPUTERNAME, $PID)
Write-ReparoLog ("[FLAGS] Bound parameters: {0}" -f ((($PSBoundParameters.Keys | Sort-Object) -join ', ')))
Write-ReparoParameterBlock
Write-ReparoDebug ("Timeouts: Winget={0}s WingetDiscovery={1}s WindowsUpdate={2}s IgnoreTimeouts={3}" -f $WingetTimeoutSeconds, $WingetDiscoveryTimeoutSeconds, $WindowsUpdateTimeoutSeconds, $IgnoreTimeouts)
Write-ReparoDebug ("Process identity: {0}" -f [Security.Principal.WindowsIdentity]::GetCurrent().Name)
Write-ReparoDebug ("PowerShell version: {0}" -f $PSVersionTable.PSVersion)

$configuredVersionLocks = @(Get-ReparoVersionLocks)
if ($configuredVersionLocks.Count -gt 0) {
    Write-ReparoLog ("[LOCK] Loaded {0} Reparo version lock(s)." -f $configuredVersionLocks.Count)
    $supportedLockMethods = @('winget', 'choco', 'scoop', 'npm', 'dotnet')
    foreach ($lock in $configuredVersionLocks) {
        Write-ReparoLog ("[LOCK] {0}:{1}={2} ({3})" -f $lock.Method, $lock.Id, $lock.Version, $lock.Source)
        if ($supportedLockMethods -notcontains $lock.Method) {
            Add-ReparoSummaryNote ("Version lock configured for {0}:{1}, but automatic skipping is not implemented for that method yet." -f $lock.Method, $lock.Id)
        }
    }
}
Write-ReparoEventLog -EventId 1000 -EntryType Information -Message @"
Reparo run started.

Computer: $env:COMPUTERNAME
PID: $PID
Version: $script:ReparoVersion
Mode: $mode
Preview: $Preview
User: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)
PowerShell: $($PSVersionTable.PSVersion)
Log: $script:ReparoLogPath
"@

if ($MigrateChocoToWinget) {
    Invoke-ReparoChocoToWingetMigration
}

if ($FinalizeChocolateyRemoval) {
    Invoke-ReparoFinalizeChocolateyRemoval
}

$runWingetSections = (Test-ReparoSectionSelected 'Winget') -or (Test-ReparoSectionSelected 'Winget(msstore)') -or $Winget -or $WingetDiscover
if ($runWingetSections) {
    $hasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
    Write-ReparoLog ("[CHECK] winget present: {0}" -f $hasWinget)

    if (-not $hasWinget) {
        $hasWinget = Ensure-ReparoWinget
    }

    if ($hasWinget) {
        if ($Winget -or $WingetDiscover) {
            Invoke-ReparoWingetDiscovery -PreviewOnly:$Preview
        }

        if (-not $WingetDiscover) {
            $wingetCommand = 'winget upgrade --all --include-unknown --accept-source-agreements --accept-package-agreements --disable-interactivity --silent --force'
            $lockedWingetIds = @(Get-ReparoLockedPackageIds -Method 'winget')
            foreach ($lockedWingetId in $lockedWingetIds) {
                $wingetCommand += (' --except {0}' -f $lockedWingetId)
            }
            if ($lockedWingetIds.Count -gt 0) {
                Add-ReparoSummaryNote ("Winget version locks active; excluding: {0}" -f ($lockedWingetIds -join ', '))
            }

            Invoke-ReparoCommandStep -Section 'Winget' -PresenceCmd 'winget' -Command $wingetCommand -TimeoutSeconds $WingetTimeoutSeconds

            $wingetStoreCommand = 'winget upgrade --source msstore --all --include-unknown --accept-source-agreements --accept-package-agreements --disable-interactivity --silent --force'
            foreach ($lockedWingetId in $lockedWingetIds) {
                $wingetStoreCommand += (' --except {0}' -f $lockedWingetId)
            }
            Invoke-ReparoCommandStep -Section 'Winget(msstore)' -PresenceCmd 'winget' -Command $wingetStoreCommand -TimeoutSeconds $WingetTimeoutSeconds
        }
        else {
            Write-Skip 'WingetDiscover requested; skipping live winget upgrade commands.'
            Write-ReparoLog '[SKIP] WingetDiscover requested; skipping live winget upgrade commands'
            Add-ReparoSummaryNote 'WingetDiscover completed discovery only; live winget upgrades were skipped.'
        }
    }
    else {
        Write-Skip 'winget not found or could not be repaired; skipping Winget sections'
        Write-ReparoLog '[SKIP] winget not found or could not be repaired; skipping Winget sections'
        Add-ReparoSummaryRecord -Bucket Skipped -Software 'Winget' -Version '-' -Method 'Winget' -Reason 'winget not found or could not be repaired'
        Add-ReparoSummaryRecord -Bucket Skipped -Software 'Winget(msstore)' -Version '-' -Method 'Winget(msstore)' -Reason 'winget not found or could not be repaired'
    }
}

$lockedPowerShell7Ids = @(Get-ReparoLockedPackageIds -Method 'winget') | Where-Object { $_ -ieq 'Microsoft.PowerShell' }
$powerShell7LockLiteral = '@({0})' -f ((@($lockedPowerShell7Ids | ForEach-Object { ConvertTo-ReparoPowerShellLiteral -Value $_ }) -join ', '))
if ($lockedPowerShell7Ids.Count -gt 0) {
    Add-ReparoSummaryNote 'PowerShell 7 winget version lock active; skipping dedicated PowerShell7 section.'
}

Invoke-ReparoCommandStep -Section 'PowerShell7' -PresenceCmd 'winget' -Command @"
`$ErrorActionPreference = 'Stop'
`$lockedPackages = $powerShell7LockLiteral
if (`$lockedPackages | Where-Object { `$_ -ieq 'Microsoft.PowerShell' }) {
    Write-Host 'Skipping locked PowerShell 7 package: Microsoft.PowerShell'
    exit 0
}

`$pwshCommand = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (`$pwshCommand) {
    try {
        `$currentVersion = & `$pwshCommand.Source -NoProfile -Command '`$PSVersionTable.PSVersion.ToString()'
    }
    catch {
        `$currentVersion = 'unknown'
    }

    Write-Host "PowerShell 7 current version: `$currentVersion"
}
else {
    Write-Host 'PowerShell 7 not found; installing Microsoft.PowerShell through winget.'
}

`$upgradeOutput = @(winget upgrade --id Microsoft.PowerShell --exact --accept-source-agreements --accept-package-agreements --disable-interactivity --silent --force 2>&1)
`$upgradeExit = `$LASTEXITCODE
`$upgradeOutput | ForEach-Object { Write-Host ([string]`$_) }
`$upgradeText = (`$upgradeOutput | ForEach-Object { [string]`$_ }) -join [Environment]::NewLine

if (`$upgradeExit -eq 0) {
    exit 0
}

`$nothingToUpgrade = `$upgradeText -match 'No installed package found matching input criteria|No applicable update found|No available upgrade found|No packages found'
if (`$pwshCommand -and `$nothingToUpgrade) {
    Write-Host 'PowerShell 7 is installed and winget reports no applicable update.'
    exit 0
}

if ((-not `$pwshCommand) -or (`$upgradeText -match 'No installed package found matching input criteria')) {
    `$installOutput = @(winget install --id Microsoft.PowerShell --exact --accept-source-agreements --accept-package-agreements --disable-interactivity --silent 2>&1)
    `$installExit = `$LASTEXITCODE
    `$installOutput | ForEach-Object { Write-Host ([string]`$_) }
    if (`$installExit -eq 0) {
        exit 0
    }

    throw "winget install Microsoft.PowerShell failed with exit code `$installExit"
}

throw "winget upgrade Microsoft.PowerShell failed with exit code `$upgradeExit"
"@ -TimeoutSeconds $WingetTimeoutSeconds
$lockedScoopIds = @(Get-ReparoLockedPackageIds -Method 'scoop')
if ($lockedScoopIds.Count -gt 0) {
    $scoopLockLiteral = '@({0})' -f ((@($lockedScoopIds | ForEach-Object { ConvertTo-ReparoPowerShellLiteral -Value $_ }) -join ', '))
    $scoopCommand = @"
scoop update
`$lockedPackages = $scoopLockLiteral
`$status = @(scoop status 2>`$null)
foreach (`$line in `$status) {
    if (`$line -match '^\s*(\S+)\s+(\S+)\s+(\S+)') {
        `$app = `$matches[1]
        if (`$lockedPackages -contains `$app) {
            Write-Host "Skipping locked Scoop package: `$app"
            continue
        }

        scoop update `$app
        if (`$LASTEXITCODE -ne 0) { throw "Failed updating Scoop package: `$app" }
    }
}
"@
    Add-ReparoSummaryNote ("Scoop version locks active; excluding: {0}" -f ($lockedScoopIds -join ', '))
}
else {
    $scoopCommand = 'scoop update; scoop update *'
}
Invoke-ReparoCommandStep -Section 'Scoop' -PresenceCmd 'scoop' -Command $scoopCommand

$lockedChocoIds = @(Get-ReparoLockedPackageIds -Method 'choco')
if ($lockedChocoIds.Count -gt 0) {
    $chocoLockLiteral = '@({0})' -f ((@($lockedChocoIds | ForEach-Object { ConvertTo-ReparoPowerShellLiteral -Value $_ }) -join ', '))
    $chocoCommand = @"
`$lockedPackages = $chocoLockLiteral
`$outdated = @(choco outdated --limit-output --no-color 2>`$null)
foreach (`$line in `$outdated) {
    if (`$line -notmatch '\|') { continue }
    `$packageId = (`$line -split '\|')[0].Trim()
    if ([string]::IsNullOrWhiteSpace(`$packageId)) { continue }
    if (`$lockedPackages -contains `$packageId) {
        Write-Host "Skipping locked Chocolatey package: `$packageId"
        continue
    }

    choco upgrade `$packageId -y --no-progress
    if (`$LASTEXITCODE -ne 0) { throw "Failed upgrading Chocolatey package: `$packageId" }
}
"@
    Add-ReparoSummaryNote ("Chocolatey version locks active; excluding: {0}" -f ($lockedChocoIds -join ', '))
}
else {
    $chocoCommand = 'choco upgrade all -y --no-progress'
}
Invoke-ReparoCommandStep -Section 'Choco' -PresenceCmd 'choco' -Command $chocoCommand

if (Test-ReparoSectionSelected 'Pip') {
    $ranPip = $false
    $seenPipSources = @{}
    foreach ($pipName in @('pip', 'pip3')) {
        if (Test-Cmd $pipName) {
            $pipCommand = Get-Command $pipName -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            $pipSourceKey = if ($pipCommand -and $pipCommand.Source) { [string]$pipCommand.Source } else { $pipName }
            if ($seenPipSources.ContainsKey($pipSourceKey)) {
                continue
            }
            $seenPipSources[$pipSourceKey] = $true

            Invoke-ReparoCommandStep -Section 'Pip' -PresenceCmd '' -Command @"
`$ErrorActionPreference = 'Continue'
`$pipName = '$pipName'
`$pipCommand = Get-Command `$pipName -CommandType Application -ErrorAction Stop | Select-Object -First 1
`$pythonCommand = `$null
if (`$pipCommand.Source) {
    `$pipScripts = Split-Path -Parent `$pipCommand.Source
    `$pipRoot = Split-Path -Parent `$pipScripts
    `$candidate = Join-Path `$pipRoot 'python.exe'
    if (Test-Path -LiteralPath `$candidate) {
        `$pythonCommand = `$candidate
    }
}
if (-not `$pythonCommand) {
    `$pythonCommandInfo = Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (`$pythonCommandInfo) {
        `$pythonCommand = `$pythonCommandInfo.Source
    }
}
if (`$pythonCommand) {
    & `$pythonCommand -m pip install --upgrade pip
}
else {
    & `$pipName install --upgrade pip
}
if (`$LASTEXITCODE -ne 0) {
    throw 'Failed upgrading pip package: pip'
}
`$outdated = & `$pipName list --outdated --format=json | Out-String
if (-not [string]::IsNullOrWhiteSpace(`$outdated)) {
    `$packages = `$outdated | ConvertFrom-Json
    foreach (`$pkg in `$packages) {
        if (`$pkg.name) {
            if ([string]`$pkg.name -ieq 'pip') {
                continue
            }
            if (`$pythonCommand) {
                & `$pythonCommand -m pip install --upgrade `$pkg.name
            }
            else {
                & `$pipName install --upgrade `$pkg.name
            }
            if (`$LASTEXITCODE -ne 0) {
                throw "Failed upgrading pip package: `$(`$pkg.name)"
            }
        }
    }
}
"@
            $ranPip = $true
            break
        }
    }

    if (-not $ranPip) {
        Write-Skip 'pip not found; skipping'
        Write-ReparoLog '[SKIP] pip not found; skipping'
        Add-ReparoSummaryRecord -Bucket Skipped -Software 'Pip' -Version '-' -Method 'pip' -Reason 'pip not found'
    }
}

Invoke-ReparoCommandStep -Section 'Pipx' -PresenceCmd 'pipx' -Command 'pipx upgrade-all'

$lockedNpmIds = @(Get-ReparoLockedPackageIds -Method 'npm')
if ($lockedNpmIds.Count -gt 0) {
    $npmLockLiteral = '@({0})' -f ((@($lockedNpmIds | ForEach-Object { ConvertTo-ReparoPowerShellLiteral -Value $_ }) -join ', '))
    $npmCommand = @"
`$lockedPackages = $npmLockLiteral
if (-not (`$lockedPackages -contains 'npm')) {
    npm install -g npm
    if (`$LASTEXITCODE -ne 0) { throw 'Failed updating npm itself.' }
}
`$jsonText = npm outdated -g --json 2>`$null | Out-String
if (-not [string]::IsNullOrWhiteSpace(`$jsonText)) {
    try { `$outdated = `$jsonText | ConvertFrom-Json } catch { `$outdated = `$null }
    if (`$outdated) {
        foreach (`$property in `$outdated.PSObject.Properties) {
            if (`$lockedPackages -contains `$property.Name) {
                Write-Host "Skipping locked npm package: `$(`$property.Name)"
                continue
            }

            npm update -g `$property.Name
            if (`$LASTEXITCODE -ne 0) { throw "Failed updating npm package: `$(`$property.Name)" }
        }
    }
}
"@
    Add-ReparoSummaryNote ("npm version locks active; excluding: {0}" -f ($lockedNpmIds -join ', '))
}
else {
    $npmCommand = 'npm install -g npm; npm update -g'
}
Invoke-ReparoCommandStep -Section 'Npm' -PresenceCmd 'npm' -Command $npmCommand
Invoke-ReparoCommandStep -Section 'Pnpm' -PresenceCmd 'pnpm' -Command 'pnpm add -g pnpm@latest; pnpm update -g'
Invoke-ReparoCommandStep -Section 'Yarn' -PresenceCmd 'yarn' -Command 'yarn global upgrade'
$lockedDotNetIds = @(Get-ReparoLockedPackageIds -Method 'dotnet')
$dotNetLockLiteral = '@({0})' -f ((@($lockedDotNetIds | ForEach-Object { ConvertTo-ReparoPowerShellLiteral -Value $_ }) -join ', '))
if ($lockedDotNetIds.Count -gt 0) {
    Add-ReparoSummaryNote (".NET tool version locks active; excluding: {0}" -f ($lockedDotNetIds -join ', '))
}
Invoke-ReparoCommandStep -Section 'DotNet' -PresenceCmd 'dotnet' -Command @"
`$ErrorActionPreference = 'Stop'
`$lockedPackages = $dotNetLockLiteral
`$tools = dotnet tool list --global 2>`$null
if (`$LASTEXITCODE -ne 0) {
    throw 'Unable to list global dotnet tools.'
}

`$toolIds = @()
foreach (`$line in `$tools) {
    if (`$line -match '^\s*(\S+)\s+(\S+)\s+(\S+)\s*$' -and `$line -notmatch 'Package Id' -and `$line -notmatch '^-+$') {
        `$toolIds += `$matches[1]
    }
}

`$toolIds = `$toolIds | Select-Object -Unique
if (-not `$toolIds -or `$toolIds.Count -eq 0) {
    Write-Host 'No global dotnet tools found.'
}
else {
    foreach (`$tool in `$toolIds) {
        if (`$lockedPackages -contains `$tool) {
            Write-Host "Skipping locked .NET tool: `$tool"
            continue
        }

        dotnet tool update --global `$tool
        if (`$LASTEXITCODE -ne 0) {
            throw "Failed updating dotnet tool: `$tool"
        }
    }
}
"@
Invoke-ReparoCommandStep -Section 'Rust' -PresenceCmd 'rustup' -Command 'rustup update'
Invoke-ReparoCommandStep -Section 'CargoBins' -PresenceCmd 'cargo-install-update' -Command 'cargo-install-update -a'
Invoke-ReparoCommandStep -Section 'Conda' -PresenceCmd 'conda' -Command 'conda update -n base conda -y; conda update --all -y'
Invoke-ReparoCommandStep -Section 'Gem' -PresenceCmd 'gem' -Command 'gem update --system; gem update'
Invoke-ReparoCommandStep -Section 'Composer' -PresenceCmd 'composer' -Command 'composer self-update; composer global update'
Invoke-ReparoSpicetify
Invoke-ReparoCommandStep -Section 'Wsl' -PresenceCmd 'wsl' -Command 'wsl --update; wsl --shutdown'

if ($WslApt -and (Test-ReparoSectionSelected 'WslApt')) {
    if (Test-Cmd 'wsl') {
        try {
            $previousErrorActionPreference = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            $rawDistros = @(& wsl -l -q 2>&1)
            $wslListExit = $LASTEXITCODE
            foreach ($line in $rawDistros) {
                $text = (([string]$line) -replace "`0", '').Trim()
                if (-not [string]::IsNullOrWhiteSpace($text)) {
                    Write-ReparoLog ("[CHECK] wsl -l -q: {0}" -f $text)
                }
            }

            if ($wslListExit -ne 0) {
                Write-Skip "WSL distro enumeration failed with exit code $wslListExit; skipping WSL apt"
                Write-ReparoLog "[SKIP] WSL distro enumeration failed with exit code $wslListExit; skipping WSL apt"
                Add-ReparoSummaryRecord -Bucket Skipped -Software 'WslApt' -Version '-' -Method 'wsl/apt' -Reason "wsl -l -q exit code $wslListExit"
                $rawDistros = @()
            }

            $distros = @(
                foreach ($raw in $rawDistros) {
                    $name = ([string]$raw) -replace "`0", ''
                    $name = $name.Trim()
                    $looksLikeWslHelp = (
                        $name -match '(?i)^(Copyright|Usage:|Arguments:|Options:|Examples:)' -or
                        $name -match '(?i)(Windows Subsystem for Linux|wsl\.exe|--install|--help|--list|--status)' -or
                        $name -match '\s{2,}' -or
                        $name -match '^\s*-\s*$'
                    )

                    if (-not [string]::IsNullOrWhiteSpace($name) -and -not $looksLikeWslHelp) {
                        $name
                    }
                }
            ) | Select-Object -Unique

            if ($distros.Count -eq 0) {
                Write-Skip 'No usable WSL distros found; skipping WSL apt'
                Write-ReparoLog '[SKIP] No usable WSL distros found; skipping WSL apt'
                Add-ReparoSummaryRecord -Bucket Skipped -Software 'WslApt' -Version '-' -Method 'wsl/apt' -Reason 'no usable WSL distros found'
            }

            foreach ($distro in $distros) {
                $testOutput = @(& wsl -d "$distro" -- bash -lc 'command -v apt >/dev/null 2>&1' 2>&1)
                $testExit = $LASTEXITCODE

                foreach ($line in $testOutput) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
                        Write-ReparoLog ([string]$line)
                    }
                }

                if ($testExit -eq 0) {
                    $sudoCheckOutput = @(& wsl -d "$distro" -- bash -lc 'if [ "$(id -u)" -eq 0 ]; then exit 0; fi; command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1' 2>&1)
                    $sudoCheckExit = $LASTEXITCODE

                    foreach ($line in $sudoCheckOutput) {
                        if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
                            Write-ReparoLog ([string]$line)
                        }
                    }

                    if ($sudoCheckExit -ne 0) {
                        Write-Skip "sudo in $distro requires a password or is unavailable; skipping WSL apt"
                        Write-ReparoLog "[SKIP] sudo in $distro requires a password or is unavailable; skipping WSL apt"
                        Add-ReparoSummaryRecord -Bucket Skipped -Software ("WslApt:{0}" -f $distro) -Version '-' -Method 'wsl/apt' -Reason 'sudo requires password or is unavailable'
                        continue
                    }

                    $aptCommand = 'if [ "$(id -u)" -eq 0 ]; then DEBIAN_FRONTEND=noninteractive apt update && DEBIAN_FRONTEND=noninteractive apt -y upgrade && DEBIAN_FRONTEND=noninteractive apt -y autoremove; else sudo -n env DEBIAN_FRONTEND=noninteractive apt update && sudo -n env DEBIAN_FRONTEND=noninteractive apt -y upgrade && sudo -n env DEBIAN_FRONTEND=noninteractive apt -y autoremove; fi'
                    $aptCommand = $aptCommand -replace '"', '\"'
                    Invoke-ReparoCommandStep -Section ("WslApt:{0}" -f $distro) -PresenceCmd '' -Command ("wsl -d ""{0}"" -- bash -lc ""{1}""" -f $distro, $aptCommand) -TimeoutSeconds $WslAptTimeoutSeconds
                }
                else {
                    Write-Skip "apt not present in $distro; skipping"
                    Write-ReparoLog "[SKIP] apt not present in $distro; skipping"
                    Add-ReparoSummaryRecord -Bucket Skipped -Software ("WslApt:{0}" -f $distro) -Version '-' -Method 'wsl/apt' -Reason 'apt not present'
                }
            }
        }
        catch {
            Write-Fail "WSL distro enumeration failed: $($_.Exception.Message)"
            Write-ReparoLog "[ERROR] WSL distro enumeration failed: $($_.Exception.Message)"
            Add-ReparoSummaryRecord -Bucket Failed -Software 'WslApt' -Version '-' -Method 'wsl/apt' -Reason $_.Exception.Message
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
    }
    else {
        Write-Skip 'wsl not found; skipping WSL apt'
        Write-ReparoLog '[SKIP] wsl not found; skipping WSL apt'
        Add-ReparoSummaryRecord -Bucket Skipped -Software 'WslApt' -Version '-' -Method 'wsl/apt' -Reason 'wsl not found'
    }
}

if (Test-ReparoSectionSelected 'WindowsUpdate') {
    if (-not (Test-Admin)) {
        Write-Skip 'WindowsUpdate requested but shell is not elevated; skipping.'
        Write-ReparoLog '[SKIP] WindowsUpdate requested but shell is not elevated'
        Add-ReparoSummaryRecord -Bucket Skipped -Software 'WindowsUpdate' -Version '-' -Method 'PSWindowsUpdate' -Reason 'shell is not elevated'
    }
    else {
        $hasWindowsUpdate = [bool](Get-Command Get-WindowsUpdate -ErrorAction SilentlyContinue)
        Write-ReparoLog ("[CHECK] Get-WindowsUpdate present: {0}" -f $hasWindowsUpdate)

        if (-not $hasWindowsUpdate) {
            Write-ReparoLog '[ACTION] Attempting PSWindowsUpdate bootstrap from PSGallery.'
        }

        if ($hasWindowsUpdate -or (Ensure-ReparoPSWindowsUpdate)) {
            if ($AllowReboot) {
                Write-ReparoLog '[INFO] WindowsUpdate reboot handling: AllowReboot requested; passing -AutoReboot.'
                $windowsUpdateCommand = 'Import-Module PSWindowsUpdate; Get-WindowsUpdate -AcceptAll -Install -AutoReboot'
            }
            else {
                Write-ReparoLog '[INFO] WindowsUpdate reboot handling: defaulting to -IgnoreReboot.'
                $windowsUpdateCommand = 'Import-Module PSWindowsUpdate; Get-WindowsUpdate -AcceptAll -Install -IgnoreReboot'
            }

            Invoke-ReparoCommandStep -Section 'WindowsUpdate' -PresenceCmd '' -Command $windowsUpdateCommand -TimeoutSeconds $WindowsUpdateTimeoutSeconds
            if (Test-ReparoPendingReboot) {
                Write-ReparoLog '[WARN] Windows indicates a reboot is pending after WindowsUpdate.'
                $script:ReparoPendingRebootDetected = $true
            }
        }
        else {
            Write-Skip 'PSWindowsUpdate module not found and bootstrap failed; skipping Windows Update.'
            Write-ReparoLog '[SKIP] PSWindowsUpdate module not found and bootstrap failed'
            Add-ReparoSummaryRecord -Bucket Skipped -Software 'WindowsUpdate' -Version '-' -Method 'PSWindowsUpdate' -Reason 'module not found and bootstrap failed'
        }
    }
}

if (-not $script:ReparoPendingRebootDetected) {
    $script:ReparoPendingRebootDetected = [bool](Test-ReparoPendingReboot)
}

if ($script:ReparoPendingRebootDetected) {
    Write-Warning 'Windows indicates a reboot is pending.'
    Write-ReparoLog '[WARN] Windows indicates a reboot is pending.'
    Add-ReparoSummaryNote 'Windows indicates a reboot is pending.'
    Write-ReparoEventLog -EventId 1300 -EntryType Warning -Message @"
Reparo detected a pending reboot.

Computer: $env:COMPUTERNAME
PID: $PID
AllowReboot: $AllowReboot
Mode: $mode
Log: $script:ReparoLogPath
"@
}

Write-ReparoSummary
Write-ReparoLog ("=== reparo end: {0} ===" -f (Get-Date))
if ($script:ReparoSummary['Failed'].Count -gt 0) {
    $script:ReparoFinalStatus = 'FAILED'
}
elseif ($Preview) {
    $script:ReparoFinalStatus = 'PREVIEW'
}
else {
    $script:ReparoFinalStatus = 'COMPLETE'
}

if ($Preview) {
    Write-Info 'Preview only. Run without -Preview to execute.'
}

Finalize-ReparoLogFile -Status $script:ReparoFinalStatus

$eventEntryType = if ($script:ReparoFinalStatus -eq 'FAILED') { 'Error' } elseif ($script:ReparoFinalStatus -eq 'PREVIEW') { 'Warning' } else { 'Information' }
$eventId = if ($script:ReparoFinalStatus -eq 'FAILED') { 1002 } elseif ($script:ReparoFinalStatus -eq 'PREVIEW') { 1003 } else { 1001 }
$failedSummary = if ($script:ReparoSummary['Failed'].Count -gt 0) {
    (($script:ReparoSummary['Failed'] | ForEach-Object { "{0} ({1})" -f $_.Software, $_.Reason }) -join '; ')
}
else {
    'None'
}

Write-ReparoEventLog -EventId $eventId -EntryType $eventEntryType -Message @"
Reparo run finished.

Computer: $env:COMPUTERNAME
PID: $PID
Version: $script:ReparoVersion
Mode: $mode
Status: $script:ReparoFinalStatus
Updated: $($script:ReparoSummary['Updated'].Count)
Skipped: $($script:ReparoSummary['Skipped'].Count)
Failed: $($script:ReparoSummary['Failed'].Count)
FailedSummary: $failedSummary
Log: $script:ReparoLogPath
"@

if ($Tail) {
    Write-Host ''
    Write-Host 'Log tail' -ForegroundColor Magenta

    if (Test-Path -LiteralPath $script:ReparoLogPath) {
        try {
            Get-Content -LiteralPath $script:ReparoLogPath -Tail $TailLines
        }
        catch {
            Write-Warning "Unable to tail log file '$script:ReparoLogPath': $($_.Exception.Message)"
        }
    }
    else {
        Write-Warning "Log file not found: $script:ReparoLogPath"
    }
}
