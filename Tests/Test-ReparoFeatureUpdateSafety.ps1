Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$source = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'Reparo.ps1') -Raw
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($name in @('Test-ReparoSectionSelected', 'Invoke-ReparoWindowsFeatureUpdate', 'Get-ReparoWingetBlockedReason', 'Get-ReparoWingetNotApplicableReason', 'Get-ReparoWingetManualInterventionReason', 'Get-ReparoWingetNonElevatedSessionReason', 'Get-ReparoWingetWorkerFailureReason', 'Get-ReparoNotUpdatedAction', 'Get-ReparoStaleRunningLog')) {
    $node = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $node) { throw "Missing function: $name" }
    Invoke-Expression $node.Extent.Text
}
function Write-ReparoDebug { param($Message) }
function Write-ReparoLog { param($Message) [void]$script:logs.Add($Message) }
function Write-Step { param($Message) $script:steps++ }
function Write-Skip { param($Message) }
function Write-Fail { param($Message) }
function Add-ReparoSummaryNote { param($Message) }
function Add-ReparoSummaryRecord { param($Bucket,$Software,$CurrentVersion,$Version,$Method,$Reason) [void]$script:rows.Add([pscustomobject]@{ Bucket=$Bucket; Software=$Software; Version=$Version; Reason=$Reason }) }
function Get-ReparoWindowsReleaseInfo { [pscustomobject]@{ Caption='fixture'; Version='fixture'; BuildNumber=$script:build } }
function Start-Process { throw 'Feature lane launched a process' }
function Invoke-WebRequest { throw 'Feature lane downloaded a payload' }
function Invoke-ReparoCommandStep { throw 'Feature lane invoked the generic success wrapper' }
$Force=$true; $Update=$false; $WindowsUpdate=$true; $WindowsFeatureUpdate=$false
$WslApt=$false; $MigrateChocoToWinget=$false; $FinalizeChocolateyRemoval=$false; $Winget=$false; $WingetDiscover=$false
$Include=@(); $Preview=$false; $AllowReboot=$false
$forceArray = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$windowsForceSections' }, $true)
Invoke-Expression $forceArray.Extent.Text
$Include=$windowsForceSections
if (Test-ReparoSectionSelected 'WindowsFeatureUpdate') { throw '-Force implicitly selects feature updates' }
$Include=@(); $Force=$false; $Update=$true
if (Test-ReparoSectionSelected 'WindowsFeatureUpdate') { throw '-Update implicitly selects feature updates' }
$Update=$false; $WindowsFeatureUpdate=$true
if (-not (Test-ReparoSectionSelected 'WindowsFeatureUpdate')) { throw 'Explicit switch was lost' }
$WindowsFeatureUpdate=$false; $Include=@('WindowsFeatureUpdate')
if (-not (Test-ReparoSectionSelected 'WindowsFeatureUpdate')) { throw 'Explicit Include was lost' }
$normalization=$ast.Find({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -eq '$PowerShell7Only' }, $true)
if (-not $normalization) { throw 'CLI selection normalization was not found' }
$PowerShell7Only=$false; $SevenZip=$false; $script:ReparoIsWindows=$true
foreach ($selection in @('force','force-switch','force-include','update')) {
    $Force=$selection -like 'force*'; $Update=$selection -eq 'update'
    $WindowsFeatureUpdate=$selection -eq 'force-switch'
    $Include=@(if ($selection -eq 'force-switch' -or $selection -eq 'force-include') { 'WindowsFeatureUpdate' })
    $updateSections=@('WindowsUpdate','Winget'); $Preview=$false
    Invoke-Expression $normalization.Extent.Text
    $expected=$selection -eq 'force-switch' -or $selection -eq 'force-include'
    if ((Test-ReparoSectionSelected 'WindowsFeatureUpdate') -ne $expected) { throw "CLI normalization lost feature selection for $selection" }
}
$Force=$false; $Update=$false; $WindowsFeatureUpdate=$false; $Include=@('WindowsFeatureUpdate')
foreach ($build in @(19045,26300)) {
    foreach ($previewMode in @($false,$true)) {
        foreach ($rebootMode in @($false,$true)) {
            $Preview=$previewMode; $AllowReboot=$rebootMode; $script:build=$build
            $script:steps=0; $script:logs=New-Object System.Collections.Generic.List[string]; $script:rows=New-Object System.Collections.Generic.List[object]
            Invoke-ReparoWindowsFeatureUpdate
            if ($script:steps -ne 1 -or $script:rows.Count -ne 1 -or $script:rows[0].Bucket -ne 'Skipped' -or $script:rows[0].Version -ne '-') { throw 'Feature skip fabricated success, target release or duplicate STEP' }
            if (($script:logs -join "`n") -notmatch 'No download, staging or reboot attempted') { throw 'No-op receipt is missing' }
            $action=Get-ReparoNotUpdatedAction -Row $script:rows[0] -Outcome SKIPPED
            if ($action -notmatch 'Settings > Windows Update') { throw 'Feature skip lacks actionable guidance' }
        }
    }
}
$blocked=Get-ReparoWingetWorkerFailureReason -Result ([pscustomobject]@{ ExitCode=-1978335145; Output=@('remove: Access is denied.: fixture.exe','Uninstall failed with exit code: 0x8a150003') })
if ($blocked -notmatch 'access denied' -or $blocked -notmatch 'file-in-use is not established' -or $blocked -notmatch '0x8A150057') { throw "Worker cause/hex code lost: $blocked" }
$action=Get-ReparoNotUpdatedAction -Row ([pscustomobject]@{ Reason=$blocked }) -Outcome SKIPPED
if ($action -notmatch 'Close the app or stop its service') { throw 'Blocked worker lacks actionable guidance' }
# Verify the retained install fallback is conditional on actual applicability output.
if ($source -notmatch 'if \(-not \(Get-ReparoWingetNotApplicableReason -Output \$nonElevatedResult.Output\)\)') { throw 'Install fallback must not retry unrelated worker failures' }
$retryBlock=$ast.Find({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -eq '$notApplicableWingetReason' }, $true)
if (-not $retryBlock) { throw 'Applicability retry block was not found' }
function Test-ReparoCurrentProcessElevated { $true }
function Get-ReparoWingetInstallerOverride { param($Id) $null }
function Invoke-ReparoNonElevatedWingetUpdate {
    param($Id,$Source,$TimeoutSeconds,$Action='upgrade',$InstallerOverride)
    [void]$script:attempts.Add($Action)
    if ($Action -eq 'install') { return [pscustomobject]@{ ExitCode=0; Output=@('Successfully installed') } }
    if ($script:retryCase -eq 'success') { return [pscustomobject]@{ ExitCode=0; Output=@('Successfully installed') } }
    if ($script:retryCase -eq 'blocked') { return [pscustomobject]@{ ExitCode=1; Output=@('remove: Access is denied.') } }
    return [pscustomobject]@{ ExitCode=1; Output=@('No applicable upgrade found.') }
}
foreach ($case in @('success','blocked','not-applicable')) {
    $script:retryCase=$case
    $script:attempts=New-Object System.Collections.Generic.List[string]
    $script:rows.Clear()
    $pendingUpdates=@([pscustomobject]@{ Id='fixture'; Source='winget'; Software='fixture'; CurrentVersion='1'; Version='2'; Method='winget' })
    $notApplicableWingetReason='fixture applicability'; $notApplicableWingetPackageIds=@('fixture'); $updatedWingetPackageIds=@(); $WingetTimeoutSeconds=1800
    Invoke-Expression $retryBlock.Extent.Text -WarningAction SilentlyContinue
    $expectedAttempts=if ($case -eq 'not-applicable') { 'upgrade,install' } else { 'upgrade' }
    if (($script:attempts -join ',') -ne $expectedAttempts -or $script:rows.Count -ne 1) { throw "Incorrect retry/receipt count for $case" }
    $expectedBucket=if ($case -eq 'blocked') { 'Skipped' } else { 'Updated' }
    if ($script:rows[0].Bucket -ne $expectedBucket) { throw "Incorrect retry outcome for $case" }
}
# Recovery is read-only here: no matching running-process log must become COMPLETE.
$LogRoot=$env:TEMP
$staleFunction=$ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-ReparoStaleRunningLog' }, $true)
if ($staleFunction.Extent.Text -match 'Stop-Process|Remove-Item|Move-Item') { throw 'Stale discovery is not read-only' }
function Get-ChildItem {
    [pscustomobject]@{ Name='reparo_FIXTURE_111_2026-10-05_181928_RUNNING.log'; FullName='owned.log' }
    [pscustomobject]@{ Name='reparo_FIXTURE_222_2026-10-05_181928_RUNNING.log'; FullName='live-pid.log' }
    [pscustomobject]@{ Name='reparo_FIXTURE_333_2026-10-05_181928_RUNNING.log'; FullName='stale.log' }
}
function Get-Process { param($Id,$ErrorAction) if ($Id -eq 222) { [pscustomobject]@{ Id=222 } } }
$stale=@(Get-ReparoStaleRunningLog -RunningProcessInfo @([pscustomobject]@{ LogPath='owned.log' }))
if ($stale.Count -ne 1 -or $stale[0].FullName -ne 'stale.log') { throw 'Stale discovery failed to preserve a live PID or run-owned log' }
Write-Host 'Feature-update selection/no-op/reboot safety and worker receipt tests passed.' -ForegroundColor Green
