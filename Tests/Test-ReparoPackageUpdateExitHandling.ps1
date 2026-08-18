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
    '`$failedPackages.Count -gt 0',
    '[void]$commands.Add(''exit 0'')'
)) {
    if (-not $wingetQueue.Value.Contains($required)) {
        throw "WinGet manual-migration exit handling is absent: $required"
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

Write-Host 'Reparo Winget manual-migration and Chocolatey enhanced-exit handling passed.' -ForegroundColor Green
