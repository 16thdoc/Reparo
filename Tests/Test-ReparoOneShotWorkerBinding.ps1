param([string]$SourcePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'Reparo.ps1'))
# Exercises the real one-shot worker builder against a harmless parameter probe.
# All Task Scheduler calls are stubs; no Reparo maintenance or Steam is launched.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$tokens=$null; $parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($SourcePath,[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
foreach ($name in @('ConvertTo-ReparoPowerShellLiteral','Resolve-ReparoScheduledTime','Get-ReparoScheduledArgumentTokens','New-ReparoTaskWorker','Invoke-ReparoSchedule')) {
    $node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    if (-not $node) { throw "Missing function $name" }
    $definition=$node.Extent.Text
    if ($name -eq 'Invoke-ReparoSchedule') { $definition=$definition.Replace('$PSCommandPath','$script:ReparoBindingProbePath') }
    Invoke-Expression $definition
}
function Test-ReparoCurrentProcessElevated { return $true }
function New-ScheduledTaskAction { param($Execute,$Argument) $script:capturedAction=$Argument; return 'fixture-action' }
function New-ScheduledTaskTrigger { param([switch]$Once,$At) return 'fixture-trigger' }
function New-ScheduledTaskPrincipal { param($UserId,$LogonType,$RunLevel) return 'fixture-principal' }
function New-ScheduledTaskSettingsSet { param([switch]$StartWhenAvailable,$MultipleInstances) return 'fixture-settings' }
function Register-ScheduledTask { [CmdletBinding()] param($TaskName,$Action,$Trigger,$Principal,$Settings,[switch]$Force) }
function Write-Done { param($Message) }
function Write-Info { param($Message) }
function Write-ReparoLog { param($Message) }
function Write-ReparoEventLog { param($EventId,$EntryType,$Message) }
function Complete-ReparoUtilityLog { param($Status) }
$tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
$temp=Join-Path $tempRoot ('reparo-worker-binding-'+[guid]::NewGuid().ToString('N'))
$previousOutput=$env:REPARO_BINDING_OUTPUT
$previousCleanup=$env:REPARO_BINDING_CLEANUP
$previousFail=$env:REPARO_BINDING_FAIL
try {
    New-Item -ItemType Directory -Path $temp | Out-Null
    $probeDirectory=Join-Path $temp "O'Brien & Steam"
    New-Item -ItemType Directory -Path $probeDirectory | Out-Null
    $script:ReparoBindingProbePath=Join-Path $probeDirectory 'probe.ps1'
    $body=@'
$received=[ordered]@{}
foreach ($key in $PSBoundParameters.Keys) {
    $value=$PSBoundParameters[$key]
    if ($value -is [Management.Automation.SwitchParameter]) { $value=[bool]$value }
    $received[$key]=$value
}
$received | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $env:REPARO_BINDING_OUTPUT -Encoding UTF8
if ($env:REPARO_BINDING_FAIL -eq '1') { exit 7 }
'@
    ('[CmdletBinding(PositionalBinding = $false)]'+[Environment]::NewLine+$ast.ParamBlock.Extent.Text+[Environment]::NewLine+$body) | Set-Content -LiteralPath $script:ReparoBindingProbePath -Encoding UTF8
    $stub=@'
function Unregister-ScheduledTask {
    [CmdletBinding()]
    param([string]$TaskName,[switch]$Confirm)
    Set-Content -LiteralPath $env:REPARO_BINDING_CLEANUP -Value $TaskName -Encoding UTF8
}
'@
    $script:ReparoIsWindows=$true
    $script:ReparoLogPath=Join-Path $temp 'fixture.log'
    $Time='5s'
    $script:ReparoBoundParameters=@{Include=@('Steam');Time='5s'}
    $script:ReparoIsWindows=$false
    $boundaryRejected=$false
    try { Invoke-ReparoSchedule | Out-Null } catch { if ($_.Exception.Message -match 'Windows only') { $boundaryRejected=$true } else { throw } }
    if (-not $boundaryRejected) { throw 'Native Linux scheduling boundary was not enforced' }
    $script:ReparoIsWindows=$true
    $cases=@(
        @{Name='SteamHeadless';Bound=@{Include=@('Steam');Headless=[Management.Automation.SwitchParameter]::new($true);Time='5s'};Fail=$false},
        @{Name='ArraysAndSwitches';Bound=@{Include=@('Steam','WindowsUpdate');Force=[Management.Automation.SwitchParameter]::new($true);AllowReboot=[Management.Automation.SwitchParameter]::new($false);Time='5s'};Fail=$false},
        @{Name='QuotedLiteral';Bound=@{Include=@('Steam');LogRoot="C:\O'Brien; Write-Error injected";Time='5s'};Fail=$false},
        @{Name='FailureAndCleanup';Bound=@{Include=@('Steam');Headless=[Management.Automation.SwitchParameter]::new($true);Time='5s'};Fail=$true}
    )
    foreach ($case in $cases) {
        $script:ReparoBoundParameters=$case.Bound
        $script:capturedAction=$null
        if (-not (Invoke-ReparoSchedule)) { throw 'One-shot registration did not complete' }
        if ($script:capturedAction -notmatch '-EncodedCommand\s+(?<Encoded>[A-Za-z0-9+/=]+)') { throw 'No encoded worker captured' }
        $worker=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($matches.Encoded))
        $workerTokens=$null; $workerErrors=$null
        $null=[Management.Automation.Language.Parser]::ParseInput($worker,[ref]$workerTokens,[ref]$workerErrors)
        if ($workerErrors.Count) { throw ($workerErrors | Out-String) }
        $workerPath=Join-Path $temp ($case.Name+'.ps1')
        ($stub+[Environment]::NewLine+$worker) | Set-Content -LiteralPath $workerPath -Encoding UTF8
        $env:REPARO_BINDING_OUTPUT=Join-Path $temp ($case.Name+'.json')
        $env:REPARO_BINDING_CLEANUP=Join-Path $temp ($case.Name+'.cleanup')
        $env:REPARO_BINDING_FAIL=if ($case.Fail) { '1' } else { '0' }
        $output=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $workerPath 2>&1
        $workerExit=$LASTEXITCODE
        if (($case.Fail -and $workerExit -eq 0) -or (-not $case.Fail -and $workerExit -ne 0)) { throw "$($case.Name): wrong worker exit $workerExit; $output" }
        $received=Get-Content -LiteralPath $env:REPARO_BINDING_OUTPUT -Raw | ConvertFrom-Json
        $receivedKeys=@($received.PSObject.Properties.Name)
        if ('Include' -notin $receivedKeys -or (@($received.Include) -join '|') -ne (@($case.Bound.Include) -join '|')) { throw "$($case.Name): named Include was lost: $($received | ConvertTo-Json -Compress)" }
        foreach ($control in @('Headless','Time','Task','RemainingInclude')) { if ($control -in $receivedKeys) { throw "$($case.Name): scheduling control $control leaked" } }
        if ($case.Bound.ContainsKey('Force') -and -not $received.Force) { throw 'True switch was lost' }
        if ($case.Bound.ContainsKey('AllowReboot') -and ('AllowReboot' -notin $receivedKeys -or $received.AllowReboot)) { throw 'Explicit false switch was lost' }
        if ($case.Bound.ContainsKey('LogRoot') -and $received.LogRoot -ne $case.Bound.LogRoot) { throw 'Quoted literal changed' }
        if (-not (Test-Path -LiteralPath $env:REPARO_BINDING_CLEANUP)) { throw "$($case.Name): worker cleanup did not run" }
        Write-Host "$($case.Name): named parameters, exit status, and cleanup passed."
    }
} finally {
    $env:REPARO_BINDING_OUTPUT=$previousOutput
    $env:REPARO_BINDING_CLEANUP=$previousCleanup
    $env:REPARO_BINDING_FAIL=$previousFail
    $resolved=[IO.Path]::GetFullPath($temp)
    if (-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'reparo-worker-binding-*') { throw 'Refusing unsafe fixture cleanup' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
