Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$source=Join-Path (Split-Path -Parent $PSScriptRoot) 'Reparo.ps1'
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$null,[ref]$null)
foreach($name in 'ConvertTo-ReparoPowerShellLiteral','New-ReparoNpmUpdateCommand'){
    $node=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    Invoke-Expression $node.Extent.Text
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('reparo-npm-reliability-'+[guid]::NewGuid().ToString('N'))
$old=$env:REPARO_NPM_FIXTURE
try {
    [void][IO.Directory]::CreateDirectory($root)
    foreach($case in 'invalid-json','exhausted-targets','engine-warning','script-warning','active-consumer','same-version'){
        $fixture=Join-Path $root $case
        [void][IO.Directory]::CreateDirectory((Join-Path $fixture 'prefix/node_modules/fixture-package'))
        $env:REPARO_NPM_FIXTURE=$fixture
        $harness=@'
$case=Split-Path $env:REPARO_NPM_FIXTURE -Leaf
$prefix=Join-Path $env:REPARO_NPM_FIXTURE prefix
function Set-Content { param($LiteralPath,$Path,$Value,$Encoding) throw 'Unexpected persistent write from generated npm command.' }
function New-Item { param($ItemType,$Path,[switch]$Force) throw 'Unexpected persistent directory write from generated npm command.' }
function Get-Command { param($Name,$CommandType,$ErrorAction) if($Name -eq 'npm'){[pscustomobject]@{Source='fixture-npm'}} }
function Get-CimInstance {
    param($ClassName,$ErrorAction)
    if($case -eq 'active-consumer'){[pscustomobject]@{Name='node.exe';CommandLine=('node '+(Join-Path $prefix 'node_modules/fixture-package/service.js'));ExecutablePath='node.exe'}}
}
function node {$global:LASTEXITCODE=0; 'v24.15.0'}
function npm {
    if($args[0] -eq 'config'){$global:LASTEXITCODE=0;$prefix;return}
    if($args[0] -eq 'root'){$global:LASTEXITCODE=0;Join-Path $prefix node_modules;return}
    if($args[0] -eq '--version'){$global:LASTEXITCODE=0;'12.0.0';return}
    if($args[0] -eq 'outdated'){
        $global:LASTEXITCODE=1
        if($case -eq 'invalid-json'){'{invalid';return}
        '{"fixture-package":{"current":"1.0.0","wanted":"1.0.0","latest":"1.0.0"}}';return
    }
    [IO.File]::AppendAllText((Join-Path $env:REPARO_NPM_FIXTURE calls),($args -join ' ')+[Environment]::NewLine)
    $global:LASTEXITCODE=0
    if($case -eq 'exhausted-targets'){$global:LASTEXITCODE=37;return}
    if($args[0] -eq 'update'){
        if($case -eq 'engine-warning'){'npm warn EBADENGINE fixture-package requires another Node channel'}
        if($case -eq 'script-warning'){'npm warn blocked install scripts; native addon functional state unverified'}
        'changed 2 packages; root version remains 1.0.0'
    }
}
'@
        $worker=Join-Path $fixture worker.ps1
        [IO.File]::WriteAllText($worker,($harness+"`n"+(New-ReparoNpmUpdateCommand)),[Text.UTF8Encoding]::new($true))
        $pref=$ErrorActionPreference;$ErrorActionPreference='Continue'
        try{$text=& powershell.exe -NoProfile -File $worker 2>&1|Out-String;$code=$LASTEXITCODE}finally{$ErrorActionPreference=$pref}
        $expectFailure=$case -in 'invalid-json','exhausted-targets'
        if(($code -ne 0) -ne $expectFailure){throw "$case wrong exit ${code}: $text"}
        if($expectFailure -and $text -notmatch 'invalid JSON|exhausted compatible targets'){throw "Missing typed npm failure: $text"}
        $calls=Get-Content (Join-Path $fixture calls)
        if($case -eq 'active-consumer' -and @($calls|Where-Object {$_ -match '^update'}).Count){throw 'Active service package was replaced.'}
        if($case -eq 'engine-warning' -and $text -notmatch 'EBADENGINE'){throw 'Engine warning lost.'}
        if($case -eq 'script-warning' -and $text -notmatch 'blocked install scripts'){throw 'Script-policy warning lost.'}
        if($case -eq 'same-version' -and $text -notmatch 'root version remains 1.0.0'){throw 'Same-version replacement output lost.'}
    }
    # Exercise the literal shipped compound commands with fake managers.
    $text=Get-Content -LiteralPath $source -Raw
    foreach($entry in @(@('Pnpm','pnpm'),@('Conda','conda'),@('Gem','gem'),@('Composer','composer'))){
        $pattern="Invoke-ReparoCommandStep -Section '"+$entry[0]+"'.*?-Command '(?<Command>[^']+)'"
        $match=[regex]::Match($text,$pattern)
        if(-not $match.Success){throw 'Compound command not found.'}
        $fixture=Join-Path $root $entry[0];[void][IO.Directory]::CreateDirectory($fixture);$env:REPARO_NPM_FIXTURE=$fixture
        $stub='function '+$entry[1]+' { [IO.File]::AppendAllText((Join-Path $env:REPARO_NPM_FIXTURE calls),"called`n"); $global:LASTEXITCODE=37 }; '+$match.Groups['Command'].Value+'; exit $LASTEXITCODE'
        $worker=Join-Path $fixture worker.ps1;[IO.File]::WriteAllText($worker,$stub)
        & powershell.exe -NoProfile -File $worker
        if($LASTEXITCODE -ne 37 -or @(Get-Content (Join-Path $fixture calls)).Count -ne 1){throw 'First subcommand failure was masked by later work.'}
    }
    Write-Host 'Generated npm JSON/engine/script-policy/same-version/active-consumer/exhausted-target and compound-command behavior passed.'
}finally{
    $env:REPARO_NPM_FIXTURE=$old
    $resolved=[IO.Path]::GetFullPath($root)
    if([IO.Path]::GetFileName($resolved) -notlike 'reparo-npm-reliability-*' -or -not $resolved.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe fixture cleanup.'}
    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
}
