Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot 'Reparo.ps1'
$remoteDeployPath = Join-Path $repoRoot 'deploy\Install-ReparoRemote.ps1'

foreach ($path in $sourcePath, $remoteDeployPath) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $path,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if ($parseErrors.Count -gt 0) {
        throw "TLS bootstrap source does not parse: $path - $($parseErrors[0].Message)"
    }
}

$source = Get-Content -LiteralPath $sourcePath -Raw
$newBlockStart = $source.IndexOf('elseif ($New) {', [StringComparison]::Ordinal)
$manifestRequest = $source.IndexOf('$manifest = Invoke-RestMethod', $newBlockStart, [StringComparison]::Ordinal)
$tlsEnable = $source.IndexOf('[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12', $newBlockStart, [StringComparison]::Ordinal)

if ($newBlockStart -lt 0 -or $manifestRequest -lt 0) {
    throw 'Could not locate the reviewed-release manifest request.'
}
if ($tlsEnable -lt $newBlockStart -or $tlsEnable -gt $manifestRequest) {
    throw 'Reparo -New must enable TLS 1.2 before requesting the reviewed-release manifest.'
}

$remoteSource = Get-Content -LiteralPath $remoteDeployPath -Raw
$remoteTlsEnable = $remoteSource.IndexOf('[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12', [StringComparison]::Ordinal)
$remoteDownload = $remoteSource.IndexOf('Invoke-WebRequest -Uri `$bootstrapUrl', [StringComparison]::Ordinal)

if ($remoteTlsEnable -lt 0 -or $remoteDownload -lt 0 -or $remoteTlsEnable -gt $remoteDownload) {
    throw 'The remote Windows installer must enable TLS 1.2 before downloading its bootstrap.'
}

Write-Host 'Reparo TLS 1.2 bootstrap contracts passed.' -ForegroundColor Green
