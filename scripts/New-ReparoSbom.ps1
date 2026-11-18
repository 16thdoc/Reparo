[CmdletBinding()]
param(
    [string]$SourceRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$ManifestPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$CreatedUtc
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ReparoDigest {
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('SHA1', 'SHA256')][string]$Algorithm
    )

    $stream = [IO.File]::OpenRead($Path)
    try {
        $hasher = [Security.Cryptography.HashAlgorithm]::Create($Algorithm)
        if (-not $hasher) { throw "Hash algorithm is unavailable: $Algorithm" }
        try {
            return (($hasher.ComputeHash($stream) | ForEach-Object { $_.ToString('x2') }) -join '')
        }
        finally {
            $hasher.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

$SourceRoot = [IO.Path]::GetFullPath($SourceRoot)
if (-not $ManifestPath) { $ManifestPath = Join-Path $SourceRoot 'deploy/reparo-release.json' }
$ManifestPath = [IO.Path]::GetFullPath($ManifestPath)
$OutputPath = [IO.Path]::GetFullPath($OutputPath)

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "Release manifest not found: $ManifestPath" }
$manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.version -notmatch '^\d+\.\d+\.\d+\.\d+$') { throw 'Release manifest version is invalid.' }
if ($manifest.commit -notmatch '^[0-9a-f]{40}$') { throw 'Release manifest commit is invalid.' }

$pinnedPrefix = 'https://raw.githubusercontent.com/16thdoc/Reparo/' + $manifest.commit + '/'
foreach ($contract in @(
    @{ Path = 'Reparo.ps1'; Url = [string]$manifest.reparoUrl; Hash = [string]$manifest.sha256 },
    @{ Path = 'linux/reparo-linux'; Url = [string]$manifest.linuxUrl; Hash = [string]$manifest.linuxSha256 },
    @{ Path = 'deploy/install-reparo-linux.sh'; Url = [string]$manifest.linuxInstallerUrl; Hash = [string]$manifest.linuxInstallerSha256 }
)) {
    if ($contract.Url -cne ($pinnedPrefix + $contract.Path)) { throw "Release URL is not pinned to the declared source commit: $($contract.Path)" }
    if ($contract.Hash -cnotmatch '^[A-F0-9]{64}$') { throw "Release SHA-256 is invalid: $($contract.Path)" }
    $localPath = Join-Path $SourceRoot ($contract.Path -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) { throw "Release file is missing: $($contract.Path)" }
    if ((Get-ReparoDigest -Path $localPath -Algorithm SHA256).ToUpperInvariant() -cne $contract.Hash) {
        throw "Local release file differs from the reviewed manifest: $($contract.Path)"
    }
}

$versionPattern = '(?m)^\$script:ReparoVersion\s*=\s*''(?<v>\d+\.\d+\.\d+\.\d+)''\s*$'
$windowsVersion = [regex]::Match([IO.File]::ReadAllText((Join-Path $SourceRoot 'Reparo.ps1')), $versionPattern).Groups['v'].Value
if ($windowsVersion -ne $manifest.version) { throw "Runtime version $windowsVersion differs from manifest version $($manifest.version)." }

$releasePaths = @(
    'Reparo.ps1',
    'linux/reparo-linux',
    'deploy/install-reparo-linux.sh',
    'deploy/install-reparo-windows.cmd',
    'deploy/Install-ReparoRemote.ps1',
    'deploy/Install-MoshiRemote.ps1'
)

$files = New-Object System.Collections.Generic.List[object]
$relationships = New-Object System.Collections.Generic.List[object]
$sha1Values = New-Object System.Collections.Generic.List[string]
foreach ($relativePath in $releasePaths) {
    $nativeRelative = $relativePath -replace '/', [IO.Path]::DirectorySeparatorChar
    $path = Join-Path $SourceRoot $nativeRelative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "SBOM release file is missing: $relativePath" }
    $sha1 = Get-ReparoDigest -Path $path -Algorithm SHA1
    $sha256 = Get-ReparoDigest -Path $path -Algorithm SHA256
    [void]$sha1Values.Add($sha1)
    $spdxId = 'SPDXRef-File-' + (($relativePath -replace '[^A-Za-z0-9.-]', '-').Trim('-'))
    [void]$files.Add([ordered]@{
        fileName = './' + $relativePath
        SPDXID = $spdxId
        checksums = @(
            [ordered]@{ algorithm = 'SHA1'; checksumValue = $sha1 },
            [ordered]@{ algorithm = 'SHA256'; checksumValue = $sha256 }
        )
        fileTypes = @('SOURCE')
        licenseConcluded = 'NOASSERTION'
        licenseInfoInFiles = @('NOASSERTION')
        copyrightText = 'NOASSERTION'
    })
    [void]$relationships.Add([ordered]@{
        spdxElementId = 'SPDXRef-Package-Reparo'
        relationshipType = 'CONTAINS'
        relatedSpdxElement = $spdxId
    })
}

$verificationMaterial = (($sha1Values | Sort-Object) -join '')
$verificationBytes = [Text.Encoding]::ASCII.GetBytes($verificationMaterial)
$verificationHasher = [Security.Cryptography.SHA1]::Create()
try {
    $verificationCode = (($verificationHasher.ComputeHash($verificationBytes) | ForEach-Object { $_.ToString('x2') }) -join '')
}
finally {
    $verificationHasher.Dispose()
}

if ($CreatedUtc) {
    $created = [DateTimeOffset]::Parse($CreatedUtc).ToUniversalTime()
}
else {
    $created = [DateTimeOffset]::UtcNow
}
$createdText = $created.ToString('yyyy-MM-ddTHH:mm:ssZ')
$manifestDigest = Get-ReparoDigest -Path $ManifestPath -Algorithm SHA256
$namespace = 'https://github.com/16thdoc/Reparo/spdx/' + $manifest.version + '/' + $manifestDigest

$document = [ordered]@{
    spdxVersion = 'SPDX-2.3'
    dataLicense = 'CC0-1.0'
    SPDXID = 'SPDXRef-DOCUMENT'
    name = 'Reparo-' + $manifest.version
    documentNamespace = $namespace
    creationInfo = [ordered]@{
        created = $createdText
        creators = @('Organization: 16thdoc', 'Tool: Reparo SBOM generator 1')
    }
    documentDescribes = @('SPDXRef-Package-Reparo')
    packages = @(
        [ordered]@{
            name = 'Reparo'
            SPDXID = 'SPDXRef-Package-Reparo'
            versionInfo = [string]$manifest.version
            downloadLocation = 'https://github.com/16thdoc/Reparo/tree/' + $manifest.commit
            filesAnalyzed = $true
            packageVerificationCode = [ordered]@{ packageVerificationCodeValue = $verificationCode }
            licenseConcluded = 'NOASSERTION'
            licenseDeclared = 'NOASSERTION'
            copyrightText = 'NOASSERTION'
            supplier = 'Organization: 16thdoc'
        }
    )
    files = $files.ToArray()
    relationships = $relationships.ToArray()
}

$parent = Split-Path -Parent $OutputPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
$json = ($document | ConvertTo-Json -Depth 10) -replace "`r`n", "`n"
[IO.File]::WriteAllText($OutputPath, $json + "`n", (New-Object Text.UTF8Encoding($false)))

$written = Get-Item -LiteralPath $OutputPath -Force
if ($written.Length -lt 1 -or (Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8 | ConvertFrom-Json).spdxVersion -ne 'SPDX-2.3') {
    throw 'SBOM write verification failed.'
}

[pscustomobject]@{
    Path = $written.FullName
    Version = [string]$manifest.version
    Commit = [string]$manifest.commit
    Files = $files.Count
    Sha256 = (Get-ReparoDigest -Path $written.FullName -Algorithm SHA256).ToUpperInvariant()
}
