Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'Reparo.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors | Out-String)}
foreach($name in 'Test-ReparoInteractiveSkip','Read-ReparoSkipKey','ConvertTo-ReparoSafeFileName','ConvertTo-ReparoPowerShellLiteral','Test-ReparoIgnorableCommandOutputLine','Sync-ReparoCommandOutputLog','Invoke-ReparoTimedCommand','Get-ReparoNotUpdatedAction'){
    $node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    if(-not $node){throw "Missing function $name"}
    Invoke-Expression $node.Extent.Text
}
if(Test-ReparoInteractiveSkip){throw 'This regression must run with redirected output/headless, never consume a real keyboard.'}
if(Read-ReparoSkipKey){throw 'Headless key polling should return false.'}
$LogRoot=Join-Path $env:TEMP ('reparo-skip-'+[guid]::NewGuid())
$script:ReparoDebug=$false
function Write-ReparoDebug {param($Message)}
function Write-ReparoLog {param($Message) $script:logLines += $Message}
function Write-Info {param($Message)}
function Write-ReparoEventLog {param($EventId,$EntryType,$Message)}
function Stop-ReparoProcessTree {param($ProcessId) throw 'A graceful skip must never kill a worker.'}
try {
    New-Item -ItemType Directory $LogRoot | Out-Null
    foreach($case in 'supported','unsupported','deadline','delivery-failed'){
        $script:ReparoLogBaseName=$case
        $script:logLines=@()
        $script:started=Join-Path $LogRoot ($case+'.started')
        $done=Join-Path $LogRoot ($case+'.done')
        function Read-ReparoSkipKey { return (Test-Path -LiteralPath $script:started) }
        $command = "Set-Content -LiteralPath '$($script:started)' -Value started; Start-Sleep -Seconds 2; Set-Content -LiteralPath '$done' -Value done; "
        if($case -ne 'unsupported'){$command += "Stop-ReparoAtSafeBoundary 'after indivisible fixture operation'; "}
        $command += "Write-Output 'fixture finished naturally'"
        if($case -eq 'delivery-failed'){
            function Set-Content {
                param($LiteralPath,$Value,$Encoding,$ErrorAction)
                if($LiteralPath -like '*.skip'){throw 'synthetic signal-file failure'}
                Microsoft.PowerShell.Management\Set-Content -LiteralPath $LiteralPath -Value $Value -Encoding $Encoding
            }
        }
        $section=if($case -eq 'deadline'){'WindowsUpdate'}else{$case}
        if($case -eq 'deadline'){function Read-ReparoSkipKey {return $false}}
        $timeout=if($case -eq 'deadline'){1}else{0}
        $result=Invoke-ReparoTimedCommand -ShellPath (Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe') -Command $command -Section $section -TimeoutSeconds $timeout
        if(-not(Test-Path $done)){throw 'Advanced without completing the indivisible operation.'}
        if($case -in 'supported','deadline'){
            if($result.ExitCode -ne 130 -or @($result.Output | Where-Object {$_ -match '^REPARO-STEP-SKIPPED'}).Count -ne 1){throw 'No acknowledged safe-boundary cancellation.'}
        }else{
            if($result.ExitCode -ne 0 -or @($result.Output | Where-Object {$_ -match '^REPARO-STEP-SKIPPED'}).Count){throw 'Unsupported/unavailable cancellation was mislabeled as skipped.'}
        }
        if($case -eq 'delivery-failed'){
            if($result.SkipRequested){throw 'Failed signal delivery was called requested.'}
            Remove-Item Function:\Set-Content
        }
        if(@(Get-ChildItem $LogRoot -Filter '*.skip').Count){throw 'Stale skip signal leaked into later work.'}
    }
    $source=Get-Content (Join-Path $repo 'Reparo.ps1') -Raw
    if($source -notmatch "exitCode -eq 130 -and" -or $source -notmatch 'REPARO-STEP-SKIPPED safe boundary:'){throw 'Parent summary must require both cancellation exit and safe-boundary receipt.'}
    $native=Get-Content (Join-Path $repo 'linux/reparo-linux') -Raw
    if($native -notmatch 'Interactive Esc cancellation is Windows-only'){throw 'Native boundary must be explicit.'}
    if((Get-ReparoNotUpdatedAction -Row ([pscustomobject]@{Reason='safe boundary: fixture'}) -Outcome SKIPPED) -notmatch 'Rerun the affected section'){throw 'Skip summary needs actionable resume guidance.'}
    Write-Host 'Graceful boundary waits, no-kill behavior, unsupported backend, cooperative deadline, signal failure, headless input and cleanup passed.'
}
finally { Remove-Item $LogRoot -Recurse -Force -ErrorAction SilentlyContinue }
