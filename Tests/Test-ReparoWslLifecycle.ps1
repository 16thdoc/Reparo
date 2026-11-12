Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'Reparo.ps1'), [ref]$null, [ref]$null)
foreach ($name in 'Test-ReparoSectionSelected','Get-ReparoAptDeltaScript','Invoke-ReparoWslApt','Complete-ReparoWslDistro','Get-ReparoWslProcessSnapshotScript','ConvertTo-ReparoPowerShellLiteral','ConvertTo-ReparoWslShellCommand') {
    $node = $ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name}, $true)
    if (-not $node) { throw "Missing function $name" }
    Invoke-Expression $node.Extent.Text
}
function Assert($condition, $message) { if (-not $condition) { throw $message } }
function Write-ReparoDebug { param($Message) }
function Write-ReparoLog { param($Message) $script:logs += $Message }
function Write-Step { param($Message) }
function Test-Cmd { param($Name) return $true }
function Resolve-ReparoShell { 'fixture-host' }
function Add-ReparoSummaryNote { param($Message) $script:notes += $Message }
function Add-ReparoSummaryRecord { param($Bucket,$Software,$Version,$Method,$Reason) $script:records += [pscustomobject]@{Bucket=$Bucket;Software=$Software;Reason=$Reason} }
$Force=$true; $Update=$false; $WindowsUpdate=$false; $WindowsFeatureUpdate=$false
$WslApt=$true; $MigrateChocoToWinget=$false; $FinalizeChocolateyRemoval=$false
$Winget=$false; $WingetDiscover=$false; $WslAptTimeoutSeconds=1800; $IgnoreTimeouts=$false
$Include=@('WslApt')
Assert (Test-ReparoSectionSelected 'WslApt:Ubuntu') 'Parent selection lost Ubuntu.'
Assert (-not (Test-ReparoSectionSelected 'Winget')) 'WSL selection broadened unrelated sections.'
$Include=@('WslApt:Ubuntu')
Assert (Test-ReparoSectionSelected 'WslApt') 'Explicit distro did not select the dispatcher.'
Assert (-not (Test-ReparoSectionSelected 'WslApt:Kali')) 'Explicit distro selected another distro.'

function Get-ReparoWslNames {
    param([switch]$Running)
    $script:queries++
    if ($script:queryFails) { throw 'state discovery failed' }
    if ($Running) { return $script:running }
    return @('Ubuntu','kali-linux','docker-desktop','docker-desktop-data','rancher-desktop','podman-machine-default')
}
function Invoke-ReparoTimedCommand {
    param($ShellPath,$Command,$Section,$TimeoutSeconds,[switch]$IgnoreTimeouts)
    Assert ($Section -like 'WslApt:*') 'Unexpected backend invoked.'
    $script:commands += $Command
    $distro = $Section.Substring(7)
    $script:running = @($script:running + $distro | Select-Object -Unique)
    if ($script:workerThrows) { throw 'synthetic worker failure after distro launch' }
    [pscustomobject]@{ExitCode=$script:workerExit;TimedOut=($script:workerExit -eq 124);Output=$script:workerOutput;SkipRequested=$script:skipRequested}
}
function Invoke-ReparoWslControl {
    param($Arguments)
    Assert ($Arguments -notcontains '--shutdown') 'Global WSL shutdown must never run.'
    $script:controls += ,$Arguments
    if ($Arguments -contains '--terminate') {
        $script:terminated += $Arguments[1]
        if (-not $script:stopFails) { $script:running = @($script:running | Where-Object { $_ -ne $Arguments[1] }) }
        return [pscustomobject]@{ExitCode=0;TimedOut=$false;Output=@()}
    }
    [pscustomobject]@{ExitCode=$script:cleanupExit;TimedOut=$false;Output=@()}
}
foreach ($case in 'success','skip-apt','skip-sudo','failed','cancelled','busy-after-timeout','unknown-cleanup','worker-exception','stop-unconfirmed','preview','query-failed','specific-distro') {
    $script:logs=@(); $script:notes=@(); $script:records=@(); $script:commands=@(); $script:controls=@(); $script:terminated=@(); $script:queries=0
    $script:running=@('Ubuntu'); $script:workerExit=0; $script:workerOutput=@(); $script:cleanupExit=0
    $script:workerThrows=$false; $script:stopFails=$false; $script:skipRequested=$false; $script:queryFails=$false
    $Preview=($case -eq 'preview'); $Include=@('WslApt')
    switch ($case) {
        'skip-apt' {$script:workerExit=20}
        'skip-sudo' {$script:workerExit=21}
        'failed' {$script:workerExit=1}
        'cancelled' {$script:workerExit=130; $script:skipRequested=$true; $script:workerOutput=@('REPARO-STEP-SKIPPED safe boundary: fixture'); $script:running=@()}
        'busy-after-timeout' {$script:workerExit=124; $script:cleanupExit=3}
        'unknown-cleanup' {$script:cleanupExit=4}
        'worker-exception' {$script:workerThrows=$true; $script:running=@()}
        'stop-unconfirmed' {$script:stopFails=$true}
        'query-failed' {$script:queryFails=$true}
        'specific-distro' {$Include=@('WslApt:kali-linux')}
    }
    Invoke-ReparoWslApt
    if ($Preview -or $script:queryFails) {
        Assert ($script:commands.Count -eq 0 -and $script:controls.Count -eq 0) "$case launched a distro."
        if ($Preview) { Assert ($script:queries -eq 0) 'Preview queried WSL.' }
        continue
    }
    Assert (@($script:commands | Where-Object { $_ -match 'docker|rancher|podman' }).Count -eq 0) "$case launched an internal distro."
    if ($case -eq 'cancelled' -or $case -eq 'worker-exception') {
        Assert ($script:commands.Count -eq 1) "$case continued after cancellation/failure."
    } else {
        Assert ($script:terminated -notcontains 'Ubuntu') "$case stopped a previously running workload."
    }
    if ($case -in 'busy-after-timeout','unknown-cleanup') {
        Assert ($script:terminated.Count -eq 0 -and $script:notes.Count -gt 0) "$case killed an unverified workload or omitted a warning."
    } elseif ($case -eq 'stop-unconfirmed') {
        Assert ($script:notes.Count -gt 0) 'Unconfirmed stop was reported as clean.'
    } else {
        Assert ($script:terminated.Count -eq 1) "$case did not clean up the maintenance-started distro."
    }
    if ($case -eq 'success') { Assert (@($script:records | Where-Object { $_.Bucket -eq 'Skipped' -and $_.Reason -match 'apt commands succeeded' }).Count -eq 2) 'Successful distro results missing.' }
    if ($case -in 'skip-apt','skip-sudo') { Assert (@($script:records | Where-Object { $_.Bucket -eq 'Skipped' -and $_.Reason -match 'apt commands succeeded' }).Count -eq 0) 'Skipped apt was reported as updated.' }
    if ($case -eq 'failed') { Assert (@($script:records | Where-Object Bucket -eq 'Failed').Count -eq 2) 'Distro failures were hidden.' }
    if ($case -eq 'specific-distro') { Assert ($script:commands.Count -eq 1 -and $script:commands[0] -match 'kali-linux') 'Per-distro selection did not stay scoped.' }
}
Write-Host 'WSL selection, no-launch preview, internal exclusions, prior workloads, safe cleanup, skips, failures, cancellation and uncertain cleanup passed.'
