Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$windowsSource = Join-Path $repoRoot 'Reparo.ps1'
$linuxSource = Join-Path $repoRoot 'linux\reparo-linux'

foreach ($path in $windowsSource, $linuxSource) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Release parity source is missing: $path" }
}

$windowsOutput = & $windowsSource -Version *>&1 | Out-String
if ($windowsOutput -notmatch '(?m)^Reparo (?<Version>\d+\.\d+\.\d+\.\d+)\r?$') { throw 'Could not read the Windows Reparo release version.' }
$windowsVersion = $matches.Version.Trim()
if ($windowsOutput -notmatch '(?m)^  "(?<Quote>.+)"\r?$') { throw 'Could not read the Windows Reparo release quote.' }
$windowsQuote = $matches.Quote.Trim()
if ($windowsOutput -notmatch '(?m)^  - (?<Source>.+)\r?$') { throw 'Could not read the Windows Reparo release quote source.' }
$windowsQuoteSource = $matches.Source.Trim()
$sourceContent = Get-Content -LiteralPath $windowsSource -Raw
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($sourceContent, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Windows release source does not parse.' }
$flavor = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-ReparoVersionFlavor' }, $true)
Invoke-Expression $flavor.Extent.Text
$windowsArt = (Get-ReparoVersionFlavor -Version $windowsVersion).Art
if (-not $windowsOutput.Contains($windowsArt)) { throw 'Windows version output omitted matching release art.' }

$linuxContent = Get-Content -LiteralPath $linuxSource -Raw
foreach ($entry in @(
    @{ Name = 'Version'; Pattern = "(?m)^REPARO_LINUX_VERSION='(?<Value>[^']+)'$"; Expected = $windowsVersion },
    @{ Name = 'Quote'; Pattern = '(?m)^REPARO_VERSION_QUOTE=(?<Delimiter>[''"])(?<Value>.+)\k<Delimiter>$'; Expected = $windowsQuote },
    @{ Name = 'Quote source'; Pattern = '(?m)^REPARO_VERSION_SOURCE=(?<Delimiter>[''"])(?<Value>.+)\k<Delimiter>$'; Expected = $windowsQuoteSource },
    @{ Name = 'Art'; Pattern = '(?m)^REPARO_VERSION_ART=(?<Delimiter>[''"])(?<Value>.+)\k<Delimiter>$'; Expected = $windowsArt.Trim() }
)) {
    if ($linuxContent -notmatch $entry.Pattern) { throw "Could not read native Linux Reparo $($entry.Name)." }
    $linuxValue = $matches.Value.Trim()
    if ($linuxValue -ne $entry.Expected) {
        throw "Reparo release parity failure for $($entry.Name): Windows='$($entry.Expected)', Linux='$linuxValue'."
    }
}

Write-Host "Reparo Windows/native Linux release parity passed: $windowsVersion" -ForegroundColor Green
