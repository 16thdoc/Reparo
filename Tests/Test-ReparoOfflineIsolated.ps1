# Real CLI install/rollback/preview/status in a disposable source copy. Only
# machine integration boundaries are replaced: PATH, schedules, telemetry/events
# and Ninja. The installed host runtime is never a target or source of state.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$sourcePath=Join-Path $repo Reparo.ps1
$source=Get-Content -LiteralPath $sourcePath -Raw
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$null,[ref]$null)
$root=Join-Path ([IO.Path]::GetTempPath()) ('reparo-offline-isolated-'+[guid]::NewGuid().ToString('N'))
$old=$env:REPARO_INSTALL_FIXTURE
[void][IO.Directory]::CreateDirectory($root)
$env:REPARO_INSTALL_FIXTURE=$root
try {
    $replacements=@{
        'Install-ReparoCommandShim'=@'
function Install-ReparoCommandShim {
    param($TargetRoot,[switch]$WhatIfOnly)
    if(-not [IO.Path]::GetFullPath($TargetRoot).StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture install escaped temporary root.'}
    if(-not $WhatIfOnly){[void][IO.Directory]::CreateDirectory((Join-Path $TargetRoot bin));[IO.File]::WriteAllText((Join-Path $TargetRoot 'bin/reparo.cmd'),'@echo off')}
}
'@
        'Install-ReparoSelfUpdateTask'='function Install-ReparoSelfUpdateTask { param($TargetRoot,[switch]$WhatIfOnly) throw ''Fixture attempted scheduler mutation.'' }'
        'Publish-ReparoInstalledNinjaVersion'='function Publish-ReparoInstalledNinjaVersion { param($TargetRoot) return $false }'
        'Invoke-ReparoReporting'='function Invoke-ReparoReporting { param($EventType,$Data) }'
        'Write-ReparoEventLog'='function Write-ReparoEventLog { param($EventId,$EntryType,$Message) }'
        'Get-ReparoRunningProcessInfo'='function Get-ReparoRunningProcessInfo { param($ExcludeProcessIds) return @() }'
        'Get-ReparoPendingRebootEvidence'='function Get-ReparoPendingRebootEvidence { return @() }'
        'Get-ReparoStaleRunningLog'='function Get-ReparoStaleRunningLog { param($RunningProcessInfo) return @() }'
    }
    $nodes=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$true)|Where-Object {$replacements.ContainsKey($_.Name)}|Sort-Object {$_.Extent.StartOffset} -Descending)
    foreach($node in $nodes){$source=$source.Substring(0,$node.Extent.StartOffset)+$replacements[$node.Name]+$source.Substring($node.Extent.EndOffset)}
    $fixtureSource=Join-Path $root Reparo.fixture.ps1
    [IO.File]::WriteAllText($fixtureSource,$source,[Text.UTF8Encoding]::new($true))
    $test=Get-Content -LiteralPath (Join-Path $PSScriptRoot Test-ReparoNewTransaction.ps1) -Raw
    $assignment='$sourcePath = Join-Path $repoRoot ''Reparo.ps1'''
    if(-not $test.Contains($assignment)){throw 'Offline fixture source binding changed; review adaptation.'}
    $test=$test.Replace($assignment,('$sourcePath = '''+$fixtureSource.Replace("'","''")+''''))
    $test=$test.Replace('$repoRoot = Split-Path -Parent $PSScriptRoot',('$repoRoot = '''+$repo.Replace("'","''")+''''))
    foreach($scope in 'User','Machine'){
        $line='    [Environment]::SetEnvironmentVariable(''Path'', $original'+$scope+'Path, '''+$scope+''')'
        if(-not $test.Contains($line)){throw 'Original fixture PATH restoration changed; review adaptation.'}
        $test=$test.Replace($line,'    # PATH integration is mocked; no persistent PATH was written or restored.')
    }
    & ([scriptblock]::Create($test))
    # The same instrumented CLI exercises BOTH end-of-run views and the reader's
    # early-return path with no package executables in the preview lane.
    $runtime=Join-Path $root smoke-runtime
    $logs=Join-Path $root smoke-logs
    $output=& powershell.exe -NoProfile -File $fixtureSource -Preview -Include Npm -InstallRoot $runtime -LogRoot $logs 2>&1|Out-String
    if($LASTEXITCODE -ne 0 -or $output -notmatch 'REPARO-REPAIR-HANDOFF/1'){throw "Actual CLI failed summary integration: $output"}
    $receipt=Get-ChildItem -LiteralPath $logs -Filter '*_repair.json'|Select-Object -First 1
    if(-not $receipt){throw 'Actual CLI did not publish a repair receipt.'}
    $before=(Get-FileHash -LiteralPath $receipt.FullName).Hash
    $status=& powershell.exe -NoProfile -File $fixtureSource -Status -InstallRoot $runtime -LogRoot $logs 2>&1|Out-String
    if($LASTEXITCODE -ne 0 -or $status -notmatch 'REPARO-REPAIR-HANDOFF/1' -or $status -match 'Saved repair receipt unavailable'){throw "Actual status failed receipt reader: $status"}
    if((Get-FileHash -LiteralPath $receipt.FullName).Hash -ne $before){throw 'Status rewrote the original parent snapshot.'}
    Write-Host 'Isolated canonical offline transaction, rollback, real preview summaries and read-only status passed; host integration boundaries mocked.'
} finally {
    $env:REPARO_INSTALL_FIXTURE=$old
    $resolved=[IO.Path]::GetFullPath($root)
    if(-not $resolved.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'reparo-offline-isolated-*'){throw 'Unsafe fixture cleanup.'}
    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
}
