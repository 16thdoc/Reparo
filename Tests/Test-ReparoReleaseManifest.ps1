Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $repoRoot 'deploy\reparo-release.json'
$sourcePath = Join-Path $repoRoot 'Reparo.ps1'
$deployerPath = Join-Path $repoRoot 'deploy\Ninja-Reparo-GitHub.ps1'
$forceDeployerPath = Join-Path $repoRoot 'deploy\Ninja-Reparo-Force-GitHub.ps1'
$directDeployerPath = Join-Path $repoRoot 'deploy\Ninja-GitHub.ps1'

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

$deployer = Get-Content -LiteralPath $deployerPath -Raw
if (-not $deployer.Contains('https://raw.githubusercontent.com/16thdoc/Reparo/refs/heads/main/deploy/reparo-release.json')) {
    throw 'Ninja release-channel deployer is not pinned to the stable main-branch manifest URL.'
}

$forceDeployer = Get-Content -LiteralPath $forceDeployerPath -Raw
foreach ($required in @(
    'https://raw.githubusercontent.com/16thdoc/Reparo/refs/heads/main/deploy/reparo-release.json',
    '& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runtimePath -Force -LogRoot $logRoot',
    'Reparo bootstrap SHA-256 mismatch'
)) {
    if (-not $forceDeployer.Contains($required)) {
        throw "Ninja Force release-channel deployer contract is absent: $required"
    }
}

$directDeployer = Get-Content -LiteralPath $directDeployerPath -Raw
if (-not $directDeployer.Contains($expectedUrl)) {
    throw 'Ninja direct-use deployer default is not pinned to the reviewed release manifest commit.'
}

Write-Host "Reparo release manifest passed: $($manifest.version) $($manifest.commit)" -ForegroundColor Green
