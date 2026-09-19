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

Write-Host 'Reparo persistent Ninja reference automation contracts passed.' -ForegroundColor Green
