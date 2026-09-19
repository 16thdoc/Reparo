Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot 'Reparo.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("reparo-new-transaction-" + [guid]::NewGuid())
$installRoot = Join-Path $testRoot 'runtime'
$logRoot = Join-Path $testRoot 'logs'
$brokenPath = Join-Path $testRoot 'Reparo.broken.ps1'
$readOnlyCandidatePath = Join-Path $testRoot 'Reparo.readonly-candidate.ps1'
$lockedCandidatePath = Join-Path $testRoot 'Reparo.locked-candidate.ps1'
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

    $readOnlyCandidateContent = (Get-Content -LiteralPath $sourcePath -Raw) + "`r`n# Read-only destination replacement test.`r`n"
    Set-Content -LiteralPath $readOnlyCandidatePath -Value $readOnlyCandidateContent -Encoding UTF8
    (Get-Item -LiteralPath $installedPath).IsReadOnly = $true
    Invoke-ReparoNewTest -CandidatePath $readOnlyCandidatePath
    $readOnlyCandidateHash = (Get-FileHash -LiteralPath $readOnlyCandidatePath -Algorithm SHA256).Hash
    $readOnlyInstalledHash = (Get-FileHash -LiteralPath $installedPath -Algorithm SHA256).Hash
    if ($readOnlyInstalledHash -ne $readOnlyCandidateHash) { throw 'Read-only installed runtime was not replaced by the staged candidate.' }
    if ((Get-Item -LiteralPath $installedPath).IsReadOnly) { throw 'Installed runtime remained read-only after replacement.' }

    $lockedCandidateContent = (Get-Content -LiteralPath $sourcePath -Raw) + "`r`n# Transient file-lock replacement test.`r`n"
    Set-Content -LiteralPath $lockedCandidatePath -Value $lockedCandidateContent -Encoding UTF8
    $lockedCandidateHash = (Get-FileHash -LiteralPath $lockedCandidatePath -Algorithm SHA256).Hash
    $fileLock = [System.IO.File]::Open($installedPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try {
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = 'powershell.exe'
        $startInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Latest -SourceUrl "{1}" -InstallRoot "{2}" -LogRoot "{3}"' -f $sourcePath, $lockedCandidatePath, $installRoot, $logRoot
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $lockedUpdateProcess = [System.Diagnostics.Process]::Start($startInfo)
        Start-Sleep -Milliseconds 1500
    }
    finally {
        $fileLock.Dispose()
    }
    $lockedUpdateProcess.WaitForExit()
    $lockedUpdateOutput = $lockedUpdateProcess.StandardOutput.ReadToEnd() + $lockedUpdateProcess.StandardError.ReadToEnd()
    if ($lockedUpdateProcess.ExitCode -ne 0) { throw "Transiently locked runtime update failed with exit code $($lockedUpdateProcess.ExitCode): $lockedUpdateOutput" }
    if ((Get-FileHash -LiteralPath $installedPath -Algorithm SHA256).Hash -ne $lockedCandidateHash) { throw 'Transiently locked installed runtime was not replaced after retry.' }
    $retryLog = Get-ChildItem -LiteralPath $logRoot -Filter '*_COMPLETE.log' | Sort-Object LastWriteTime | Select-Object -Last 1
    if (-not $retryLog -or -not (Select-String -LiteralPath $retryLog.FullName -SimpleMatch '[DEPLOY-WAIT]' -Quiet)) { throw 'Transient file-lock replacement did not exercise the retry path.' }

    $baselineHash = (Get-FileHash -LiteralPath $installedPath -Algorithm SHA256).Hash

    $brokenContent = Get-Content -LiteralPath $sourcePath -Raw
    $expectedVersionOutput = 'Write-Host "Reparo $script:ReparoVersion"'
    if (-not $brokenContent.Contains($expectedVersionOutput)) { throw 'Could not create a deterministic broken candidate; version output was not found.' }
    $brokenContent = $brokenContent.Replace($expectedVersionOutput, 'Write-Host "Broken $script:ReparoVersion"')
    Set-Content -LiteralPath $brokenPath -Value $brokenContent -Encoding UTF8

    Invoke-ReparoNewTest -CandidatePath $brokenPath -ExpectFailure
    $finalHash = (Get-FileHash -LiteralPath $installedPath -Algorithm SHA256).Hash
    if ($finalHash -ne $baselineHash) { throw 'Failed deployment did not restore the previous runtime.' }

    $source = Get-Content -LiteralPath $sourcePath -Raw
    foreach ($required in @(
        'function Copy-ReparoFileWithRetry',
        '$deploymentErrorMessage = $_.Exception.Message',
        'Reparo deployment rollback also failed:',
        'Original deployment error:',
        'Rollback also failed:'
    )) {
        if (-not $source.Contains($required)) { throw "Transactional replacement/rollback contract is absent: $required" }
    }

    Write-Host 'Reparo transactional -Latest integration test passed.' -ForegroundColor Green
}
finally {
    [Environment]::SetEnvironmentVariable('Path', $originalUserPath, 'User')
    [Environment]::SetEnvironmentVariable('Path', $originalMachinePath, 'Machine')
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
