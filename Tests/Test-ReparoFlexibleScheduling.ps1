param([switch]$LiveProbe)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$source=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'Reparo.ps1') -Raw
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$blockedDefinition=$ast.Find({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$script:ReparoTaskBlockedParameters'},$true)
Invoke-Expression $blockedDefinition.Extent.Text
foreach ($name in @('Resolve-ReparoScheduledTime','Resolve-ReparoRecurrence','ConvertTo-ReparoPowerShellLiteral','Get-ReparoTaskRunParameters','New-ReparoTaskWorker','New-ReparoTaskXml')) {
    $node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    if (-not $node) { throw "Missing function $name" }; Invoke-Expression $node.Extent.Text
}
$fixtures=@(
    @('5am Mondays','Weekly','05:00:00'), @('Mondays at 17:30','Weekly','17:30:00'),
    @('5am First Monday','MonthlyWeek','05:00:00'), @('last Friday at 5pm','MonthlyWeek','17:00:00'),
    @('15th at 5am','Monthly','05:00:00'), @('monthly 1st,15th at 5am','Monthly','05:00:00'),
    @('daily 12am','Daily','00:00:00'), @('weekdays 5am,5pm','Weekly','05:00:00'),
    @('weekends at 23:59','Weekly','23:59:00'), @('last day of month at 5am','Monthly','05:00:00')
)
foreach ($f in $fixtures) {
    $r=Resolve-ReparoRecurrence -Value $f[0]
    if ($r.Kind -ne $f[1] -or $r.Times[0] -ne $f[2]) { throw "Wrong recurrence: $($f[0])" }
    [xml]$xml=New-ReparoTaskXml -Recurrence $r -Worker 'exit 0' -Executable 'C:\fixture&name\powershell.exe'
    if ($xml.Task.Settings.MultipleInstancesPolicy -ne 'IgnoreNew' -or $xml.Task.Principals.Principal.UserId -ne 'S-1-5-18') { throw 'Identity/overlap contract missing' }
}
$weekly=Resolve-ReparoRecurrence -Value 'weekdays at 5am,5pm'
if ($weekly.Days.Count -ne 5 -or $weekly.Times.Count -ne 2) { throw 'Multi-day/time selection failed' }
$hourly=Resolve-ReparoRecurrence -Value 'every 6 hours' -Start '2026-11-04T06:00:00'
[xml]$hourXml=New-ReparoTaskXml -Recurrence $hourly -Worker 'exit 0' -Executable 'powershell.exe'
if ($hourXml.Task.Triggers.TimeTrigger.Repetition.Interval -ne 'PT6H') { throw 'Anchored hourly recurrence missing' }
$daily=Resolve-ReparoRecurrence -Value 'every 2 days at 5am' -Start '2026-11-04T00:00:00'
[xml]$dayXml=New-ReparoTaskXml -Recurrence $daily -Worker 'exit 0' -Executable 'powershell.exe'
if ($dayXml.Task.Triggers.CalendarTrigger.ScheduleByDay.DaysInterval -ne '2') { throw 'Anchored daily recurrence missing' }
$legacy=Resolve-ReparoRecurrence -Value 'Hourly 12hr'
if ($legacy.Kind -ne 'Hours' -or $legacy.Interval -ne 12) { throw 'Legacy Hourly spelling lost' }
foreach ($bad in @('Mondays','25am Monday','32nd at 5am','fifth Monday 5am','every 2 days','5am Monday; exit 0','every 0 hours','tomorrow 5am','5am First Monday Tuesday')) {
    $rejected=$false; try { Resolve-ReparoRecurrence -Value $bad | Out-Null } catch { $rejected=$true }
    if (-not $rejected) { throw "Accepted ambiguous/unsafe recurrence: $bad" }
}
foreach ($bad in @('2026-11-04','2026-11-04T00:00:00Z','2026-02-30T00:00:00')) {
    $rejected=$false; try { Resolve-ReparoRecurrence -Value 'every 2 days' -Start $bad | Out-Null } catch { $rejected=$true }
    if (-not $rejected) { throw "Accepted invalid anchor: $bad" }
}
$bound=@{ Task=$true; TaskName='fixture'; Preview=$true; Force=$true; Include=@('Winget','WindowsUpdate'); LogRoot="C:\logs\O'Brien; Write-Error hacked"; AllowReboot=$false }
$run=Get-ReparoTaskRunParameters -BoundParameters $bound
if ($run.ContainsKey('Preview') -or $run.ContainsKey('Task') -or $run.Include.Count -ne 2) { throw 'Scheduling controls leaked or arrays lost' }
$worker=New-ReparoTaskWorker -RunParameters $run -ScriptPath "C:\O'Brien\Reparo.ps1"
$workerAst=[Management.Automation.Language.Parser]::ParseInput($worker,[ref]$tokens,[ref]$errors)
if ($errors.Count -or $worker -notmatch '@run') { throw 'Worker is not safely parsed/splatted' }
foreach ($blocked in @('New','Install','Ninja','Kill','FinalizeChocolateyRemoval','Syslog')) {
    $rejected=$false; try { Get-ReparoTaskRunParameters -BoundParameters @{ Task=$true; $blocked=$true } | Out-Null } catch { $rejected=$true }
    if (-not $rejected) { throw "Scheduled administrative mode accepted: $blocked" }
}
$runtimePath=Join-Path (Split-Path -Parent $PSScriptRoot) 'Reparo.ps1'
foreach ($arguments in @(@('-TaskName','guardprobe'),@('-Task','-Syslog','off','-Preview','daily 5am'))) {
    $ErrorActionPreference='Continue'
    try { $guardOutput=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runtimePath @arguments 2>&1 | Out-String }
    finally { $ErrorActionPreference='Stop' }
    if ($LASTEXITCODE -eq 0 -or $guardOutput -match 'REPARO starting|Failed to finalize') { throw 'Invalid scheduling controls did not fail cleanly before initialization' }
}
Write-Host 'Flexible scheduling parser, XML, anchors, quoting, arrays and blocked-mode tests passed.' -ForegroundColor Green
if ($LiveProbe) {
    # Disposable tasks execute only `exit 0`: no Reparo maintenance or power action.
    $name='Reparo-Managed-Probe-'+[guid]::NewGuid().ToString('N')
    $exe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    try {
        foreach ($value in @('daily 5am','Mondays at 5am','15th at 5am','last day of month at 5am','first Monday at 5am','last Monday at 5am','every 6 hours','every 2 days at 5am')) {
            $r=Resolve-ReparoRecurrence -Value $value -Start '2030-01-02T00:00:00'
            $taskXmlText=New-ReparoTaskXml -Recurrence $r -Worker 'exit 0' -Executable $exe
            Register-ScheduledTask -TaskName $name -Xml $taskXmlText -Force -ErrorAction Stop | Out-Null
        }
        Disable-ScheduledTask -TaskName $name -ErrorAction Stop | Out-Null
        if ((Get-ScheduledTask -TaskName $name).State -ne 'Disabled') { throw 'Disposable disable failed' }
        Enable-ScheduledTask -TaskName $name -ErrorAction Stop | Out-Null
        Start-ScheduledTask -TaskName $name -ErrorAction Stop
        $deadline=(Get-Date).AddSeconds(30)
        do { Start-Sleep -Milliseconds 250; $info=Get-ScheduledTaskInfo -TaskName $name } while (($info.LastRunTime.Year -lt 2026 -or (Get-ScheduledTask -TaskName $name).State -eq 'Running') -and (Get-Date) -lt $deadline)
        if ($info.LastRunTime.Year -lt 2026 -or $info.LastTaskResult -ne 0) { throw 'Disposable exit-zero worker did not finish successfully' }
        Write-Host 'Live Task Scheduler XML, enable/disable, no-maintenance execution and cleanup probe passed.' -ForegroundColor Green
    }
    finally { Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue }
    $cliName='CliProbe-'+[guid]::NewGuid().ToString('N')
    $runtimePath=Join-Path (Split-Path -Parent $PSScriptRoot) 'Reparo.ps1'
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runtimePath -Task 'daily 5am' -TaskName $cliName -TaskStart '2030-01-02T00:00:00' -Include __NoMaintenanceProbe
        if ($LASTEXITCODE -ne 0) { throw 'CLI scheduling creation failed' }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runtimePath -Task -TaskName $cliName -TaskAction Disable
        if ($LASTEXITCODE -ne 0 -or (Get-ScheduledTask -TaskName ('Reparo-Managed-'+$cliName)).State -ne 'Disabled') { throw 'CLI disable failed' }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runtimePath -Task -TaskName $cliName -TaskAction Enable
        if ($LASTEXITCODE -ne 0 -or (Get-ScheduledTask -TaskName ('Reparo-Managed-'+$cliName)).State -ne 'Ready') { throw 'CLI enable failed' }
        $shown=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runtimePath -Task -TaskName $cliName -TaskAction Show | Out-String
        if ($LASTEXITCODE -ne 0 -or $shown -notmatch 'CalendarTrigger') { throw 'CLI Show swallowed the task XML' }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runtimePath -Task -TaskName $cliName -TaskAction Remove
        if ($LASTEXITCODE -ne 0 -or (Get-ScheduledTask -TaskName ('Reparo-Managed-'+$cliName) -ErrorAction SilentlyContinue)) { throw 'CLI removal failed' }
        Write-Host 'Live CLI create/show/enable/disable/remove passed; future-only no-maintenance task removed.' -ForegroundColor Green
    }
    finally { Unregister-ScheduledTask -TaskName ('Reparo-Managed-'+$cliName) -Confirm:$false -ErrorAction SilentlyContinue }
}
