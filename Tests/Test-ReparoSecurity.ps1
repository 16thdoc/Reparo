Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$reparoPath = Join-Path $repoRoot 'Reparo.ps1'
$remotePath = Join-Path $repoRoot 'deploy\Install-ReparoRemote.ps1'
$windowsInstallerPath = Join-Path $repoRoot 'deploy\install-reparo-windows.cmd'
$moshiPath = Join-Path $repoRoot 'deploy\Install-MoshiRemote.ps1'
$workflowPath = Join-Path $repoRoot '.github\workflows\test-steam-headless.yml'

foreach ($path in @($reparoPath, $remotePath, $moshiPath)) {
    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "Security source does not parse: $path - $($errors[0].Message)" }
}

$reparo = Get-Content -LiteralPath $reparoPath -Raw
foreach ($required in @(
    'function Protect-ReparoWindowsInstallRoot',
    'Refusing privileged installation through a reparse point',
    '$acl.SetAccessRuleProtection($true, $false)',
    "New-Object Security.Principal.SecurityIdentifier('S-1-5-32-545')",
    'Remote Reparo sources must use an absolute HTTPS URL without embedded credentials.',
    'Downloaded Reparo.ps1 SHA-256 mismatch.',
    '-ExpectedHash $installExpectedHash -ExpectedVersion $installExpectedVersion',
    'existing hard link could otherwise modify a different file.',
    "Assert-ReparoWindowsPathHasNoReparsePoint -Path `$protectedPath"
)) {
    if (-not $reparo.Contains($required)) { throw "Missing Windows runtime security contract: $required" }
}

$windowsInstaller = Get-Content -LiteralPath $windowsInstallerPath -Raw
foreach ($required in @(
    'deploy/reparo-release.json',
    'Custom REPARO_URL requires an uppercase 64-character REPARO_SHA256.',
    'Get-FileHash -LiteralPath $bootstrap -Algorithm SHA256',
    "('ReparoInstall-' + [guid]::NewGuid().ToString('N'))"
)) {
    if (-not $windowsInstaller.Contains($required)) { throw "Missing Windows bootstrap security contract: $required" }
}
if ($windowsInstaller -match 'contents/Reparo\.ps1\?ref=main') {
    throw 'Windows bootstrap still defaults to mutable main source execution.'
}

$remoteSource = Get-Content -LiteralPath $remotePath -Raw
foreach ($required in @(
    'SourceSha256',
    'ReleaseManifestUrl',
    "('ReparoRemote-' + [guid]::NewGuid().ToString('N'))",
    'Reparo SHA-256 mismatch.',
    'SourceUrl and SourceSha256 must be supplied together',
    'throw "Invalid SSH target: ''$target''"',
    "'--',"
)) {
    if (-not $remoteSource.Contains($required)) { throw "Missing remote bootstrap security contract: $required" }
}
if ($remoteSource -match "SourceUrl\s*=\s*'https://raw\.githubusercontent\.com/16thdoc/Reparo/main") {
    throw 'Remote bootstrap still defaults to mutable main source execution.'
}
$remoteTokens = $null
$remoteErrors = $null
$remoteAst = [Management.Automation.Language.Parser]::ParseInput($remoteSource, [ref]$remoteTokens, [ref]$remoteErrors)
foreach ($functionName in @('ConvertTo-ReparoPowerShellLiteral','New-ReparoRemoteInstallScript')) {
    $name = $functionName
    $definition = $remoteAst.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true)
    if (-not $definition) { throw "Remote installer helper is missing: $functionName" }
    Invoke-Expression $definition.Extent.Text
}
$generatedRemote = New-ReparoRemoteInstallScript -RemoteSourceUrl '' -RemoteSourceSha256 '' -RemoteManifestUrl 'https://example.invalid/release.json' -RemoteInstallRoot 'C:\ProgramData\Reparo'
$generatedTokens = $null
$generatedErrors = $null
[void][Management.Automation.Language.Parser]::ParseInput($generatedRemote, [ref]$generatedTokens, [ref]$generatedErrors)
if ($generatedErrors.Count) { throw "Generated remote bootstrap does not parse: $($generatedErrors[0].Message)" }

$moshi = Get-Content -LiteralPath $moshiPath -Raw
if ($moshi -match 'curl[^\r\n]+\|\s*(?:INSTALL_DIR[^\r\n]+)?sh') {
    throw 'Moshi deployment still pipes a network response directly to a shell.'
}
foreach ($required in @('MoshiHookInstallSha256', 'sha256sum "$hook_installer"', 'sh -n "$hook_installer"')) {
    if (-not $moshi.Contains($required)) { throw "Missing Moshi installer verification contract: $required" }
}

$workflow = Get-Content -LiteralPath $workflowPath -Raw
if ($workflow -match 'uses:\s*actions/checkout@v\d+') {
    throw 'GitHub Actions dependencies must be pinned to immutable commit SHAs.'
}

$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('reparo-security-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
    $failureMessage = $null
    try {
        & $reparoPath -Latest -SourceUrl 'http://example.invalid/Reparo.ps1' -InstallRoot (Join-Path $fixtureRoot 'runtime') -LogRoot (Join-Path $fixtureRoot 'logs')
    }
    catch {
        $failureMessage = ([string]$_.Exception.Message) + ' | ' + ([string]$_.ScriptStackTrace)
    }
    if ($failureMessage -notmatch 'absolute HTTPS URL') { throw "An insecure HTTP Reparo source was not rejected before download. Failure='$failureMessage'" }
}
finally {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'Reparo security contracts passed.' -ForegroundColor Green
