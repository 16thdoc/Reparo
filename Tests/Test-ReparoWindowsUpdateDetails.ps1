Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'Reparo.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($name in 'New-ReparoWindowsUpdateCommand','Add-ReparoWindowsUpdateReceipts') {
    $node = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    Invoke-Expression $node.Extent.Text
}
$root = Join-Path $env:TEMP ('reparo-wu-details-' + [guid]::NewGuid())
$oldFixture = $env:REPARO_WU_FIXTURE
try {
    New-Item -ItemType Directory $root | Out-Null
    foreach ($case in 'empty','success','download-failed','install-failed','mixed-install-results','unknown-result','invalid-identity','scan-error','skip-after-scan','skip-after-download','partial-skip','auto-reboot') {
        $fixture = Join-Path $root $case
        New-Item -ItemType Directory $fixture | Out-Null
        $env:REPARO_WU_FIXTURE = $fixture
        $harness = @'
function Import-Module { param($Name,$ErrorAction) }
function Write-ReparoChildOutput { param($Value) Add-Content (Join-Path $env:REPARO_WU_FIXTURE 'output') $Value }
function Stop-ReparoAtSafeBoundary {
    param($Boundary)
    $case = Split-Path $env:REPARO_WU_FIXTURE -Leaf
    if (($case -eq 'skip-after-scan' -and $Boundary -eq 'after scan, before download/install') -or
        ($case -eq 'skip-after-download' -and $Boundary -eq 'after download, before installation') -or
        ($case -eq 'partial-skip' -and $Boundary -eq 'between Windows updates' -and $script:installs -eq 1)) {
        Write-ReparoChildOutput "REPARO-STEP-SKIPPED safe boundary: $Boundary"
        exit 130
    }
}
$script:installs = 0
function Get-WindowsUpdate {
    [CmdletBinding()]
    param($UpdateID,[switch]$AcceptAll,[switch]$Download,[switch]$Install,[switch]$IgnoreReboot,[switch]$AutoReboot)
    $case = Split-Path $env:REPARO_WU_FIXTURE -Leaf
    $phase = if($Install){'install'}elseif($Download){'download'}else{'scan'}
    "$phase | $UpdateID | ignore=$IgnoreReboot auto=$AutoReboot" | Add-Content (Join-Path $env:REPARO_WU_FIXTURE 'calls')
    Write-Verbose "backend phase: $phase"
    if($case -eq 'scan-error'){throw 'synthetic scan failure'}
    if($case -eq 'empty'){return}
    $result = if($Install){if($case -eq 'install-failed'){'Failed'}elseif($case -eq 'unknown-result'){'Accepted'}else{'Installed'}}elseif($Download){if($case -eq 'download-failed'){'Failed'}else{'Downloaded'}}else{''}
    if($Install){$script:installs++}
    if($case -eq 'mixed-install-results' -and $Install){[pscustomobject]@{Title='Fixture security update (KB1234567)';KB='KB1234567';Size='10MB';Result='Failed';HResult=-1}}
    $identity = if($case -eq 'invalid-identity'){'------------------------------------'}else{'11111111-1111-1111-1111-111111111111'}
    [pscustomobject]@{ Title='Fixture security update (KB1234567)'; KB='KB1234567'; Size='10MB'; Result=$result; HResult=0; Identity=[pscustomobject]@{UpdateID=$identity} }
    if($case -eq 'partial-skip' -and $phase -eq 'scan'){
        [pscustomobject]@{Title='Second fixture'; KB='KB1234568'; Size='20MB';Result='';HResult=0;Identity=[pscustomobject]@{UpdateID='22222222-2222-2222-2222-222222222222'}}
    }
}
'@
        $command = New-ReparoWindowsUpdateCommand -AutoReboot:($case -eq 'auto-reboot')
        $worker = Join-Path $fixture 'worker.ps1'
        Set-Content $worker ($harness + "`r`n" + $command)
        $text = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $worker 2>&1 | Out-String
        $code = $LASTEXITCODE
        $lines = @(Get-Content (Join-Path $fixture 'output'))
        $calls = @(Get-Content (Join-Path $fixture 'calls'))
        $expected = if($case -in 'skip-after-scan','skip-after-download','partial-skip'){130}elseif($case -in 'download-failed','install-failed','mixed-install-results','unknown-result','invalid-identity','scan-error'){1}else{0}
        if($code -ne $expected){throw "$case exit $code expected ${expected}: $text"}
        if($case -in 'skip-after-scan','empty','invalid-identity' -and $calls.Count -ne 1){throw 'Cancellation/empty/invalid-identity scan started later work.'}
        if($case -in 'skip-after-download','download-failed' -and @($calls | Where-Object {$_ -match '^install'}).Count){throw 'Install started after canceled/failed download.'}
        if($case -eq 'partial-skip' -and @($lines | Where-Object {$_ -match '"Outcome":"Updated"'}).Count -ne 1){throw 'Partial success receipt lost.'}
        if($case -eq 'success' -and ($lines -join "`n") -notmatch '\[WU-INSTALL\].*KB1234567.*Installed'){throw 'Typed per-update details missing.'}
        if($case -eq 'auto-reboot' -and $calls[-1] -notmatch 'ignore=False auto=True'){throw 'Explicit AutoReboot was lost.'}
        if($case -eq 'success' -and $calls[-1] -notmatch 'ignore=True auto=False'){throw 'Default reboot suppression was lost.'}
        if(($lines -join "`n") -match 'System.__ComObject'){throw 'COM objects were stringified.'}
        $script:receipts = @()
        function Add-ReparoSummaryRecord { param($Bucket,$Software,$Version,$Method,$Reason) $script:receipts += [pscustomobject]@{Bucket=$Bucket;Software=$Software;Reason=$Reason} }
        function Add-ReparoSummaryNote { param($Note) }
        Add-ReparoWindowsUpdateReceipts -Output $lines
        if($case -in 'unknown-result','mixed-install-results' -and @($script:receipts | Where-Object Bucket -eq Failed).Count -ne 1){throw 'Missing/mixed terminal results were called success.'}
    }
    Write-Host 'Windows Update phases/details, identity scope, empty/error/failure/unknown outcomes, reboot policy, safe cancellation and partial receipts passed (no live updates).'
}
finally { $env:REPARO_WU_FIXTURE = $oldFixture; Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }
