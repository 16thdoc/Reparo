param([string]$SourcePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'Reparo.ps1'))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($SourcePath,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors | Out-String)}
foreach($name in 'ConvertTo-ReparoSafeFileName','ConvertTo-ReparoPowerShellLiteral','Test-ReparoIgnorableCommandOutputLine','Sync-ReparoCommandOutputLog','Invoke-ReparoTimedCommand'){
    $node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    Invoke-Expression $node.Extent.Text
}
$LogRoot=Join-Path $env:TEMP ('reparo-worker-errors-'+[guid]::NewGuid().ToString('N'))
$script:ReparoDebug=$false
function Write-ReparoDebug {param($Message)}
function Write-ReparoLog {param($Message) $script:logLines += $Message}
function Write-Info {param($Message)}
function Write-ReparoEventLog {param($EventId,$EntryType,$Message)}
function Test-ReparoInteractiveSkip {return $false}
function Read-ReparoSkipKey {return $false}
function Write-Host {param($Object)}
try {
    New-Item -ItemType Directory -Path $LogRoot | Out-Null
    $shell=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
    $script:ReparoLogBaseName='terminating-error'; $script:logLines=@()
    $command=@'
$ErrorActionPreference='Stop'
Write-ReparoChildOutput 'scan started'
throw [System.Runtime.InteropServices.COMException]::new('Synthetic scan failure: access denied', -2147024891)
'@
    $result=Invoke-ReparoTimedCommand -ShellPath $shell -Command $command -Section WindowsUpdate
    if($result.ExitCode -eq 0){throw 'Terminating error was reported successful.'}
    if(($result.Output -join "`n") -notmatch 'Synthetic scan failure: access denied'){throw 'The worker lost the terminating exception message.'}
    if(($result.Output -join "`n") -notmatch '0x80070005'){throw 'The worker lost the exception HRESULT.'}
    if(($script:logLines -join "`n") -notmatch 'Synthetic scan failure: access denied'){throw 'The final log lost the exception message.'}
    foreach($case in @(
        @{Name='parser-error';Command='if (';Expected=1;Pattern='ParserError'},
        @{Name='direct-stderr';Command="[Console]::Error.WriteLine('synthetic direct stderr'); exit 7";Expected=7;Pattern='synthetic direct stderr'},
        @{Name='warning-success';Command="[Console]::Error.WriteLine('synthetic benign stderr'); exit 0";Expected=0;Pattern='synthetic benign stderr'},
        @{Name='pipe-capacity';Command="[Console]::Out.WriteLine(('x' * 100000)); [Console]::Error.WriteLine('large pipe drained'); exit 3";Expected=3;Pattern='large pipe drained'}
    )){
        $script:ReparoLogBaseName=$case.Name; $script:logLines=@()
        $result=Invoke-ReparoTimedCommand -ShellPath $shell -Command $case.Command -Section Fixture
        if($result.ExitCode -ne $case.Expected){throw "$($case.Name): unexpected exit $($result.ExitCode)"}
        if(($result.Output -join "`n") -notmatch $case.Pattern){throw "$($case.Name): lost child stream diagnostic"}
    }
    Microsoft.PowerShell.Utility\Write-Host 'Worker exception/HRESULT, parse failure, direct stderr, benign stderr and full-pipe diagnostics passed.'
} finally {
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    $resolved=[IO.Path]::GetFullPath($LogRoot)
    if(-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'reparo-worker-errors-*'){throw 'Unsafe fixture cleanup path.'}
    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
}
