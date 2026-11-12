param([string]$SourcePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'Reparo.ps1'))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($SourcePath,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors | Out-String)}
# Import definitions only. No runner startup, discovery, scheduler, installer or
# maintenance entry point is evaluated by this fixture.
foreach($name in @('ConvertTo-ReparoSafeFileName','ConvertTo-ReparoPowerShellLiteral',
    'Get-ReparoOutcomeLedger','Get-ReparoOutcomeId','Write-ReparoAtomicJson','Save-ReparoReceipt',
    'Add-ReparoOutcome','Add-ReparoLegacyOutcome','Get-ReparoRepairView','Get-ReparoRepairLines',
    'Write-ReparoRepairSummary','Add-ReparoSummaryRecord','Add-ReparoSectionUpdates',
    'ConvertFrom-ReparoCapturedBytes','Invoke-ReparoTimedCommand','Invoke-ReparoWingetPackageQueue',
    'Get-ReparoLatestCompletedLog','Get-ReparoLatestRepairView','New-ReparoWingetWorkerScript','Read-ReparoStableText','Get-ReparoConsumerDecision','Add-ReparoAptOutcomes','Invoke-ReparoCommandStep')) {
    $node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    if(-not $node){throw "Missing function $name"}
    Invoke-Expression $node.Extent.Text
}
function Assert($Condition,$Message) { if(-not $Condition){throw $Message} }
function Write-ReparoLog {param($Message)}
function Write-ReparoEventLog {param($EventId,$EntryType,$Message)}
function Write-Info {param($Message)}
function Read-ReparoSkipKey {return $false}
$root=Join-Path ([IO.Path]::GetTempPath()) ('reparo-reliability-'+[guid]::NewGuid().ToString('N'))
$LogRoot=$root
$script:ReparoLogBaseName='reparo_FIXTURE_123_2026-01-01_010101'
$script:ReparoVersion='1.4.4.8';$script:ReparoSourcePath=$SourcePath
$script:ReparoSyslogFailureReported=$false
$script:ReparoLogPath=Join-Path $root 'parent.log'
$script:ReparoFinalStatus='COMPLETE'
$script:ReparoSummary=[ordered]@{}
foreach($bucket in 'Updated','Skipped','Failed','Pending','Notes'){$script:ReparoSummary[$bucket]=New-Object 'System.Collections.Generic.List[object]'}
New-Item -ItemType Directory -Path $root | Out-Null
try {
    # Eleven command-success receipts followed by a separate launch exception.
    1..11 | ForEach-Object { Add-ReparoSummaryRecord -Bucket Updated -Software "package-$_" -CurrentVersion '1' -Version '2' -Method winget -Reason updated }
    Add-ReparoSummaryRecord -Bucket Failed -Software deferred-launch -Method winget -Reason 'Synthetic launch exception'
    $ledger=Get-ReparoOutcomeLedger
    $ledger.parent.execution_finished=$true
    $view=Get-ReparoRepairView $ledger
    Assert ($view.counts.legacy_success_receipts -eq 11) 'Earlier successes were lost.'
    Assert ($view.counts.confirmed_changes -eq 0) 'Advertised target versions became confirmed changes.'
    $successLines=Get-ReparoRepairLines -View $view -RepairPath 'fictional-repair.json'
    Assert (($successLines.Human -join '') -match 'Commands: 0 \| Package receipts: 11') 'Human summary hid successful package receipts or conflated them with commands.'
    Add-ReparoSummaryRecord -Bucket Updated -Software package-1 -CurrentVersion '1' -Version '2' -Method winget -Reason updated
    Assert ((Get-ReparoRepairView $ledger).counts.legacy_success_receipts -eq 11) 'Replay double counted a package.'
    Assert ($script:ReparoSummary.Updated.Count -eq 11) 'Legacy rows double counted replay.'
    # Null/signed/unsigned/hex survive an eventual worker without changing parent exit.
    $id='worker-fixture'
    Add-ReparoOutcome -Id $id -Backend winget -Package Fixture.Package -Phase worker -Outcome pending -Reason 'Await receipt'
    $statusPath=Join-Path $root 'worker.status.json'
    $ledger.workers[$id]=@{id=$id;status_path='worker.status.json'}
    $pending=Get-ReparoRepairView $ledger
    Assert (-not $pending.finality.settled) 'Missing worker settled successfully.'
    Set-Content -LiteralPath $statusPath -Value '{broken'
    Assert ((Get-ReparoRepairView $ledger).counts.pending_unknown -eq 1) 'Corrupt worker ceased being unresolved.'
    [void](Write-ReparoAtomicJson $statusPath @{schema='reparo-worker/1';worker_id=$id;state='terminal';ExitCode=-1978335090;reason='Installer technology mismatch';capture_health='complete'})
    $late=Get-ReparoRepairView $ledger
    $item=@($late.attention | Where-Object id -EQ $id)[0]
    Assert ($item.outcome -eq 'failed' -and $item.code.hex -eq '0x8A15008E') 'Late failure code was lost.'
    Assert ($null -eq $late.parent.exit_code) 'Parent exit was invented.'
    Assert ((Get-ReparoRepairView $ledger).attention.Count -eq $late.attention.Count) 'Read-only reconciliation duplicated records.'
    Assert ($ledger.records[$id].outcome -eq 'pending') 'Read-only reconciliation rewrote historical parent snapshot.'
    # Unicode, long messages, overflow and round-trip manual ingestion.
    1..5 | ForEach-Object { Add-ReparoOutcome -Backend fixture -Package "unicode-$_-雪" -Outcome unknown -Reason ("line`n"+('long '*80)) }
    $view=Get-ReparoRepairView $ledger
    $path=Save-ReparoReceipt -Name repair -Value $view
    $parsed=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $lines=Get-ReparoRepairLines -View $parsed -RepairPath $path
    Assert ($lines.Human.Count -eq 8 -and $lines.Brief.Count -le 6) 'Compact summary budget exceeded.'
    Assert (($lines.Brief -join "`n") -match '\+\d+ groups in complete repair file') 'Attention overflow was hidden.'
    Assert ($parsed.attention.Count -eq $view.attention.Count) 'Structured round trip lost attention records.'
    Assert (($parsed.records.PSObject.Properties.Name -join ',') -eq (($view.records.PSObject.Properties.Name) -join ',')) 'Stable IDs changed on round trip.'
    # Real harmless children: capture before generated try, short exits, warnings,
    # large concurrent stdout/stderr, and native negative Windows error codes.
    $shell=(Get-Process -Id $PID).Path
    foreach($case in @(
        @{Command="exit 0";Exit=0;Pattern=''},
        @{Command="exit 37";Exit=37;Pattern=''},
        @{Command="[Console]::Error.WriteLine('benign warning'); exit 0";Exit=0;Pattern='benign warning'},
        @{Command="if (";Exit=1;Pattern='ParserError'},
        @{Command="[Console]::Out.WriteLine(('x' * 100000)); [Console]::Error.WriteLine('drained'); exit 3";Exit=3;Pattern='drained'}
    )) {
        $result=Invoke-ReparoTimedCommand -ShellPath $shell -Command $case.Command -Section fixture
        Assert ($result.ExitCode -eq $case.Exit) "Known exit was lost: $($case.Command) -> $($result.ExitCode)"
        if($case.Pattern){Assert (($result.Output -join "`n") -match $case.Pattern) ("Child diagnostic missing for " + $case.Command + ": " + ($result.Output -join "`n"))}
        Assert (Test-Path -LiteralPath $result.Receipt.stdout) 'Successful raw stdout was deleted.'
        Assert (Test-Path -LiteralPath $result.Receipt.stderr) 'Raw stderr was deleted.'
    }
    # The saved receipt reader ignores newer corrupt/worker/control artifacts.
    $savedView=Get-ReparoRepairView $ledger
    [void](Save-ReparoReceipt -Name repair -Value $savedView)
    [IO.File]::WriteAllText((Join-Path $root 'reparo_newer_repair.json'),'{broken')
    $selected=Get-ReparoLatestRepairView
    Assert ($selected.View.run_id -eq $ledger.run_id) 'Status selected invalid parent metadata.'
    # Renderer failure cannot erase a known successful native exit.
    function Write-ReparoLog {param($Message) throw 'Synthetic denied/full renderer'}
    $result=Invoke-ReparoTimedCommand -ShellPath $shell -Command 'exit 0' -Section render-failure
    Assert ($result.ExitCode -eq 0 -and $result.CaptureHealth -eq 'degraded') 'Rendering changed command success or hid capture degradation.'
    function Write-ReparoLog {param($Message)}
    # Invalid shell is a launch failure with null exit, never reconstructed 1.
    $result=Invoke-ReparoTimedCommand -ShellPath (Join-Path $root 'absent.exe') -Command 'exit 0' -Section launch-failure
    Assert ($null -eq $result.ExitCode) 'Missing native exit was invented.'
    # Denied/contended primary receipt output, then independent fallback.
    $primary=Join-Path $root ($ledger.run_id+'_denied.json')
    $lock=[IO.File]::Open($primary,[IO.FileMode]::Create,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try { $fallback=Save-ReparoReceipt -Name denied -Value @{exit_code=37}; Assert ($fallback -and $fallback -ne $primary -and (Test-Path -LiteralPath $fallback)) 'Independent receipt fallback was not retained.' }
    finally {$lock.Dispose()}
    # Failed primary AND fallback publication cannot announce a sidecar.
    $atomic=(Get-Command Write-ReparoAtomicJson -CommandType Function).Definition
    function Write-ReparoAtomicJson {param($Path,$Value) throw 'Synthetic final publication failure'}
    $missing=Save-ReparoReceipt -Name both-denied -Value @{exit_code=37}
    if($missing){throw 'A nonexistent sidecar was announced.'}
    $unavailable=Get-ReparoRepairView $ledger
    $unavailableLines=Get-ReparoRepairLines -View $unavailable -RepairPath $missing
    Assert (($unavailableLines.Brief -join '') -match 'unavailable;.*publication failed') 'Missing final receipt was hidden.'
    Set-Item Function:\Write-ReparoAtomicJson ([scriptblock]::Create($atomic))
    # Raw UTF16 and UTF8 decode independently; display never rewrites source bytes.
    Assert ((ConvertFrom-ReparoCapturedBytes ([Text.Encoding]::Unicode.GetPreamble()+[Text.Encoding]::Unicode.GetBytes('雪')))-eq '雪') 'UTF16 decoding failed.'
    Assert ((ConvertFrom-ReparoCapturedBytes ([Text.Encoding]::UTF8.GetBytes('雪')))-eq '雪') 'UTF8 decoding failed.'
    # Status cannot select newer worker/control/stale artifacts or itself.
    $real=Join-Path $root 'reparo_FIXTURE_123_2026-01-01_010101_COMPLETE.log'
    Set-Content -LiteralPath $real -Value '[MAINTENANCE-RUN] parent execution finished'
    foreach($name in 'reparo_FIXTURE_124_2026-01-01_020202_COMPLETE.log','reparo_FIXTURE_123_2026-01-01_010101_WindowsUpdate.out.log','reparo_FIXTURE_123_2026-01-01_010101_STALE.log') { Set-Content -LiteralPath (Join-Path $root $name) -Value 'control' }
    Assert ((Get-ReparoLatestCompletedLog).FullName -eq $real) 'Status selected a control/worker/stale log.'
    # The exact identity predicate is shared by the native token launcher.
    $launcher=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Start-ReparoProcessWithExplorerToken'},$true)
    $csharp=$launcher.Find({param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst] -and $n.Value -like '*public static class ReparoExplorerTokenLauncherV1448*'},$true).Value
    if(-not ('ReparoExplorerTokenLauncherV1448' -as [type])){Add-Type -TypeDefinition $csharp}
    Assert ([ReparoExplorerTokenLauncherV1448]::IdentityMatches('fixture-sid',1,'fixture-sid',1,0,'S-1-16-8192')) 'Valid same-user medium identity was blocked.'
    foreach($case in @(
        @('other-sid',1,0,'S-1-16-8192'),@('fixture-sid',2,0,'S-1-16-8192'),
        @('fixture-sid',1,1,'S-1-16-8192'),@('fixture-sid',1,0,'S-1-16-12288'),@('',1,0,''),@('fixture-sid',0,0,'S-1-16-8192')
    )) { Assert (-not [ReparoExplorerTokenLauncherV1448]::IdentityMatches('fixture-sid',1,$case[0],$case[1],$case[2],$case[3])) 'Mismatched or unknown identity accepted.' }
    $blocked=$false
    try{[void][ReparoExplorerTokenLauncherV1448]::Start('unused.exe','',0)}catch{$blocked=$true}
    Assert $blocked 'SYSTEM/cross-session boundary did not fail closed.'
    Assert ((Get-ReparoConsumerDecision -PackagePath 'C:\fictional\pkg' -Processes @([pscustomobject]@{CommandLine='node C:\fictional\pkg\service.js';ExecutablePath='node.exe'})) -match '^blocked:') 'Active node service was ignored.'
    Assert ((Get-ReparoConsumerDecision -PackagePath 'C:\fictional\pkg' -Processes @() -VisibilityComplete $false) -match '^blocked:') 'Unknown consumer visibility allowed mutation.'
    # Transient read denial recovers after a harmless owned handle closes.
    $acf=Join-Path $root 'fixture.acf'
    [IO.File]::WriteAllText($acf,'"AppState" { "StateFlags" "4" }')
    Assert ((Read-ReparoStableText $acf) -match 'StateFlags') 'Valid stable manifest unreadable.'
    [IO.File]::WriteAllText($acf,'"AppState" {')
    $blocked=$false;try{[void](Read-ReparoStableText $acf)}catch{$blocked=$true}
    Assert $blocked 'Persistent partial manifest was accepted.'
    # Apt metadata-only/no-op versus one/many installed version deltas.
    $prior=(Get-ReparoRepairView $ledger).counts.confirmed_changes
    Add-ReparoAptOutcomes -Backend 'WslApt:fixture' -Output @('REPARO-APT-INVENTORY available') -ExitCode 0
    Assert ((Get-ReparoRepairView $ledger).counts.confirmed_changes -eq $prior) 'Apt no-op counted as a package change.'
    Add-ReparoAptOutcomes -Backend 'WslApt:fixture' -Output @('REPARO-APT-INVENTORY available',"REPARO-APT-DELTA`tpackage-a`t1.0`t1.1","REPARO-APT-DELTA`tpackage-b`t2.0`t2.1") -ExitCode 0
    Assert ((Get-ReparoRepairView $ledger).counts.confirmed_changes -eq ($prior+2)) 'Observed apt version deltas were lost.'
    # Fail raw spool publication AFTER script creation. The child still drains
    # and exits normally; capture failure must not become an invented install failure.
    function Set-Content {
        [CmdletBinding()]param($LiteralPath,$Value,$Encoding)
        Microsoft.PowerShell.Management\Set-Content -LiteralPath $LiteralPath -Value $Value -Encoding $Encoding
        if($LiteralPath -like '*.command.ps1'){
            [void][IO.Directory]::CreateDirectory(($LiteralPath -replace '\.command\.ps1$','.stdout.raw'))
        }
    }
    $result=Invoke-ReparoTimedCommand -ShellPath $shell -Command "Write-Output 'survived spool denial'; exit 0" -Section denied-spool
    Remove-Item Function:\Set-Content
    Assert ($result.ExitCode -eq 0 -and $result.CaptureHealth -eq 'degraded' -and ($result.Output -join '') -match 'survived spool denial') 'Denied spool lost the actual success or retained bytes.'
    # Replay the REAL queue and section dispatcher. Every execution boundary is
    # replaced before invocation; the fake shell and fake command cannot resolve
    # to a maintenance executable even if the timed-command stub regresses.
    function Test-ReparoSectionSelected {param($Section) return $true}
    function Resolve-ReparoShell {return 'nonexistent-fixture-shell'}
    function New-ReparoWingetUpgradeQueueCommand {param($Section,$ExcludedIds,$PendingUpdates) return 'FAKE-MANAGER-BOUNDARY'}
    function Invoke-ReparoTimedCommand {
        param($ShellPath,$Command,$Section,$TimeoutSeconds,[switch]$IgnoreTimeouts)
        if($ShellPath -ne 'nonexistent-fixture-shell' -or $Command -ne 'FAKE-MANAGER-BOUNDARY'){throw 'Unexpected executable fixture boundary.'}
        $lines=if($Section -eq 'Winget:Microsoft.PowerShell'){@('REPARO-WINGET-SKIP deferred Microsoft.PowerShell')}else{@('REPARO-WINGET-UPDATED '+$Section.Substring(7))}
        return [pscustomobject]@{ExitCode=0;TimedOut=$false;Output=$lines;Elapsed=[TimeSpan]::Zero}
    }
    function Invoke-ReparoDeferredWingetUpdate {param($Id,$Source,$WaitForProcessId,$TimeoutSeconds) throw 'Synthetic deferred launch failure after eleven successes'}
    function Get-ReparoWingetManualInterventionReason {param($Output) return $null}
    function Get-ReparoWingetNonElevatedSessionReason {param($Output) return $null}
    function Get-ReparoWingetNotApplicableReason {param($Output) return $null}
    function Get-ReparoWingetBlockedReason {param($Output) return $null}
    function Write-Step {param($Message)}
    function Write-Done {param($Message)}
    function Write-Fail {param($Message)}
    function Write-ReparoDebug {param($Message)}
    $script:ReparoDebug=$false;$Preview=$false;$IgnoreTimeouts=$false;$WingetTimeoutSeconds=0
    $script:ReparoSummary=[ordered]@{}
    foreach($bucket in 'Updated','Skipped','Failed','Pending','Notes'){$script:ReparoSummary[$bucket]=New-Object 'System.Collections.Generic.List[object]'}
    Remove-Variable ReparoOutcomeLedger -Scope Script
    $packages=@(1..11|ForEach-Object{[pscustomobject]@{Id="Fixture.Success$_";Software='Shared display label';CurrentVersion='1';Version='2';Method='winget';Source='winget'}})
    $packages += [pscustomobject]@{Id='Microsoft.PowerShell';Software='Deferred fixture';CurrentVersion='1';Version='2';Method='winget';Source='winget'}
    Invoke-ReparoCommandStep -Section Winget -Command FAKE-MANAGER-BOUNDARY -PendingUpdates $packages
    Assert ($script:ReparoSummary.Updated.Count -eq 11 -and $script:ReparoSummary.Failed.Count -eq 1) 'Real queue/dispatcher lost prior successes after deferred failure.'
    Assert ((Get-ReparoRepairView (Get-ReparoOutcomeLedger)).counts.legacy_success_receipts -eq 11) 'Different manager IDs with the same display label were merged.'
    Write-Host 'Reliability: partial receipts, eventual workers, round trips, summaries, capture, native exits, fallback, decoding and status passed.'
} finally {
    $resolved=[IO.Path]::GetFullPath($root)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(-not $resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'reparo-reliability-*'){throw 'Unsafe fixture cleanup.'}
    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
}
