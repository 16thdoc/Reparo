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
    [switch]$Help,
    [switch]$Version,
    [Alias('Install')]
    [switch]$New,
    [switch]$Preview,
    [switch]$WindowsUpdate,
    [Alias('WSL')]
    [switch]$WslApt,
    [switch]$Update,
    [switch]$Force,
    [switch]$Kill,
    [string]$LogRoot = "$env:ProgramData\Reparo\Logs",
    [string]$InstallRoot = "$env:ProgramData\Reparo",
    [string]$SourceUrl = 'https://raw.githubusercontent.com/16thdoc/Reparo/main/Reparo.ps1',
    [switch]$NoBackup,
    [Alias('Log')]
    [switch]$Tail,
    [string[]]$Include,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingInclude
)

$ErrorActionPreference = 'Stop'
$script:ReparoVersion = '0.2.3'

if ($RemainingInclude -and $RemainingInclude.Count -gt 0) {
    $Include = @($Include) + @($RemainingInclude)
}

function Show-ReparoHelp {
    $helpText = @"
Reparo $script:ReparoVersion

Usage:
  reparo
  reparo -Version
  reparo -Kill
  reparo -Update
  reparo -Install
  reparo -Preview -Update
  reparo -Include Winget Choco

Modes:
  Default              Run Windows Update only.
  -Update              Run the managed-client pass: Winget, Winget(msstore), Choco, WindowsUpdate.
                        Updated package rows show current version -> target version when available.
  -Install, -New       Install/update C:\ProgramData\Reparo\Reparo.ps1 from GitHub.
  -Force               Run all sections, including developer toolchains and WSL apt handling.
  -Kill                Stop running Reparo PowerShell processes.
  -Preview             Show what would run without executing update commands.
  -Tail, -Log          Print the current run's log file at the end of execution.
  -Include <sections>  Run only selected sections, for example: -Include Winget Choco.
  -Version             Show the Reparo version.
  -Help                Show this help.

Windows Update:
  Reparo will try to install PSWindowsUpdate from PSGallery if the module is missing
  and the session has the rights and network access to do so.

Install/update:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -Install

After install, new PowerShell sessions can usually run:
  reparo -Update
  reparo -Install

Common sections:
  Winget, Winget(msstore), Choco, WindowsUpdate, Scoop, Pip, Pipx, Npm,
  Pnpm, Yarn, DotNet, Rust, CargoBins, Conda, Gem, Composer, Wsl, WslApt.

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
    return
}

$updateSections = @(
    'WindowsUpdate'
    'Winget'
    'Winget(msstore)'
    'Choco'
)

if ($Force) {
    $Preview = $false
    $WindowsUpdate = $true
    $WslApt = $true
    $Include = $null
}
elseif ($Update) {
    $WindowsUpdate = $true
    $Include = $updateSections
}

if (-not (Test-Path -LiteralPath $LogRoot)) {
    New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
}

$logFile = Join-Path $LogRoot ("reparo_{0}_{1}_{2}.log" -f $env:COMPUTERNAME, $PID, (Get-Date -Format 'yyyy-MM-dd_HHmmss'))

function Write-Info($Message) { Write-Host "INFO  $Message" -ForegroundColor Cyan }
function Write-Step($Message) { Write-Host "STEP  $Message" -ForegroundColor Yellow }
function Write-Skip($Message) { Write-Host "SKIP  $Message" -ForegroundColor DarkGray }
function Write-Done($Message) { Write-Host "DONE  $Message" -ForegroundColor Green }
function Write-Fail($Message) { Write-Host "FAIL  $Message" -ForegroundColor Red }

function Invoke-ReparoKill {
    [CmdletBinding()]
    param()

    $ownPid = $PID
    $excludedPids = New-Object System.Collections.Generic.HashSet[int]
    $null = $excludedPids.Add([int]$ownPid)

    $ancestor = Get-CimInstance Win32_Process -Filter "ProcessId = $ownPid" -ErrorAction SilentlyContinue
    while ($ancestor -and $ancestor.ParentProcessId) {
        if (-not $excludedPids.Add([int]$ancestor.ParentProcessId)) {
            break
        }

        $ancestor = Get-CimInstance Win32_Process -Filter "ProcessId = $($ancestor.ParentProcessId)" -ErrorAction SilentlyContinue
    }

    $processes = @(
        Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction SilentlyContinue |
            Where-Object {
                -not $excludedPids.Contains([int]$_.ProcessId) -and
                $_.CommandLine -and
                $_.CommandLine -match '(?i)(^|[\\/\s''"])Reparo\.ps1([\\/\s''"]|$)' -and
                $_.CommandLine -notmatch '(?i)(^|\s)-Kill(\s|$)'
            }
    )

    if (-not $processes -or $processes.Count -eq 0) {
        Write-Info 'No running Reparo PowerShell processes found.'
        return
    }

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
                Stop-Process -Id ([int]$process.ProcessId) -Force -ErrorAction Stop
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
            PID     = [int]$process.ProcessId
            Name    = $process.Name
            Status  = $status
            Error   = $errorText
        }
    }

    $results | Format-Table -AutoSize
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
                return
            }
        }

        if ($WhatIfOnly) {
            Write-Info "Would replace: $scriptPath"
            Write-Info "New SHA256: $newHash"
            Install-ReparoCommandShim -TargetRoot $TargetRoot -WhatIfOnly
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
                $logFile,
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

            Write-Warning "Failed to write to log file '$logFile': $($_.Exception.Message)"
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

function Test-ReparoSectionSelected($Section) {
    if ($Force) { return $true }
    if ($Include -and $Include.Count -gt 0) {
        return ($Include -contains $Section)
    }

    return ($Section -eq 'WindowsUpdate')
}

function Ensure-ReparoPSWindowsUpdate {
    if (Get-Command Get-WindowsUpdate -ErrorAction SilentlyContinue) {
        return $true
    }

    try {
        Write-ReparoLog '[INFO] PSWindowsUpdate not found; attempting install from PSGallery.'

        if (Get-Command Set-PSRepository -ErrorAction SilentlyContinue) {
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue | Out-Null
        }

        if (-not (Get-Module -ListAvailable -Name 'NuGet')) {
            try {
                Install-PackageProvider -Name NuGet -Force -Scope AllUsers -ErrorAction Stop | Out-Null
            }
            catch {
                Write-ReparoLog ("[WARN] NuGet provider install failed: {0}" -f $_.Exception.Message)
            }
        }

        Install-Module -Name 'PSWindowsUpdate' -Force -AllowClobber -Scope AllUsers -Repository 'PSGallery' -ErrorAction Stop | Out-Null
        Import-Module PSWindowsUpdate -Force -ErrorAction Stop

        if (Get-Command Get-WindowsUpdate -ErrorAction SilentlyContinue) {
            Write-ReparoLog '[DONE] PSWindowsUpdate installed successfully.'
            return $true
        }

        throw 'PSWindowsUpdate installed, but Get-WindowsUpdate is still unavailable.'
    }
    catch {
        Write-ReparoLog ("[WARN] PSWindowsUpdate install failed: {0}" -f $_.Exception.Message)
        return $false
    }
}

function Resolve-ReparoShell {
    foreach ($shellName in @('pwsh', 'powershell')) {
        $command = Resolve-ReparoCommand -Name $shellName
        if (-not $command) { continue }

        try {
            $output = @(& $command.Source -NoProfile -ExecutionPolicy Bypass -Command '$PSVersionTable.PSVersion.ToString()' 2>&1)
            $exitCode = $LASTEXITCODE
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
    Write-Host ("Log: {0}" -f $logFile) -ForegroundColor Cyan
    Write-ReparoLog ("[SUMMARY] Log: {0}" -f $logFile)
}

function Invoke-ReparoTimedCommand {
    param(
        [Parameter(Mandatory)][string]$ShellPath,
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string]$Section,
        [int]$TimeoutSeconds = 1800
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $escapedCommand = $Command.Replace('"', '""')
    $arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"${escapedCommand}`""

    Write-ReparoLog ("[CMD-START] {0} | timeout={1}s" -f $Section, $TimeoutSeconds)

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $ShellPath
    $psi.Arguments = $arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    $null = $process.Start()

    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill() } catch { }
        $stopwatch.Stop()
        Write-ReparoLog ("[CMD-TIMEOUT] {0} timed out after {1}s" -f $Section, $TimeoutSeconds)
        return [pscustomobject]@{
            TimedOut = $true
            ExitCode = 124
            Output   = @("[TIMEOUT] $Section exceeded ${TimeoutSeconds}s")
            Elapsed  = $stopwatch.Elapsed
        }
    }

    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $stopwatch.Stop()

    $output = New-Object System.Collections.Generic.List[string]
    foreach ($line in @($stdout -split "`r?`n")) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            [void]$output.Add($line)
        }
    }
    foreach ($line in @($stderr -split "`r?`n")) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            [void]$output.Add($line)
        }
    }

    Write-ReparoLog ("[CMD-END] {0} exit={1} elapsed={2}" -f $Section, $process.ExitCode, $stopwatch.Elapsed)

    [pscustomobject]@{
        TimedOut = $false
        ExitCode = $process.ExitCode
        Output   = $output.ToArray()
        Elapsed  = $stopwatch.Elapsed
    }
}

function Invoke-ReparoCommandStep {
    param(
        [string]$Section,
        [string]$PresenceCmd,
        [string]$Command,
        [int]$TimeoutSeconds = 1800
    )

    if (-not (Test-ReparoSectionSelected $Section)) { return }

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
        $result = Invoke-ReparoTimedCommand -ShellPath $shell -Command $Command -Section $Section -TimeoutSeconds $TimeoutSeconds
        $output = @($result.Output)
        $exitCode = $result.ExitCode

        foreach ($item in $output) {
            $line = [string]$item
            Write-Host $line
            Write-ReparoLog $line
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

if ($Force) {
    $mode = 'FORCE'
}
elseif ($Update) {
    $mode = 'UPDATE'
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

Invoke-ReparoCommandStep -Section 'Winget' -PresenceCmd 'winget' -Command 'winget upgrade --all --include-unknown --accept-source-agreements --accept-package-agreements' -TimeoutSeconds 90
Invoke-ReparoCommandStep -Section 'Winget(msstore)' -PresenceCmd 'winget' -Command 'winget upgrade --source msstore --all --include-unknown --accept-source-agreements --accept-package-agreements' -TimeoutSeconds 90
Invoke-ReparoCommandStep -Section 'Scoop' -PresenceCmd 'scoop' -Command 'scoop update; scoop update *'
Invoke-ReparoCommandStep -Section 'Choco' -PresenceCmd 'choco' -Command 'choco upgrade all -y --no-progress'

if (Test-ReparoSectionSelected 'Pip') {
    $ranPip = $false
    foreach ($pipName in @('pip', 'pip3')) {
        if (Test-Cmd $pipName) {
            Invoke-ReparoCommandStep -Section 'Pip' -PresenceCmd '' -Command @"
`$ErrorActionPreference = 'Stop'
& $pipName install --upgrade pip
`$outdated = & $pipName list --outdated --format=json | Out-String
if (-not [string]::IsNullOrWhiteSpace(`$outdated)) {
    `$packages = `$outdated | ConvertFrom-Json
    foreach (`$pkg in `$packages) {
        if (`$pkg.name) {
            & $pipName install --upgrade `$pkg.name
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
Invoke-ReparoCommandStep -Section 'Npm' -PresenceCmd 'npm' -Command 'npm install -g npm; npm update -g'
Invoke-ReparoCommandStep -Section 'Pnpm' -PresenceCmd 'pnpm' -Command 'pnpm add -g pnpm@latest; pnpm update -g'
Invoke-ReparoCommandStep -Section 'Yarn' -PresenceCmd 'yarn' -Command 'yarn global upgrade'
Invoke-ReparoCommandStep -Section 'DotNet' -PresenceCmd 'dotnet' -Command @"
`$ErrorActionPreference = 'Stop'
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
Invoke-ReparoCommandStep -Section 'Wsl' -PresenceCmd 'wsl' -Command 'wsl --update; wsl --shutdown'

if ($WslApt -and (Test-ReparoSectionSelected 'WslApt')) {
    if (Test-Cmd 'wsl') {
        try {
            $rawDistros = & wsl -l -q 2>$null
            $distros = @(
                foreach ($raw in $rawDistros) {
                    $name = ([string]$raw) -replace "`0", ''
                    $name = $name.Trim()
                    if (-not [string]::IsNullOrWhiteSpace($name)) {
                        $name
                    }
                }
            ) | Select-Object -Unique

            foreach ($distro in $distros) {
                $testOutput = @(& wsl -d "$distro" -- bash -lc 'command -v apt >/dev/null 2>&1' 2>&1)
                $testExit = $LASTEXITCODE

                foreach ($line in $testOutput) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
                        Write-ReparoLog ([string]$line)
                    }
                }

                if ($testExit -eq 0) {
                    Invoke-ReparoCommandStep -Section ("WslApt:{0}" -f $distro) -PresenceCmd '' -Command ("wsl -d ""{0}"" -- bash -lc ""sudo apt update && sudo apt -y upgrade && sudo apt -y autoremove""" -f $distro)
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
        Invoke-ReparoCommandStep -Section 'WindowsUpdate' -PresenceCmd '' -Command 'Import-Module PSWindowsUpdate; Get-WindowsUpdate -AcceptAll -Install -IgnoreReboot' -TimeoutSeconds 120
        }
        else {
            Write-Skip 'PSWindowsUpdate module not found and bootstrap failed; skipping Windows Update.'
            Write-ReparoLog '[SKIP] PSWindowsUpdate module not found and bootstrap failed'
            Add-ReparoSummaryRecord -Bucket Skipped -Software 'WindowsUpdate' -Version '-' -Method 'PSWindowsUpdate' -Reason 'module not found and bootstrap failed'
        }
    }
}

Write-ReparoSummary
Write-ReparoLog ("=== reparo end: {0} ===" -f (Get-Date))

if ($Preview) {
    Write-Info 'Preview only. Run without -Preview to execute.'
}

if ($Tail) {
    Write-Host ''
    Write-Host 'Log tail' -ForegroundColor Magenta

    if (Test-Path -LiteralPath $logFile) {
        try {
            Get-Content -LiteralPath $logFile -Tail 200
        }
        catch {
            Write-Warning "Unable to tail log file '$logFile': $($_.Exception.Message)"
        }
    }
    else {
        Write-Warning "Log file not found: $logFile"
    }
}
