Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'Reparo.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Reparo source does not parse.' }
$builder = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'New-ReparoOpencodeUpdateCommand' }, $true)
Invoke-Expression $builder.Extent.Text
$root = Join-Path $env:TEMP ('reparo-opencode-' + [guid]::NewGuid())
$oldFixture = $env:REPARO_OC_FIXTURE
try {
    New-Item -ItemType Directory -Path $root | Out-Null
    foreach ($case in 'v2','v1','coexist-v1','coexist-v2','migration-failed','rollback-failed','running','locked','missing','standalone','failed','npm-missing') {
        $fixture = Join-Path $root $case
        $prefix = Join-Path $fixture 'owning prefix'
        New-Item -ItemType Directory -Path $prefix -Force | Out-Null
        $env:REPARO_OC_FIXTURE = $fixture
        foreach ($package in 'opencode-ai','@opencode/cli') {
            if ($package -eq '@opencode/cli' -and $case -in 'v1','migration-failed','rollback-failed') { continue }
            $dir = Join-Path $prefix "node_modules/$package"
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Set-Content (Join-Path $dir 'package.json') '{"name":"fixture","version":"1.19.0"}'
        }
        $package = if ($case -in 'v1','coexist-v1','migration-failed','rollback-failed') { 'opencode-ai' } else { '@opencode/cli' }
        $shim = "@echo off`r`nrem node_modules\$($package.Replace('/','\'))\bin\opencode.exe`r`necho opencode v2.0.29"
        if ($case -eq 'standalone') { $shim = '@echo off' }
        if ($case -ne 'missing') { Set-Content (Join-Path $prefix 'opencode.cmd') $shim }
        $npm = @'
if ($args[0] -eq 'config') { Add-Content (Join-Path $env:REPARO_OC_FIXTURE 'configs') 'config'; Join-Path $env:REPARO_OC_FIXTURE 'different prefix'; $global:LASTEXITCODE = 0; return }
($args | ConvertTo-Json -Compress) | Add-Content (Join-Path $env:REPARO_OC_FIXTURE 'calls')
if ((Split-Path $env:REPARO_OC_FIXTURE -Leaf) -eq 'failed') { $global:LASTEXITCODE = 17; return }
if ((Split-Path $env:REPARO_OC_FIXTURE -Leaf) -in 'migration-failed','rollback-failed' -and $args[0] -eq 'install' -and $args[4] -eq '@opencode/cli@latest') { $global:LASTEXITCODE = 17; return }
if ((Split-Path $env:REPARO_OC_FIXTURE -Leaf) -eq 'rollback-failed' -and $args[0] -eq 'install') { $global:LASTEXITCODE = 19; return }
if ((Split-Path $env:REPARO_OC_FIXTURE -Leaf) -eq 'missing') {
    $p = Join-Path $env:REPARO_OC_FIXTURE 'owning prefix/opencode.cmd'
    Set-Content $p "@echo off`r`necho opencode v2.0.29"
}
$global:LASTEXITCODE = 0
'@
        Set-Content (Join-Path $fixture 'npm.ps1') $npm
        $harness = @'
function Get-Command {
    param($Name, $CommandType, $ErrorAction)
    $f = $env:REPARO_OC_FIXTURE
    if ($Name -eq 'npm' -and (Split-Path $f -Leaf) -ne 'npm-missing') { [pscustomobject]@{ Source = (Join-Path $f 'npm.ps1') }; return }
    if ($Name -eq 'opencode') {
        $p = Join-Path $f 'owning prefix/opencode.cmd'
        if (Test-Path $p) { [pscustomobject]@{ Source = $p } }
    }
}
function Get-Process {
    param($Name, $ErrorAction)
    if ((Split-Path $env:REPARO_OC_FIXTURE -Leaf) -eq 'running') { [pscustomobject]@{ ProcessName = 'opencode' } }
}
'@
        $locks = if ($case -eq 'locked') { @('@opencode/cli') } else { @() }
        $worker = Join-Path $fixture 'worker.ps1'
        Set-Content $worker ($harness + "`r`n" + (New-ReparoOpencodeUpdateCommand -LockedPackages $locks))
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $worker 2>&1 | Out-String
        $code = $LASTEXITCODE
        $callsPath = Join-Path $fixture 'calls'
        if ($case -ne 'missing' -and (Test-Path (Join-Path $fixture 'configs'))) { throw 'Configured npm prefix must not shadow the active OpenCode command.' }
        $skipped = $case -in 'running','locked','standalone','npm-missing','coexist-v1'
        if ($skipped) {
            if ($code -ne 0 -or $output -notmatch '\[SKIP\] Opencode:' -or (Test-Path $callsPath)) { throw "$case did not safely skip: $output" }
        }
        elseif ($case -eq 'failed') {
            if ($code -eq 0 -or $output -notmatch 'exit code 17') { throw "npm failure was swallowed: $output" }
        }
        elseif ($case -in 'migration-failed','rollback-failed') {
            $calls = @(Get-Content $callsPath)
            if ($code -eq 0 -or $calls.Count -ne 4 -or $calls[3] -notmatch 'opencode-ai@1.19.0') { throw "Migration rollback not attempted: $output" }
            if ($case -eq 'migration-failed' -and $output -notmatch 'restored opencode-ai 1.19.0') { throw "Successful rollback not reported: $output" }
            if ($case -eq 'rollback-failed' -and $output -notmatch 'rollback also failed') { throw "Rollback failure not reported: $output" }
        }
        else {
            if ($code -ne 0) { throw "$case failed: $output" }
            $calls = @(Get-Content $callsPath)
            if ($case -eq 'v1' -and ($calls.Count -ne 2 -or $calls[0] -notmatch 'uninstall.*opencode-ai')) { throw 'V1 must be removed before installing V2.' }
            $call = @($calls[-1] | ConvertFrom-Json)
            if ($call.Count -ne 5 -or $call[0] -ne 'install' -or $call[2] -ne '--prefix' -or $call[4] -ne '@opencode/cli@latest') { throw "Wrong update arguments for ${case}: $call" }
            $expectedPrefix = if ($case -eq 'missing') { Join-Path $fixture 'different prefix' } else { $prefix }
            if ($call[3] -ne $expectedPrefix) { throw "Wrong owning prefix for ${case}: $call" }
        }
    }
    $source = Get-Content (Join-Path $repo 'Reparo.ps1') -Raw
    if ($builder.Extent.Text -match 'oc -s|opencode upgrade|service (stop|restart)') { throw 'Updater still invokes interactive upgrades, legacy sync, or kills sessions.' }
    if ($source -notmatch "property.Name -in @\('opencode-ai', '@opencode/cli'\)") { throw 'General npm pass must exclude both OpenCode packages.' }
    if ($source -notmatch "opencodeSkip.Count -gt 0") { throw 'OpenCode skips must be reported as skipped, not updated.' }
    Write-Host 'OpenCode V2 migration/rollback, ownership, coexistence, spaces, running service, locks, V2 fallback, unsupported install and npm failure tests passed.'
}
finally {
    $env:REPARO_OC_FIXTURE = $oldFixture
    Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
}
