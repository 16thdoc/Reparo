Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $repoRoot 'deploy\reparo-release.json'
$sourcePath = Join-Path $repoRoot 'Reparo.ps1'

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -ErrorAction Stop
if ($manifest.version -notmatch '^\d+\.\d+\.\d+\.\d+$') { throw 'Release manifest version is invalid.' }
if ($manifest.commit -notmatch '^[0-9a-f]{40}$') { throw 'Release manifest commit must be a full lowercase SHA-1.' }
if ($manifest.sha256 -notmatch '^[A-F0-9]{64}$') { throw 'Release manifest SHA-256 must be uppercase hexadecimal.' }

$expectedUrl = 'https://raw.githubusercontent.com/16thdoc/Reparo/{0}/Reparo.ps1' -f $manifest.commit
if ($manifest.reparoUrl -ne $expectedUrl) { throw 'Release manifest Reparo URL is not pinned to its commit.' }

$sourceVersion = (Select-String -LiteralPath $sourcePath -Pattern "ReparoVersion\s*=\s*'([^']+)'" | Select-Object -First 1).Matches[0].Groups[1].Value
if ($manifest.version -ne $sourceVersion) { throw "Release manifest version $($manifest.version) does not match Reparo.ps1 $sourceVersion." }

$sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
if ($manifest.sha256 -ne $sourceHash) { throw "Release manifest SHA-256 does not match Reparo.ps1. Manifest=$($manifest.sha256) Source=$sourceHash" }
foreach ($artifact in @(
    @{ Url = 'linuxUrl'; Hash = 'linuxSha256'; Path = 'linux/reparo-linux' },
    @{ Url = 'linuxInstallerUrl'; Hash = 'linuxInstallerSha256'; Path = 'deploy/install-reparo-linux.sh' }
)) {
    $expected = 'https://raw.githubusercontent.com/16thdoc/Reparo/{0}/{1}' -f $manifest.commit, $artifact.Path
    if ($manifest.($artifact.Url) -cne $expected) { throw "Native artifact URL is not commit-pinned: $($artifact.Path)" }
    $digest = (Get-FileHash -LiteralPath (Join-Path $repoRoot $artifact.Path) -Algorithm SHA256).Hash
    if ($manifest.($artifact.Hash) -cne $digest) { throw "Native artifact digest mismatch: $($artifact.Path)" }
}

Write-Host "Reparo release manifest passed: $($manifest.version) $($manifest.commit)" -ForegroundColor Green
