Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot 'Reparo.ps1'
$source = Get-Content -LiteralPath $sourcePath -Raw

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    throw "Reparo.ps1 has PowerShell parse errors: $($parseErrors.Message -join '; ')"
}

foreach ($required in @(
    'uninstall-no-record-file',
    'pip install\s+--ignore-installed\s+--no-deps\s+pip==',
    "`$repairArguments += '--user'",
    'reinstalling pip `$repairVersion in the same scope before retrying the upgrade',
    "Invoke-ReparoPipCommand -Arguments @('install', '--upgrade', 'pip')"
)) {
    if (-not $source.Contains($required)) {
        throw "Pip missing-RECORD recovery contract is absent: $required"
    }
}

$normalUpgradeCount = ([regex]::Matches(
    $source,
    [regex]::Escape("Invoke-ReparoPipCommand -Arguments @('install', '--upgrade', 'pip')")
)).Count
if ($normalUpgradeCount -lt 2) {
    throw 'Pip recovery must retry the normal upgrade after repairing the damaged version.'
}

Write-Host 'Reparo Pip missing-RECORD recovery contract passed.' -ForegroundColor Green

# Execute the real generated pip command with a fake pip executable boundary.
$pipNode=$ast.Find({param($n)
    $n -is [Management.Automation.Language.ExpandableStringExpressionAst] -and $n.Extent.Text.Contains('function Invoke-ReparoPipCommand')
},$true)
if(-not $pipNode){throw 'Missing worker-scoped pip PATH advisory guard.'}
$pipName='pip'
$command=Invoke-Expression $pipNode.Extent.Text
$root=Join-Path $env:TEMP ('reparo-pip-fixture-'+[guid]::NewGuid().ToString('N'))
$previous=$env:PIP_NO_WARN_SCRIPT_LOCATION
try {
    New-Item -ItemType Directory -Path $root | Out-Null
    $env:PIP_NO_WARN_SCRIPT_LOCATION='0'
    $harness=@'
function Get-Command {param($Name,$CommandType,$ErrorAction) if($Name -eq 'pip'){[pscustomobject]@{Source=''}}}
function Stop-ReparoAtSafeBoundary {param($Boundary)}
function pip {
    if($args[0] -eq 'install' -and '--no-warn-script-location' -notin $args){throw 'Pip still attempts unrelated PATH warning traversal.'}
    if($args[0] -eq 'list'){'[{"name":"fixture-package"}]'}
    elseif('fixture-package' -in $args -and $env:REPARO_PIP_FIXTURE_FAIL -eq '1'){$global:LASTEXITCODE=9;return}
    $global:LASTEXITCODE=0
}
'@
    $worker=Join-Path $root 'worker.ps1'
    Set-Content -LiteralPath $worker -Value ($harness+"`n"+$command) -Encoding UTF8
    foreach($fail in '0','1'){
        $env:REPARO_PIP_FIXTURE_FAIL=$fail
        $savedErrorAction=$ErrorActionPreference
        try {
            $ErrorActionPreference='Continue'
            $output=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $worker 2>&1 | Out-String
            $code=$LASTEXITCODE
        } finally {$ErrorActionPreference=$savedErrorAction}
        if(($fail -eq '0' -and $code -ne 0) -or ($fail -eq '1' -and $code -eq 0)){throw "Pip fixture failure semantics changed: $output"}
        if($env:PIP_NO_WARN_SCRIPT_LOCATION -ne '0'){throw 'Pip setting escaped its worker.'}
    }
    Write-Host 'Real pip command guards all install calls against PATH advisory traversal and preserves install failures.'
} finally {
    $env:PIP_NO_WARN_SCRIPT_LOCATION=$previous
    Remove-Item Env:\REPARO_PIP_FIXTURE_FAIL -ErrorAction SilentlyContinue
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    $resolved=[IO.Path]::GetFullPath($root)
    if(-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'reparo-pip-fixture-*'){throw 'Unsafe pip fixture cleanup.'}
    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
}
