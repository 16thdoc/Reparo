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
    'Winget package requires manual uninstall/reinstall:',
    'Winget package requires a non-elevated session:',
    'Winget packages pending a non-elevated session:',
    'REPARO-WINGET-SKIP not-applicable',
    'Winget packages not applicable to this system or its current requirements:',
    '`$failedPackages.Count -gt 0',
    '[void]$commands.Add(''exit 0'')'
)) {
    if (-not $wingetQueue.Value.Contains($required)) {
        throw "WinGet manual-migration exit handling is absent: $required"
    }
}

$wingetElevation = [regex]::Match($source, '(?s)function Get-ReparoWingetNonElevatedSessionReason \{.*?(?=function Invoke-ReparoWingetRepair)')
if (-not $wingetElevation.Success) { throw 'Could not locate the WinGet non-elevated-session classifier.' }
if (-not $wingetElevation.Value.Contains('installer cannot be run from an administrator context')) {
    throw 'WinGet elevated-installer detection is absent.'
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
    'Review failed section diagnostics'
)) {
    if (-not $summaryGuidance.Value.Contains($required)) {
        throw "Final-summary guidance is absent: $required"
    }
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
