Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$isWindowsHost = $env:OS -eq 'Windows_NT'
if (-not $isWindowsHost) {
    Write-Host 'Reparo Windows ACL integration skipped on a non-Windows host.' -ForegroundColor Yellow
    return
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if ($identity.User.Value -ne 'S-1-5-18' -and -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'The Windows ACL integration test requires an Administrator or SYSTEM runner.'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$reparoPath = Join-Path $repoRoot 'Reparo.ps1'
$source = Get-Content -LiteralPath $reparoPath -Raw
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw "Reparo source does not parse: $($errors[0].Message)" }

foreach ($functionName in @(
    'Assert-ReparoWindowsPathHasNoReparsePoint',
    'Get-ReparoWindowsTreeItemsWithoutLinks',
    'Protect-ReparoWindowsPrivateDataRoot',
    'Protect-ReparoWindowsInstallRoot',
    'Copy-ReparoFileWithRetry'
)) {
    $name = $functionName
    $definition = $ast.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true)
    if (-not $definition) { throw "Windows security helper is missing: $functionName" }
    Invoke-Expression $definition.Extent.Text
}

$script:ReparoIsWindows = $true
$script:ReparoLogPath = $null
function Write-ReparoLog { param([string]$Message) }

$usersSid = 'S-1-5-32-545'
$administratorsSid = 'S-1-5-32-544'
$broadSids = @('S-1-1-0', 'S-1-5-11', $usersSid)
$writeMask = [Security.AccessControl.FileSystemRights]::WriteData -bor
    [Security.AccessControl.FileSystemRights]::AppendData -bor
    [Security.AccessControl.FileSystemRights]::WriteAttributes -bor
    [Security.AccessControl.FileSystemRights]::WriteExtendedAttributes -bor
    [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
    [Security.AccessControl.FileSystemRights]::Delete -bor
    [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
    [Security.AccessControl.FileSystemRights]::TakeOwnership

function Get-ReparoRuleSid {
    param([Parameter(Mandatory)]$Rule)
    $Rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
}

function Assert-ReparoNoBroadAllow {
    param([Parameter(Mandatory)][string]$Path)
    $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    foreach ($rule in @($acl.Access | Where-Object AccessControlType -eq 'Allow')) {
        $sid = Get-ReparoRuleSid -Rule $rule
        if ($sid -in $broadSids) { throw "Private Reparo data grants $sid access: $Path" }
    }
}

function Assert-ReparoUsersReadOnly {
    param([Parameter(Mandatory)][string]$Path)
    $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    $rules = @($acl.Access | Where-Object {
        $_.AccessControlType -eq 'Allow' -and (Get-ReparoRuleSid -Rule $_) -eq $usersSid
    })
    if (-not $rules) { throw "Reparo runtime is not readable by the built-in Users group: $Path" }
    $readAndExecute = [Security.AccessControl.FileSystemRights]::ReadAndExecute
    if (-not @($rules | Where-Object { ($_.FileSystemRights -band $readAndExecute) -eq $readAndExecute })) {
        throw "Reparo runtime lacks read-and-execute rights for built-in Users: $Path"
    }
    if (@($rules | Where-Object { ($_.FileSystemRights -band $writeMask) -ne 0 })) {
        throw "Reparo runtime remains writable by built-in Users: $Path"
    }
}

function Assert-ReparoAdministratorsOwner {
    param([Parameter(Mandatory)][string]$Path)
    $owner = (Get-Acl -LiteralPath $Path -ErrorAction Stop).GetOwner([Security.Principal.SecurityIdentifier]).Value
    if ($owner -ne $administratorsSid) { throw "Reparo path owner is $owner instead of built-in Administrators: $Path" }
}

$suffix = [guid]::NewGuid().ToString('N')
$fixtureRoot = Join-Path $env:ProgramData "Reparo-Acl-CI-$suffix"
$externalRoot = Join-Path $env:ProgramData "Reparo-Acl-CI-External-$suffix"
$rootJunction = Join-Path $env:ProgramData "Reparo-Acl-CI-Junction-$suffix"
$nestedJunction = $null
$testUserName = $null
$testUserSid = $null

try {
    New-Item -ItemType Directory -Path $fixtureRoot, $externalRoot -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'bin'), (Join-Path $fixtureRoot 'Logs'), (Join-Path $fixtureRoot 'Backups') -Force | Out-Null
    Copy-Item -LiteralPath $reparoPath -Destination (Join-Path $fixtureRoot 'Reparo.ps1') -Force
    Set-Content -LiteralPath (Join-Path $fixtureRoot 'bin/reparo.cmd') -Value '@echo off' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $fixtureRoot 'reparo-settings.json') -Value '{}' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $fixtureRoot 'winget-health.json') -Value '{}' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $fixtureRoot 'version-locks.json') -Value '[]' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $fixtureRoot 'Logs/run.log') -Value 'private-log' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $fixtureRoot 'Backups/old.ps1') -Value 'private-backup' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $externalRoot 'marker.txt') -Value 'outside' -Encoding ASCII

    # Seed a deliberately unsafe legacy ACL so the migration behavior is tested.
    foreach ($path in @($fixtureRoot, (Join-Path $fixtureRoot 'Logs'), (Join-Path $fixtureRoot 'Backups'))) {
        $acl = Get-Acl -LiteralPath $path
        $users = New-Object Security.Principal.SecurityIdentifier($usersSid)
        $inheritance = [Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit'
        $rule = New-Object Security.AccessControl.FileSystemAccessRule(
            $users,
            [Security.AccessControl.FileSystemRights]::FullControl,
            $inheritance,
            [Security.AccessControl.PropagationFlags]::None,
            [Security.AccessControl.AccessControlType]::Allow
        )
        $acl.AddAccessRule($rule)
        Set-Acl -LiteralPath $path -AclObject $acl
    }

    # A nested link must be rejected before the private tree's ACL is touched.
    $logs = Join-Path $fixtureRoot 'Logs'
    $nestedJunction = Join-Path $logs 'linked-outside'
    New-Item -ItemType Junction -Path $nestedJunction -Target $externalRoot | Out-Null
    $beforeSddl = (Get-Acl -LiteralPath $logs).GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::All)
    $failure = $null
    try { Protect-ReparoWindowsPrivateDataRoot -Path $logs }
    catch { $failure = $_.Exception.Message }
    if ($failure -notmatch 'reparse point') { throw "A nested private-data junction was not rejected: $failure" }
    $afterSddl = (Get-Acl -LiteralPath $logs).GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::All)
    if ($afterSddl -cne $beforeSddl) { throw 'Private-data ACL changed before nested reparse-point validation completed.' }
    [IO.Directory]::Delete($nestedJunction)
    $nestedJunction = $null
    if ((Get-Content -LiteralPath (Join-Path $externalRoot 'marker.txt') -Raw).Trim() -ne 'outside') {
        throw 'Junction cleanup altered the external target.'
    }

    Protect-ReparoWindowsInstallRoot -Path $fixtureRoot

    $rootAcl = Get-Acl -LiteralPath $fixtureRoot
    if (-not $rootAcl.AreAccessRulesProtected) { throw 'Reparo runtime ACL still inherits from ProgramData.' }
    foreach ($runtimePath in @(
        $fixtureRoot,
        (Join-Path $fixtureRoot 'Reparo.ps1'),
        (Join-Path $fixtureRoot 'bin'),
        (Join-Path $fixtureRoot 'bin/reparo.cmd'),
        (Join-Path $fixtureRoot 'reparo-settings.json'),
        (Join-Path $fixtureRoot 'winget-health.json'),
        (Join-Path $fixtureRoot 'version-locks.json')
    )) {
        Assert-ReparoUsersReadOnly -Path $runtimePath
        Assert-ReparoAdministratorsOwner -Path $runtimePath
    }

    foreach ($privatePath in @(
        (Join-Path $fixtureRoot 'Logs'),
        (Join-Path $fixtureRoot 'Logs/run.log'),
        (Join-Path $fixtureRoot 'Backups'),
        (Join-Path $fixtureRoot 'Backups/old.ps1')
    )) {
        Assert-ReparoNoBroadAllow -Path $privatePath
        Assert-ReparoAdministratorsOwner -Path $privatePath
    }

    # Exercise the installed runner through a real non-admin token. Reparo must
    # select that account's LocalAppData and the token must be unable to create
    # files in either the runtime root or the private machine log root.
    $testUserName = 'RprCi' + $suffix.Substring(0, 8)
    $testUserPassword = 'Rpr!9aA' + $suffix.Substring(8, 12)
    $net = Join-Path $env:SystemRoot 'System32/net.exe'
    $netOutput = @(& $net user $testUserName $testUserPassword /add /expires:never /passwordchg:no 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Unable to create ACL test user: $($netOutput -join ' ')" }
    $account = New-Object Security.Principal.NTAccount($env:COMPUTERNAME, $testUserName)
    $testUserSidObject = $account.Translate([Security.Principal.SecurityIdentifier])
    $testUserSid = $testUserSidObject.Value

    $resultRoot = Join-Path $externalRoot 'standard-user-result'
    New-Item -ItemType Directory -Path $resultRoot | Out-Null
    $resultAcl = Get-Acl -LiteralPath $resultRoot
    $resultRule = New-Object Security.AccessControl.FileSystemAccessRule(
        $testUserSidObject,
        [Security.AccessControl.FileSystemRights]::Modify,
        [Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
        [Security.AccessControl.PropagationFlags]::None,
        [Security.AccessControl.AccessControlType]::Allow
    )
    $resultAcl.AddAccessRule($resultRule)
    Set-Acl -LiteralPath $resultRoot -AclObject $resultAcl

    function ConvertTo-ReparoChildLiteral {
        param([Parameter(Mandatory)][string]$Value)
        "'" + $Value.Replace("'", "''") + "'"
    }
    $runtimeLiteral = ConvertTo-ReparoChildLiteral (Join-Path $fixtureRoot 'Reparo.ps1')
    $rootLiteral = ConvertTo-ReparoChildLiteral $fixtureRoot
    $machineLogsLiteral = ConvertTo-ReparoChildLiteral (Join-Path $fixtureRoot 'Logs')
    $childScript = @"
`$ErrorActionPreference = 'Stop'
try {
    `$runtime = $runtimeLiteral
    `$installRoot = $rootLiteral
    `$machineLogs = $machineLogsLiteral
    `$localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace(`$localAppData)) { throw 'LocalAppData is unavailable.' }
    `$localLogs = Join-Path (Join-Path `$localAppData 'Reparo') 'Logs'
    `$statusText = (@(& `$runtime -Status -InstallRoot `$installRoot 2>&1) | Out-String)
    if (`$statusText.IndexOf(('Log root: ' + `$localLogs), [StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw "Standard-user status did not report LocalAppData logging. Output: `$statusText"
    }
    if (-not (Test-Path -LiteralPath `$localLogs -PathType Container)) { throw 'Reparo did not create the LocalAppData log root.' }
    `$localProbe = Join-Path `$localLogs 'write-probe.txt'
    [IO.File]::WriteAllText(`$localProbe, 'local-user-write')
    Remove-Item -LiteralPath `$localProbe -Force
    foreach (`$protectedRoot in @(`$installRoot, `$machineLogs)) {
        `$blockedProbe = Join-Path `$protectedRoot 'unauthorized-write-probe.txt'
        `$blocked = `$false
        try { [IO.File]::WriteAllText(`$blockedProbe, 'must-not-write') }
        catch [UnauthorizedAccessException] { `$blocked = `$true }
        if (-not `$blocked -or (Test-Path -LiteralPath `$blockedProbe)) {
            Remove-Item -LiteralPath `$blockedProbe -Force -ErrorAction SilentlyContinue
            throw "Standard user could write protected Reparo path: `$protectedRoot"
        }
    }
    exit 0
}
catch {
    [Console]::Error.WriteLine(`$_.Exception.ToString())
    exit 1
}
"@
    $childTokens = $null
    $childErrors = $null
    [void][Management.Automation.Language.Parser]::ParseInput($childScript, [ref]$childTokens, [ref]$childErrors)
    if ($childErrors.Count) { throw "Standard-user child test does not parse: $($childErrors[0].Message)" }
    $encodedChild = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))
    $securePassword = ConvertTo-SecureString $testUserPassword -AsPlainText -Force
    $credential = New-Object Management.Automation.PSCredential(("$env:COMPUTERNAME\$testUserName"), $securePassword)
    $stdoutPath = Join-Path $resultRoot 'stdout.txt'
    $stderrPath = Join-Path $resultRoot 'stderr.txt'
    $windowsPowerShell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
    $child = Start-Process -FilePath $windowsPowerShell -Credential $credential -LoadUserProfile -WindowStyle Hidden `
        -WorkingDirectory $env:SystemRoot -ArgumentList @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encodedChild) `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -Wait -PassThru
    if ($child.ExitCode -ne 0) {
        $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw } else { '' }
        $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { '' }
        throw "Standard-user Reparo execution failed with exit $($child.ExitCode). stdout='$stdout' stderr='$stderr'"
    }
    foreach ($privateRoot in @((Join-Path $fixtureRoot 'Logs'), (Join-Path $fixtureRoot 'Backups'))) {
        if (-not (Get-Acl -LiteralPath $privateRoot).AreAccessRulesProtected) {
            throw "Private Reparo root still inherits runtime read access: $privateRoot"
        }
    }

    # Replacing a hard-linked destination must unlink it before copying so an
    # attacker cannot redirect a privileged update into another file.
    $outsideFile = Join-Path $externalRoot 'hardlink-source.txt'
    $replacement = Join-Path $externalRoot 'replacement.txt'
    $destination = Join-Path $fixtureRoot 'Reparo.ps1'
    Set-Content -LiteralPath $outsideFile -Value 'outside-original' -Encoding ASCII
    Set-Content -LiteralPath $replacement -Value 'replacement-runtime' -Encoding ASCII
    Remove-Item -LiteralPath $destination -Force
    New-Item -ItemType HardLink -Path $destination -Target $outsideFile | Out-Null
    Copy-ReparoFileWithRetry -Source $replacement -Destination $destination -Attempts 1 -DelayMilliseconds 0
    if ((Get-Content -LiteralPath $outsideFile -Raw).Trim() -ne 'outside-original') {
        throw 'Replacing a hard-linked runtime modified the external file.'
    }
    if ((Get-Content -LiteralPath $destination -Raw).Trim() -ne 'replacement-runtime') {
        throw 'Hard-linked runtime was not replaced with the reviewed source.'
    }
    Assert-ReparoUsersReadOnly -Path $destination

    # The install root itself cannot be a junction into another tree.
    New-Item -ItemType Junction -Path $rootJunction -Target $externalRoot | Out-Null
    $failure = $null
    try { Protect-ReparoWindowsInstallRoot -Path $rootJunction }
    catch { $failure = $_.Exception.Message }
    if ($failure -notmatch 'privileged installation through a reparse point') {
        throw "A junction install root was not rejected: $failure"
    }
    [IO.Directory]::Delete($rootJunction)
}
finally {
    foreach ($junction in @($nestedJunction, $rootJunction)) {
        if ($junction -and (Test-Path -LiteralPath $junction)) {
            try { [IO.Directory]::Delete($junction) } catch { }
        }
    }
    if ($testUserSid) {
        try {
            Get-CimInstance -ClassName Win32_UserProfile -Filter ("SID='{0}'" -f $testUserSid) -ErrorAction SilentlyContinue |
                Where-Object { -not $_.Loaded } |
                Remove-CimInstance -ErrorAction SilentlyContinue
        }
        catch { }
    }
    if ($testUserName) {
        try { & (Join-Path $env:SystemRoot 'System32/net.exe') user $testUserName /delete | Out-Null } catch { }
    }
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $externalRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'Reparo Windows ACL and link integration passed.' -ForegroundColor Green
