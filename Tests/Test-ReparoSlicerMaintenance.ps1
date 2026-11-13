# Independent section/ledger invariants; no package manager, private owner or task runs.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Test-ReparoSlicer.ps1') -HelpersOnly
$script:rsChecks=0
if(-not (Get-Command Invoke-ReparoSlicerMaintenance -ErrorAction SilentlyContinue)){throw 'Slicer maintenance implementation is not present yet.'}
foreach($name in @('Test-ReparoSectionSelected','Get-ReparoOutcomeLedger','Get-ReparoOutcomeId','Write-ReparoAtomicJson','Save-ReparoReceipt','Add-ReparoOutcome')){
    $node=$script:rsAst.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    if(-not $node){throw ('Maintenance fixture dependency missing: '+$name)}
    Invoke-Expression $node.Extent.Text
}
function Write-ReparoDebug {param($Message)}
function Write-ReparoLog {param($Message)}
function Write-Step {param($Message)}
function Write-Skip {param($Message)}
function Write-Fail {param($Message)}
function Add-ReparoSummaryRecord {
    param($Bucket,$Software,$CurrentVersion,$Version,$Method,$Reason,$PackageId)
    $script:rsSummary+=@([pscustomobject]@{Bucket=$Bucket;Software=$Software;CurrentVersion=$CurrentVersion;Version=$Version;Method=$Method;Reason=$Reason})
}
function Get-ReparoSlicerExistingToken {throw 'Maintenance fixture attempted real credential lookup.'}
function Invoke-ReparoSlicerOwnerDownload {throw 'Maintenance fixture attempted private acquisition.'}
function Invoke-ReparoSlicer {
    param($Action,$InstallRoot,$OwnerCacheRoot,$PackageZip,$PackagePath,$ExpectedSHA256,$Version,[switch]$Preview,[switch]$Force,[switch]$Unattended,[switch]$NoPathUpdate)
    $script:rsCalls+=@([pscustomobject]@{Action=$Action;InstallRoot=$InstallRoot;Preview=[bool]$Preview;Force=[bool]$Force;NoPathUpdate=[bool]$NoPathUpdate})
    if($script:rsScenario -in @('adapter-blocked','adapter-unknown')){
        $state=if($script:rsScenario -eq 'adapter-blocked'){'NotStarted'}else{'Unknown'}
        $receipt=[pscustomobject][ordered]@{AdapterSchema='reparo.slicer.adapter.v1';Component='Reparo.Slicer';Action='Update';Outcome=$(if($state -eq 'NotStarted'){'Blocked'}else{'Failed'});ErrorCode='CredentialsMissing';Message='Independent fixture access unavailable';InvocationState=$state;OwnerExitCode=$null}
        $script:rsReturned+=@($receipt)
        return [pscustomobject]@{ExitCode=1;Result=$receipt}
    }
    $receipt=New-RSReceipt $Action
    $receipt.InstalledVersion='0.2.4';$receipt.DesiredVersion='0.2.4';$receipt.Currentness='Current';$receipt.Integrity='Verified'
    if($Preview){$receipt.Outcome='Preview'}
    elseif($Action -eq 'Status'){
        if($script:rsScenario -eq 'updated'){$receipt.InstalledVersion='0.2.3';$receipt.Currentness='Outdated'}
        elseif($script:rsScenario -in @('repaired','rolled-back','unknown')){$receipt.Currentness='Drifted';$receipt.Integrity='Drifted'}
    }else{
        switch($script:rsScenario){
            'updated'{$receipt.Outcome='Updated';$receipt.Changed=$true}
            'current'{$receipt.Outcome='Current'}
            'repaired'{$receipt.Outcome='Repaired';$receipt.Changed=$true}
            'rolled-back'{$receipt.Outcome='FailedRolledBack';$receipt.ErrorCode='SyntheticCopyFailure';$receipt.Rollback.Attempted=$true;$receipt.Rollback.Succeeded=$true}
            'unknown'{$receipt.Outcome='FailedRollback';$receipt.Changed=$true;$receipt.ErrorCode='SyntheticRollbackFailure';$receipt.Rollback.Attempted=$true;$receipt.Rollback.Succeeded=$false}
        }
    }
    $code=if($receipt.Outcome -like 'Failed*'){17}else{0}
    $script:rsReturned+=@($receipt)
    [pscustomobject]@{ExitCode=$code;Result=$receipt}
}
function Initialize-RSMaintenance {
    param([string]$Name,[string]$Scenario='current',[switch]$Installed)
    $script:rsScenario=$Scenario;$script:rsCalls=@();$script:rsReturned=@();$script:rsSummary=@()
    $script:rsCaseRoot=Join-Path $script:rsRoot $Name
    $script:ReparoOutcomeLedger=$null
    Remove-Variable -Name ReparoOutcomeLedger -Scope Script -ErrorAction SilentlyContinue
    $script:ReparoVersion='0.0.0.0';$script:ReparoSourcePath=$script:rsSource
    # Atomic receipt writes append another GUID. Keep the synthetic run-id short
    # enough for Windows PowerShell's legacy path limit in nested owned fixtures.
    $script:ReparoLogBaseName='rs-'+[guid]::NewGuid().ToString('N').Substring(0,8)
    $script:LogRoot=Join-Path $script:rsCaseRoot 'logs';[void][IO.Directory]::CreateDirectory($script:LogRoot)
    $script:SlicerInstallRoot=Join-Path $script:rsCaseRoot 'installed'
    $script:SlicerOwnerCacheRoot=Join-Path $script:rsCaseRoot 'private cache'
    $script:SlicerVersion='0.2.4';$script:SlicerPackageZip=$null;$script:SlicerPackagePath=$null;$script:SlicerExpectedSHA256=$null
    $script:SlicerNoPathUpdate=$true;$script:SlicerUnattended=$true
    if($Installed){
        $version=if($Scenario -eq 'updated'){'0.2.3'}else{'0.2.4'}
        [void][IO.Directory]::CreateDirectory($script:SlicerInstallRoot)
        [IO.File]::WriteAllText((Join-Path $script:SlicerInstallRoot 'Slicer.psd1'),("@{RootModule='Slicer.psm1';ModuleVersion='"+$version+"'}"))
        [IO.File]::WriteAllText((Join-Path $script:SlicerInstallRoot 'Slicer.psm1'),'# Independent installed-identity fixture')
        [IO.File]::WriteAllText((Join-Path $script:SlicerInstallRoot 'Slicer.Release.json'),('{"Name":"Slicer","Version":"'+$version+'"}'))
    }
    $script:Include=@('Slicer');$script:Force=$false;$script:Update=$false;$script:WindowsUpdate=$false;$script:WindowsFeatureUpdate=$false
    $script:WslApt=$false;$script:MigrateChocoToWinget=$false;$script:FinalizeChocolateyRemoval=$false
    $script:Winget=$false;$script:WingetDiscover=$false;$script:Preview=$false
    $script:ReparoIsWindows=$true;$script:ReparoDebug=$false
}
$script:rsRoot=Join-Path ([IO.Path]::GetTempPath()) ('reparo-slicer-maintenance-'+[guid]::NewGuid().ToString('N'))
$paths=@{};foreach($scope in @('Process','User','Machine')){$paths[$scope]=[Environment]::GetEnvironmentVariable('Path',$scope)}
try{
    [void][IO.Directory]::CreateDirectory($script:rsRoot)
    Initialize-RSMaintenance 'selection'
    $Include=@();$Force=$false;$Update=$false
    Assert-RS (-not (Test-ReparoSectionSelected Slicer) -and (Test-ReparoSectionSelected WindowsUpdate)) 'Default maintenance must remain Windows Update only.'
    $Include=@('Slicer');Assert-RS (Test-ReparoSectionSelected Slicer) 'Explicit Include Slicer was not selected.'

    Initialize-RSMaintenance 'absent'
    Invoke-ReparoSlicerMaintenance
    Assert-RS ($script:rsCalls.Count -eq 0 -and -not [IO.Directory]::Exists($SlicerOwnerCacheRoot) -and -not [IO.Directory]::Exists($SlicerInstallRoot)) 'Normal maintenance installed/acquired an absent tool.'
    Initialize-RSMaintenance 'empty directory';[void][IO.Directory]::CreateDirectory($SlicerInstallRoot)
    Invoke-ReparoSlicerMaintenance
    Assert-RS ($script:rsCalls.Count -eq 0) 'An empty directory was mistaken for an installed Slicer identity.'
    foreach($identityFault in @('boolean-name','boolean-version','boolean-module','boolean-module-version')){
        Initialize-RSMaintenance $identityFault 'current' -Installed
        if($identityFault -eq 'boolean-name'){
            [IO.File]::WriteAllText((Join-Path $SlicerInstallRoot 'Slicer.Release.json'),'{"Name":true,"Version":"0.2.4"}')
        }elseif($identityFault -eq 'boolean-version'){
            [IO.File]::WriteAllText((Join-Path $SlicerInstallRoot 'Slicer.Release.json'),'{"Name":"Slicer","Version":true}')
        }elseif($identityFault -eq 'boolean-module'){
            [IO.File]::WriteAllText((Join-Path $SlicerInstallRoot 'Slicer.psd1'),'@{RootModule=$true;ModuleVersion=''0.2.4''}')
        }else{
            [IO.File]::WriteAllText((Join-Path $SlicerInstallRoot 'Slicer.psd1'),'@{RootModule=''Slicer.psm1'';ModuleVersion=$true}')
        }
        Invoke-ReparoSlicerMaintenance
        Assert-RS ($script:rsCalls.Count -eq 0 -and @($script:rsSummary|Where-Object {$_.Bucket -eq 'Failed'}).Count -eq 1) 'Boolean installed identity was coerced into a trusted runtime.'
    }

    foreach($scenario in @('updated','current','repaired','rolled-back','unknown')){
        Initialize-RSMaintenance $scenario $scenario -Installed
        Invoke-ReparoSlicerMaintenance
        Assert-RS ($script:rsCalls.Count -gt 0 -and @($script:rsCalls|Where-Object {$_.Action -eq 'Install'}).Count -eq 0) 'Installed-only maintenance entered the Install lane.'
        $ledger=Get-ReparoOutcomeLedger
        Assert-RS ($ledger.evidence_health -eq 'complete' -and $ledger.publication_errors.Count -eq 0) 'Owner/ledger receipts fell back instead of publishing in the owned log root.'
        $records=@($ledger.records.Values|Where-Object {$_.package -eq 'Slicer'})
        Assert-RS ($records.Count -gt 0) 'Dedicated Slicer maintenance omitted ledger evidence.'
        $receipts=@(Get-ChildItem -LiteralPath $LogRoot -Filter '*.json'|ForEach-Object {Get-Content -LiteralPath $_.FullName -Raw|ConvertFrom-Json}|Where-Object {$_.PSObject.Properties['SchemaVersion'] -and $_.SchemaVersion -eq 1})
        Assert-RS ($receipts.Count -gt 0) 'Original canonical owner receipt was not saved.'
        $last=$script:rsReturned[-1]
        Assert-RS (@($receipts|Where-Object {$_.Outcome -eq $last.Outcome -and $_.Action -eq $last.Action}).Count -gt 0) 'Saved owner receipt changed action/outcome.'
        if($scenario -eq 'current'){
            Assert-RS (@($script:rsSummary|Where-Object {$_.Bucket -eq 'Updated'}).Count -eq 0) 'Current no-op was reported as Updated.'
            Assert-RS (@($records|Where-Object {$_.delta.effect -match 'changed' -and $_.delta.effect -notmatch 'unchanged'}).Count -eq 0) 'Current no-op fabricated a changed effect.'
        }elseif($scenario -eq 'repaired'){
            Assert-RS (@($records|Where-Object {$_.delta.old -and $_.delta.new -and $_.delta.old -ne $_.delta.new}).Count -eq 0) 'Same-version repair fabricated a version delta.'
        }elseif($scenario -in @('rolled-back','unknown')){
            Assert-RS (@($script:rsSummary|Where-Object {$_.Bucket -eq 'Failed'}).Count -gt 0 -and @($records|Where-Object {$_.outcome -match 'fail|unknown|blocked'}).Count -gt 0) 'Rollback/uncertain failure was promoted to maintenance success.'
        }
    }
    Initialize-RSMaintenance 'preview' 'updated' -Installed;$Preview=$true;$Force=$true
    Invoke-ReparoSlicerMaintenance
    Assert-RS ($script:rsCalls.Count -eq 0) 'Force/Preview entered owner acquisition or execution.'
    Assert-RS (@($script:rsSummary|Where-Object {$_.Bucket -eq 'Updated'}).Count -eq 0) 'Preview claimed an update.'
    foreach($scenario in @('adapter-blocked','adapter-unknown')){
        Initialize-RSMaintenance $scenario $scenario -Installed
        Invoke-ReparoSlicerMaintenance
        $ledger=Get-ReparoOutcomeLedger
        Assert-RS ($ledger.evidence_health -eq 'complete' -and $ledger.publication_errors.Count -eq 0) 'Adapter evidence publication degraded.'
        $expected=if($scenario -eq 'adapter-blocked'){'blocked'}else{'unknown'}
        Assert-RS (@($ledger.records.Values|Where-Object {$_.package -eq 'Slicer' -and $_.outcome -eq $expected}).Count -eq 1) 'Adapter blocker/unknown truth was collapsed into a generic failure.'
        $saved=@(Get-ChildItem -LiteralPath $LogRoot -Filter '*.json'|ForEach-Object {Get-Content -LiteralPath $_.FullName -Raw|ConvertFrom-Json}|Where-Object {$_.PSObject.Properties['AdapterSchema']})
        Assert-RS ($saved.Count -eq 1 -and ($saved[0]|ConvertTo-Json -Depth 12 -Compress) -ceq ($script:rsReturned[-1]|ConvertTo-Json -Depth 12 -Compress)) 'Original adapter uncertainty receipt was changed or lost.'
    }
    Initialize-RSMaintenance 'normal force' 'current' -Installed;$Force=$true
    Invoke-ReparoSlicerMaintenance
    Assert-RS ($script:rsCalls.Count -eq 1 -and -not $script:rsCalls[0].Force -and $script:rsCalls[0].Action -eq 'Update') 'Normal Force escalated to owner Force or fresh Install.'
    foreach($scope in $paths.Keys){Assert-RS ([Environment]::GetEnvironmentVariable('Path',$scope) -ceq $paths[$scope]) ($scope+' PATH changed.')}
    Write-Host ('PASS: '+$script:rsChecks+' isolated installed-only Slicer maintenance/ledger checks ('+$PSVersionTable.PSVersion+').')
    Write-Host 'LIMIT: owner transport is an independent receipt fixture; actual private lifecycle acceptance is separate.'
}finally{Remove-RSRoot $script:rsRoot}
