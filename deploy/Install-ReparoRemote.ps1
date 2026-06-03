<#
.SYNOPSIS
Installs or updates standalone Reparo on one or more SSH-reachable Windows hosts.

.DESCRIPTION
Uses OpenSSH to run a no-profile encoded PowerShell command on each target. The
remote command downloads the current Reparo.ps1 from GitHub, installs it into
C:\ProgramData\Reparo, verifies the shim, and prints Reparo help.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string[]]$ComputerName,

    [string]$SourceUrl = 'https://raw.githubusercontent.com/16thdoc/Reparo/main/Reparo.ps1',

    [string]$InstallRoot = '$env:ProgramData\Reparo',

    [string]$SshCommand = 'ssh',

    [int]$ConnectTimeoutSeconds = 10,

    [switch]$Preview
)

$ErrorActionPreference = 'Stop'

function New-ReparoRemoteInstallScript {
    param(
        [Parameter(Mandatory)]
        [string]$RemoteSourceUrl,

        [Parameter(Mandatory)]
        [string]$RemoteInstallRoot
    )

@"
`$ErrorActionPreference = 'Stop'
`$installRoot = "$RemoteInstallRoot"
`$bootstrapUrl = "$RemoteSourceUrl"

New-Item -ItemType Directory -Force -Path `$installRoot | Out-Null
`$bootstrapPath = Join-Path `$installRoot 'Reparo.bootstrap.ps1'

Invoke-WebRequest -Uri `$bootstrapUrl -OutFile `$bootstrapPath -UseBasicParsing
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File `$bootstrapPath -Install -InstallRoot `$installRoot -SourceUrl `$bootstrapUrl

`$scriptPath = Join-Path `$installRoot 'Reparo.ps1'
`$shimPath = Join-Path `$installRoot 'bin\reparo.cmd'
Write-Output "REPARO_DEPLOY|Computer=`$env:COMPUTERNAME|Script=`$scriptPath|Shim=`$shimPath|ScriptExists=`$(Test-Path -LiteralPath `$scriptPath)|ShimExists=`$(Test-Path -LiteralPath `$shimPath)"

& `$shimPath -Help
"@
}

$results = New-Object System.Collections.Generic.List[object]

foreach ($target in $ComputerName) {
    Write-Host ""
    Write-Host "========== $target ==========" -ForegroundColor Cyan

    try {
        $remoteScript = New-ReparoRemoteInstallScript -RemoteSourceUrl $SourceUrl -RemoteInstallRoot $InstallRoot
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($remoteScript))
        $sshArgs = @(
            '-o', "ConnectTimeout=$ConnectTimeoutSeconds",
            $target,
            'powershell.exe',
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-EncodedCommand',
            $encoded
        )

        if ($Preview) {
            Write-Host "[Preview] Would run: $SshCommand $($sshArgs -join ' ')" -ForegroundColor Yellow
            $results.Add([pscustomobject]@{
                ComputerName = $target
                Status       = 'Preview'
                Details      = 'No changes made.'
            }) | Out-Null
            continue
        }

        $output = @(& $SshCommand @sshArgs 2>&1)
        $exitCode = $LASTEXITCODE

        if ($output) {
            $output | ForEach-Object { Write-Host $_ }
        }

        if ($exitCode -ne 0) {
            throw "SSH deploy failed with exit code $exitCode"
        }

        $deployLine = $output | Where-Object { [string]$_ -match '^REPARO_DEPLOY\|' } | Select-Object -Last 1
        $results.Add([pscustomobject]@{
            ComputerName = $target
            Status       = 'Success'
            Details      = if ($deployLine) { [string]$deployLine } else { 'Installed, but no deploy marker was returned.' }
        }) | Out-Null
    }
    catch {
        Write-Host "Failed: $($_.Exception.Message)" -ForegroundColor Red
        $results.Add([pscustomobject]@{
            ComputerName = $target
            Status       = 'Failed'
            Details      = $_.Exception.Message
        }) | Out-Null
    }
}

Write-Host ""
Write-Host "========== SUMMARY ==========" -ForegroundColor Magenta
$results | Format-Table -AutoSize

if ($results.Status -contains 'Failed') {
    exit 1
}
