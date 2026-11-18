Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$generator = Join-Path $repoRoot 'scripts/New-ReparoSbom.ps1'
$releaseWorkflow = Join-Path $repoRoot '.github/workflows/release-attestation.yml'
$testWorkflow = Join-Path $repoRoot '.github/workflows/test-steam-headless.yml'

foreach ($path in @($generator, $releaseWorkflow, $testWorkflow)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Supply-chain file is missing: $path" }
}

$tokens = $null
$errors = $null
[void][Management.Automation.Language.Parser]::ParseFile($generator, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw "SBOM generator does not parse: $($errors[0].Message)" }

$source = Get-Content -LiteralPath (Join-Path $repoRoot 'Reparo.ps1') -Raw
$versionMatch = [regex]::Match($source, '(?m)^\$script:ReparoVersion\s*=\s*''(?<v>\d+\.\d+\.\d+\.\d+)''\s*$')
if (-not $versionMatch.Success) { throw 'Cannot read Reparo source version for SBOM fixture.' }
$version = $versionMatch.Groups['v'].Value
$fixtureCommit = '0123456789abcdef0123456789abcdef01234567'
$prefix = "https://raw.githubusercontent.com/16thdoc/Reparo/$fixtureCommit/"
$fixture = [ordered]@{
    version = $version
    commit = $fixtureCommit
    reparoUrl = $prefix + 'Reparo.ps1'
    sha256 = (Get-FileHash -LiteralPath (Join-Path $repoRoot 'Reparo.ps1') -Algorithm SHA256).Hash
    linuxUrl = $prefix + 'linux/reparo-linux'
    linuxSha256 = (Get-FileHash -LiteralPath (Join-Path $repoRoot 'linux/reparo-linux') -Algorithm SHA256).Hash
    linuxInstallerUrl = $prefix + 'deploy/install-reparo-linux.sh'
    linuxInstallerSha256 = (Get-FileHash -LiteralPath (Join-Path $repoRoot 'deploy/install-reparo-linux.sh') -Algorithm SHA256).Hash
}

$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('reparo-supply-chain-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
    $fixtureManifest = Join-Path $fixtureRoot 'manifest.json'
    $utf8 = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($fixtureManifest, (($fixture | ConvertTo-Json -Depth 5) -replace "`r`n", "`n") + "`n", $utf8)
    $first = Join-Path $fixtureRoot 'first.spdx.json'
    $second = Join-Path $fixtureRoot 'second.spdx.json'
    $created = '2026-11-18T00:00:00Z'
    & $generator -SourceRoot $repoRoot -ManifestPath $fixtureManifest -OutputPath $first -CreatedUtc $created | Out-Null
    & $generator -SourceRoot $repoRoot -ManifestPath $fixtureManifest -OutputPath $second -CreatedUtc $created | Out-Null
    $firstBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($first))
    $secondBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($second))
    if ($firstBytes -cne $secondBytes) {
        throw 'SBOM generation is not deterministic for identical inputs.'
    }

    $sbom = Get-Content -LiteralPath $first -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($sbom.spdxVersion -ne 'SPDX-2.3' -or $sbom.dataLicense -ne 'CC0-1.0') { throw 'Unexpected SPDX document contract.' }
    $createdValue = $sbom.creationInfo.created
    $actualCreated = if ($createdValue -is [DateTime]) {
        ([DateTime]$createdValue).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
    else {
        [DateTimeOffset]::Parse([string]$createdValue).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
    if ($actualCreated -ne $created -or $sbom.packages[0].versionInfo -ne $version) {
        throw "SBOM release identity is incorrect. Created='$actualCreated' Version='$($sbom.packages[0].versionInfo)' ExpectedCreated='$created' ExpectedVersion='$version'"
    }
    if ($sbom.files.Count -ne 6 -or $sbom.relationships.Count -ne 6) { throw 'SBOM must describe the six supported release artifacts.' }
    if ($sbom.packages[0].packageVerificationCode.packageVerificationCodeValue -notmatch '^[0-9a-f]{40}$') { throw 'SBOM package verification code is invalid.' }
    foreach ($file in @($sbom.files)) {
        $relative = ([string]$file.fileName).Substring(2)
        $path = Join-Path $repoRoot ($relative -replace '/', [IO.Path]::DirectorySeparatorChar)
        $recorded = @($file.checksums | Where-Object algorithm -eq 'SHA256' | Select-Object -ExpandProperty checksumValue)
        if ($recorded.Count -ne 1 -or $recorded[0] -cne (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()) {
            throw "SBOM checksum mismatch: $relative"
        }
    }

    $tampered = $fixture | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    $tampered.reparoUrl = 'https://raw.githubusercontent.com/16thdoc/Reparo/main/Reparo.ps1'
    $tamperedManifest = Join-Path $fixtureRoot 'tampered.json'
    [IO.File]::WriteAllText($tamperedManifest, (($tampered | ConvertTo-Json -Depth 5) -replace "`r`n", "`n") + "`n", $utf8)
    $failure = $null
    try {
        & $generator -SourceRoot $repoRoot -ManifestPath $tamperedManifest -OutputPath (Join-Path $fixtureRoot 'bad.spdx.json') -CreatedUtc $created | Out-Null
    }
    catch { $failure = $_.Exception.Message }
    if ($failure -notmatch 'not pinned') { throw "Mutable SBOM input was not rejected. Failure='$failure'" }
}
finally {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$workflowFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot '.github/workflows') -File | Where-Object Extension -in @('.yml', '.yaml'))
foreach ($workflow in $workflowFiles) {
    $text = Get-Content -LiteralPath $workflow.FullName -Raw
    foreach ($match in [regex]::Matches($text, '(?m)^\s*-?\s*uses:\s*(?<action>[^\s#]+)')) {
        if ($match.Groups['action'].Value -notmatch '@[0-9a-f]{40}$') {
            throw "Workflow action is not pinned to a full commit SHA: $($workflow.Name) $($match.Groups['action'].Value)"
        }
    }
    $checkoutCount = [regex]::Matches($text, 'uses:\s*actions/checkout@[0-9a-f]{40}').Count
    $credentialCount = [regex]::Matches($text, '(?m)^\s*persist-credentials:\s*false\s*$').Count
    if ($credentialCount -lt $checkoutCount) { throw "Every checkout must disable persisted credentials: $($workflow.Name)" }
}

$attestation = Get-Content -LiteralPath $releaseWorkflow -Raw
foreach ($required in @(
    'id-token: write',
    'attestations: write',
    '$sourceCommit = ''${{ steps.release.outputs.source_commit }}''',
    'git archive --format=zip',
    '-SourceRoot $sourceRoot',
    'actions/attest-build-provenance@e8998f949152b193b063cb0ec769d69d929409be',
    'actions/attest-sbom@bd218ad0dbcb3e146bd073d1d9c6d78e08aa8a0b',
    'actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02'
)) {
    if (-not $attestation.Contains($required)) { throw "Release attestation contract is missing: $required" }
}

Write-Host 'Reparo supply-chain contracts passed.' -ForegroundColor Green
