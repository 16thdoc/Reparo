Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$sourcePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Reparo.ps1'
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($sourcePath,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Reparo reporting source failed to parse.'}
$branch=$ast.Find({param($a) $a -is [Management.Automation.Language.IfStatementAst] -and $a.Extent.Text.StartsWith('if ($Install -or $New -or $Latest) {')},$true)
if(-not $branch){throw 'Outer lifecycle branch unavailable.'}
$script:ReportingFixtureCode=$branch.Extent.Text
$script:ReportingFixtureRecords=@()

function Invoke-ReportingFixture {
    param([string]$Failure,[switch]$PreviewOnly,[switch]$Unchanged)
    $Install=$Failure -ne 'manifest'; $New=-not $Install; $Latest=$false
    $Preview=[bool]$PreviewOnly; $NoBackup=$false; $SkipNinjaPublish=$false
    $InstallRoot=Join-Path $env:ProgramData 'Reparo'; $SourceUrl='fixture'; $PSCommandPath='fixture'
    $script:ReparoIsWindows=$true; $script:ReparoDeploymentChanged=$false
    $script:ReportingFixtureRecords=@()
    function Get-ReparoInstalledVersion { param($TargetRoot) '1.4.1.3' }
    function Write-Info { param($Message) }
    function Write-ReparoLog { param($Message) }
    function Invoke-RestMethod { throw 'fixture_manifest_failure' }
    function Invoke-ReparoNew {
        param($TargetRoot,$Url,[switch]$SkipBackup,[switch]$WhatIfOnly)
        if($Failure -eq 'replacement'){throw 'fixture_replacement_failure'}
        $script:ReparoDeploymentChanged=-not $Unchanged
    }
    function Publish-ReparoInstalledNinjaVersion { param($TargetRoot) if($Failure -eq 'publication'){throw 'fixture_publication_failure'} }
    function Install-ReparoSelfUpdateTask { param($TargetRoot) if($Failure -eq 'schedule'){throw 'fixture_schedule_failure'} }
    function Complete-ReparoUtilityLog { param($Status) if($Failure -eq 'finalization'){throw 'fixture_finalization_failure'} }
    function Invoke-ReparoLifecycleReporting {
        param($Method,$Outcome,$PreviousVersion)
        $script:ReportingFixtureRecords += [pscustomobject]@{Method=$Method;Outcome=$Outcome;Previous=$PreviousVersion}
    }
    $caught=$null
    try { & ([scriptblock]::Create($script:ReportingFixtureCode)) } catch { $caught=$_.Exception.Message }
    if($script:ReportingFixtureRecords.Count -ne 1){throw 'Outer lifecycle produced missing/duplicate/partial reports.'}
    if($Failure){
        if($script:ReportingFixtureRecords[0].Outcome -ne 'failed' -or $caught -notmatch 'fixture_'){throw 'Reporting replaced/lost the original deployment failure.'}
    } else {
        $expected=if($PreviewOnly){'preview'}elseif($Unchanged){'unchanged'}else{'succeeded'}
        if($caught -or $script:ReportingFixtureRecords[0].Outcome -ne $expected){throw "Wrong final reporting outcome: $expected"}
    }
}
Invoke-ReportingFixture
Invoke-ReportingFixture -PreviewOnly
Invoke-ReportingFixture -Unchanged
foreach($stage in @('manifest','replacement','publication','schedule','finalization')) { Invoke-ReportingFixture -Failure $stage }

$source=[IO.File]::ReadAllText($sourcePath)
foreach($required in @("`$env:REPARO_REPORT_SKIP = '1'",'WaitForExit(25000)','reporting-client.json','reparo-reporting-client-1','manifestSha256',"`$env:NODE_TLS_REJECT_UNAUTHORIZED='1'")) {
    if(-not $source.Contains($required)){throw "Missing bounded/protected reporting contract: $required"}
}
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('reparo-report-controls-'+[guid]::NewGuid())
try {
    foreach($args in @(
        @('-ReportingOutcome','succeeded'),
        @('-ReportLifecycle','-ReportingOutcome','succeeded','-Force'),
        @('-ReportLifecycle','-ReportingOutcome','succeeded','-Task')
    )) {
        $previousPreference=$ErrorActionPreference
        try { $ErrorActionPreference='Continue'; & powershell.exe -NoProfile -NonInteractive -File $sourcePath @args -LogRoot $testRoot 2>&1 | Out-Null; $code=$LASTEXITCODE }
        finally { $ErrorActionPreference=$previousPreference }
        if($code -eq 0){throw 'Invalid reporter controls did not reject before maintenance.'}
    }
    if(Test-Path -LiteralPath $testRoot){throw 'Invalid report controls initialized runtime state.'}
} finally { if(Test-Path -LiteralPath $testRoot){Remove-Item -LiteralPath $testRoot -Recurse -Force} }
Write-Host 'Reparo outer lifecycle reporting/failure/preview/control fixtures passed.' -ForegroundColor Green
