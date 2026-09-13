Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot 'Reparo.ps1'
$source = Get-Content -LiteralPath $sourcePath -Raw

$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    throw "Reparo.ps1 has PowerShell parse errors: $($parseErrors.Message -join '; ')"
}

$wingetQueue = [regex]::Match($source, '(?s)function New-ReparoWingetUpgradeQueueCommand \{.*?(?=function New-ReparoVersionLockRecord)')
if (-not $wingetQueue.Success) { throw 'Could not locate the WinGet upgrade queue builder.' }
foreach ($required in @(
    '[Parameter(Mandatory)][AllowEmptyCollection()][object[]]$PendingUpdates',
    'Winget package requires manual uninstall/reinstall:',
    'REPARO-WINGET-SKIP manual',
    'Winget package requires a non-elevated session:',
    'package installed for user scope cannot be uninstalled when running with administrator privileges',
    'Winget packages pending a non-elevated session:',
    'REPARO-WINGET-SKIP not-applicable',
    'REPARO-WINGET-SKIP blocked',
    'Winget packages blocked by files in use or access denied:',
    'REPARO-WINGET-UPDATED',
    'Winget packages not applicable to this system or its current requirements:',
    '`$failedPackages.Count -gt 0',
    '[void]$commands.Add(''exit 0'')'
)) {
    if (-not $wingetQueue.Value.Contains($required)) {
        throw "WinGet manual-migration exit handling is absent: $required"
    }
}

$blockedClassifier = [regex]::Match($source, '(?s)function Get-ReparoWingetBlockedReason \{.*?(?=function Invoke-ReparoWingetRepair)')
if (-not $blockedClassifier.Success) { throw 'Could not locate the blocked WinGet package classifier.' }
Invoke-Expression $blockedClassifier.Value
$blockedSample = @(
    'remove: Access is denied.: "C:\Users\Example\AppData\Local\Microsoft\WinGet\Packages\Vendor.Package\agent.exe"',
    'Uninstall failed with exit code: 0x8a150003 : Executing command failed'
)
if (-not (Get-ReparoWingetBlockedReason -Output $blockedSample)) {
    throw 'The blocked WinGet classifier did not recognize an access-denied portable package replacement.'
}
if (Get-ReparoWingetBlockedReason -Output @('Uninstall failed with exit code: 0x8a150003 : Executing command failed')) {
    throw 'The blocked WinGet classifier treated a generic execution failure as access denied.'
}
if ($wingetQueue.Value.Contains('Get-ReparoPendingUpdates -Section $Section')) {
    throw 'WinGet queue construction still performs a duplicate update discovery.'
}

$goRow = 'Go Programming Language amd64 go1.26.5 GoLang.Go 1.26.5 1.27.0'
$goMatch = [regex]::Match($goRow, '^(?<name>.+)\s+(?<id>(?=[\w-]*[A-Za-z])[\w-]+(?:\.[\w-]+)+)\s+(?<version>\S+)\s+(?<available>\S+)(?:\s+(?<source>\S+))?\s*$')
if (-not $goMatch.Success -or $goMatch.Groups['id'].Value -ne 'GoLang.Go') {
    throw 'WinGet table parsing does not retain GoLang.Go when a display name contains go1.26.5.'
}
$notepadRow = 'Notepad++ (64-bit x64) Notepad++.Notepad++ 8.9.7 8.9.8'
$notepadMatch = [regex]::Match($notepadRow, '^(?<name>.+)\s+(?<id>(?=[\w+.-]*[A-Za-z])[\w+-]+(?:\.[\w+-]+)+)\s+(?<version>\S+)\s+(?<available>\S+)(?:\s+(?<source>\S+))?\s*$')
if (-not $notepadMatch.Success -or $notepadMatch.Groups['id'].Value -ne 'Notepad++.Notepad++') {
    throw 'WinGet table parsing does not retain Notepad++.Notepad++ package IDs.'
}

$wingetElevation = [regex]::Match($source, '(?s)function Get-ReparoWingetNonElevatedSessionReason \{.*?(?=function Invoke-ReparoWingetRepair)')
if (-not $wingetElevation.Success) { throw 'Could not locate the WinGet non-elevated-session classifier.' }
foreach ($required in @(
    'installer cannot be run from an administrator context',
    'package installed for user scope cannot be uninstalled when running with administrator privileges'
)) {
    if (-not $wingetElevation.Value.Contains($required)) {
        throw "WinGet elevated-installer detection is absent: $required"
    }
}

$commandStep = [regex]::Match($source, '(?s)function Invoke-ReparoCommandStep \{.*?(?=function )')
if (-not $commandStep.Success) { throw 'Could not locate the WinGet result classifier.' }
if (-not $commandStep.Value.Contains('(?:Winget package requires manual uninstall/reinstall:|REPARO-WINGET-SKIP manual)')) {
    throw 'WinGet manual-reinstall marker is not parsed into the summary.'
}
foreach ($required in @(
    'function Invoke-ReparoNonElevatedWingetUpdate',
    'Start-ReparoProcessWithExplorerToken',
    'Started non-elevated Winget worker for $Id; tailing its status.',
    "-Section 'Winget(non-elevated)'",
    "-Source `$nonElevatedUpdate[0].Source",
    "-Action install",
    'Get-ReparoWingetInstallerOverride',
    "-InstallerOverride `$installOverride",
    "if ([string]::IsNullOrWhiteSpace(`$Source)) { `$Source = 'winget' }",
    'Invoke-ReparoDeferredWingetUpdate',
    'Queued deferred Winget update for $Id after Reparo exits.',
    "updated by non-elevated Explorer-shell worker"
)) {
    if (-not $source.Contains($required)) {
        throw "WinGet non-elevated worker contract is absent: $required"
    }
}
if (-not $commandStep.Value.Contains('REPARO-WINGET-UPDATED\s*(?<Id>\S+)')) {
    throw 'WinGet successful updates are not receipt-gated in the summary.'
}
if (-not $commandStep.Value.Contains('REPARO-WINGET-SKIP blocked\s*(?<Id>\S+)')) {
    throw 'Blocked WinGet packages are not parsed into the summary.'
}
if (-not $commandStep.Value.Contains("`$PSBoundParameters.ContainsKey('PendingUpdates')")) {
    throw 'WinGet command execution cannot reuse its queue discovery snapshot.'
}

$windowsUpdate = [regex]::Match($source, '(?s)if \(Test-ReparoSectionSelected ''WindowsUpdate''\) \{.*')
if (-not $windowsUpdate.Success) { throw 'Could not locate the Windows Update section.' }
foreach ($required in @(
    "`$ErrorActionPreference = ''Stop''",
    'Get-WindowsUpdate -AcceptAll -Install -AutoReboot -ErrorAction Stop -Verbose 4>&1; $global:LASTEXITCODE = 0',
    'Get-WindowsUpdate -AcceptAll -Install -IgnoreReboot -ErrorAction Stop -Verbose 4>&1; $global:LASTEXITCODE = 0',
    'WindowsUpdate started; console heartbeat enabled every 60 seconds while active.'
)) {
    if (-not $windowsUpdate.Value.Contains($required)) {
        throw "Windows Update exit-code handling is absent: $required"
    }
}

$timedCommand = [regex]::Match($source, '(?s)function Invoke-ReparoTimedCommand \{.*?(?=function Test-ReparoIgnorableCommandOutputLine)')
if (-not $timedCommand.Success) { throw 'Could not locate the timed command runner.' }
if (-not $timedCommand.Value.Contains('WindowsUpdate is still active (elapsed {0}). Windows Update can be quiet while it scans, downloads, or stages an install.')) {
    throw 'Windows Update console heartbeat is absent.'
}

$summaryGuidance = [regex]::Match($source, '(?s)function Write-ReparoSummaryNextSteps \{.*?(?=function Write-ReparoSummary \{)')
if (-not $summaryGuidance.Success) { throw 'Could not locate final-summary next-step guidance.' }
foreach ($required in @(
    'non-elevated user session',
    'reparo -Include Winget',
    'Reparo did not force-kill it.',
    'Review failed section diagnostics'
)) {
    if (-not $summaryGuidance.Value.Contains($required)) {
        throw "Final-summary guidance is absent: $required"
    }
}

$summaryWriter = [regex]::Match($source, '(?s)function Write-ReparoSummary \{.*?(?=function Invoke-ReparoTimedCommand)')
if (-not $summaryWriter.Success) { throw 'Could not locate the final summary writer.' }
if (-not $summaryWriter.Value.Contains('Write-ReparoSummaryNextSteps')) {
    throw 'Next-step guidance is not emitted by the final summary.'
}
if ($timedCommand.Value.Contains('Write-ReparoSummaryNextSteps')) {
    throw 'Timed child commands must not emit accumulated final-summary guidance.'
}
if ($source.Contains('Format-Table -AutoSize -Wrap')) {
    throw 'Final summary still uses width-dependent wrapped tables.'
}
if ($source.Contains('completed, but no package-level update list was available.')) {
    throw 'Successful sections still generate noisy missing package-list notes.'
}

$chocoSection = [regex]::Match($source, '(?s)\$chocoCommand = @".*?(?="@\s*if \(\$lockedChocoIds)')
if (-not $chocoSection.Success) { throw 'Could not locate the Chocolatey update command.' }
foreach ($required in @(
    'choco outdated --limit-output --no-color 2>&1',
    '`$chocoOutdatedExitCode -notin @(0, 2)',
    'Chocolatey outdated query failed with exit code `$chocoOutdatedExitCode. Output:'
)) {
    if (-not $chocoSection.Value.Contains($required)) {
        throw "Chocolatey enhanced-exit handling is absent: $required"
    }
}

Write-Host 'Reparo Winget elevation/manual-migration, Windows Update exit, and Chocolatey handling passed.' -ForegroundColor Green
