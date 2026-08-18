Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot 'Reparo.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("reparo-new-transaction-" + [guid]::NewGuid())
$installRoot = Join-Path $testRoot 'runtime'
$logRoot = Join-Path $testRoot 'logs'
$brokenPath = Join-Path $testRoot 'Reparo.broken.ps1'
$originalUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$originalMachinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')

function Invoke-ReparoNewTest {
    param([Parameter(Mandatory)][string]$CandidatePath, [switch]$ExpectFailure)

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sourcePath -Latest -SourceUrl $CandidatePath -InstallRoot $installRoot -LogRoot $logRoot
    $exitCode = $LASTEXITCODE
    if ($ExpectFailure -and $exitCode -eq 0) { throw 'Broken candidate unexpectedly deployed successfully.' }
    if (-not $ExpectFailure -and $exitCode -ne 0) { throw "Known-good candidate failed deployment with exit code $exitCode." }
}

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sourcePath -Install -InstallRoot $installRoot -LogRoot $logRoot
    if ($LASTEXITCODE -ne 0) { throw "Offline -Install failed with exit code $LASTEXITCODE." }
    if (-not (Test-Path -LiteralPath (Join-Path $installRoot 'Reparo.ps1') -PathType Leaf)) { throw 'Offline -Install did not create the runtime.' }
    Invoke-ReparoNewTest -CandidatePath $sourcePath

    $installedPath = Join-Path $installRoot 'Reparo.ps1'
    if (-not (Test-Path -LiteralPath $installedPath -PathType Leaf)) { throw 'Known-good candidate did not create the runtime.' }
    $baselineHash = (Get-FileHash -LiteralPath $installedPath -Algorithm SHA256).Hash

    $brokenContent = Get-Content -LiteralPath $sourcePath -Raw
    $expectedVersionOutput = 'Write-Host "Reparo $script:ReparoVersion"'
    if (-not $brokenContent.Contains($expectedVersionOutput)) { throw 'Could not create a deterministic broken candidate; version output was not found.' }
    $brokenContent = $brokenContent.Replace($expectedVersionOutput, 'Write-Host "Broken $script:ReparoVersion"')
    Set-Content -LiteralPath $brokenPath -Value $brokenContent -Encoding UTF8

    Invoke-ReparoNewTest -CandidatePath $brokenPath -ExpectFailure
    $finalHash = (Get-FileHash -LiteralPath $installedPath -Algorithm SHA256).Hash
    if ($finalHash -ne $baselineHash) { throw 'Failed deployment did not restore the previous runtime.' }

    Write-Host 'Reparo transactional -Latest integration test passed.' -ForegroundColor Green
}
finally {
    [Environment]::SetEnvironmentVariable('Path', $originalUserPath, 'User')
    [Environment]::SetEnvironmentVariable('Path', $originalMachinePath, 'Machine')
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
