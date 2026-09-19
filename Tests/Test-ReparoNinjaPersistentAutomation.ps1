Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'examples\Reparo-Ninja-Persistent-Automation.ps1'

if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw 'Persistent Ninja reference automation is missing.'
}

$source = Get-Content -LiteralPath $scriptPath -Raw
$tokens = $null
$parseErrors = $null

[void][System.Management.Automation.Language.Parser]::ParseInput(
    $source,
    [ref]$tokens,
    [ref]$parseErrors
)

if ($parseErrors.Count -gt 0) {
    throw "Persistent Ninja automation does not parse: $($parseErrors[0].Message)"
}

foreach ($required in @(
    'function Publish-ReparoNinjaField',
    "'winget'",
    "Invoke-Reparo -Arguments @('-WG')",
    "'force at 7 pm'",
    "Invoke-Reparo -Arguments @('-Force', '-Time', '7pm')",
    "'kill'",
    "Invoke-Reparo -Arguments @('-Kill')",
    'Set-NinjaProperty',
    'Ninja-Property-Set',
    'C:\ProgramData\NinjaRMMAgent\ninjarmm-cli.exe',
    'Repair or update the Ninja agent.',
    'Invoke-ReparoTlsBootstrap.ps1',
    '[Net.SecurityProtocolType]::Tls12',
    '$commandTokens -join '' ''',
    'return $false'
)) {
    if (-not $source.Contains($required)) {
        throw "Persistent Ninja automation contract is absent: $required"
    }
}

$wingetBlock = [regex]::Match(
    $source,
    "(?ms)^\s*'winget'\s*\{(?<body>.*?)^\s*\}"
)

if (-not $wingetBlock.Success) {
    throw 'Could not locate the persistent Ninja Winget action.'
}

if (-not $wingetBlock.Groups['body'].Value.Contains("@('-WG')")) {
    throw 'The persistent Ninja Winget action must run health-only -WG mode.'
}

if ($wingetBlock.Groups['body'].Value.Contains("@('-Winget')")) {
    throw 'The persistent Ninja Winget action must not run package upgrades.'
}

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'reparo-ninja-tls-bootstrap-' + [guid]::NewGuid()
)

try {
    $installRoot = Join-Path $testRoot "runtime's spaced crypt"
    $testScriptPath = Join-Path $testRoot 'Reparo-Ninja-Persistent-Automation.ps1'
    $fakeReparoPath = Join-Path $installRoot 'Reparo.ps1'
    $markerPath = Join-Path $testRoot 'tls-marker.txt'
    New-Item -ItemType Directory -Path $installRoot -Force | Out-Null

    $escapedInstallRoot = $installRoot.Replace("'", "''")
    $testSource = $source.Replace(
        '$InstallRoot = ''C:\ProgramData\Reparo''',
        "`$InstallRoot = '$escapedInstallRoot'"
    )
    if ($testSource -eq $source) {
        throw 'Could not redirect the persistent Ninja integration test install root.'
    }
    Set-Content -LiteralPath $testScriptPath -Value $testSource -Encoding UTF8

    $escapedMarkerPath = $markerPath.Replace("'", "''")
    @"
param(
    [switch]`$New,
    [string]`$InstallRoot,
    [switch]`$Version
)

if (`$Version) {
    Write-Host 'Reparo 1.3.3.1'
    return
}
if (-not `$New) { throw 'Expected the staged -New lifecycle action.' }
if (([Net.ServicePointManager]::SecurityProtocol -band [Net.SecurityProtocolType]::Tls12) -ne [Net.SecurityProtocolType]::Tls12) {
    throw 'The staged lifecycle child did not enable TLS 1.2.'
}
Set-Content -LiteralPath '$escapedMarkerPath' -Value `$InstallRoot -Encoding UTF8
"@ | Set-Content -LiteralPath $fakeReparoPath -Encoding UTF8

    $integrationOutput = @(
        & powershell.exe `
            -NoProfile `
            -ExecutionPolicy Bypass `
            -File $testScriptPath `
            -Action New `
            2>&1
    )
    if ($LASTEXITCODE -ne 0) {
        throw "Persistent Ninja TLS bootstrap integration failed: $($integrationOutput -join [Environment]::NewLine)"
    }
    if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) {
        throw 'The staged lifecycle child did not execute the fake Reparo runtime.'
    }
    if ((Get-Content -LiteralPath $markerPath -Raw).Trim() -ne $installRoot) {
        throw 'The staged lifecycle child did not preserve the Reparo argument list.'
    }
}
finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'Reparo persistent Ninja reference automation contracts passed.' -ForegroundColor Green
