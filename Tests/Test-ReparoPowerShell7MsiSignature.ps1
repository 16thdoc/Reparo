Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot 'Reparo.ps1'
$source = Get-Content -LiteralPath $sourcePath -Raw

$powerShellSection = [regex]::Match($source, '(?s)Invoke-ReparoCommandStep -Section ''PowerShell7'' -Command @".*?"@ -TimeoutSeconds')
if (-not $powerShellSection.Success) {
    throw 'Could not locate the PowerShell 7 MSI section.'
}

foreach ($required in @(
    'Get-AuthenticodeSignature -FilePath `$msiPath',
    '`$signature.Status -ne ''Valid''',
    '`$signature.SignerCertificate.Subject -notmatch ''(^|,\s*)CN=Microsoft Corporation(,|$)''',
    'PowerShell MSI signature is not a valid Microsoft Authenticode signature',
    '& msiexec.exe @msiArguments'
)) {
    if (-not $powerShellSection.Value.Contains($required)) {
        throw "PowerShell 7 MSI signature validation is missing: $required"
    }
}

$signatureIndex = $powerShellSection.Value.IndexOf('Get-AuthenticodeSignature -FilePath `$msiPath')
$installerIndex = $powerShellSection.Value.IndexOf('& msiexec.exe @msiArguments')
if ($signatureIndex -lt 0 -or $installerIndex -lt 0 -or $signatureIndex -ge $installerIndex) {
    throw 'PowerShell 7 MSI signature validation must run before msiexec.'
}

Write-Host 'Reparo PowerShell 7 MSI Authenticode validation contract passed.' -ForegroundColor Green
