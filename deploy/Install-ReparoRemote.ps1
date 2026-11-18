<#
.SYNOPSIS
Installs or updates standalone Reparo on one or more SSH-reachable Windows hosts.

.DESCRIPTION
Uses OpenSSH to run a no-profile encoded PowerShell command on each target. The
remote command validates GitHub's reviewed release manifest, downloads its pinned
artifact through the public file mirror (with a GitHub transport fallback), installs it into
C:\ProgramData\Reparo, verifies the shim, and prints Reparo help.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string[]]$ComputerName,

    [ValidatePattern('^$|^https://')]
    [string]$SourceUrl = '',

    [ValidatePattern('^$|^[A-Fa-f0-9]{64}$')]
    [string]$SourceSha256 = '',

    [ValidatePattern('^https://')]
    [string]$ReleaseManifestUrl = 'https://raw.githubusercontent.com/16thdoc/Reparo/main/deploy/reparo-release.json',

    [string]$InstallRoot = 'C:\ProgramData\Reparo',

    [string]$SshCommand = 'ssh',

    [int]$ConnectTimeoutSeconds = 10,

    [switch]$Preview
)

$ErrorActionPreference = 'Stop'

function ConvertTo-ReparoPowerShellLiteral {
    param([AllowEmptyString()][string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function New-ReparoRemoteInstallScript {
    param(
        [string]$RemoteSourceUrl,

        [string]$RemoteSourceSha256,

        [Parameter(Mandatory)]
        [string]$RemoteManifestUrl,

        [Parameter(Mandatory)]
        [string]$RemoteInstallRoot
    )

    $template = @"
`$ErrorActionPreference = 'Stop'
`$installRoot = __INSTALL_ROOT__
`$bootstrapUrl = __SOURCE_URL__
`$bootstrapSha256 = __SOURCE_SHA256__
`$manifestUrl = __MANIFEST_URL__
`$bootstrapFallbackUrl = `$null
`$expectedVersion = `$null

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
`$stageRoot = Join-Path ([IO.Path]::GetTempPath()) ('ReparoRemote-' + [guid]::NewGuid().ToString('N'))
`$bootstrapPath = Join-Path `$stageRoot 'Reparo.ps1'
`$manifestPath = Join-Path `$stageRoot 'release.json'
New-Item -ItemType Directory -Path `$stageRoot -ErrorAction Stop | Out-Null
try {
    if ([string]::IsNullOrWhiteSpace(`$bootstrapUrl)) {
        `$manifestUri = `$null
        if (-not [Uri]::TryCreate(`$manifestUrl, [UriKind]::Absolute, [ref]`$manifestUri) -or `$manifestUri.Scheme -ne 'https' -or `$manifestUri.UserInfo) { throw 'Release manifest URL must be absolute HTTPS without credentials.' }
        Invoke-WebRequest -Uri `$manifestUri -Headers @{'User-Agent'='Reparo';'Cache-Control'='no-cache';'Pragma'='no-cache'} -OutFile `$manifestPath -UseBasicParsing
        if ((Get-Item -LiteralPath `$manifestPath).Length -gt 16384) { throw 'Release manifest exceeds 16 KiB.' }
        `$manifest = Get-Content -LiteralPath `$manifestPath -Raw | ConvertFrom-Json -ErrorAction Stop
        `$fields = @('version','commit','reparoUrl','sha256','linuxUrl','linuxSha256','linuxInstallerUrl','linuxInstallerSha256')
        if ((@(`$manifest.PSObject.Properties.Name | Sort-Object) -join ',') -cne (@(`$fields | Sort-Object) -join ',')) { throw 'Release manifest schema is invalid.' }
        if (`$manifest.version -notmatch '^\d+\.\d+\.\d+\.\d+$' -or `$manifest.commit -cnotmatch '^[0-9a-f]{40}$' -or `$manifest.reparoUrl -cne ('https://raw.githubusercontent.com/16thdoc/Reparo/{0}/Reparo.ps1' -f `$manifest.commit) -or `$manifest.sha256 -cnotmatch '^[A-F0-9]{64}$') { throw 'Release manifest pin is invalid.' }
        `$bootstrapFallbackUrl = [string]`$manifest.reparoUrl
        `$bootstrapUrl = 'https://file.thetechnologist.io/reparo/{0}/Reparo.ps1' -f `$manifest.commit
        `$bootstrapSha256 = [string]`$manifest.sha256
        `$expectedVersion = [string]`$manifest.version
    }
    elseif (`$bootstrapSha256 -cnotmatch '^[A-F0-9]{64}$') { throw 'A custom SourceUrl requires SourceSha256.' }

    `$sourceUri = `$null
    if (-not [Uri]::TryCreate(`$bootstrapUrl, [UriKind]::Absolute, [ref]`$sourceUri) -or `$sourceUri.Scheme -ne 'https' -or `$sourceUri.UserInfo) { throw 'Reparo source URL must be absolute HTTPS without credentials.' }
    `$downloadHeaders = @{'User-Agent'='Reparo';'Cache-Control'='no-cache';'Pragma'='no-cache'}
    `$downloadOptions = @{}
    if (`$bootstrapFallbackUrl) { `$downloadHeaders['User-Agent'] = 'Reparo-Download/Windows/Install'; `$downloadOptions['TimeoutSec'] = 60 }
    try {
        Invoke-WebRequest -Uri `$sourceUri -Headers `$downloadHeaders -OutFile `$bootstrapPath -UseBasicParsing -ErrorAction Stop @downloadOptions
    }
    catch {
        if (-not `$bootstrapFallbackUrl) { throw }
        if (-not (`$_.Exception -is [Net.WebException]) -and `$_.Exception.GetType().FullName -notin @('System.Net.Http.HttpRequestException','Microsoft.PowerShell.Commands.HttpResponseException','System.Threading.Tasks.TaskCanceledException','System.TimeoutException')) { throw }
        Write-Warning 'Reparo download mirror unavailable; using the reviewed GitHub artifact. This download is omitted from mirror analytics.'
        Invoke-WebRequest -Uri `$bootstrapFallbackUrl -Headers `$downloadHeaders -OutFile `$bootstrapPath -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
    }
    `$item = Get-Item -LiteralPath `$bootstrapPath
    if (`$item.Length -lt 1 -or `$item.Length -gt 2097152) { throw 'Downloaded Reparo.ps1 size is outside the 1-byte to 2-MiB limit.' }
    `$actualHash = (Get-FileHash -LiteralPath `$bootstrapPath -Algorithm SHA256).Hash
    if (`$actualHash -cne `$bootstrapSha256) { throw "Reparo SHA-256 mismatch. Expected `$bootstrapSha256, got `$actualHash." }
    `$text = [IO.File]::ReadAllText(`$bootstrapPath)
    `$versions = [regex]::Matches(`$text, '(?m)^\`$script:ReparoVersion\s*=\s*''(?<v>\d+\.\d+\.\d+\.\d+)''\s*\r?`$')
    if (`$versions.Count -ne 1 -or (`$expectedVersion -and `$versions[0].Groups['v'].Value -ne `$expectedVersion)) { throw 'Downloaded Reparo.ps1 version identity is invalid.' }
    Unblock-File -LiteralPath `$bootstrapPath -ErrorAction SilentlyContinue
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `$bootstrapPath -Install -InstallRoot `$installRoot
    if (`$LASTEXITCODE -ne 0) { throw "Reparo install exited with code `$LASTEXITCODE." }
}
finally {
    Remove-Item -LiteralPath `$stageRoot -Recurse -Force -ErrorAction SilentlyContinue
}

`$scriptPath = Join-Path `$installRoot 'Reparo.ps1'
`$shimPath = Join-Path `$installRoot 'bin\reparo.cmd'
Write-Output "REPARO_DEPLOY|Computer=`$env:COMPUTERNAME|Script=`$scriptPath|Shim=`$shimPath|ScriptExists=`$(Test-Path -LiteralPath `$scriptPath)|ShimExists=`$(Test-Path -LiteralPath `$shimPath)"

& `$shimPath -Help
"@

    return $template.
        Replace('__INSTALL_ROOT__', (ConvertTo-ReparoPowerShellLiteral $RemoteInstallRoot)).
        Replace('__SOURCE_URL__', (ConvertTo-ReparoPowerShellLiteral $RemoteSourceUrl)).
        Replace('__SOURCE_SHA256__', (ConvertTo-ReparoPowerShellLiteral $RemoteSourceSha256.ToUpperInvariant())).
        Replace('__MANIFEST_URL__', (ConvertTo-ReparoPowerShellLiteral $RemoteManifestUrl))
}

if ([string]::IsNullOrWhiteSpace($SourceUrl) -xor [string]::IsNullOrWhiteSpace($SourceSha256)) {
    throw 'SourceUrl and SourceSha256 must be supplied together; omit both to use the reviewed release manifest.'
}
if ($InstallRoot -notmatch '^[A-Za-z]:\\' -or $InstallRoot -match '[\x00-\x1F\x7F]') {
    throw 'InstallRoot must be an absolute Windows drive path without control characters.'
}

$results = New-Object System.Collections.Generic.List[object]

foreach ($target in $ComputerName) {
    Write-Host ""
    Write-Host "========== $target ==========" -ForegroundColor Cyan

    try {
        if ([string]::IsNullOrWhiteSpace($target) -or $target -match '^-|[\x00-\x1F\x7F]') {
            throw "Invalid SSH target: '$target'"
        }
        $remoteScript = New-ReparoRemoteInstallScript -RemoteSourceUrl $SourceUrl -RemoteSourceSha256 $SourceSha256 -RemoteManifestUrl $ReleaseManifestUrl -RemoteInstallRoot $InstallRoot
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($remoteScript))
        $sshArgs = @(
            '-o', "ConnectTimeout=$ConnectTimeoutSeconds",
            '--',
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
