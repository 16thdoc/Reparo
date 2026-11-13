Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$source=Join-Path (Split-Path -Parent $PSScriptRoot) Reparo.ps1
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$null,[ref]$null)
foreach($name in 'ConvertTo-ReparoSafeFileName','ConvertTo-ReparoPowerShellLiteral','Get-ReparoOutcomeLedger','Get-ReparoOutcomeId','Write-ReparoAtomicJson','Save-ReparoReceipt','Add-ReparoOutcome','Get-ReparoRepairView','Get-ReparoRepairLines','Invoke-ReparoTimedCommand','ConvertFrom-ReparoCapturedBytes','Complete-ReparoWslDistro','Get-ReparoWslProcessSnapshotScript','Invoke-ReparoWslControl','ConvertTo-ReparoWslShellCommand'){
    $fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    Invoke-Expression $fn.Extent.Text
}
function Assert($ok,$why){if(-not $ok){throw $why}}
function Write-ReparoLog {param($Message)}
function Write-Info {param($Message)}
function Read-ReparoSkipKey {return $false}
function Add-ReparoSummaryNote {param($Message)}
function Get-ReparoWslNames {param([switch]$Running) 'FixtureDistro'}
function Resolve-ReparoShell {(Get-Process -Id $PID).Path}
$root=Join-Path ([IO.Path]::GetTempPath()) ('reparo-cleanup-outcomes-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$LogRoot=$root;$script:ReparoVersion='1.4.4.9';$script:ReparoSourcePath=$source;$script:ReparoLogBaseName='reparo_FIXTURE_cleanup'
try{
    $expected=Invoke-ReparoTimedCommand -ShellPath (Resolve-ReparoShell) -Command 'exit 3' -Section WslControl -WslCleanupProbe
    Assert ($expected.ExitCode -eq 3 -and $expected.Receipt.control_outcome -eq 'workload-preserved') 'Expected control result lost its actual exit or interpretation.'
    $ledger=Get-ReparoOutcomeLedger
    Assert ($ledger.records['command-'+$expected.Receipt.id].outcome -eq 'coverage') 'Safe preservation counted as failed maintenance.'
    # The real control wrapper must explicitly forward context; no wsl.exe runs.
    $realTimed=(Get-Command Invoke-ReparoTimedCommand).Definition
    function Invoke-ReparoTimedCommand {
        param($ShellPath,$Command,$Section,$TimeoutSeconds,[switch]$WslCleanupProbe)
        Assert ($Section -eq 'WslControl' -and $WslCleanupProbe) 'Cleanup interpretation was not explicitly passed at the real call site.'
        $script:fixtureCalls++
        [pscustomobject]@{ExitCode=$script:fixtureExit;TimedOut=$script:fixtureTimeout;Output=@()}
    }
    $script:fixtureCalls=0;$script:fixtureExit=3;$script:fixtureTimeout=$false
    Complete-ReparoWslDistro -Distro FixtureDistro -Baseline '/tmp/fictional-baseline'
    Assert ($script:fixtureCalls -eq 1) 'A known new workload reached termination.'
    $ledger.parent.execution_finished=$true;$ledger.parent.reported_status='COMPLETE'
    $view=Get-ReparoRepairView $ledger
    Assert ($view.counts.failed -eq 0 -and $view.counts.pending_unknown -eq 0 -and $view.counts.workloads_preserved -eq 1 -and $view.finality.settled) 'Safe cleanup deferral remained unsettled or failed.'
    $lines=Get-ReparoRepairLines -View $view -RepairPath 'fixture.json'
    Assert (($lines.Human -join '') -match 'Workloads preserved: 1' -and ($lines.Human -join '') -match 'No repair action') 'Human panel hid intentional preservation or requested unnecessary retry.'
    Assert (($lines.Brief -join '') -notmatch 'failed|pending') 'AI block invented failed/pending maintenance.'
    foreach($case in @(@{Code=4;Timeout=$false},@{Code=3;Timeout=$true})){
        Remove-Variable ReparoOutcomeLedger -Scope Script
        $script:fixtureExit=$case.Code;$script:fixtureTimeout=$case.Timeout
        Complete-ReparoWslDistro -Distro FixtureDistro -Baseline '/tmp/fictional-baseline'
        $uncertain=Get-ReparoRepairView (Get-ReparoOutcomeLedger)
        Assert ($uncertain.counts.pending_unknown -eq 1 -and -not $uncertain.finality.settled) 'Unknown/timeout cleanup was falsely settled.'
    }
    Set-Item Function:\Invoke-ReparoTimedCommand ([scriptblock]::Create($realTimed))
    Remove-Variable ReparoOutcomeLedger -Scope Script
    $ordinary=Invoke-ReparoTimedCommand -ShellPath (Resolve-ReparoShell) -Command 'exit 3' -Section fixture
    Assert ((Get-ReparoRepairView (Get-ReparoOutcomeLedger)).counts.failed -eq 1) 'An unrelated native exit3 was excused.'
    $failed=Invoke-ReparoTimedCommand -ShellPath (Resolve-ReparoShell) -Command 'exit 4' -Section WslControl -WslCleanupProbe
    Assert ($failed.ExitCode -eq 4 -and $null -eq $failed.Receipt.control_outcome) 'Unexpected control failure acquired expected semantics.'
    Write-Output 'Actual child exit3, explicit WSL context, no-terminate guard, human/AI agreement and unknown/error controls passed.'
}finally{
    $resolved=[IO.Path]::GetFullPath($root)
    if(-not $resolved.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'reparo-cleanup-outcomes-*'){throw 'Unsafe fixture cleanup'}
    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
}
