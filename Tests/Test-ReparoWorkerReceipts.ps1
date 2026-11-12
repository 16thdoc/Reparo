# Execute the actual generated worker after substituting ONLY its package command
# with a harmless known-exit child. No Explorer token or package manager launch.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$source=Join-Path (Split-Path -Parent $PSScriptRoot) Reparo.ps1
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$null,[ref]$null)
foreach($name in @('ConvertTo-ReparoSafeFileName','ConvertTo-ReparoPowerShellLiteral','Get-ReparoOutcomeLedger','Get-ReparoOutcomeId','Write-ReparoAtomicJson','Save-ReparoReceipt','Add-ReparoOutcome','ConvertFrom-ReparoCapturedBytes','Invoke-ReparoTimedCommand','Start-ReparoProcessWithExplorerToken','New-ReparoWingetWorkerScript')){
    $node=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    Invoke-Expression $node.Extent.Text
}
$script:ReparoVersion='1.4.4.8'
$root=Join-Path ([IO.Path]::GetTempPath()) ('reparo-worker-receipts-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
try {
    foreach($case in 'known-exit','wrong-owner','parent-deadline','denied-final'){
        $dir=Join-Path $root $case;[void][IO.Directory]::CreateDirectory($dir)
        $status=Join-Path $dir status.json;$fallback=Join-Path $dir fallback.json
        if($case -eq 'denied-final'){[void][IO.Directory]::CreateDirectory($status)}
        $parent=if($case -eq 'parent-deadline'){$PID}else{0}
        $created=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')
        $worker=New-ReparoWingetWorkerScript -Id Fixture.Package -Source winget -WorkerId fixture-worker -StatusPath $status -FallbackPath $fallback -WorkerRoot (Join-Path $dir fixture) -ParentId $parent -ParentCreatedUtc $created -WaitSeconds 1
        $command="[Console]::Out.WriteLine('known child executed'); exit 37"
        $generated=[Management.Automation.Language.Parser]::ParseInput($worker,[ref]$null,[ref]$null)
        $assignment=@($generated.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -eq '$settings'})
        if($assignment.Count -ne 1){throw 'Generated worker settings boundary is ambiguous.'}
        $literal=$assignment[0].Find({param($n)$n -is [Management.Automation.Language.StringConstantExpressionAst] -and $n.Value.StartsWith('{')},$true)
        if(-not $literal){throw 'Generated worker settings JSON not found.'}
        $settings=$literal.Value|ConvertFrom-Json
        $settings.Command=$command
        if($case -eq 'wrong-owner'){$settings.ExpectedSid='S-1-5-0'}
        $safeLiteral=ConvertTo-ReparoPowerShellLiteral ($settings|ConvertTo-Json -Compress)
        $worker=$worker.Substring(0,$literal.Extent.StartOffset)+$safeLiteral+$worker.Substring($literal.Extent.EndOffset)
        # This guard is mandatory before writing or launching a fixture script.
        if($worker -match '(?i)&\s*winget\s+upgrade|--accept-package-agreements'){throw 'Unsubstituted maintenance boundary in generated worker fixture.'}
        $path=Join-Path $dir worker.ps1
        [IO.File]::WriteAllText($path,$worker,[Text.UTF8Encoding]::new($true))
        & powershell.exe -NoProfile -File $path *> (Join-Path $dir console)
        $receiptPath=if(Test-Path -LiteralPath $status -PathType Leaf){$status}else{$fallback}
        if(-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)){throw 'Generated worker lost its terminal/fallback receipt.'}
        $receipt=Get-Content -LiteralPath $receiptPath -Raw|ConvertFrom-Json
        if($receipt.worker_id -ne 'fixture-worker' -or $receipt.state -ne 'terminal'){throw 'Generated worker identity/state changed.'}
        if($receipt.reason -match 'identity|mismatch'){
            if($null -ne $receipt.ExitCode){throw 'Blocked identity invented a child exit.'}
            continue # A high-integrity fixture host must fail closed too.
        }
        if($case -eq 'wrong-owner'){throw 'Wrong owner reached a package boundary.'}
        if($case -eq 'parent-deadline'){
            if($null -ne $receipt.ExitCode -or $receipt.reason -notmatch 'deadline'){throw 'Parent deadline started work or fabricated an exit.'}
        }else{
            if($receipt.ExitCode -ne 37 -or -not $receipt.identity.verified){throw ('Actual generated worker lost known child exit or verified identity: exit=' + $receipt.ExitCode + '; reason=' + $receipt.reason)}
            if($case -eq 'denied-final' -and ($receiptPath -ne $fallback -or $receipt.capture_health -ne 'degraded')){throw 'Generated worker final receipt fallback was not honest.'}
        }
    }
    Write-Host 'Actual generated worker identity guard, harmless child exit, parent-wait deadline and final receipt fallback passed.'
}finally{
    $resolved=[IO.Path]::GetFullPath($root)
    if(-not $resolved.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'reparo-worker-receipts-*'){throw 'Unsafe fixture cleanup.'}
    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
}
