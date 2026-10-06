Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$path=Join-Path (Split-Path -Parent $PSScriptRoot) 'deploy\Deploy-WinGet-System.ps1'
$source=Get-Content -LiteralPath $path -Raw
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($name in @('Get-WinGetReleaseAsset','Save-WinGetReleaseAsset','Get-WinGetBundleIdentity')) {
    $node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    Invoke-Expression $node.Extent.Text
}
$fixture=Join-Path $env:TEMP ('reparo-winget-provisioning-'+[guid]::NewGuid())
try {
    New-Item -ItemType Directory -Path $fixture | Out-Null
    $offline=New-Item -ItemType Directory -Path (Join-Path $fixture 'offline')
    $staging=New-Item -ItemType Directory -Path (Join-Path $fixture 'staging')
    $assetPath=Join-Path $offline.FullName 'fixture.xml'
    Set-Content -LiteralPath $assetPath -Value 'verified fixture' -Encoding UTF8
    $asset=[pscustomobject]@{ name='fixture.xml'; digest='sha256:'+(Get-FileHash $assetPath -Algorithm SHA256).Hash; browser_download_url='https://github.com/microsoft/winget-cli/releases/download/v1.0.0/fixture.xml' }
    function Invoke-WebRequest { throw 'Offline helper unexpectedly accessed the network' }
    $saved=Save-WinGetReleaseAsset -Asset $asset -Directory $staging.FullName -OfflineDirectory $offline.FullName
    if ((Get-FileHash $saved -Algorithm SHA256).Hash -ne (Get-FileHash $assetPath -Algorithm SHA256).Hash) { throw 'Offline verification failed' }
    foreach ($mutation in @('digest','url','name')) {
        $bad=[pscustomobject]@{ name=$asset.name; digest=$asset.digest; browser_download_url=$asset.browser_download_url }
        switch ($mutation) { digest { $bad.digest='sha256:'+('0'*64) }; url { $bad.browser_download_url='https://example.invalid/fixture.xml' }; name { $bad.name='../fixture.xml' } }
        $rejected=$false; try { Save-WinGetReleaseAsset $bad $staging.FullName $offline.FullName | Out-Null } catch { $rejected=$true }
        if (-not $rejected) { throw "Unsafe asset $mutation accepted" }
    }
    $release=[pscustomobject]@{ assets=@($asset,$asset) }
    $rejected=$false; try { Get-WinGetReleaseAsset $release 'fixture\.xml' | Out-Null } catch { $rejected=$true }
    if (-not $rejected) { throw 'Ambiguous asset selection accepted' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    Add-Type -AssemblyName System.IO.Compression
    foreach ($publisher in @('Microsoft Corporation','Untrusted Fixture')) {
        $bundlePath=Join-Path $fixture ($publisher.Replace(' ','')+'.msixbundle')
        $zip=[IO.Compression.ZipFile]::Open($bundlePath,[IO.Compression.ZipArchiveMode]::Create)
        try {
            $entry=$zip.CreateEntry('AppxMetadata/AppxBundleManifest.xml')
            $writer=New-Object IO.StreamWriter($entry.Open())
            try { $writer.Write('<Bundle><Identity Name="Microsoft.DesktopAppInstaller" Publisher="CN='+$publisher+'" Version="1.2.3.4" /></Bundle>') } finally { $writer.Dispose() }
        } finally { $zip.Dispose() }
        if ($publisher -eq 'Microsoft Corporation') { if ((Get-WinGetBundleIdentity $bundlePath) -ne [version]'1.2.3.4') { throw 'Bundle version reading failed' } }
        else { $rejected=$false; try { Get-WinGetBundleIdentity $bundlePath | Out-Null } catch { $rejected=$true }; if (-not $rejected) { throw 'Wrong publisher accepted' } }
    }
    $comparison=$ast.Find({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$existing'},$true)
    $targetVersion=[version]'1.2.3.4'
    function Get-AppxProvisionedPackage { param([switch]$Online,$ErrorAction) [pscustomobject]@{ DisplayName='Microsoft.DesktopAppInstaller'; Version=$script:fixtureVersion } }
    foreach ($v in @('1.2.3.3','1.2.3.4','1.2.3.5')) {
        $script:fixtureVersion=$v; Invoke-Expression $comparison.Extent.Text
        $expected=if ([version]$v -ge $targetVersion) { 1 } else { 0 }
        if ($existing.Count -ne $expected) { throw "Target/newer no-downgrade selection failed for $v" }
    }
    $preview=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $path -Preview 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $preview -notmatch 'no network, package changes or reboot') { throw "Provisioning preview failed: $preview" }
    $x86=Join-Path $env:SystemRoot 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
    $guard=& $x86 -NoProfile -ExecutionPolicy Bypass -File $path -Preview 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -or $guard -notmatch '32-bit/ARM') { throw '32-bit guard did not fail closed' }
    if ($source -match '\bRestart-Computer\b|shutdown\.exe|Add-AppxPackage\s+-Register|\s-SkipLicense\b') { throw 'Provisioning artifact contains a power, registration or license-bypass operation' }
}
finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host 'WinGet provisioning offline digest/URL/name checks, preview and 32-bit guard passed; endpoint provisioning remains unverified.' -ForegroundColor Green
