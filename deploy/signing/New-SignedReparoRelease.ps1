<#
.SYNOPSIS
Builds and verifies a fully signed Reparo release working tree.

.DESCRIPTION
Run this on the signing workstation after any Reparo or deployment-source change and
before reviewing/committing a release. It signs Reparo source first, regenerates every
embedded artifact from that signed source, signs the generated artifacts, and verifies
the approved signer thumbprint. It never commits, pushes, or deploys.
#>
[CmdletBinding()]
param(
    [string]$Thumbprint = '081400500D9EBC932690D277D95D8F1097CB5A88',
    [string]$TimestampServer = 'http://timestamp.digicert.com'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$certificate = Get-Item -LiteralPath "Cert:\CurrentUser\My\$Thumbprint" -ErrorAction Stop
if (-not $certificate.HasPrivateKey) { throw "Signing certificate lacks a private key: $Thumbprint" }

function Assert-ReparoSigner {
    param([Parameter(Mandatory)][string]$Path)

    $signature = Get-AuthenticodeSignature -FilePath $Path
    if (-not $signature.SignerCertificate -or $signature.SignerCertificate.Thumbprint -ne $Thumbprint) {
        throw "Unexpected or missing Reparo signer on $Path."
    }
    Write-Host "Verified signer: $Path ($($signature.Status))"
}

$sourcePath = Join-Path $repoRoot 'Reparo.ps1'
$parityTest = Join-Path $repoRoot 'Tests\Test-ReparoReleaseParity.ps1'
& $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $parityTest
if ($LASTEXITCODE -ne 0) { throw "Windows/native Linux release parity validation failed with exit code $LASTEXITCODE." }

$sourceSignature = Set-AuthenticodeSignature -FilePath $sourcePath -Certificate $certificate -TimestampServer $TimestampServer
if (-not $sourceSignature.SignerCertificate -or $sourceSignature.SignerCertificate.Thumbprint -ne $Thumbprint) {
    throw "Could not sign Reparo source with $Thumbprint."
}

$generator = Join-Path $repoRoot 'deploy\New-NinjaEmbeddedDeployment.ps1'
$generationCommands = @(
    @(),
    @('-OutputPath', (Join-Path $repoRoot 'deploy\Ninja-Embedded-Offline.ps1'), '-FixedAction', 'OfflineInstallOnly'),
    @('-OutputPath', (Join-Path $repoRoot 'deploy\Ninja-Reparo-ReportOnly.ps1'), '-FixedAction', 'ReportOnly'),
    @('-OutputPath', (Join-Path $repoRoot 'deploy\Ninja-Reparo-Update.ps1'), '-FixedAction', 'Update'),
    @('-OutputPath', (Join-Path $repoRoot 'deploy\Ninja-Reparo-Force-AllowReboot.ps1'), '-FixedAction', 'ForceAllowReboot'),
    @('-OutputPath', (Join-Path $repoRoot 'deploy\Ninja-Reparo-Kill.ps1'), '-FixedAction', 'Kill'),
    @('-OutputPath', (Join-Path $repoRoot 'deploy\ScreenConnect\ScreenConnect-Reparo-Embedded.ps1'), '-DeploymentLabel', 'ScreenConnect Toolbox', '-DisableNinjaCustomField', '-FixedAction', 'Dynamic')
)

foreach ($generationArgs in $generationCommands) {
    & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $generator @generationArgs
    if ($LASTEXITCODE -ne 0) { throw "Artifact generation failed with exit code $LASTEXITCODE." }
}

& $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Sign-ReparoArtifacts.ps1') -Thumbprint $Thumbprint -TimestampServer $TimestampServer
if ($LASTEXITCODE -ne 0) { throw "Artifact signing failed with exit code $LASTEXITCODE." }

$signedTargets = @(
    $sourcePath,
    (Join-Path $repoRoot 'deploy\Ninja-Embedded.ps1'),
    (Join-Path $repoRoot 'deploy\Ninja-Embedded-Offline.ps1'),
    (Join-Path $repoRoot 'deploy\Ninja-Reparo-ReportOnly.ps1'),
    (Join-Path $repoRoot 'deploy\Ninja-Reparo-Update.ps1'),
    (Join-Path $repoRoot 'deploy\Ninja-Reparo-Force-AllowReboot.ps1'),
    (Join-Path $repoRoot 'deploy\Ninja-Reparo-Kill.ps1'),
    (Join-Path $repoRoot 'deploy\Ninja-Reparo-New.ps1'),
    (Join-Path $repoRoot 'deploy\Ninja-Reparo-Uninstall.ps1'),
    (Join-Path $repoRoot 'deploy\Ninja-Reparo-Diagnostic.ps1'),
    (Join-Path $repoRoot 'deploy\ScreenConnect\ScreenConnect-Reparo-Embedded.ps1'),
    (Join-Path $repoRoot 'deploy\ScreenConnect\ScreenConnect-Reparo-Uninstall.ps1'),
    (Join-Path $repoRoot 'deploy\signing\Install-ReparoInternalSigningTrust.ps1')
)
foreach ($target in $signedTargets) { Assert-ReparoSigner -Path $target }

Write-Host 'Signed Reparo release working tree is ready for review, commit, and intentional rollout.'
