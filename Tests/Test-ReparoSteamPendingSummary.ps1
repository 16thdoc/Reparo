# Replay the user's six-game receipt through the real dispatcher and summary.
# No Steam, Task Scheduler, game files, network or maintenance is exercised.
param([string]$SourcePath=(Join-Path (Split-Path -Parent $PSScriptRoot) 'Reparo.ps1'))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$source=$SourcePath
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Source does not parse'}
foreach($name in @('Add-ReparoSummaryRecord','Invoke-ReparoSteamGameUpdates','Write-ReparoSummary','Write-ReparoSummaryTable','Write-ReparoNotUpdatedReport','Get-ReparoNotUpdatedAction','Write-ReparoSummaryNextSteps')){
    $fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    if(-not $fn){throw ('Missing '+$name)}
    Invoke-Expression $fn.Extent.Text
}
function Write-ReparoLog {param($Message) $script:logs.Add([string]$Message)}
function Write-ReparoConsole {param($Message,$Color,[switch]$NoNewline) Write-Host $Message -NoNewline:$NoNewline}
function Test-ReparoConsoleColor {return $false}
function Write-ReparoEventLog {param($EventId,$EntryType,$Message) if($EntryType -eq 'Error'){$script:errorEvents++}}
function Test-ReparoSectionSelected {param($Section) return $true}
function Write-Step {param($Message)}
function Write-Info {param($Message)}
function Write-Skip {param($Message)}
function Get-ReparoSteamClientPath {return 'C:\fixture\steam.exe'}
function Get-ReparoSteamGameInventory {param($SteamRoot) return $script:games}
function Select-ReparoSteamQueueGames {param($Games,$AppIds) [pscustomobject]@{Eligible=$Games;Skipped=@()}}
function Get-ReparoSteamDesktopContext {[pscustomobject]@{Available=$true;Reason='';Sid='fixture';SessionId=1}}
function Invoke-ReparoSteamQueue {param($SteamPath,$Games,$Desktop,$WaitSeconds) [pscustomobject]@{Status='Processed';Results=$script:results}}
$script:ReparoIsWindows=$true
$script:ReparoLogPath='fixture.log'
$script:ReparoPendingRebootDetected=$false
$Preview=$false;$SteamAppId=@();$SteamWaitSeconds=0
function Reset-Summary {
    $script:logs=[Collections.Generic.List[string]]::new()
    $script:errorEvents=0
    $script:ReparoSummary=[ordered]@{}
    foreach($key in @('Updated','Skipped','Failed','Pending','Notes')){$script:ReparoSummary[$key]=[Collections.Generic.List[object]]::new()}
}
function Set-Results([string[]]$States){
    $names=@('Dune: Awakening','Lightyear Frontier','Once Human','Deep Rock Galactic: Rogue Core',"No Man's Sky",'Satisfactory')
    $script:games=@();$script:results=@()
    for($i=0;$i -lt $States.Count;$i++){
        $script:games += [pscustomobject]@{AppId=[string]($i+1);Name=$names[$i];UpdateFlagged=$true;StateFlags=6}
        $script:results += [pscustomobject]@{AppId=[string]($i+1);Name=$names[$i];Status=$States[$i];Accepted=($States[$i] -ne 'Unconfirmed');Reason=$(if($States[$i] -eq 'Unconfirmed'){'request sent; Steam acknowledgment not observed within the wait window'}else{'fixture result'})}
    }
}
function Assert-Receipt($Condition,$Message){if(-not $Condition){throw $Message}}
foreach($first in @('Unconfirmed','Downloading')){
    Reset-Summary
    Set-Results @($first,'Queued','Queued','Queued','Queued','Queued')
    Invoke-ReparoSteamGameUpdates
    Write-ReparoSummary
    $output=$script:logs -join "`n"
    Assert-Receipt ($script:ReparoSummary.Pending.Count -eq 6 -and $script:ReparoSummary.Failed.Count -eq 0 -and $script:ReparoSummary.Skipped.Count -eq 0 -and $script:ReparoSummary.Updated.Count -eq 0) 'Queued/in-progress/unconfirmed requests were falsely counted as failed/skipped/updated'
    Assert-Receipt ($output -match 'Result=PENDING' -and $output -match 'Pending=6') 'Pending summary outcome/count missing'
    Assert-Receipt ($output -notmatch 'No automatic action was taken|update manually|Result=FAILED') 'Pending requests gave false manual/failure advice'
    Assert-Receipt ($script:errorEvents -eq 0) 'Uncertainty emitted an error event'
}
Reset-Summary;Set-Results @('Completed');Invoke-ReparoSteamGameUpdates;Write-ReparoSummary
Assert-Receipt ($script:ReparoSummary.Updated.Count -eq 1 -and $script:ReparoSummary.Pending.Count -eq 0) 'Completed update was not counted correctly'
Reset-Summary;Set-Results @('Failed','Queued');Invoke-ReparoSteamGameUpdates;Write-ReparoSummary
Assert-Receipt ($script:ReparoSummary.Failed.Count -eq 1 -and $script:ReparoSummary.Pending.Count -eq 1 -and ($script:logs -join "`n") -match 'Result=FAILED' -and $script:errorEvents -eq 1) 'Genuine failures were hidden by pending work'
# Existing isolated/non-Steam callers may supply the previous bucket layout.
Reset-Summary;$script:ReparoSummary.Remove('Pending');Write-ReparoSummary
Write-Host 'Six-game replay, pending counts, truthful advice, uncertainty, genuine failures and legacy summary layout passed.'
