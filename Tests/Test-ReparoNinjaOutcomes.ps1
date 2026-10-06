Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$source=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'examples\Reparo-Ninja-Persistent-Automation.ps1') -Raw
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-ReparoAutomationOutcome'},$true)
Invoke-Expression $node.Extent.Text
foreach ($f in @(
    @{ Args=@('-WG'); Output=@('WG:USER'); Expected='blocked-no-work' },
    @{ Args=@('-WG'); Output=@('winget available'); Expected='discovery-only' },
    @{ Args=@('-New'); Output=@('installed'); Expected='deployment' },
    @{ Args=@('-Force'); Output=@('Updated: 0 | Skipped: 10 | Failed: 0'); Expected='no-changes-with-skips' },
    @{ Args=@('-Force'); Output=@('Updated: 2 | Skipped: 1 | Failed: 0'); Expected='maintenance-reported-changes' },
    @{ Args=@('-Force'); Output=@('Updated: 0 | Skipped: 0 | Failed: 1'); Expected='maintenance-failed' },
    @{ Args=@('-Force'); Output=@(''); Expected='unverified-maintenance-receipt' },
    @{ Args=@('-Force','-Time','7pm'); Output=@('scheduled'); Expected='scheduled-only' }
)) {
    $actual=Get-ReparoAutomationOutcome -Arguments $f.Args -Output $f.Output
    if ($actual -ne $f.Expected) { throw "Wrong Ninja outcome: $actual expected $($f.Expected)" }
}
if ($source -notmatch 'failed during \{0\}' -or $source -notmatch 'exit 2') { throw 'Operation-specific/non-success blocked receipt missing' }
$fixture=Join-Path $env:TEMP ('reparo-ninja-outcomes-'+[guid]::NewGuid())
try {
    New-Item -ItemType Directory -Path $fixture | Out-Null
    $runtime=Join-Path $fixture 'Reparo.ps1'
    $wrapper=Join-Path $fixture 'wrapper.ps1'
    $fixtureSource=$source.Replace("`$InstallRoot = 'C:\ProgramData\Reparo'", "`$InstallRoot = '$($fixture.Replace("'","''"))'")
    # Never publish to a real Ninja agent in a fixture.
    $fixtureSource=$fixtureSource.Replace('function Publish-ReparoNinjaField {', 'function Publish-ReparoNinjaField { return $false')
    Set-Content -LiteralPath $wrapper -Value $fixtureSource -Encoding UTF8
    foreach ($case in @('blocked','skips','failure')) {
        $receipt=if ($case -eq 'blocked') { 'WG:USER' } elseif ($case -eq 'skips') { 'Updated: 0 | Skipped: 2 | Failed: 0' } else { 'Updated: 0 | Skipped: 0 | Failed: 1' }
        Set-Content -LiteralPath $runtime -Value "param([switch]`$WG,[switch]`$Force); Write-Host '$receipt'; exit 0" -Encoding UTF8
        $action=if ($case -eq 'blocked') { 'Winget' } else { 'Force' }
        $ErrorActionPreference='Continue'
        try { $output=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $wrapper -Action $action 2>&1 | Out-String }
        finally { $ErrorActionPreference='Stop' }
        $expected=if ($case -eq 'blocked') { 2 } elseif ($case -eq 'failure') { 1 } else { 0 }
        if ($LASTEXITCODE -ne $expected) { throw "Wrong wrapper exit for ${case}: $LASTEXITCODE; $output" }
        if ($case -eq 'skips' -and $output -notmatch 'no-changes-with-skips') { throw 'Wrapper lost no-work receipt' }
        if ($case -eq 'failure' -and $output -notmatch 'child execution') { throw 'Wrapper failure lost operation context' }
    }
}
finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host 'Ninja deployment/discovery/blocked/maintenance/failure outcome tests passed.' -ForegroundColor Green
