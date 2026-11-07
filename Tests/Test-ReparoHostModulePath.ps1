# Reproduce the PowerShell 7 -> cmd.exe -> Windows PowerShell autoload boundary.
# No real maintenance, Steam actions, persistent environment changes or tasks.
$ErrorActionPreference='Stop'
$source=Join-Path (Split-Path -Parent $PSScriptRoot) 'Reparo.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Source does not parse'}
$fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Initialize-ReparoHostModulePath'},$true)
if(-not $fn){throw 'Missing host module initializer'}
$tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$temp=Join-Path $tempRoot ('reparo-module-fixture-'+[guid]::NewGuid().ToString('N'))
$previous=$env:PSModulePath
try{
    $foreign=Join-Path $temp 'foreign\Microsoft.PowerShell.Security'
    New-Item -ItemType Directory -Path $foreign -Force|Out-Null
    "@{ModuleVersion='99.0.0';RootModule='MissingForeignSecurity.dll';CmdletsToExport=@('Get-AuthenticodeSignature')}"|Set-Content -LiteralPath (Join-Path $foreign 'Microsoft.PowerShell.Security.psd1') -Encoding UTF8
    $probe=Join-Path $temp 'probe.ps1'
    $body=@'
$ErrorActionPreference='Stop'
$original=$env:PSModulePath
$failedBefore=$false
try{Get-AuthenticodeSignature -FilePath ($PSHOME+'\powershell.exe') -ErrorAction Stop|Out-Null}catch{$failedBefore=$true}
if(-not $failedBefore){throw 'Contaminated module fixture did not reproduce autoload failure'}
Initialize-ReparoHostModulePath
$paths=$env:PSModulePath -split ';'
if($paths[0] -ne ($PSHOME+'\Modules')){throw 'Host core modules were not prioritized'}
foreach($p in ($original -split ';')){if($p -and $p -notin $paths){throw 'Existing module path was discarded'}}
$signature=Microsoft.PowerShell.Security\Get-AuthenticodeSignature -FilePath ($PSHOME+'\powershell.exe') -ErrorAction Stop
$module=Get-Module Microsoft.PowerShell.Security
if(-not $module.Path.StartsWith(($PSHOME+'\'),[StringComparison]::OrdinalIgnoreCase)){throw ('Foreign security module loaded: '+$module.Path)}
if($null -eq $signature){throw 'Host signature cmdlet failed'}
$once=$env:PSModulePath
Initialize-ReparoHostModulePath
if($once -ne $env:PSModulePath){throw 'Initializer is not idempotent'}
Write-Host 'Host module precedence, preserved custom paths, idempotence and cmd-shim security autoload passed.'
'@
    ($fn.Extent.Text+"`n"+$body)|Set-Content -LiteralPath $probe -Encoding UTF8
    $env:PSModulePath=(Split-Path -Parent $foreign)+';'+$previous
    $command='powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$probe+'"'
    & $env:ComSpec /d /s /c $command
    if($LASTEXITCODE -ne 0){throw 'Windows PowerShell via cmd.exe regression failed'}
}finally{
    $env:PSModulePath=$previous
    $resolved=[IO.Path]::GetFullPath($temp)
    if(-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'reparo-module-fixture-*'){throw 'Unsafe fixture cleanup'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
