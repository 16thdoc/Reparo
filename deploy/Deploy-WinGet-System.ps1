#requires -Version 5.1
<#
.SYNOPSIS
Provision stable Microsoft App Installer machine-wide, independently of Reparo.
.DESCRIPTION
Reviewed from the original 2026-10-01 standalone baseline. Use 64-bit Windows
PowerShell on supported x64 Windows client builds. Non-preview exit 0 proves provisioning
at target/newer version, not user registration, WinGet runtime or maintenance.
Preview exit 0 proves only a non-executing plan. Never reboots, runs Reparo,
upgrades apps or attempts SYSTEM AppX registration.
Offline inputs must be previously trusted GitHub release metadata/assets.
#>
[CmdletBinding()]
param(
    [switch]$Preview,
    [string]$ReleaseMetadata,
    [string]$AssetDirectory,
    [uri]$Proxy,
    [ValidateRange(10,1800)][int]$DownloadTimeoutSeconds=900,
    [string]$LogRoot="$env:ProgramData\WinGetDeployment\Logs"
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$exitCode=1; $work=$null; $transcribing=$false

function Get-WinGetReleaseAsset {
    param([object]$Release,[string]$Pattern)
    $assets=@($Release.assets | Where-Object { $_.name -match $Pattern })
    if ($assets.Count -ne 1) { throw "Expected one release asset matching '$Pattern'; found $($assets.Count)." }
    return $assets[0]
}

function Save-WinGetReleaseAsset {
    param([object]$Asset,[string]$Directory,[string]$OfflineDirectory,[uri]$Proxy,[int]$TimeoutSeconds=900)
    if ($Asset.name -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]+$' -or $Asset.name -ne [IO.Path]::GetFileName($Asset.name)) { throw 'Unsafe release asset filename.' }
    if ($Asset.digest -notmatch '^sha256:([a-fA-F0-9]{64})$') { throw "Missing release SHA256 digest: $($Asset.name)." }
    $expected=$Matches[1]
    $uri=[uri]$Asset.browser_download_url
    if ($uri.Scheme -ne 'https' -or $uri.Host -ne 'github.com' -or $uri.AbsolutePath -notlike '/microsoft/winget-cli/releases/download/*' -or $uri.Query -or $uri.UserInfo) { throw 'Asset URL is not an allowed Microsoft WinGet GitHub release.' }
    $path=Join-Path $Directory $Asset.name
    if ($OfflineDirectory) { Copy-Item -LiteralPath (Join-Path $OfflineDirectory $Asset.name) -Destination $path -ErrorAction Stop }
    else {
        Write-Host "Downloading $($Asset.name)..."
        $request=@{ Uri=$uri; OutFile=$path; UseBasicParsing=$true; TimeoutSec=$TimeoutSeconds; ErrorAction='Stop' }
        if ($Proxy) { $request.Proxy=$Proxy }
        Invoke-WebRequest @request
    }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $expected) { throw "SHA256 mismatch: $($Asset.name)." }
    return $path
}

function Get-WinGetBundleIdentity {
    param([string]$Path)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=[IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry=$zip.GetEntry('AppxMetadata/AppxBundleManifest.xml')
        if (-not $entry) { throw 'Bundle manifest missing.' }
        $reader=New-Object IO.StreamReader($entry.Open())
        try { [xml]$manifest=$reader.ReadToEnd() } finally { $reader.Dispose() }
        if ($manifest.Bundle.Identity.Name -ne 'Microsoft.DesktopAppInstaller' -or $manifest.Bundle.Identity.Publisher -notmatch '(^|,\s*)CN=Microsoft Corporation(,|$)') { throw 'Unexpected App Installer bundle identity/publisher.' }
        return [version]$manifest.Bundle.Identity.Version
    }
    finally { $zip.Dispose() }
}

try {
    if (-not [Environment]::Is64BitProcess -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') { throw 'Use 64-bit Windows PowerShell on x64 Windows; 32-bit/ARM hosts are unsupported by this artifact.' }
    $os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    if ([int]$os.BuildNumber -lt 17763 -or $os.ProductType -ne 1) { throw 'This artifact supports x64 Windows client build 17763 or newer; legacy/Server provisioning is not verified.' }
    if ([bool]$ReleaseMetadata -ne [bool]$AssetDirectory) { throw 'Offline deployment requires both -ReleaseMetadata and -AssetDirectory.' }
    if ($Proxy -and ($Proxy.Scheme -notin @('http','https') -or $Proxy.UserInfo)) { throw 'Proxy must be an HTTP(S) endpoint without embedded credentials.' }
    if ($Preview) {
        Write-Output 'PREVIEW: stable App Installer provisioning only; no network, package changes or reboot.'
        Write-Output "Transport: $(if ($ReleaseMetadata) {'trusted offline release metadata/assets'} else {'Microsoft WinGet GitHub stable release'}); timeout=$DownloadTimeoutSeconds seconds per download."
        Write-Output 'Next: elevation, release/hash validation, target/newer-version comparison, signature-enforced DISM provisioning and independent verification.'
        exit 0
    }
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    $principal=New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run as SYSTEM or an elevated administrator.' }
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
    $runId='{0}_{1}' -f (Get-Date -Format yyyyMMdd_HHmmss),[guid]::NewGuid().ToString('N')
    $log=Join-Path $LogRoot "deploy_$runId.log"
    Start-Transcript -Path $log -ErrorAction Stop | Out-Null; $transcribing=$true
    $work=Join-Path (Split-Path -Parent $LogRoot) "staging_$runId"
    New-Item -ItemType Directory -Path $work -ErrorAction Stop | Out-Null
    Write-Output "Context: $(if ($identity.IsSystem) {'SYSTEM'} else {'elevated administrator'}); scope: provisioning only."
    [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Import-Module Dism -ErrorAction Stop
    if ($ReleaseMetadata) { $release=Get-Content -LiteralPath $ReleaseMetadata -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
    else {
        $request=@{ Uri='https://api.github.com/repos/microsoft/winget-cli/releases/latest'; Headers=@{ 'User-Agent'='Reparo-WinGet-Provisioning'; Accept='application/vnd.github+json' }; TimeoutSec=120; ErrorAction='Stop' }
        if ($Proxy) { $request.Proxy=$Proxy }; $release=Invoke-RestMethod @request
    }
    if ($release.draft -or $release.prerelease -or $release.tag_name -notmatch '^v?\d+\.\d+\.\d+') { throw 'Release is not a stable versioned WinGet release.' }
    $bundleAsset=Get-WinGetReleaseAsset $release '^Microsoft\.DesktopAppInstaller_.*\.msixbundle$'
    $bundle=Save-WinGetReleaseAsset $bundleAsset $work $AssetDirectory $Proxy $DownloadTimeoutSeconds
    $targetVersion=Get-WinGetBundleIdentity $bundle
    $existing=@(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -eq 'Microsoft.DesktopAppInstaller' -and [version]$_.Version -ge $targetVersion })
    if ($existing.Count -eq 0) {
        $license=Save-WinGetReleaseAsset (Get-WinGetReleaseAsset $release '_License[0-9]*\.xml$') $work $AssetDirectory $Proxy $DownloadTimeoutSeconds
        $dependenciesZip=Save-WinGetReleaseAsset (Get-WinGetReleaseAsset $release '^DesktopAppInstaller_Dependencies\.zip$') $work $AssetDirectory $Proxy $DownloadTimeoutSeconds
        $dependenciesRoot=Join-Path $work 'Dependencies'
        Expand-Archive -LiteralPath $dependenciesZip -DestinationPath $dependenciesRoot -ErrorAction Stop
        $dependencies=@(Get-ChildItem -LiteralPath $dependenciesRoot -Recurse -File | Where-Object { $_.Extension -in @('.appx','.msix') -and $_.FullName -match '[\\/]x64[\\/]' } | ForEach-Object { $_.FullName })
        if ($dependencies.Count -eq 0) { throw 'Release contains no x64 dependency packages.' }
        # DISM enforces package trust/signatures; no SkipLicense/unsigned bypass.
        $result=Add-AppxProvisionedPackage -Online -PackagePath $bundle -LicensePath $license -DependencyPackagePath $dependencies -ErrorAction Stop
        if ($result.RestartNeeded) { Write-Warning 'Provisioning reports a pending restart. No reboot was requested; the operator must handle it.' }
    }
    else { Write-Output "Already provisioned at target/newer version: $($existing[0].Version); no downgrade or reprovisioning." }
    $verified=@(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -eq 'Microsoft.DesktopAppInstaller' -and [version]$_.Version -ge $targetVersion })
    if ($verified.Count -eq 0) { throw 'Target/newer App Installer provisioning was not independently verified.' }
    Write-Output "PROVISIONED: $($verified[0].Version); release=$($release.tag_name)."
    Write-Output 'User registration may require sign-out/sign-in. Runtime, sources and user/machine maintenance remain UNVERIFIED. No reboot requested.'
    $exitCode=0
}
catch {
    Write-Output "FAILED provisioning: $($_.Exception.Message) (error-id=$($_.FullyQualifiedErrorId))"
    if ($work) { Write-Output "Staging retained: $work" }
    Write-Output 'Review C:\Windows\Logs\DISM\dism.log and package deployment policy. This result is not successful maintenance.'
}
finally {
    if ($exitCode -eq 0 -and $work) { try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction Stop } catch { Write-Warning 'Successful provisioning staging cleanup failed; deployment result preserved.' } }
    if ($transcribing) { try { Stop-Transcript | Out-Null } catch { Write-Warning 'Transcript finalization failed; provisioning result preserved.' } }
}
exit $exitCode
