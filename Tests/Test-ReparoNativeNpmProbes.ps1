param([string]$SourcePath=(Join-Path (Split-Path -Parent $PSScriptRoot) Reparo.ps1))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$ast=[Management.Automation.Language.Parser]::ParseFile($SourcePath,[ref]$null,[ref]$null)
foreach($name in 'ConvertTo-ReparoPowerShellLiteral','New-ReparoNpmUpdateCommand'){
    $fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    Invoke-Expression $fn.Extent.Text
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('reparo-native-probes-'+[guid]::NewGuid().ToString('N'))
$old=$env:REPARO_NATIVE_PROBE
try{
    foreach($case in 'success','root-failure'){
        $dir=Join-Path $root $case;$bin=Join-Path $dir bin
        [void][IO.Directory]::CreateDirectory($bin)
        [void][IO.Directory]::CreateDirectory((Join-Path $dir 'prefix/node_modules/fixture-package'))
        $env:REPARO_NATIVE_PROBE=$dir
        $producer=Join-Path $dir producer.ps1
        [IO.File]::WriteAllText($producer,@'
$root=$env:REPARO_NATIVE_PROBE
$prefix=Join-Path $root prefix
$case=Split-Path $root -Leaf
switch($args[0]){
    config { $first=$prefix }
    root { $first=Join-Path $prefix node_modules }
    --version { $first='12.0.0' }
    outdated { [Console]::Out.WriteLine('{"fixture-package":{"current":"1","wanted":"2","latest":"2"}}');exit 1 }
    default { [IO.File]::AppendAllText((Join-Path $root calls),($args -join ' ')+[Environment]::NewLine);exit 0 }
}
[Console]::Out.WriteLine($first)
[Console]::Out.Flush()
[Threading.Thread]::Sleep(150)
# More than a pipe buffer proves that the consumer drains a native producer.
[Console]::Out.WriteLine(('fixture probe tail ' * 8000))
if($args[0] -eq 'root' -and $case -eq 'root-failure'){exit 37}
exit 0
'@)
        $npm=Join-Path $bin npm.cmd
        [IO.File]::WriteAllText($npm,('@echo off'+"`r`n"+'"'+$env:WINDIR+'\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "'+$producer+'" %*'+"`r`n"+'exit /b %ERRORLEVEL%'+"`r`n"),[Text.Encoding]::ASCII)
        [IO.File]::WriteAllText((Join-Path $bin node.cmd),"@echo off`r`necho v24.15.0`r`nexit /b 0`r`n",[Text.Encoding]::ASCII)
        $header=@'
$ErrorActionPreference='Stop'
$bin=Join-Path $env:REPARO_NATIVE_PROBE bin
$env:PATH=$bin+[IO.Path]::PathSeparator+$env:PATH
foreach($name in 'npm','node'){
    $resolved=(Get-Command $name -ErrorAction Stop).Source
    if($resolved -ne (Join-Path $bin ($name+'.cmd'))){throw 'Fixture native boundary did not resolve to the disposable shim.'}
}
function Get-CimInstance { param($ClassName,$ErrorAction) return @() }
function Set-Content { throw 'Unexpected persistent write from generated updater' }
function New-Item { throw 'Unexpected persistent directory write from generated updater' }
'@
        $worker=Join-Path $dir worker.ps1
        [IO.File]::WriteAllText($worker,($header+"`n"+(New-ReparoNpmUpdateCommand)),[Text.UTF8Encoding]::new($true))
        $saved=$ErrorActionPreference;$ErrorActionPreference='Continue'
        try{$output=& (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $worker 2>&1|Out-String;$code=$LASTEXITCODE}finally{$ErrorActionPreference=$saved}
        if($case -eq 'success'){
            if($code -ne 0){throw "Native multi-buffer probe was falsely rejected: $output"}
            if(-not (Select-String -LiteralPath (Join-Path $dir calls) -Pattern '^update -g fixture-package$')){throw 'Valid native root did not reach fake package update.'}
        }else{
            if($code -eq 0 -or $output -notmatch 'npm owning root is unverified'){throw 'Genuine root probe failure was ignored.'}
            if(Select-String -LiteralPath (Join-Path $dir calls) -Pattern '^update' -Quiet){throw 'Mutation followed failed native root probe.'}
        }
    }
    Write-Output 'Native npm shims: full producer drain, preserved root failure and isolated mutation boundary passed.'
}finally{
    $env:REPARO_NATIVE_PROBE=$old
    $resolved=[IO.Path]::GetFullPath($root)
    if(-not $resolved.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'reparo-native-probes-*'){throw 'Unsafe fixture cleanup'}
    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
}
