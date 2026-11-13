<# Public, independent protocol fixtures only. No private Slicer implementation is included. #>
[CmdletBinding()]
param([switch]$HelpersOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:rsSource=Join-Path (Split-Path -Parent $PSScriptRoot) 'Reparo.ps1'
$tokens=$null;$parseErrors=$null
$script:rsAst=[Management.Automation.Language.Parser]::ParseFile($script:rsSource,[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw 'Reparo Slicer source does not parse.'}
foreach($node in @($script:rsAst.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -like '*-ReparoSlicer*'},$true))){Invoke-Expression $node.Extent.Text}

function Assert-RS {
    param([bool]$Condition,[string]$Message)
    $script:rsChecks++
    if(-not $Condition){throw ('ASSERT FAILED: '+$Message)}
}
function Get-RSHash {
    param([byte[]]$Bytes)
    $hash=[Security.Cryptography.SHA256]::Create()
    try{([BitConverter]::ToString($hash.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}finally{$hash.Dispose()}
}
function New-RSReceipt {
    param([string]$Action='Status',[string]$Outcome='Status')
    [pscustomobject][ordered]@{SchemaVersion=1;Action=$Action;Outcome=$Outcome;Changed=$false;InstalledVersion=$null;DesiredVersion=$null;Currentness='Unknown';Integrity='Unknown';Trust='None';ArtifactSHA256=$null;RequiresElevation=$false;PlannedChanges=@();Rollback=[pscustomobject]@{Attempted=$false;Succeeded=$null;BackupPath=$null;PathRestored=$null};ErrorCode=$null;Message=$null;LocalChecks=$null}
}
function New-RSCase {
    param([string]$Name)
    $root=Join-Path $script:rsRoot $Name
    [void][IO.Directory]::CreateDirectory($root)
    # This independently authored owner merely echoes protocol values. It does
    # not implement or pretend to accept private runtime installation behavior.
    $protocol=@'
[CmdletBinding()]
param([string]$Action='Status',[string]$InstallRoot,[string]$PackageZip,[string]$PackagePath,[string]$ExpectedSHA256,[string]$ExpectedVersion,[string]$Version,[switch]$Preview,[switch]$Force,[switch]$Unattended,[switch]$NoPathUpdate,[string]$Format='Json')
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$outcome=if($Preview){'Preview'}elseif($Action -eq 'SelfTest'){'SelfTestPassed'}else{'Status'}
$receipt=[ordered]@{SchemaVersion=1;Action=$Action;Outcome=$outcome;Changed=$false;InstalledVersion=$null;DesiredVersion=$null;Currentness='Unknown';Integrity='Unknown';Trust='None';ArtifactSHA256=$null;RequiresElevation=$false;PlannedChanges=@();Rollback=@{Attempted=$false;Succeeded=$null;BackupPath=$null;PathRestored=$null};ErrorCode=$null;Message=$null;LocalChecks=$null;Fixture=@{InstallRoot=$InstallRoot;PackageZip=$PackageZip;PackagePath=$PackagePath;ExpectedSHA256=$ExpectedSHA256;ExpectedVersion=$ExpectedVersion;Force=[bool]$Force;Unattended=[bool]$Unattended;NoPathUpdate=[bool]$NoPathUpdate}}
$receipt|ConvertTo-Json -Depth 12 -Compress
exit 0
'@
    $files=[ordered]@{
        'Manage-Slicer.ps1'=[Text.Encoding]::UTF8.GetBytes($protocol.Replace("`r`n","`n"))
        'Slicer.Management.psm1'=[Text.Encoding]::UTF8.GetBytes("# Independent inert protocol fixture; no private owner code.`n")
        'Bootstrap-Slicer.ps1'=[Text.Encoding]::UTF8.GetBytes($protocol.Replace("`r`n","`n"))
    }
    $hashes=[ordered]@{};foreach($key in $files.Keys){$hashes[$key]=Get-RSHash $files[$key]}
    $script:rsCase=[pscustomobject]@{Root=$root;Cache=(Join-Path $root 'private cache');Install=(Join-Path $root "runtime O'Brien & spaced");Files=$files;Pins=[pscustomobject][ordered]@{Schema='reparo.slicer.owner.v1';Repository='16thdoc/Slicer';Commit=('1'*40);Version='0.2.4';ReceiptSchemaVersion=1;Files=$hashes};TokenCalls=0;Downloads=0;Processes=0;Token='synthetic-credential-never-log';DownloadFault='';Response=$null;Request=$null;UseRealProcess=$false;AssertLease=$false;LeaseBlocked=0;PrivateWrites=0}
    $script:rsCase
}
function Set-RSSeams {
    Set-Item Function:script:Get-ReparoSlicerPins -Value {$script:rsCase.Pins}
    Set-Item Function:script:Get-ReparoSlicerExistingToken -Value {$script:rsCase.TokenCalls++;$script:rsCase.Token}
    Set-Item Function:script:Invoke-ReparoSlicerOwnerDownload -Value {
        param($Name,$Destination,$Token,$Pins)
        $script:rsCase.Downloads++
        if($Token -cne $script:rsCase.Token){throw 'Fixture credential transport changed.'}
        $parent=[IO.Path]::GetDirectoryName($Destination)
        $acl=Get-Acl -LiteralPath $parent
        if(-not $acl.AreAccessRulesProtected){throw 'Private payload destination inherited public access.'}
        $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
        try{$allowed=@($identity.User.Value,'S-1-5-18','S-1-5-32-544')}finally{$identity.Dispose()}
        foreach($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){
            if($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and $rule.IdentityReference.Value -notin $allowed){throw 'Private payload ACL contains an unrelated allow identity.'}
        }
        $script:rsCase.PrivateWrites++
        if($script:rsCase.DownloadFault -eq 'throw' -and $script:rsCase.Downloads -eq 2){throw ('Authorization: '+$Token)}
        $bytes=$script:rsCase.Files[$Name]
        if($script:rsCase.DownloadFault -eq 'hash'){$bytes=[Text.Encoding]::UTF8.GetBytes('wrong synthetic bytes')}
        [IO.File]::WriteAllBytes($Destination,$bytes)
    }
    Set-Item Function:script:Invoke-ReparoSlicerOwnerProcess -Value {
        param($EntryPoint,$Parameters,$OwnerRoot,$Pins)
        $script:rsCase.Processes++
        $script:rsCase.Request=[pscustomobject]@{EntryPoint=$EntryPoint;Parameters=$Parameters;OwnerRoot=$OwnerRoot;Pins=$Pins}
        if($script:rsCase.AssertLease){
            foreach($file in @($script:rsCase.Files.Keys)+@('provenance.json')){
                $stream=$null
                try{$stream=[IO.File]::Open((Join-Path $OwnerRoot $file),[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::Read);throw 'Validated owner bytes were writable during execution.'}
                catch [IO.IOException]{$script:rsCase.LeaseBlocked++}
                finally{if($stream){$stream.Dispose()}}
            }
        }
        if($script:rsCase.UseRealProcess){return & $script:rsRealProcess -EntryPoint $EntryPoint -Parameters $Parameters -OwnerRoot $OwnerRoot -Pins $Pins}
        if($script:rsCase.Response){return $script:rsCase.Response}
        $action=$Parameters.Action
        $outcome=if($Parameters.ContainsKey('Preview') -and [bool]$Parameters.Preview){'Preview'}elseif($action -eq 'SelfTest'){'SelfTestPassed'}else{'Status'}
        $receipt=New-RSReceipt $action $outcome
        [pscustomobject]@{ExitCode=0;Output=($receipt|ConvertTo-Json -Depth 12 -Compress);Error=''}
    }
}
function Invoke-RS {
    param([string]$Action='Status',[hashtable]$Options=@{})
    $items=@(Invoke-ReparoSlicer -Action $Action -InstallRoot $script:rsCase.Install -OwnerCacheRoot $script:rsCase.Cache @Options)
    Assert-RS ($items.Count -eq 1 -and $items[0].PSObject.Properties['ExitCode'] -and $items[0].PSObject.Properties['Result']) 'Consumer must return exactly one explicit wrapper.'
    $items[0]
}
function Get-RSSnapshot {
    param([string]$Root)
    if(-not [IO.Directory]::Exists($Root)){return '<absent>'}
    @([IO.Directory]::GetFiles($Root,'*',[IO.SearchOption]::AllDirectories)|Sort-Object|ForEach-Object {$_+'|'+(Get-RSHash ([IO.File]::ReadAllBytes($_)))}) -join "`n"
}
function Test-RSBlocked {
    param($Result,[string]$Message)
    Assert-RS ($Result.ExitCode -ne 0 -and $Result.Result.AdapterSchema -eq 'reparo.slicer.adapter.v1' -and -not $Result.Result.PSObject.Properties['SchemaVersion']) $Message
}
function New-RSCliPrefix {
    param([string]$Path,[switch]$ArgumentSpy)
    $branch=@($script:rsAst.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.IfStatementAst] -and $_.Clauses[0].Item1.Extent.Text -eq '$Slicer' -and $_.Extent.Text.Contains('Invoke-ReparoSlicer')})
    if($branch.Count -ne 1){throw 'Actual early Slicer CLI branch is unavailable for safe extraction.'}
    $text=[IO.File]::ReadAllText($script:rsSource).Substring(0,$branch[0].Extent.EndOffset)
    $replacements=@{
        'Get-ReparoSlicerExistingToken'="function Get-ReparoSlicerExistingToken { throw 'FIXTURE_UNEXPECTED_AUTH' }"
        'Invoke-ReparoSlicerOwnerDownload'="function Invoke-ReparoSlicerOwnerDownload { throw 'FIXTURE_UNEXPECTED_NETWORK' }"
        'Invoke-ReparoSlicerOwnerProcess'="function Invoke-ReparoSlicerOwnerProcess { throw 'FIXTURE_UNEXPECTED_OWNER' }"
    }
    if($ArgumentSpy){$replacements['Invoke-ReparoSlicer']=@'
function Invoke-ReparoSlicer {
    param($Action,$InstallRoot,$OwnerCacheRoot,$PackageZip,$PackagePath,$ExpectedSHA256,$Version,[switch]$Preview,[switch]$Force,[switch]$Unattended,[switch]$NoPathUpdate)
    [pscustomobject]@{ExitCode=19;Result=[pscustomobject]@{Fixture='independent-argument-boundary';Action=$Action;InstallRoot=$InstallRoot;PackagePath=$PackagePath;Force=[bool]$Force;Preview=[bool]$Preview;Unattended=[bool]$Unattended;NoPathUpdate=[bool]$NoPathUpdate}}
}
'@}
    $nodes=@($script:rsAst.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$true)|Where-Object {$replacements.ContainsKey($_.Name) -and $_.Extent.EndOffset -le $branch[0].Extent.EndOffset}|Sort-Object {$_.Extent.StartOffset} -Descending)
    foreach($node in $nodes){$text=$text.Substring(0,$node.Extent.StartOffset)+$replacements[$node.Name]+$text.Substring($node.Extent.EndOffset)}
    # Normal initialization/maintenance is intentionally unreachable even if a
    # tested early guard regresses. This is a copied source fixture, never a
    # test-only production switch or a real maintenance invocation.
    $text+="`nthrow 'FIXTURE_SLICER_FALLTHROUGH'`n"
    [IO.File]::WriteAllText($Path,$text,(New-Object Text.UTF8Encoding($true)))
}
function Invoke-RSCli {
    param([string]$Source,[object[]]$Requests,[switch]$NegativeLoop)
    $data=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((@{Source=$Source;Requests=$Requests;NegativeLoop=[bool]$NegativeLoop}|ConvertTo-Json -Depth 12 -Compress)))
    $code=@'
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$request=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__DATA__'))|ConvertFrom-Json
$outcomes=@()
foreach($item in $request.Requests){
    $bound=@{};foreach($property in $item.PSObject.Properties){$bound[$property.Name]=$property.Value}
    if($request.NegativeLoop){
        try{& $request.Source @bound|Out-Null;$outcomes+=@{Caught=$false;Message='returned'}}
        catch{$outcomes+=@{Caught=$true;Message=$_.Exception.Message}}
    }else{& $request.Source @bound;exit $LASTEXITCODE}
}
$outcomes|ConvertTo-Json -Depth 8 -Compress
'@
    $code=$code.Replace('__DATA__',$data)
    $root=Join-Path $script:rsRoot 'cli environment'
    foreach($directory in @('home','home/local','home/roaming','temp','cache','gh')){[void][IO.Directory]::CreateDirectory((Join-Path $root $directory))}
    $engine=Join-Path $PSHOME $(if($PSVersionTable.PSEdition -eq 'Desktop'){'powershell.exe'}else{'pwsh.exe'})
    $start=New-Object Diagnostics.ProcessStartInfo;$start.FileName=$engine
    $start.Arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    foreach($entry in @{PSModulePath=(Join-Path $PSHOME 'Modules');USERPROFILE=(Join-Path $root 'home');HOME=(Join-Path $root 'home');LOCALAPPDATA=(Join-Path $root 'home/local');APPDATA=(Join-Path $root 'home/roaming');TEMP=(Join-Path $root 'temp');TMP=(Join-Path $root 'temp');PSModuleAnalysisCachePath=(Join-Path $root 'cache/ModuleAnalysisCache');GH_TOKEN='';GITHUB_TOKEN='';GH_CONFIG_DIR=(Join-Path $root 'gh');GH_PROMPT_DISABLED='1'}.GetEnumerator()){$start.EnvironmentVariables[$entry.Key]=[string]$entry.Value}
    $process=New-Object Diagnostics.Process;$process.StartInfo=$start;$started=$false;$complete=$false
    try{
        [void]$process.Start();$started=$true
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        if(-not $process.WaitForExit(90000) -or -not $stdout.Wait(5000) -or -not $stderr.Wait(5000)){$script:rsKeepFixture=$true;throw ('Owned early-CLI child '+$process.Id+' did not finish; fixture retained without retry or forced termination.')}
        $complete=$true
        [pscustomobject]@{ExitCode=$process.ExitCode;Output=$stdout.GetAwaiter().GetResult();Error=$stderr.GetAwaiter().GetResult()}
    }catch{if($started -and -not $complete){$script:rsKeepFixture=$true};throw}finally{$process.Dispose()}
}
function Remove-RSRoot {
    param([string]$Root)
    $full=[IO.Path]::GetFullPath($Root);$prefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if(-not $full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($full) -notmatch '^reparo-slicer-(unit|maintenance)-[a-f0-9]{32}$'){throw 'Unsafe Slicer fixture cleanup root.'}
    if([IO.Directory]::Exists($full)){Remove-Item -LiteralPath $full -Recurse -Force}
}
if($HelpersOnly){return}

$script:rsChecks=0
if(-not (Get-Command Invoke-ReparoSlicer -ErrorAction SilentlyContinue)){throw 'Inline Reparo Slicer implementation is not present yet.'}
$script:rsRealProcess=${function:Invoke-ReparoSlicerOwnerProcess}
$script:rsRoot=Join-Path ([IO.Path]::GetTempPath()) ('reparo-slicer-unit-'+[guid]::NewGuid().ToString('N'))
$savedEnv=@{};foreach($name in @('GH_TOKEN','GITHUB_TOKEN','GH_CONFIG_DIR','GH_PROMPT_DISABLED')){$savedEnv[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
$paths=@{};foreach($scope in @('Process','User','Machine')){$paths[$scope]=[Environment]::GetEnvironmentVariable('Path',$scope)}
$junction=$null
$script:rsKeepFixture=$false
try{
    [void][IO.Directory]::CreateDirectory($script:rsRoot)
    $env:GH_TOKEN='';$env:GITHUB_TOKEN='';$env:GH_CONFIG_DIR=Join-Path $script:rsRoot 'empty gh';$env:GH_PROMPT_DISABLED='1'
    $null=New-RSCase 'offline';Set-RSSeams
    $before=Get-RSSnapshot $script:rsRoot
    foreach($action in @('Check','Install','Update','Repair')){
        $r=Invoke-RS $action @{Preview=$true}
        Assert-RS ($r.ExitCode -eq 0 -and $r.Result.Outcome -eq 'Preview') 'Missing-owner Preview must produce a truthful plan.'
    }
    foreach($action in @('Status','SelfTest')){Test-RSBlocked (Invoke-RS $action) 'Offline action acquired missing private code or fabricated an owner receipt.'}
    Assert-RS ($script:rsCase.TokenCalls -eq 0 -and $script:rsCase.Downloads -eq 0 -and $script:rsCase.Processes -eq 0) 'Offline/Preview consulted acquisition or transport.'
    Assert-RS ((Get-RSSnapshot $script:rsRoot) -ceq $before) 'Offline/Preview created cache artifacts.'

    $null=New-RSCase 'verified';Set-RSSeams
    $r=Invoke-RS Check
    Assert-RS ($r.ExitCode -eq 0 -and $r.Result.SchemaVersion -eq 1 -and $r.Result.Action -ceq 'Status') 'Check lost the actual owner Status receipt.'
    Assert-RS ($script:rsCase.Downloads -eq 3 -and $script:rsCase.PrivateWrites -eq 3 -and $script:rsCase.TokenCalls -eq 1) 'Acquisition did not use one credential and three protected fixed files.'
    $names=@([IO.Directory]::GetFiles($script:rsCase.Cache)|ForEach-Object {[IO.Path]::GetFileName($_)}|Sort-Object)
    Assert-RS ($names.Count -eq 4 -and @(Compare-Object -ReferenceObject @('Bootstrap-Slicer.ps1','Manage-Slicer.ps1','Slicer.Management.psm1','provenance.json') -DifferenceObject $names -CaseSensitive).Count -eq 0) 'Published cache file set is not exact.'
    foreach($file in $script:rsCase.Files.Keys){Assert-RS ((Get-RSHash ([IO.File]::ReadAllBytes((Join-Path $script:rsCase.Cache $file)))) -ceq $script:rsCase.Pins.Files[$file]) 'Cache bytes differ from trusted synthetic pins.'}
    $snapshot=Get-RSSnapshot $script:rsCase.Cache
    $script:rsCase.AssertLease=$true
    foreach($action in @('Status','SelfTest')){$r=Invoke-RS $action;Assert-RS ($r.ExitCode -eq 0) 'Verified offline owner failed.'}
    Assert-RS ($script:rsCase.LeaseBlocked -eq 8) 'Validated source/provenance leases did not deny concurrent writes.'
    Assert-RS ($script:rsCase.TokenCalls -eq 1 -and $script:rsCase.Downloads -eq 3 -and (Get-RSSnapshot $script:rsCase.Cache) -ceq $snapshot) 'Verified offline actions reacquired or mutated private code.'
    $script:rsCase.AssertLease=$false

    $r=Invoke-RS 'uPdAtE' @{PackagePath=(Join-Path $script:rsCase.Root "candidate O'Brien & spaced");Force=$false;Unattended=$false;NoPathUpdate=$false;Preview=$true}
    Assert-RS ($r.ExitCode -eq 0 -and $script:rsCase.Request.Parameters.Action -ceq 'Update' -and -not [bool]$script:rsCase.Request.Parameters.Force -and -not [bool]$script:rsCase.Request.Parameters.NoPathUpdate) 'Argument mapping changed case, false flags or local routing.'
    Assert-RS ($script:rsCase.Request.EntryPoint -like '*Manage-Slicer.ps1') 'Local candidate did not select the canonical local owner.'

    $valid=New-RSReceipt
    foreach($bad in @(
        [pscustomobject]@{ExitCode=0;Output='not-json';Error=''},
        [pscustomobject]@{ExitCode=0;Output='';Error=''},
        [pscustomobject]@{ExitCode=0;Output=($valid|ConvertTo-Json -Depth 12 -Compress);Error='synthetic secret on error stream'},
        [pscustomobject]@{ExitCode=17;Output=($valid|ConvertTo-Json -Depth 12 -Compress);Error=''}
    )){$script:rsCase.Response=$bad;Test-RSBlocked (Invoke-RS Status) 'Malformed/error/exit-mismatched transport was accepted.'}
    foreach($schema in @($true,'1',1.5)){
        $bad=New-RSReceipt;$bad.SchemaVersion=$schema
        $script:rsCase.Response=[pscustomobject]@{ExitCode=0;Output=($bad|ConvertTo-Json -Depth 12 -Compress);Error=''}
        Test-RSBlocked (Invoke-RS Status) 'Receipt schema type was coerced.'
    }
    $bad=New-RSReceipt 'Install' 'Installed';$script:rsCase.Response=[pscustomobject]@{ExitCode=0;Output=($bad|ConvertTo-Json -Depth 12 -Compress);Error=''}
    Test-RSBlocked (Invoke-RS Status) 'Wrong action/outcome receipt was accepted.'
    $failure=New-RSReceipt 'Update' 'FailedRolledBack';$failure.Rollback.Attempted=$true;$failure.Rollback.Succeeded=$true;$failure.ErrorCode='SyntheticCopyFailure';$failure.Message='Synthetic rollback retained'
    $script:rsCase.Response=[pscustomobject]@{ExitCode=17;Output=($failure|ConvertTo-Json -Depth 12 -Compress);Error=''}
    $r=Invoke-RS Update @{PackagePath=(Join-Path $script:rsCase.Root 'rollback candidate')}
    Assert-RS ($r.ExitCode -eq 17 -and $r.Result.Outcome -eq 'FailedRolledBack' -and $r.Result.Rollback.Succeeded -and -not $r.Result.Changed) 'Failure exit/rollback truth was replaced with success.'
    $script:rsCase.Response=$null;$script:rsCase.UseRealProcess=$true
    $quoted=Join-Path $script:rsCase.Root "arg O'Brien & spaced"
    $r=Invoke-RS Status @{PackagePath=$quoted;NoPathUpdate=$true;Force=$false;Unattended=$true}
    Assert-RS ($r.ExitCode -eq 0 -and $r.Result.Fixture.PackagePath -ceq $quoted -and $r.Result.Fixture.NoPathUpdate -and -not $r.Result.Fixture.Force -and $r.Result.Fixture.Unattended) 'Real trusted-child protocol changed quoted arguments or boolean values.'

    $cli=Join-Path $script:rsRoot 'actual early CLI.ps1';New-RSCliPrefix $cli
    $unused=@(@{SlicerJson=$true},@{SlicerUnattended=$true},@{SlicerOwnerCacheRoot=(Join-Path $script:rsRoot 'unused cache')},@{Include=@('Npm');SlicerNoPathUpdate=$true})
    $native=Invoke-RSCli $cli $unused -NegativeLoop
    $parsedRejections=$native.Output|ConvertFrom-Json
    $rejected=@($parsedRejections)
    Assert-RS ($native.ExitCode -eq 0 -and [string]::IsNullOrWhiteSpace($native.Error) -and $rejected.Count -eq 4) 'Unused Slicer controls did not return four clean early guard failures.'
    foreach($item in $rejected){Assert-RS ($item.Caught -and $item.Message -match 'Slicer' -and $item.Message -notmatch 'FIXTURE_') 'Unused Slicer controls reached normal initialization/auth/maintenance.'}
    $cliRuntime=Join-Path $script:rsRoot "CLI O'Brien & runtime";$cliCache=Join-Path $script:rsRoot 'CLI missing owner'
    $native=Invoke-RSCli $cli @(@{Slicer='Update';SlicerInstallRoot=$cliRuntime;SlicerOwnerCacheRoot=$cliCache;Preview=$true;SlicerJson=$true;Force=$false;SlicerUnattended=$false;SlicerNoPathUpdate=$false})
    $plan=$native.Output|ConvertFrom-Json
    Assert-RS ($native.ExitCode -eq 0 -and [string]::IsNullOrWhiteSpace($native.Error) -and $plan.AdapterSchema -eq 'reparo.slicer.adapter.v1' -and $plan.Outcome -eq 'Preview' -and -not [IO.Directory]::Exists($cliCache) -and -not [IO.Directory]::Exists($cliRuntime)) 'Actual CLI Preview contaminated JSON or initialized a target.'
    $spy=Join-Path $script:rsRoot 'actual binding argument spy.ps1';New-RSCliPrefix $spy -ArgumentSpy
    $native=Invoke-RSCli $spy @(@{Slicer='Update';SlicerInstallRoot=$cliRuntime;SlicerOwnerCacheRoot=$cliCache;SlicerPackagePath=$quoted;SlicerJson=$true;Force=$false;SlicerUnattended=$true;SlicerNoPathUpdate=$false})
    $echo=$native.Output|ConvertFrom-Json
    Assert-RS ($native.ExitCode -eq 19 -and [string]::IsNullOrWhiteSpace($native.Error) -and $echo.Fixture -eq 'independent-argument-boundary' -and $echo.InstallRoot -ceq $cliRuntime -and $echo.PackagePath -ceq $quoted -and -not $echo.Force -and -not $echo.NoPathUpdate -and $echo.Unattended) 'Actual public parameter binding lost false flags, quoted values, pure JSON or exact exit.'

    foreach($fault in @('hash','throw')){
        $null=New-RSCase ('download-'+$fault);Set-RSSeams;$script:rsCase.DownloadFault=$fault
        $r=Invoke-RS Check
        Test-RSBlocked $r 'Faulted acquisition published executable private bytes.'
        Assert-RS ($script:rsCase.Processes -eq 0 -and -not [IO.Directory]::Exists($script:rsCase.Cache)) 'Partial acquisition executed or published its final cache.'
        Assert-RS (($r|ConvertTo-Json -Depth 14 -Compress) -notmatch [regex]::Escape($script:rsCase.Token)) 'Acquisition failure exposed the synthetic credential.'
    }
    $null=New-RSCase 'missing credential';Set-RSSeams;$script:rsCase.Token=$null
    Test-RSBlocked (Invoke-RS Check) 'Missing approved credentials were treated as successful acquisition.'
    Assert-RS ($script:rsCase.Downloads -eq 0 -and $script:rsCase.Processes -eq 0 -and -not [IO.Directory]::Exists($script:rsCase.Cache)) 'Missing credentials wrote private cache bytes.'
    foreach($fault in @('tampered','partial','provenance','provenance-boolean','provenance-hash-boolean','extra')){
        $null=New-RSCase ('cache-'+$fault);Set-RSSeams;$null=Invoke-RS Check
        switch($fault){
            'tampered'{[IO.File]::AppendAllText((Join-Path $script:rsCase.Cache 'Manage-Slicer.ps1'),'changed')}
            'partial'{[IO.File]::Delete((Join-Path $script:rsCase.Cache 'Bootstrap-Slicer.ps1'))}
            'provenance'{[IO.File]::WriteAllText((Join-Path $script:rsCase.Cache 'provenance.json'),'{}')}
            'provenance-boolean'{$p=Join-Path $script:rsCase.Cache 'provenance.json';$value=[IO.File]::ReadAllText($p)|ConvertFrom-Json;$value.ReceiptSchemaVersion=$true;[IO.File]::WriteAllText($p,($value|ConvertTo-Json -Depth 8))}
            'provenance-hash-boolean'{$p=Join-Path $script:rsCase.Cache 'provenance.json';$value=[IO.File]::ReadAllText($p)|ConvertFrom-Json;$value.Files.'Manage-Slicer.ps1'=$true;[IO.File]::WriteAllText($p,($value|ConvertTo-Json -Depth 8))}
            'extra'{[IO.File]::WriteAllText((Join-Path $script:rsCase.Cache 'unexpected.txt'),'extra')}
        }
        $before=Get-RSSnapshot $script:rsCase.Cache;$count=$script:rsCase.Processes
        Test-RSBlocked (Invoke-RS Update @{Force=$true}) 'Force accepted an unverified existing cache.'
        Assert-RS ($script:rsCase.Processes -eq $count -and (Get-RSSnapshot $script:rsCase.Cache) -ceq $before) 'Unverified cache was executed or silently repaired.'
    }
    foreach($suffix in @('.',' ')){
        $null=New-RSCase ('win32 alias '+[int][char]$suffix);Set-RSSeams
        $script:rsCase.Cache=$script:rsCase.Install+$suffix+'\private-owner'
        Test-RSBlocked (Invoke-RS Check) 'Win32 alias component bypassed cache/runtime isolation.'
        Assert-RS ($script:rsCase.Downloads -eq 0 -and $script:rsCase.TokenCalls -eq 0) 'Win32 alias refusal happened after acquisition.'
    }
    foreach($field in @('Schema','Repository','Commit','Version')){
        $null=New-RSCase ('provenance-type-'+$field);Set-RSSeams;$null=Invoke-RS Check
        $path=Join-Path $script:rsCase.Cache 'provenance.json';$value=[IO.File]::ReadAllText($path)|ConvertFrom-Json
        $value.$field=$true;[IO.File]::WriteAllText($path,($value|ConvertTo-Json -Depth 8))
        $count=$script:rsCase.Processes
        Test-RSBlocked (Invoke-RS Update @{Force=$true}) 'Boolean provenance string field was coerced into its compiled pin.'
        Assert-RS ($script:rsCase.Processes -eq $count) 'Malformed provenance reached owner execution.'
    }
    foreach($option in @(@{PackagePath=''},@{Version=''},@{ExpectedSHA256=''})){
        $null=New-RSCase ('empty-'+[guid]::NewGuid().ToString('N'));Set-RSSeams
        Test-RSBlocked (Invoke-RS Check $option) 'Explicit empty modifier silently selected online acquisition.'
        Assert-RS ($script:rsCase.TokenCalls -eq 0) 'Explicit empty modifier reached credential lookup.'
    }
    $null=New-RSCase 'candidate overlap';Set-RSSeams
    Test-RSBlocked (Invoke-RS Check @{PackagePath=$script:rsCase.Cache}) 'Candidate input overlapped the private executable cache.'
    Assert-RS ($script:rsCase.TokenCalls -eq 0) 'Candidate/cache overlap reached credential lookup.'
    $null=New-RSCase 'permissions';Set-RSSeams;$null=Invoke-RS Check
    # Positive private ACLs above are inspected on every real stage write.
    # This negative boundary avoids SACL/SeSecurityPrivilege requirements when
    # modifying an existing descriptor on a non-elevated host.
    $script:rsActualAcl=Get-Acl -LiteralPath $script:rsCase.Cache
    $script:rsUnprotectedAcl=[pscustomobject]@{AreAccessRulesProtected=$false}
    $script:rsUnprotectedAcl|Add-Member ScriptMethod GetOwner {param($type)$script:rsActualAcl.GetOwner($type)}
    $script:rsUnprotectedAcl|Add-Member ScriptMethod GetAccessRules {param($explicit,$inherited,$type)$script:rsActualAcl.GetAccessRules($explicit,$inherited,$type)}
    Set-Item Function:script:Get-Acl -Value {
        param([string]$LiteralPath)
        if($LiteralPath -ceq $script:rsCase.Cache){return $script:rsUnprotectedAcl}
        Microsoft.PowerShell.Security\Get-Acl -LiteralPath $LiteralPath
    }
    try{
        $count=$script:rsCase.Processes
        Test-RSBlocked (Invoke-RS Status) 'An unprotected cache ACL boundary was accepted.'
        Assert-RS ($script:rsCase.Processes -eq $count) 'Unprotected private cache reached execution.'
    }finally{Remove-Item Function:script:Get-Acl}
    $null=New-RSCase 'overlap';Set-RSSeams;$script:rsCase.Install=$script:rsCase.Cache
    Test-RSBlocked (Invoke-RS Check) 'Runtime and private cache overlap was accepted.'
    Assert-RS ($script:rsCase.TokenCalls -eq 0 -and $script:rsCase.Downloads -eq 0) 'Unsafe overlap reached credentials.'
    $null=New-RSCase 'git';Set-RSSeams;[void][IO.Directory]::CreateDirectory((Join-Path $script:rsCase.Root '.git'))
    Test-RSBlocked (Invoke-RS Check) 'Private payload cache was allowed inside a Git tree.'
    Assert-RS ($script:rsCase.Downloads -eq 0) 'Git-tree refusal happened after private bytes arrived.'
    $null=New-RSCase 'junction';Set-RSSeams;$target=Join-Path $script:rsCase.Root 'target';[void][IO.Directory]::CreateDirectory($target)
    $junction=$script:rsCase.Cache;$null=New-Item -ItemType Junction -Path $junction -Target $target
    Test-RSBlocked (Invoke-RS Check) 'Linked cache was accepted.'
    Assert-RS ($script:rsCase.Downloads -eq 0) 'Linked cache reached acquisition.'
    [IO.Directory]::Delete($junction);$junction=$null
    foreach($scope in $paths.Keys){Assert-RS ([Environment]::GetEnvironmentVariable('Path',$scope) -ceq $paths[$scope]) ($scope+' PATH changed.')}
    Write-Host ('PASS: '+$script:rsChecks+' isolated Reparo Slicer protocol/cache checks ('+$PSVersionTable.PSVersion+').')
    Write-Host 'LIMIT: independent synthetic owner protocol; no real private runtime, authentication, network, provider, production install or fleet acceptance.'
}finally{
    if($junction -and [IO.Directory]::Exists($junction)){[IO.Directory]::Delete($junction)}
    foreach($name in $savedEnv.Keys){[Environment]::SetEnvironmentVariable($name,$savedEnv[$name],'Process')}
    if(-not $script:rsKeepFixture){Remove-RSRoot $script:rsRoot}
}
