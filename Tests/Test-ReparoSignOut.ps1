param([string]$SourcePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'Reparo.ps1'))
# Isolated sign-out safety checks. The OS request boundary is always mocked;
# no maintenance, sign-out, power action, task registration or network access.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$source = Get-Content -LiteralPath $SourcePath -Raw
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
$script:checks = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
    $script:checks++
}

function Assert-Rejected {
    param([string]$Name, [scriptblock]$Action, [string]$Pattern = '.')
    $failure = $null
    try { & $Action | Out-Null } catch { $failure = $_ }
    if ($null -eq $failure) { throw "$Name was accepted" }
    if ($failure.Exception.Message -notmatch $Pattern) {
        throw "$Name failed for an unexpected reason: $($failure.Exception.Message)"
    }
    $script:checks++
}

function New-FixtureContext {
    param($SessionId = 7, $UserSid = 'S-1-5-21-111-222-333-1001', $Owners = @('S-1-5-21-111-222-333-1001'))
    [pscustomobject]@{ SessionId = $SessionId; UserSid = $UserSid; DesktopOwnerSids = @($Owners) }
}

$definitions = @{}
foreach ($name in @('Get-ReparoSignOutContext', 'Assert-ReparoSignOutContext', 'Invoke-ReparoSignOutRequest', 'Invoke-ReparoSignOut')) {
    $nodes = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true))
    if ($nodes.Count -ne 1) { throw "Expected one function $name; found $($nodes.Count)" }
    $definitions[$name] = $nodes[0]
}
# Never import the real native request function or native identity discovery.
Invoke-Expression $definitions['Assert-ReparoSignOutContext'].Extent.Text
Invoke-Expression $definitions['Invoke-ReparoSignOut'].Extent.Text

$script:events = New-Object 'System.Collections.Generic.List[string]'
$script:requestExit = 0
function Write-Info { param($Message) [void]$script:events.Add('info:' + $Message) }
function Write-Warning { param($Message) [void]$script:events.Add('warning:' + $Message) }
function Write-ReparoLog { param($Message) [void]$script:events.Add('log:' + $Message) }
function Write-ReparoEventLog { param($EventId, $EntryType, $Message) [void]$script:events.Add('event:' + $EventId) }
function Get-ReparoSignOutContext { [void]$script:events.Add('context'); return $script:currentContext }
function Invoke-ReparoSignOutRequest { [void]$script:events.Add('native-request'); return $script:requestExit }

$script:ReparoIsWindows = $true
$script:ReparoLogPath = 'fixture-finalized.log'
$mode = 'Force'
$valid = New-FixtureContext
Assert-ReparoSignOutContext -Context $valid | Out-Null
$script:checks++
Assert-ReparoSignOutContext -Context (New-FixtureContext -Owners @($valid.UserSid, $valid.UserSid)) | Out-Null
$script:checks++
$azure = New-FixtureContext -UserSid 'S-1-12-1-111-222-333-444' -Owners @('S-1-12-1-111-222-333-444')
Assert-ReparoSignOutContext -Context $azure | Out-Null
$script:checks++
Assert-ReparoSignOutContext -Context $valid -ExpectedContext $valid | Out-Null
$script:checks++

foreach ($badSession in @(0, -1)) {
    $context = New-FixtureContext -SessionId $badSession
    Assert-Rejected -Name "session $badSession" -Action { Assert-ReparoSignOutContext -Context $context }
}
foreach ($serviceSid in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20', 'S-1-5-80-1-2-3-4-5')) {
    $context = New-FixtureContext -UserSid $serviceSid -Owners @($serviceSid)
    Assert-Rejected -Name "service identity $serviceSid" -Action { Assert-ReparoSignOutContext -Context $context }
}
foreach ($owners in @(
    @{ Name = 'no desktop owner'; Values = @() },
    @{ Name = 'different desktop owner'; Values = @('S-1-5-21-111-222-333-1002') },
    @{ Name = 'ambiguous desktop owners'; Values = @($valid.UserSid, 'S-1-5-21-111-222-333-1002') }
)) {
    $context = New-FixtureContext -Owners $owners.Values
    Assert-Rejected -Name $owners.Name -Action { Assert-ReparoSignOutContext -Context $context }
}
$context = New-FixtureContext -UserSid '' -Owners @('')
Assert-Rejected -Name 'missing user identity' -Action { Assert-ReparoSignOutContext -Context $context }
Assert-Rejected -Name 'changed session during maintenance' -Action {
    Assert-ReparoSignOutContext -Context (New-FixtureContext -SessionId 8) -ExpectedContext $valid
}
Assert-Rejected -Name 'changed caller during maintenance' -Action {
    Assert-ReparoSignOutContext -Context (New-FixtureContext -UserSid 'S-1-5-21-111-222-333-1002' -Owners @('S-1-5-21-111-222-333-1002')) -ExpectedContext $valid
}
$script:ReparoIsWindows = $false
Assert-Rejected -Name 'native Linux context' -Action { Assert-ReparoSignOutContext -Context $valid }
$script:ReparoIsWindows = $true

$SignOut = $false
$Preview = $false
$script:ReparoSignOutContext = $valid
$script:currentContext = $valid
$script:events.Clear()
Invoke-ReparoSignOut | Out-Null
Assert-True -Condition ($script:events.Count -eq 0) -Message 'A run without SignOut queried or changed the user session'

$SignOut = $true
$Preview = $true
$script:events.Clear()
Invoke-ReparoSignOut | Out-Null
Assert-True -Condition (-not $script:events.Contains('native-request')) -Message 'Preview requested an actual sign-out'
Assert-True -Condition (($script:events -join "`n") -match '(?i)preview|would') -Message 'Preview did not describe its intended action'

$Preview = $false
$script:events.Clear()
Invoke-ReparoSignOut | Out-Null
Assert-True -Condition (@($script:events | Where-Object { $_ -eq 'native-request' }).Count -eq 1) -Message 'Valid caller did not make exactly one sign-out request'
Assert-True -Condition ($script:events.IndexOf('context') -lt $script:events.IndexOf('native-request')) -Message 'Session was not revalidated before sign-out'
Assert-True -Condition (@($script:events | Where-Object { $_ -like 'log:*' }).Count -gt 0) -Message 'Sign-out request has no durable log intent'

foreach ($previewCase in @($false, $true)) {
    $Preview = $previewCase
    $script:currentContext = New-FixtureContext -SessionId 8
    $script:events.Clear()
    Assert-Rejected -Name "changed session, Preview=$previewCase" -Action { Invoke-ReparoSignOut }
    Assert-True -Condition (-not $script:events.Contains('native-request')) -Message 'Changed caller session reached the native request'
}
$Preview = $false
$script:currentContext = $valid
$script:ReparoSignOutContext = $null
$script:events.Clear()
Assert-Rejected -Name 'missing initial session proof' -Action { Invoke-ReparoSignOut }
Assert-True -Condition (-not $script:events.Contains('native-request')) -Message 'Sign-out without an initial session proof reached the native request'
$script:ReparoSignOutContext = $valid
$script:requestExit = 5
$script:events.Clear()
Assert-Rejected -Name 'native sign-out failure' -Pattern '5' -Action { Invoke-ReparoSignOut }
Assert-True -Condition (@($script:events | Where-Object { $_ -eq 'native-request' }).Count -eq 1) -Message 'Native failure retried sign-out'

# Security boundary: the real helper must invoke only /l, using the Windows
# system executable rather than a session selector or PATH-discovered tool.
$native = $definitions['Invoke-ReparoSignOutRequest']
$nativeCalls = @($native.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] -and @($n.CommandElements | Where-Object { $_.Extent.Text -eq '/l' }).Count -gt 0 }, $true))
Assert-True -Condition ($nativeCalls.Count -eq 1) -Message 'Native request must make one /l invocation'
Assert-True -Condition ($nativeCalls[0].CommandElements.Count -eq 2) -Message 'Native sign-out request contains force, timeout, target or other extra arguments'
Assert-True -Condition ($native.Extent.Text -match '(?i)System32|SpecialFolder.*System|GetFolderPath\([^)]*System') -Message 'Native sign-out executable is not resolved from the Windows system directory'
$sessionSelectors = @($native.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -match '(?i)(^|[\\/])logoff(?:\.exe)?$' }, $true))
Assert-True -Condition ($sessionSelectors.Count -eq 0) -Message 'Native sign-out request can select another user session'

# Exercise only the early option guard together with the real parameter
# declarations. This probe cannot reach initialization or maintenance.
$guard = @($ast.EndBlock.Statements | Where-Object {
    $_ -is [Management.Automation.Language.IfStatementAst] -and $_.Clauses[0].Item1.Extent.Text -eq '$SignOut'
} | Sort-Object { $_.Extent.StartOffset } | Select-Object -First 1)
Assert-True -Condition ($guard.Count -eq 1 -and $guard[0].Extent.StartOffset -lt $definitions['Get-ReparoSignOutContext'].Extent.StartOffset) -Message 'Sign-out option guard does not run before initialization'
$probe = [scriptblock]::Create('[CmdletBinding(PositionalBinding = $false)]' + [Environment]::NewLine + $ast.ParamBlock.Extent.Text + [Environment]::NewLine + $guard[0].Extent.Text + [Environment]::NewLine + "'SIGNOUT_PARAMETER_PROBE_PASSED'")
foreach ($case in @(
    @{ Name = 'Headless'; Bound = @{ Force = $true; SignOut = $true; Headless = $true } },
    @{ Name = 'Task'; Bound = @{ Force = $true; SignOut = $true; Task = $true } },
    @{ Name = 'Time'; Bound = @{ Force = $true; SignOut = $true; Time = '5s' } },
    @{ Name = 'Reboot alias'; Bound = @{ Force = $true; SignOut = $true; Reboot = $true } },
    @{ Name = 'Shutdown alias'; Bound = @{ Force = $true; SignOut = $true; Shutdown = $true } },
    @{ Name = 'AllowRestart alias'; Bound = @{ Force = $true; SignOut = $true; AllowRestart = $true } },
    @{ Name = 'Install'; Bound = @{ SignOut = $true; Install = $true } },
    @{ Name = 'New'; Bound = @{ SignOut = $true; New = $true } },
    @{ Name = 'Latest'; Bound = @{ SignOut = $true; Latest = $true } },
    @{ Name = 'Ninja'; Bound = @{ SignOut = $true; Ninja = $true } },
    @{ Name = 'Status'; Bound = @{ SignOut = $true; Status = $true } },
    @{ Name = 'Kill'; Bound = @{ SignOut = $true; Kill = $true } },
    @{ Name = 'Sweep'; Bound = @{ SignOut = $true; Sweep = $true } },
    @{ Name = 'Search'; Bound = @{ SignOut = $true; Search = $true } },
    @{ Name = 'ListVersionLocks'; Bound = @{ SignOut = $true; ListVersionLocks = $true } },
    @{ Name = 'AddVersionLock'; Bound = @{ SignOut = $true; AddVersionLock = @('winget:fixture=1') } },
    @{ Name = 'CheckApp'; Bound = @{ SignOut = $true; CheckApp = 'fixture' } },
    @{ Name = 'LockApp'; Bound = @{ SignOut = $true; LockApp = 'fixture' } },
    @{ Name = 'WingetHealth'; Bound = @{ SignOut = $true; WingetHealth = $true } },
    @{ Name = 'WingetDiscover'; Bound = @{ SignOut = $true; WingetDiscover = $true } }
)) {
    $bound = $case.Bound
    Assert-Rejected -Name ("SignOut with " + $case.Name) -Pattern 'SignOut' -Action { & $probe @bound }
}
foreach ($bound in @(
    @{ Force = $true; SignOut = $true },
    @{ Force = $true; SignOut = $true; Preview = $true },
    @{ SignOut = $true; Help = $true },
    @{ SignOut = $true; Version = $true }
)) {
    Assert-True -Condition ((& $probe @bound) -contains 'SIGNOUT_PARAMETER_PROBE_PASSED') -Message 'Valid maintenance, preview or harmless help/version was rejected'
}
$blockedAssignment = $ast.Find({ param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$script:ReparoTaskBlockedParameters' }, $true)
if (-not $blockedAssignment) { throw 'Scheduled worker blocklist is absent' }
Invoke-Expression $blockedAssignment.Extent.Text
Assert-True -Condition ($script:ReparoTaskBlockedParameters -contains 'SignOut') -Message 'Persisted scheduled worker can carry SignOut into SYSTEM execution'

# Completion receipts must be written before requesting an action that can
# terminate Reparo itself. Inspect only actual top-level execution statements.
$completionNames = @('Finalize-ReparoLogFile', 'Write-ReparoRepairSummary', 'Write-ReparoNinjaMaintenanceActivity', 'Write-ReparoEventLog', 'Invoke-ReparoReporting', 'Invoke-ReparoSignOut')
$topCommands = @($ast.EndBlock.Statements | ForEach-Object {
    $statement = $_
    if ($statement -isnot [Management.Automation.Language.FunctionDefinitionAst]) {
        $statement.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -in $completionNames }, $false)
    }
})
$signOutCalls = @($topCommands | Where-Object { $_.GetCommandName() -eq 'Invoke-ReparoSignOut' })
Assert-True -Condition ($signOutCalls.Count -eq 1) -Message 'Expected one final maintenance sign-out dispatch'
$signOutOffset = $signOutCalls[0].Extent.StartOffset
foreach ($name in @('Finalize-ReparoLogFile', 'Write-ReparoRepairSummary', 'Write-ReparoNinjaMaintenanceActivity', 'Write-ReparoEventLog', 'Invoke-ReparoReporting')) {
    $lastCall = @($topCommands | Where-Object { $_.GetCommandName() -eq $name } | Sort-Object { $_.Extent.StartOffset } | Select-Object -Last 1)
    Assert-True -Condition ($lastCall.Count -eq 1 -and $lastCall[0].Extent.StartOffset -lt $signOutOffset) -Message "$name does not finish before sign-out dispatch"
}

# Run the actual CLI and maintenance-completion dispatch from a disposable
# source copy. Replace external boundaries before execution; the request stub
# verifies the real finalized log and repair JSON before recording its marker.
$runningOnWindows = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
if ($runningOnWindows) {
    $fixtureFunctions = @{
        'Get-ReparoSignOutContext' = @'
function Get-ReparoSignOutContext {
    [pscustomobject]@{ SessionId=7; UserSid='S-1-5-21-111-222-333-1001'; DesktopOwnerSids=@('S-1-5-21-111-222-333-1001') }
}
'@
        'Invoke-ReparoSignOutRequest' = @'
function Invoke-ReparoSignOutRequest {
    if ($script:ReparoLogPath -notmatch '_(COMPLETE|FAILED)\.log$' -or -not (Test-Path -LiteralPath $script:ReparoLogPath)) { throw 'Fixture request preceded log finalization' }
    $repairs = @(Get-ChildItem -LiteralPath $LogRoot -Filter '*_repair.json' -File)
    if ($repairs.Count -ne 1) { throw 'Fixture request preceded the repair receipt' }
    $repair = Get-Content -LiteralPath $repairs[0].FullName -Raw | ConvertFrom-Json
    if (-not $repair.parent.execution_finished) { throw 'Fixture request preceded finished maintenance' }
    $trace = @(Get-Content -LiteralPath $env:REPARO_SIGNOUT_FIXTURE_TRACE)
    if ($trace -notcontains 'ninja' -or $trace -notcontains 'event:1001' -or $trace -notcontains 'reporting:maintenance_summary') { throw 'Fixture request preceded completion reporting' }
    Add-Content -LiteralPath $env:REPARO_SIGNOUT_FIXTURE_TRACE -Value 'native-request'
    return [int]$env:REPARO_SIGNOUT_FIXTURE_EXIT
}
'@
        'Read-ReparoSettings' = 'function Read-ReparoSettings { [pscustomobject]@{} }'
        'Test-ReparoExecutable' = 'function Test-ReparoExecutable { param($Name,$Arguments) return $false }'
        'Test-ReparoSectionTool' = 'function Test-ReparoSectionTool { param($Section,$PresenceCmd) return $false }'
        'Get-ReparoToolCapability' = "function Get-ReparoToolCapability { param(`$Name) [pscustomobject]@{State='absent';Path=`$null;Reason='Fixture: executable absent'} }"
        'Test-ReparoPendingReboot' = 'function Test-ReparoPendingReboot { return $false }'
        'Invoke-ReparoTimedCommand' = "function Invoke-ReparoTimedCommand { throw 'Fixture attempted an actual maintenance command' }"
        'Write-ReparoEventLog' = @'
function Write-ReparoEventLog {
    param($EventId,$EntryType,$Message)
    Add-Content -LiteralPath $env:REPARO_SIGNOUT_FIXTURE_TRACE -Value ('event:' + $EventId)
}
'@
        'Write-ReparoNinjaMaintenanceActivity' = @'
function Write-ReparoNinjaMaintenanceActivity {
    param($Mode,$Status)
    Add-Content -LiteralPath $env:REPARO_SIGNOUT_FIXTURE_TRACE -Value 'ninja'
}
'@
        'Invoke-ReparoReporting' = @'
function Invoke-ReparoReporting {
    param($EventType,$Data)
    Add-Content -LiteralPath $env:REPARO_SIGNOUT_FIXTURE_TRACE -Value ('reporting:' + $EventType)
}
'@
        'Invoke-ReparoForcedReboot' = "function Invoke-ReparoForcedReboot { if (`$ForceReboot) { throw 'Fixture attempted an actual reboot' } }"
        'Invoke-ReparoForcedShutdown' = "function Invoke-ReparoForcedShutdown { if (`$ForceShutdown) { throw 'Fixture attempted an actual shutdown' } }"
    }
    $replacements = foreach ($name in $fixtureFunctions.Keys) {
        $node = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
        if (-not $node) { throw "Fixture boundary $name is absent" }
        [pscustomobject]@{ Offset=$node.Extent.StartOffset; Length=$node.Extent.EndOffset-$node.Extent.StartOffset; Text=$fixtureFunctions[$name] }
    }
    $fixtureSource = $source
    foreach ($replacement in @($replacements | Sort-Object Offset -Descending)) {
        $fixtureSource = $fixtureSource.Remove($replacement.Offset,$replacement.Length).Insert($replacement.Offset,$replacement.Text)
    }
    Assert-True -Condition (-not $fixtureSource.Contains($definitions['Invoke-ReparoSignOutRequest'].Extent.Text)) -Message 'CLI fixture retained the actual Windows sign-out helper'
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    $fixtureRoot = Join-Path $tempBase ('reparo-signout-test-' + [guid]::NewGuid().ToString('N'))
    $previousTrace = $env:REPARO_SIGNOUT_FIXTURE_TRACE
    $previousExit = $env:REPARO_SIGNOUT_FIXTURE_EXIT
    try {
        New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
        $fixturePath = Join-Path $fixtureRoot 'Reparo.fixture.ps1'
        Set-Content -LiteralPath $fixturePath -Value $fixtureSource -Encoding UTF8
        $enginePath = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        foreach ($case in @(
            @{Name='preview';Preview=$true;NativeExit=0;ExpectedExit=0},
            @{Name='live-request-stub';Preview=$false;NativeExit=0;ExpectedExit=0},
            @{Name='native-failure-stub';Preview=$false;NativeExit=5;ExpectedExit=1}
        )) {
            $caseRoot = Join-Path $fixtureRoot $case.Name
            New-Item -ItemType Directory -Path $caseRoot | Out-Null
            $caseLogs = Join-Path $caseRoot 'logs'
            $env:REPARO_SIGNOUT_FIXTURE_TRACE = Join-Path $caseRoot 'trace.txt'
            $env:REPARO_SIGNOUT_FIXTURE_EXIT = [string]$case.NativeExit
            $arguments = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$fixturePath,'-Include','Npm','-SignOut','-InstallRoot',(Join-Path $caseRoot 'install'),'-LogRoot',$caseLogs,'-VersionLockPath',(Join-Path $caseRoot 'version-locks.json'))
            if ($case.Preview) { $arguments += '-Preview' }
            $output = @(& $enginePath @arguments 2>&1)
            $exitCode = $LASTEXITCODE
            Assert-True -Condition ($exitCode -eq $case.ExpectedExit) -Message ("CLI fixture $($case.Name) exited $exitCode; output: " + ($output -join "`n"))
            $trace = @(Get-Content -LiteralPath $env:REPARO_SIGNOUT_FIXTURE_TRACE)
            $requests = @($trace | Where-Object { $_ -eq 'native-request' })
            if ($case.Preview) {
                Assert-True -Condition ($requests.Count -eq 0) -Message 'Real CLI preview reached the native request boundary'
                Assert-True -Condition (($output -join "`n") -match '(?i)Preview: would request Windows sign-out') -Message 'Real CLI preview lost the sign-out action'
            }
            else {
                Assert-True -Condition ($requests.Count -eq 1 -and $trace.IndexOf('reporting:maintenance_summary') -lt $trace.IndexOf('native-request')) -Message 'Real CLI sign-out dispatch or reporting order failed'
                Assert-True -Condition (@(Get-ChildItem -LiteralPath $caseLogs -Filter '*_COMPLETE.log' -File).Count -eq 1) -Message 'CLI action failure discarded or relabeled successful maintenance results'
                if ($case.NativeExit -ne 0) {
                    $finalLog = @(Get-ChildItem -LiteralPath $caseLogs -Filter '*_COMPLETE.log' -File)[0]
                    Assert-True -Condition ((Get-Content -LiteralPath $finalLog.FullName -Raw) -match '\[SIGNOUT-FAILED\].*exit code 5') -Message 'CLI native failure lacks a clear durable action receipt'
                }
            }
        }
    }
    finally {
        $env:REPARO_SIGNOUT_FIXTURE_TRACE = $previousTrace
        $env:REPARO_SIGNOUT_FIXTURE_EXIT = $previousExit
        $resolved = [IO.Path]::GetFullPath($fixtureRoot)
        if (-not $resolved.StartsWith($tempBase,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'reparo-signout-test-*') { throw 'Refusing unsafe sign-out fixture cleanup' }
        if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    }
}

# Verify the discovery query stays in the invoking process's session, using
# harmless process/CIM stubs and only the real current SID. No desktop is touched.
if ($runningOnWindows) {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try { $script:probeSid = $identity.User.Value } finally { $identity.Dispose() }
    $script:probeSession = 7
    $script:probeOwnerResult = 0
    $script:probeFilter = ''
    function Get-Process { [CmdletBinding()] param($Id) [pscustomobject]@{ SessionId = $script:probeSession } }
    function Get-CimInstance {
        [CmdletBinding()] param($ClassName, $Filter)
        if ($ClassName -ne 'Win32_Process') { throw 'Unexpected discovery class' }
        $script:probeFilter = $Filter
        [pscustomobject]@{ ProcessId = 1234 }
    }
    function Invoke-CimMethod {
        [CmdletBinding()] param($InputObject, $MethodName)
        if ($MethodName -ne 'GetOwnerSid') { throw 'Unexpected identity method' }
        [pscustomobject]@{ ReturnValue = $script:probeOwnerResult; Sid = $script:probeSid }
    }
    Invoke-Expression $definitions['Get-ReparoSignOutContext'].Extent.Text
    $discovered = Get-ReparoSignOutContext
    Assert-ReparoSignOutContext -Context $discovered | Out-Null
    Assert-True -Condition ($discovered.SessionId -eq 7 -and $discovered.UserSid -eq $script:probeSid) -Message 'Discovery changed the invoking identity'
    Assert-True -Condition ($script:probeFilter -match "(?i)Name\s*=\s*'explorer\.exe'\s+AND\s+SessionId\s*=\s*7\s*$") -Message 'Discovery can select a desktop outside the invoking session'
    $script:probeOwnerResult = 5
    Assert-Rejected -Name 'unverifiable desktop owner discovery' -Action { Get-ReparoSignOutContext }
    $script:probeSession = 0
    $script:probeFilter = ''
    Assert-Rejected -Name 'session-zero discovery' -Action { Get-ReparoSignOutContext }
    Assert-True -Condition ($script:probeFilter -eq '') -Message 'Session-zero caller queried a desktop owner'
}

Write-Host "Reparo sign-out identity, option boundaries, preview, native-request failure and completion-order checks passed ($script:checks assertions)." -ForegroundColor Green
