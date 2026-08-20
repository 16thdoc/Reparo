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

$ensureWinget = [regex]::Match($source, '(?s)function Ensure-ReparoWinget \{.*?(?=function Invoke-ReparoWingetDiscovery)')
if (-not $ensureWinget.Success) {
    throw 'Could not locate Ensure-ReparoWinget.'
}

$body = $ensureWinget.Value
foreach ($required in @(
    'Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe',
    'Repair-WinGetPackageManager is not supported by Windows PowerShell 5.1',
    'PowerShell 7 is not installed; no Microsoft.WinGet.Client repair was attempted',
    'Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ForceBootstrap -Scope AllUsers -Confirm:$false -ErrorAction Stop',
    'Import-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop',
    'Install-Module -Name Microsoft.WinGet.Client -Force -AllowClobber -Scope AllUsers -Repository PSGallery -Confirm:$false -ErrorAction Stop',
    "& `$pwshPath -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command `$repairCommand",
    "`$requiresInteractiveUser = ((`$detail -match '(?i)Local System account is not allowed') -or (`$appxRegistrationError -match '(?i)Local System account is not allowed'))",
    "Set-ReparoWingetHealth -Status USER -Detail 'App Installer deployment requires an interactive user context; SYSTEM cannot perform this AppX operation.'",
    "Write-ReparoLog '[SKIP] Direct App Installer fallback skipped because Local System cannot perform this AppX operation.'"
)) {
    if (-not $body.Contains($required)) {
        throw "WinGet host-agnostic repair contract is absent: $required"
    }
}

foreach ($required in @(
    "[ValidateSet('OK', 'USER', 'FAIL', 'OLD')][string]`$Status",
    "if (`$health.Status -in @('OK', 'USER', 'FAIL', 'OLD')) { `$status = `$health.Status }",
    "elseif (Test-ReparoWingetUnsupportedWindows) {",
    'function Test-ReparoWingetUnsupportedWindows',
    'Set-ReparoWingetHealth -Status OLD -Detail $legacyWingetDetail',
    "Add-ReparoSummaryRecord -Bucket Skipped -Software 'Winget' -Version '-' -Method 'Winget' -Reason 'unsupported legacy Windows build'"
)) {
    if (-not $source.Contains($required)) {
        throw "WinGet legacy Windows classification contract is absent: $required"
    }
}

$installBlock = [regex]::Match($source, '(?s)if \(\$New\) \{.*?(?=if \(\$Kill\) \{)')
if (-not $installBlock.Success) {
    throw 'Could not locate the Reparo install path.'
}

foreach ($required in @(
    "Join-Path `$env:ProgramData 'Reparo'",
    "`$wingetRepairArguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', `$installedReparoPath, '-WingetDiscover')",
    "if (-not `$InstallNuGetProvider) { `$wingetRepairArguments += '-InstallNuGetProvider:`$false' }",
    '& powershell.exe @wingetRepairArguments'
)) {
    if (-not $installBlock.Value.Contains($required)) {
        throw "Reparo install does not perform the unattended Winget repair/discovery contract: $required"
    }
}

$discovery = [regex]::Match($source, '(?s)function Invoke-ReparoWingetDiscovery \{.*?(?=function Resolve-ReparoShell \{)')
if (-not $discovery.Success) {
    throw 'Could not locate Invoke-ReparoWingetDiscovery.'
}

foreach ($required in @(
    "@{ Section = 'Winget(source list)'; Command = 'winget source list --disable-interactivity' }",
    "@{ Section = 'Winget(list upgrades)'; Command = 'winget list --upgrade-available --accept-source-agreements --disable-interactivity' }",
    "@{ Section = 'Winget(upgrade list)'; Command = 'winget upgrade --accept-source-agreements --disable-interactivity' }"
)) {
    if (-not $discovery.Value.Contains($required)) {
        throw "WinGet discovery non-interactive agreement contract is absent: $required"
    }
}

$appxIndex = $body.IndexOf('Add-AppxPackage -RegisterByFamilyName')
$pwshIndex = $body.IndexOf('Attempting Microsoft.WinGet.Client repair through PowerShell 7')
if ($appxIndex -lt 0 -or $pwshIndex -lt 0 -or $appxIndex -gt $pwshIndex) {
    throw 'WinGet repair must attempt host-native AppX registration before the PowerShell 7 fallback.'
}

Write-Host 'Reparo WinGet host-agnostic repair contract passed.' -ForegroundColor Green
