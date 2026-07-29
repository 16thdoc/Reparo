<#
.SYNOPSIS
Signs Reparo source and generated deployment scripts with the local internal signer.

.DESCRIPTION
The private signing key is intentionally non-exportable in CurrentUser\My. This script
must run on the signing workstation under the account that owns that key.
#>
[CmdletBinding()]
param(
    [string]$Thumbprint = '93CE2552E5C7F90600C36BDB83541921FCC97ED1',
    [string]$TimestampServer = 'http://timestamp.digicert.com'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$certificate = Get-Item -LiteralPath "Cert:\CurrentUser\My\$Thumbprint" -ErrorAction Stop
if (-not $certificate.HasPrivateKey) { throw "Signing certificate lacks a private key: $Thumbprint" }

$targets = @(
    (Join-Path $repoRoot 'Reparo.ps1'),
    (Join-Path $repoRoot 'deploy\Ninja-Embedded.ps1'),
    (Join-Path $repoRoot 'deploy\Ninja-Embedded-Offline.ps1'),
    (Join-Path $repoRoot 'deploy\Ninja-Reparo-ReportOnly.ps1'),
    (Join-Path $repoRoot 'deploy\Ninja-Reparo-Update.ps1'),
    (Join-Path $repoRoot 'deploy\Ninja-Reparo-Force-AllowReboot.ps1'),
    (Join-Path $repoRoot 'deploy\Ninja-Reparo-Kill.ps1'),
    (Join-Path $repoRoot 'deploy\Ninja-Reparo-Diagnostic.ps1'),
    (Join-Path $repoRoot 'deploy\ScreenConnect\ScreenConnect-Reparo-Embedded.ps1'),
    (Join-Path $repoRoot 'deploy\signing\Install-ReparoInternalSigningTrust.ps1')
)

foreach ($target in $targets) {
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "Signing target missing: $target" }
    $result = Set-AuthenticodeSignature -FilePath $target -Certificate $certificate -TimestampServer $TimestampServer
    if (-not $result.SignerCertificate -or $result.SignerCertificate.Thumbprint -ne $Thumbprint) {
        throw "Signing did not bind the expected signer to $target."
    }
    if ($result.Status -notin @('Valid', 'UnknownError')) {
        throw "Signing failed for $target. $($result.Status): $($result.StatusMessage)"
    }
    if ($result.Status -eq 'UnknownError') {
        Write-Warning "Signed $target, but this signing workstation does not yet trust the internal root locally. Fleet validation occurs after trust deployment."
    }
    Write-Host "Signed: $target"
}
