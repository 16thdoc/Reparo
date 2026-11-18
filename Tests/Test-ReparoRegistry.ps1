# Disposable builtin-client fixtures. No live telemetry, installer, maintenance,
# machine task, network request or production identity is used by these tests.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$sourcePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Reparo.ps1'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Registry source does not parse.' }
foreach ($name in @('Assert-ReparoRegistryPrivatePath','Initialize-ReparoRegistryDirectory','Initialize-ReparoRegistryCreatedFileOwner','Write-ReparoRegistryState','Get-ReparoRegistryFacts','Send-ReparoRegistryReceipt','Invoke-ReparoRegistryWorker','Invoke-ReparoRegistryProcess','Invoke-ReparoRegistry','Get-ReparoRegistryMaintenance','Invoke-ReparoLifecycleReporting')) {
    $node = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $node) { throw "Missing registry function: $name" }
    Invoke-Expression $node.Extent.Text
}
function Assert-Fixture { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }
function Assert-Rejected { param([scriptblock]$Action, [string]$Message) $failed = $false; try { & $Action } catch { $failed = $true }; Assert-Fixture $failed $Message }
$originalFacts = ${function:Get-ReparoRegistryFacts}.ToString()
$testBase = Join-Path ([IO.Path]::GetTempPath()) ('reparo-registry-' + [guid]::NewGuid().ToString('N'))
$oldSkip = $env:REPARO_REPORT_SKIP; $oldDisable = $env:REPARO_REGISTRY_DISABLE
[void][IO.Directory]::CreateDirectory($testBase)
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$script:RegistrySent = @(); $script:RegistryFailSend = $true
$script:RegistryOwnerInjected = @{}; $script:RegistryOwnerSet = @{}; $script:RegistryUnsafeOwnerPath = $null
# Reproduce an elevated token's Administrators default owner without requiring
# elevation on the developer host. Real files/ACLs are used; only the first read
# of each newly-created file's owner is supplied as the elevated default. The
# production setter must explicitly select the current user's owner and persist
# it before the subsequent real ACL verification can succeed.
function Get-Acl {
    [CmdletBinding()]param([string]$LiteralPath)
    $acl = Microsoft.PowerShell.Security\Get-Acl -LiteralPath $LiteralPath -ErrorAction Stop
    $newFile = $LiteralPath -like '*.tmp' -or $LiteralPath -like '*\state.lock'
    if (($newFile -and -not $script:RegistryOwnerInjected.ContainsKey($LiteralPath)) -or $LiteralPath -eq $script:RegistryUnsafeOwnerPath) {
        $script:RegistryOwnerInjected[$LiteralPath] = $true
        $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
    }
    return $acl
}
function Set-Acl {
    [CmdletBinding()]param([string]$LiteralPath, [object]$AclObject)
    if ($LiteralPath -like '*.tmp' -or $LiteralPath -like '*\state.lock') {
        Assert-Fixture ($AclObject.GetOwner([Security.Principal.SecurityIdentifier]).Value -eq $sid) 'New user-state file did not explicitly select its owner.'
        $script:RegistryOwnerSet[$LiteralPath] = $true
    }
    Microsoft.PowerShell.Security\Set-Acl -LiteralPath $LiteralPath -AclObject $AclObject -ErrorAction Stop
}
function Send-ReparoRegistryReceipt {
    param($Receipt, $Secret, $TimeoutMilliseconds)
    Assert-Fixture ($Secret -cmatch '^[0-9a-f]{64}$') 'Per-install credential is not 256 random bits.'
    $script:RegistrySent += @($Receipt | ConvertTo-Json -Depth 14 -Compress | ConvertFrom-Json)
    if ($script:RegistryFailSend) { throw 'fixture_transport_outage' }
}
function Get-ReparoRegistryFacts {
    param($InputData, $State)
    [ordered]@{ machine_name = 'FIXTURE-DEVICE'; fqdn = 'fixture.example.invalid'; organization = $null; site = $null; asset_label = $null
        first_install_at = $State.first_install_at; first_install_source = $State.first_install_source
        installed_version = '1.2.3.4'; executed_version = '1.2.3.4'; source_sha256 = $State.source_sha256; source_commit = $State.source_commit
        os_family = 'windows'; os_edition = 'fixture'; os_version = '10.0'; os_build = '00000'; architecture = 'x64'
        domain_joined = $true; domain_name = 'example.invalid'; workgroup = $null; entra_joined = $null
        last_boot_at = $null; uptime_seconds = $null; pending_reboot = $null
        schedule = @{ supported = $true; enabled = $null; next_due = $null; last_result = $null }
        reporting = @{ status = 'automatic'; queued = @($State.queue).Count; retry_count = $State.retry_count; last_success_at = $State.last_success_at }
        volume = @{ free_bytes = $null; total_bytes = $null }; package_managers = @('winget') }
}
try {
    $inputData = [pscustomobject]@{ state_root = (Join-Path $testBase 'state'); policy_root = $testBase; machine = $false
        install_root = (Join-Path $testBase 'runtime'); executed_version = '1.2.3.4'; client_time = [DateTime]::UtcNow.ToString('o')
        event_type = 'update'; fresh_successful_install = $false; source_commit = ('a' * 40); source_sha256 = ('b' * 64)
        operation = @{ previous_version = '1.2.3.3'; current_version = '1.2.3.4'; outcome = 'succeeded'; attempted_at = [DateTime]::UtcNow.AddSeconds(-1).ToString('o'); duration_ms = 1000; failure_stage = $null; source = 'mirror'; maintenance = $null } }
    Invoke-ReparoRegistryWorker -InputData $inputData
    $path = Join-Path $inputData.state_root 'state.json'
    $state = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    Assert-Fixture ($state.installation_id -match '^[0-9a-f-]{36}$') 'Automatic identity missing.'
    Assert-Fixture ($null -eq $state.first_install_at) 'Existing installation received an invented first-install date.'
    Assert-Fixture (@($state.queue).Count -eq 1 -and $state.retry_count -eq 1) 'Outage lost the durable receipt.'
    Assert-ReparoRegistryPrivatePath -Path $inputData.state_root -AllowedSids @($sid) -Directory
    Assert-ReparoRegistryPrivatePath -Path $path -AllowedSids @($sid)
    Assert-Fixture ($script:RegistryOwnerSet.ContainsKey((Join-Path $inputData.state_root 'state.lock')) -and $script:RegistryOwnerSet.Count -ge 2) 'New lock/atomic state files relied on the token default owner.'
    $id = $state.installation_id; $secret = $state.secret; $event = $state.queue[0].event_id
    Invoke-ReparoRegistryWorker -InputData $inputData
    $state = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    Assert-Fixture ($state.installation_id -eq $id -and $state.secret -eq $secret) 'Retry regenerated the identity or credential.'
    Assert-Fixture ($script:RegistrySent[1].event_id -eq $event) 'Retry changed the original event ID.'
    $script:RegistryFailSend = $false
    Invoke-ReparoRegistryWorker -InputData $inputData
    $state = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    Assert-Fixture (@($state.queue).Count -eq 1 -and $state.retry_count -eq 0 -and $state.last_success_at) 'Recovery did not drain two receipts within its shared budget.'
    Assert-Fixture ($script:RegistrySent[2].event_id -eq $event) 'Recovered transport sent a different original event.'
    $script:RegistryFailSend = $true
    for ($i = 0; $i -lt 12; $i++) { Invoke-ReparoRegistryWorker -InputData $inputData }
    $state = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    Assert-Fixture (@($state.queue).Count -eq 8 -and (Get-Item -LiteralPath $path).Length -le 262144) 'Offline queue is unbounded.'
    $state.queue[0].client_time = [DateTime]::UtcNow.AddDays(-8).ToString('o')
    $expired = $state.queue[0].event_id
    Write-ReparoRegistryState -Path $path -State $state -AllowedSids @($sid)
    Invoke-ReparoRegistryWorker -InputData $inputData
    $state = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    Assert-Fixture (@($state.queue | Where-Object { $_.event_id -eq $expired }).Count -eq 0) 'Expired queued receipt was retained.'
    # The new-file owner setter must never become an existing-state ACL repair.
    foreach ($existing in @($path, (Join-Path $inputData.state_root 'state.lock'))) {
        $script:RegistryUnsafeOwnerPath = $existing
        $setCount = $script:RegistryOwnerSet.Count; $before = (Get-FileHash -LiteralPath $path).Hash
        Assert-Rejected { Invoke-ReparoRegistryWorker -InputData $inputData } 'Existing unsafe registry owner was accepted.'
        Assert-Fixture ($script:RegistryOwnerSet.Count -eq $setCount -and (Get-FileHash -LiteralPath $path).Hash -eq $before) 'Existing unsafe owner was silently repaired or state changed.'
        $script:RegistryUnsafeOwnerPath = $null
    }
    # Successful fresh installation records the completion time once. Repeated
    # updates or a mistaken future fresh flag cannot reset that recorded date.
    $inputData.state_root = Join-Path $testBase 'fresh'
    $inputData.event_type = 'install'; $inputData.fresh_successful_install = $true
    $first = $inputData.client_time
    Invoke-ReparoRegistryWorker -InputData $inputData
    $freshPath = Join-Path $inputData.state_root 'state.json'
    $state = Get-Content -LiteralPath $freshPath -Raw | ConvertFrom-Json
    Assert-Fixture ([DateTimeOffset]$state.first_install_at -eq [DateTimeOffset]$first -and $state.first_install_source -eq 'recorded-install') 'Fresh successful installation date missing.'
    $inputData.client_time = [DateTime]::UtcNow.AddSeconds(1).ToString('o')
    Invoke-ReparoRegistryWorker -InputData $inputData
    $state = Get-Content -LiteralPath $freshPath -Raw | ConvertFrom-Json
    Assert-Fixture ([DateTimeOffset]$state.first_install_at -eq [DateTimeOffset]$first) 'Update rewrote the original install date.'
    Assert-Fixture ($state.source_commit -eq ('a' * 40) -and $state.source_sha256 -eq ('b' * 64)) 'Validated installed source provenance lost.'
    $state.schema = 'unknown-future-format'
    Write-ReparoRegistryState -Path $freshPath -State $state -AllowedSids @($sid)
    $before = (Get-FileHash -LiteralPath $freshPath).Hash
    Invoke-ReparoRegistryWorker -InputData $inputData
    Assert-Fixture ((Get-FileHash -LiteralPath $freshPath).Hash -eq $before) 'Unknown state schema was overwritten.'
    # Existing broad-readable state must fail closed, without repairing access or
    # writing a secret into it. Likewise, state cannot escape its storage root.
    $unsafe = Join-Path $testBase 'unsafe'; [void][IO.Directory]::CreateDirectory($unsafe)
    Assert-Rejected { Initialize-ReparoRegistryDirectory -Root $unsafe -AllowedSids @($sid) -PolicyRoot $testBase } 'Inherited/broad directory was silently accepted.'
    Assert-Fixture (-not (Test-Path -LiteralPath (Join-Path $unsafe 'state.json'))) 'Unsafe state directory received credentials.'
    Assert-Rejected { Initialize-ReparoRegistryDirectory -Root $testBase -AllowedSids @($sid) -PolicyRoot $inputData.state_root } 'Registry storage escape accepted.'
    # Null/unknown remains distinct from zero/false in the maintenance contract.
    $summary = @{ Updated = @([pscustomobject]@{Method='Winget'}); Skipped = @([pscustomobject]@{Method='npm'}); Failed = @(); Pending = @([pscustomobject]@{Method='Winget'}) }
    $maintenance = Get-ReparoRegistryMaintenance -Summary $summary
    Assert-Fixture ($maintenance.updated -eq 1 -and $maintenance.skipped -eq 1 -and $maintenance.failed -eq 0 -and $maintenance.unknown -eq 1) 'Maintenance outcomes were conflated.'
    Assert-Fixture (@($maintenance.managers | Where-Object { $_.name -eq 'winget' -and $_.updated -eq 1 -and $_.unknown -eq 1 }).Count -eq 1) 'Per-manager maintenance result missing.'
    $typedSummary = @{}
    foreach ($bucket in @('Updated','Skipped','Failed','Pending')) {
        $list = New-Object 'System.Collections.Generic.List[object]'
        foreach ($record in $summary[$bucket]) { $list.Add($record) }
        $typedSummary[$bucket] = $list
    }
    $typedMaintenance = Get-ReparoRegistryMaintenance -Summary $typedSummary
    Assert-Fixture ($typedMaintenance.updated -eq 1 -and $typedMaintenance.unknown -eq 1) 'Actual List[object] summary shape failed optional reporting.'
    # Opt-out and fixture skip happen before state, identity, facts or processes.
    $script:ReparoIsWindows = $true; $Preview = $false
    $env:REPARO_REPORT_SKIP = '1'; $env:REPARO_REGISTRY_DISABLE = $null
    Invoke-ReparoRegistry -EventType run -Operation @{}
    $env:REPARO_REPORT_SKIP = $null; $env:REPARO_REGISTRY_DISABLE = '1'
    Invoke-ReparoRegistry -EventType run -Operation @{}
    $env:REPARO_REGISTRY_DISABLE = $null; $Preview = $true
    Invoke-ReparoRegistry -EventType run -Operation @{}
    # No InstallRoot was defined for these calls: proceeding beyond the guard
    # would hit strict mode. Ensure the source keeps version/help utility exits.
    $source = [IO.File]::ReadAllText($sourcePath)
    Assert-Fixture ($source.IndexOf('if ($Version) {') -lt $source.IndexOf('function Invoke-ReparoRegistry {')) 'Version utility starts registry reporting.'
    Assert-Fixture ($source.Contains("Get-ScheduledTask -TaskName 'Reparo-SelfUpdate-Tuesday-1000'")) 'Schedule probe uses a different task name from the installer.'
    Assert-Fixture (-not $originalFacts.Contains('InstallDate')) 'OS installation time is used as Reparo installation time.'
    Assert-Fixture (-not $originalFacts.Contains('Win32_UserAccount') -and -not $originalFacts.Contains('Win32_NetworkAdapter')) 'Unrequested user/hardware inventory entered discovery.'
    Assert-Fixture ($source.Contains("Create('https://file.thetechnologist.io/api/reparo/v1/report')") -and $source.Contains('$request.AllowAutoRedirect = $false')) 'Registry destination/redirect bound changed.'
    # The actual fact collector sees only synthetic WMI/task data. In particular,
    # OS InstallDate is deliberately a different date and never becomes Reparo's.
    $syntheticFacts = ${function:Get-ReparoRegistryFacts}.ToString()
    $factsResult = & {
        Set-Item -Path Function:\Get-ReparoRegistryFacts -Value ([scriptblock]::Create($originalFacts))
        function Get-CimInstance {
            param($ClassName,$Property,$OperationTimeoutSec,$ErrorAction)
            if ($ClassName -eq 'Win32_ComputerSystem') { [pscustomobject]@{ DNSHostName='TEST-PC';Domain='example.invalid';PartOfDomain=$true;Workgroup=$null } }
            elseif ($ClassName -eq 'Win32_OperatingSystem') { [pscustomobject]@{ Caption='Windows fixture';Version='10.0.12345';BuildNumber='12345';LastBootUpTime=[DateTime]::UtcNow.AddHours(-2);InstallDate=[DateTime]'2001-01-01' } }
            else { throw 'Unexpected WMI collection.' }
        }
        function Get-ScheduledTask { param($TaskName,$ErrorAction) Assert-Fixture ($TaskName -eq 'Reparo-SelfUpdate-Tuesday-1000') 'Wrong task name.'; [pscustomobject]@{ Settings=[pscustomobject]@{Enabled=$true} } }
        function Get-ScheduledTaskInfo { param($InputObject,$ErrorAction) [pscustomobject]@{ NextRunTime=[DateTime]::UtcNow.AddDays(1);LastTaskResult=0 } }
        function Get-Command { param($Name,$CommandType,$ErrorAction) if($Name -eq 'winget'){[pscustomobject]@{Name='winget'}} }
        function Test-Path {
            param($LiteralPath,$PathType,$ErrorAction)
            if ($LiteralPath -like '*\dsregcmd.exe') { return $false }
            if ($LiteralPath -like 'HKLM:*') { return $false }
            Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath
        }
        $runtime = Join-Path $testBase 'runtime'; [void][IO.Directory]::CreateDirectory($runtime)
        $runtimePath = Join-Path $runtime 'Reparo.ps1'
        [IO.File]::WriteAllText($runtimePath, "`$script:ReparoVersion = '1.2.3.4'`n")
        $fakeState = [pscustomobject]@{ first_install_at=$null;first_install_source=$null;queue=@();retry_count=0;last_success_at=$null;source_sha256=(Get-FileHash -LiteralPath $runtimePath).Hash.ToLowerInvariant();source_commit=('c'*40) }
        $facts = Get-ReparoRegistryFacts -InputData ([pscustomobject]@{install_root=$runtime;executed_version='1.2.3.3';machine=$false}) -State $fakeState
        Assert-Fixture ($facts.machine_name -eq 'TEST-PC' -and $facts.fqdn -eq 'TEST-PC.example.invalid' -and $facts.domain_joined -eq $true) 'Machine/domain discovery lost its source facts.'
        Assert-Fixture ($facts.entra_joined -eq $null -and $facts.pending_reboot -eq $false -and $facts.first_install_at -eq $null) 'Unsupported Entra/date became invented data.'
        Assert-Fixture ($facts.os_build -eq '12345' -and $facts.installed_version -eq '1.2.3.4' -and $facts.executed_version -eq '1.2.3.3') 'Installed/executed/OS versions were conflated.'
        Assert-Fixture ($facts.source_commit -eq ('c'*40) -and $facts.uptime_seconds -ge 7190 -and $facts.schedule.enabled -eq $true) 'Hash provenance, boot or task discovery missing.'
        Assert-Fixture (@($facts.package_managers).Count -eq 1 -and $facts.package_managers[0] -eq 'winget') 'Manager discovery executed or invented tools.'
        $fakeState.source_sha256 = 'd'*64
        $changed = Get-ReparoRegistryFacts -InputData ([pscustomobject]@{install_root=$runtime;executed_version='1.2.3.3';machine=$false}) -State $fakeState
        Assert-Fixture ($changed.source_commit -eq $null) 'Installed hash mismatch retained a claimed source commit.'
        $facts
    }
    Set-Item -Path Function:\Get-ReparoRegistryFacts -Value ([scriptblock]::Create($syntheticFacts))
    # Run the same stdin bootstrap used in production with a synthetic facts
    # collector and a throwing sender. This exercises child serialization/ACLs
    # without letting the test discover this host or open a network connection.
    $inputData.state_root = Join-Path $testBase 'child'; $inputData.fresh_successful_install = $false
    $inputData.client_time = [DateTime]::UtcNow.ToString('o')
    $names = @('Assert-ReparoRegistryPrivatePath','Initialize-ReparoRegistryDirectory','Initialize-ReparoRegistryCreatedFileOwner','Write-ReparoRegistryState','Get-ReparoRegistryFacts','Invoke-ReparoRegistryWorker')
    $defs = @($names | ForEach-Object { 'function ' + $_ + ' {' + (Get-Item ('Function:\' + $_)).Definition + "`n}" }) -join "`n"
    $encodedInput = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($inputData | ConvertTo-Json -Depth 14 -Compress)))
    $worker = "`$env:PSModulePath=([Environment]::GetEnvironmentVariable('PSModulePath','Machine')+';'+(Join-Path `$PSHOME 'Modules'))`n" + $defs + "`nfunction Send-ReparoRegistryReceipt { param(`$Receipt,`$Secret) throw 'fixture_no_network' }`nInvoke-ReparoRegistryWorker -InputData ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encodedInput')) | ConvertFrom-Json)"
    $bootstrap = '$code=[Console]::In.ReadToEnd(); & ([scriptblock]::Create($code))'
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $start.Arguments = '-NoProfile -NonInteractive -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($bootstrap))
    $start.UseShellExecute=$false; $start.CreateNoWindow=$true; $start.RedirectStandardInput=$true; $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
    $child = New-Object Diagnostics.Process; $child.StartInfo = $start
    try {
        [void]$child.Start(); $outTask=$child.StandardOutput.ReadToEndAsync(); $errTask=$child.StandardError.ReadToEndAsync()
        $child.StandardInput.Write($worker); $child.StandardInput.Close()
        if (-not $child.WaitForExit(10000)) { $child.Kill(); throw 'Fixture worker exceeded the process bound.' }
        Assert-Fixture ($child.ExitCode -eq 0) ('Fixture worker failed: ' + $errTask.GetAwaiter().GetResult())
    } finally { $child.Dispose() }
    $childState = Get-Content -LiteralPath (Join-Path $inputData.state_root 'state.json') -Raw | ConvertFrom-Json
    Assert-Fixture (@($childState.queue).Count -eq 1 -and $childState.queue[0].facts.machine_name -eq 'FIXTURE-DEVICE') 'Actual child lost its synthetic receipt.'
    # A hung child which never reads stdin must not bypass the total deadline.
    # Kill only the process tree created by this fixture, then verify its exit.
    $pidFile = Join-Path $testBase 'hung-child.pid'
    $sleepCode = "[IO.File]::WriteAllText('" + $pidFile.Replace("'", "''") + "',[string]`$PID); Start-Sleep -Seconds 30"
    $hungStart = New-Object Diagnostics.ProcessStartInfo
    $hungStart.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $hungStart.Arguments = '-NoProfile -NonInteractive -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($sleepCode))
    $hungStart.UseShellExecute=$false; $hungStart.CreateNoWindow=$true; $hungStart.RedirectStandardInput=$true; $hungStart.RedirectStandardOutput=$true; $hungStart.RedirectStandardError=$true
    $hungClock = [Diagnostics.Stopwatch]::StartNew()
    Assert-Rejected { Invoke-ReparoRegistryProcess -StartInfo $hungStart -Worker ('x' * 1048576) -TimeoutMilliseconds 1500 } 'Nonreading registry worker did not hit its input deadline.'
    Assert-Fixture ($hungClock.ElapsedMilliseconds -lt 5000) 'Stdin write escaped the reporting deadline.'
    Assert-Fixture (Test-Path -LiteralPath $pidFile) 'Hung-reader fixture did not start.'
    $hungProcessId = [int][IO.File]::ReadAllText($pidFile)
    Assert-Fixture ($null -eq (Get-Process -Id $hungProcessId -ErrorAction SilentlyContinue)) 'Timed-out owned worker remained running.'
    # Exercise the fallback when the tree-kill helper exits unsuccessfully.
    # This test-local function replaces only taskkill with inert cmd /c exit 1;
    # the sleeper still must be killed and observed through its owned handle.
    $processBody = ${function:Invoke-ReparoRegistryProcess}.ToString()
    $fakeKillerBody = $processBody.Replace("'System32\taskkill.exe'", "'System32\cmd.exe'").Replace("'/PID ' + `$process.Id + ' /T /F'", "'/c exit 1'")
    Assert-Fixture ($fakeKillerBody -ne $processBody -and $fakeKillerBody.Contains("'/c exit 1'")) 'Failed-helper fixture did not replace the tree-kill command.'
    try {
        Set-Item -Path Function:\Invoke-ReparoRegistryProcess -Value ([scriptblock]::Create($fakeKillerBody))
        Remove-Item -LiteralPath $pidFile -Force
        Assert-Rejected { Invoke-ReparoRegistryProcess -StartInfo $hungStart -Worker ('x' * 1048576) -TimeoutMilliseconds 1500 } 'Failed tree-kill helper bypassed the input deadline.'
        Assert-Fixture (Test-Path -LiteralPath $pidFile) 'Failed-helper sleeper did not start.'
        $hungProcessId = [int][IO.File]::ReadAllText($pidFile)
        Assert-Fixture ($null -eq (Get-Process -Id $hungProcessId -ErrorAction SilentlyContinue)) 'Nonzero tree-kill helper left the owned worker running.'
    } finally { Set-Item -Path Function:\Invoke-ReparoRegistryProcess -Value ([scriptblock]::Create($processBody)) }
    Write-Host 'Automatic Windows registry identity, private state, first-install provenance, retry IDs, bounded queue, opt-outs and maintenance fixtures passed.' -ForegroundColor Green
} finally {
    $env:REPARO_REPORT_SKIP = $oldSkip; $env:REPARO_REGISTRY_DISABLE = $oldDisable
    $resolved = [IO.Path]::GetFullPath($testBase)
    if (-not $resolved.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'reparo-registry-*') { throw 'Unsafe registry fixture cleanup.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
