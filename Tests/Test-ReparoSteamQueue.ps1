# No real Steam actions or Task Scheduler changes. The only written manifests are fixtures.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'Reparo.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
$names=@('Read-ReparoSteamManifestState','Test-ReparoSteamPublisher','Test-ReparoSteamInputDesktop','Get-ReparoSteamDesktopContext','Test-ReparoSteamAppRunning','Initialize-ReparoSteamAutomation','Get-ReparoSteamAutomationSnapshot','Find-ReparoSteamQueueRow','Invoke-ReparoSteamQueueButton','Get-ReparoSteamRequestOutcome','Invoke-ReparoSteamDesktopQueue','New-ReparoSteamQueueWorker','Invoke-ReparoSteamQueue','Select-ReparoSteamQueueGames')
foreach($name in $names){
    $node=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    if(-not $node){throw "Missing queue function $name"}
    Invoke-Expression $node.Extent.Text
}
function Assert-Queue($Condition,[string]$Message){if(-not $Condition){throw $Message}}
$tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
$temp=Join-Path $tempRoot ('reparo-queue-fixture-'+[guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Path $temp|Out-Null
    $gameDirectory=Join-Path $temp 'common\Pilot'
    New-Item -ItemType Directory -Path $gameDirectory -Force|Out-Null
    $manifest=Join-Path $temp 'appmanifest_100.acf'
    function Reset-Manifest {
        @'
"AppState"
{
    "name" "Pilot™"
    "StateFlags" "6"
    "buildid" "1"
    "LastUpdated" "100"
    "AutoUpdateBehavior" "0"
    "installdir" "Pilot"
    "BytesDownloaded" "0"
    "BytesToDownload" "500000"
}
'@|Set-Content -LiteralPath $manifest -Encoding UTF8
    }
    Reset-Manifest
    $before=Read-ReparoSteamManifestState -Path $manifest
    Assert-Queue ($before.Name -eq 'Pilot™' -and $before.UpdateFlagged -and $before.FullyInstalled) 'UTF-8 manifest/state parsing failed'
    $game=[pscustomobject]@{AppId='100';Name='Pilot™';ManifestPath=$manifest;InstallDirectory=$gameDirectory;FullyInstalled=$true;UpdateFlagged=$true;AutoUpdateBehavior='0'}
    $selection=Select-ReparoSteamQueueGames -Games @($game) -AppIds @('100')
    Assert-Queue ($selection.Eligible.Count -eq 1) 'Installed pending game was not selected'
    $selection=Select-ReparoSteamQueueGames -Games @($game) -AppIds @('999')
    Assert-Queue ($selection.Eligible.Count -eq 0 -and $selection.Skipped[0].Reason -match 'not installed') 'Uninstalled AppID fell through to another game'
    $selection=Select-ReparoSteamQueueGames -Games @() -AppIds @('999')
    Assert-Queue ($selection.Eligible.Count -eq 0) 'Empty library was not safe'
    $game.AutoUpdateBehavior='1'
    Assert-Queue ((Select-ReparoSteamQueueGames -Games @($game)).Skipped[0].Reason -match 'only on launch') 'Only-on-launch policy was ignored'
    $game.AutoUpdateBehavior='0';$game.InstallDirectory=Join-Path $temp 'missing'
    Assert-Queue ((Select-ReparoSteamQueueGames -Games @($game)).Eligible.Count -eq 0) 'Missing game directory could trigger a new installation'
    $game.InstallDirectory=$gameDirectory
    $duplicate=[pscustomobject]@{AppId='101';Name='Pilot™';ManifestPath=$manifest;InstallDirectory=$gameDirectory;FullyInstalled=$true;UpdateFlagged=$true;AutoUpdateBehavior='0'}
    Assert-Queue ((Select-ReparoSteamQueueGames -Games @($game,$duplicate)).Eligible.Count -eq 0) 'Duplicate game names were not blocked'
    $row=[pscustomobject]@{Name='Pilot™ 489.2 KB Scheduled for Tomorrow 1:00 AM Download now';Enabled=$true;Offscreen=$false;Rectangle='1,2,3,4';Element=$null}
    $snapshot=[pscustomobject]@{Window=$null;Rows=@($row,$row)}
    Assert-Queue ([bool](Find-ReparoSteamQueueRow -Snapshot $snapshot -Name 'Pilot™')) 'Duplicate Chromium trees were not deduplicated'
    Assert-Queue (-not (Find-ReparoSteamQueueRow -Snapshot $snapshot -Name 'Pilot')) 'Game-name prefix collision selected another title'
    $row2=[pscustomobject]@{Name=$row.Name;Enabled=$true;Offscreen=$false;Rectangle='5,6,7,8';Element=$null}
    $rejected=$false
    try{Find-ReparoSteamQueueRow -Snapshot ([pscustomobject]@{Rows=@($row,$row2)}) -Name 'Pilot™'|Out-Null}catch{$rejected=$true}
    Assert-Queue $rejected 'Distinct matching download rows were not rejected'
    $stale=[pscustomobject]@{UpdateFlagged=$false;FullyInstalled=$true;BuildId='1';LastUpdated=100;BytesDownloaded=0}
    Assert-Queue ((Get-ReparoSteamRequestOutcome -Before $before -After $stale -Accepted $true) -eq 'Queued') 'Cleared flag alone falsely claimed a completed update'
    $progress=[pscustomobject]@{UpdateFlagged=$true;FullyInstalled=$true;BuildId='1';LastUpdated=100;BytesDownloaded=100}
    Assert-Queue ((Get-ReparoSteamRequestOutcome -Before $before -After $progress -Accepted $false) -eq 'Downloading') 'Measured download progress was lost'
    $complete=[pscustomobject]@{UpdateFlagged=$false;FullyInstalled=$true;BuildId='2';LastUpdated=200;BytesDownloaded=500000}
    Assert-Queue ((Get-ReparoSteamRequestOutcome -Before $before -After $complete -Accepted $false) -eq 'Completed') 'Fresh completed manifest was not recognized'
    $complete.FullyInstalled=$false
    Assert-Queue ((Get-ReparoSteamRequestOutcome -Before $before -After $complete -Accepted $true) -ne 'Completed') 'Incomplete installation falsely claimed completion'
    $complete.FullyInstalled=$true
    $worker=New-ReparoSteamQueueWorker
    $workerTokens=$null;$workerErrors=$null
    $null=[Management.Automation.Language.Parser]::ParseInput($worker,[ref]$workerTokens,[ref]$workerErrors)
    Assert-Queue ($workerErrors.Count -eq 0) 'Embedded desktop worker does not parse'
    Assert-Queue ($worker -notmatch 'Start-Process.+Reparo.ps1|Restart-Computer|Stop-Process|SendKeys|SendInput') 'Desktop worker includes an unsafe or unrelated operation'
    # Compile the shipped interop and activate native UIA8 without invoking any control.
    Initialize-ReparoSteamAutomation
    $nativeClient=[ReparoSteamNative.Client]::new()
    Assert-Queue ($null -ne $nativeClient) 'Native UI Automation 8 could not initialize'

    # Exercise the real orchestration with substituted UI boundaries and fixture files.
    $script:desktopOpen=$true;$script:publisherValid=$true;$script:running=$false;$script:requests=0;$script:completeRequest=$true
    function Test-ReparoSteamInputDesktop {return $script:desktopOpen}
    function Test-ReparoSteamPublisher {param($Path) return $script:publisherValid}
    function Test-ReparoSteamAppRunning {param($Game) return $script:running}
    function Get-ReparoSteamAutomationSnapshot {
        param($SteamPath,$SessionId)
        [pscustomobject]@{Window=$null;Rows=$(if($script:requests -eq 0 -or -not $script:completeRequest){@($row)}else{@()})}
    }
    function Invoke-ReparoSteamQueueButton {
        param($Row)
        $script:requests++
        if($script:completeRequest){
            (Get-Content -LiteralPath $manifest -Raw -Encoding UTF8).Replace('"StateFlags" "6"','"StateFlags" "4"').Replace('"buildid" "1"','"buildid" "2"').Replace('"LastUpdated" "100"','"LastUpdated" "200"')|Set-Content -LiteralPath $manifest -Encoding UTF8
        }
    }
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $session=(Get-Process -Id $PID).SessionId
    $config=[pscustomobject]@{RunId='fixture';SteamPath='C:\fixture\steam.exe';Games=@($game);Sid=$sid;SessionId=$session;WaitSeconds=0;CancelPath=(Join-Path $temp 'cancel')}
    $config.SessionId=$session+1
    Assert-Queue ((Invoke-ReparoSteamDesktopQueue -Config $config).Reason -match 'mismatch') 'Wrong desktop session was not blocked'
    $config.SessionId=$session;$script:desktopOpen=$false
    Assert-Queue ((Invoke-ReparoSteamDesktopQueue -Config $config).Reason -match 'locked') 'Locked desktop was not blocked'
    $script:desktopOpen=$true;$script:publisherValid=$false
    Assert-Queue ((Invoke-ReparoSteamDesktopQueue -Config $config).Reason -match 'signature') 'Invalid Steam publisher was not blocked'
    $script:publisherValid=$true;$script:running=$true
    $receipt=Invoke-ReparoSteamDesktopQueue -Config $config
    Assert-Queue ($receipt.Results[0].Status -eq 'Skipped' -and $script:requests -eq 0) 'Running game was not protected'
    $script:running=$false
    $receipt=Invoke-ReparoSteamDesktopQueue -Config $config
    Assert-Queue ($receipt.Results[0].Status -eq 'Completed' -and $script:requests -eq 1) 'Desktop queue orchestration did not recognize the fixture Steam completion'
    Reset-Manifest;$script:requests=0;$script:completeRequest=$false
    $receipt=Invoke-ReparoSteamDesktopQueue -Config $config
    Assert-Queue ($receipt.Results[0].Status -eq 'Unconfirmed') 'Unacknowledged UI invocation falsely passed'
    Reset-Manifest;$script:requests=0
    Set-Content -LiteralPath $config.CancelPath -Value 'cancel'
    $receipt=Invoke-ReparoSteamDesktopQueue -Config $config
    Assert-Queue ($script:requests -eq 0 -and $receipt.Results[0].Reason -match 'cancellation') 'Cancellation allowed a later UI request'

    # Simulate the SYSTEM-to-interactive-user bridge; no actual task or ACL mutation.
    $InstallRoot=Join-Path $temp 'bridge'
    $script:principal=$null;$script:unregistered=0;$script:receiptMode='valid'
    function Test-ReparoCurrentProcessElevated {return $true}
    function Set-Acl {param($LiteralPath,$AclObject)}
    function New-ScheduledTaskAction {param($Execute,$Argument) [pscustomobject]@{Execute=$Execute;Arguments=$Argument}}
    function New-ScheduledTaskPrincipal {param($UserId,$LogonType,$RunLevel) $script:principal=[pscustomobject]@{UserId=$UserId;LogonType=$LogonType;RunLevel=$RunLevel};$script:principal}
    function New-ScheduledTaskSettingsSet {param($MultipleInstances,$ExecutionTimeLimit,[switch]$AllowStartIfOnBatteries,[switch]$DontStopIfGoingOnBatteries) return 'fixture'}
    function Register-ScheduledTask {[CmdletBinding()]param($TaskName,$Action,$Principal,$Settings)}
    function Write-ReparoLog {param($Message)}
    function Unregister-ScheduledTask {[CmdletBinding()]param($TaskName,[switch]$Confirm) $script:unregistered++}
    function Start-ScheduledTask {
        [CmdletBinding()]param($TaskName)
        $run=Join-Path (Join-Path $InstallRoot 'SteamQueue') $TaskName.Substring('Reparo-SteamQueue-'.Length)
        $inputConfig=Get-Content -LiteralPath (Join-Path $run 'input.json') -Raw|ConvertFrom-Json
        $receiptSid=if($script:receiptMode -eq 'wrong-user'){'S-1-5-19'}else{$inputConfig.Sid}
        [pscustomobject]@{RunId=$inputConfig.RunId;Done=$true;Status='Processed';Reason='';Sid=$receiptSid;SessionId=$inputConfig.SessionId;WorkerPID=123;Results=@()}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $run 'Receipt\result.json') -Encoding UTF8
    }
    $desktop=[pscustomobject]@{Sid=$sid;SessionId=$session+1}
    $receipt=Invoke-ReparoSteamQueue -SteamPath 'C:\fixture\steam.exe' -Games @($game) -Desktop $desktop -WaitSeconds 0 -RequestTimeoutSeconds 1
    Assert-Queue ($receipt.Status -eq 'Processed' -and $script:principal.LogonType -eq 'Interactive' -and $script:principal.RunLevel -eq 'Limited' -and $script:unregistered -eq 1) 'Desktop bridge principal or cleanup contract failed'
    $script:receiptMode='wrong-user'
    $receipt=Invoke-ReparoSteamQueue -SteamPath 'C:\fixture\steam.exe' -Games @($game) -Desktop $desktop -WaitSeconds 0 -RequestTimeoutSeconds 1
    Assert-Queue ($receipt.Status -eq 'Blocked' -and $receipt.Reason -match 'timed out') 'A receipt from another user was accepted'
    Write-Host 'Steam queue selection, UTF-8, identity, lock, running-game, cancellation, receipt, completion and limited-user bridge tests passed.' -ForegroundColor Green
}finally{
    $resolved=[IO.Path]::GetFullPath($temp)
    if(-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'reparo-queue-fixture-*'){throw 'Refusing unsafe fixture cleanup'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
