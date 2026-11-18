# Exercises actual updater/download and generated bootstrap code with inert files,
# mocked HTTPS, and no endpoint installation, PATH, task, or maintenance changes.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$source = [IO.File]::ReadAllText((Join-Path $repo 'Reparo.ps1'))
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'Runtime source does not parse.' }
foreach ($name in @('Get-ReparoWindowsArtifactMirrorUrl','Invoke-ReparoNew','Get-ReparoFileHash','Test-ReparoScriptParse')) {
    $wanted = $name
    $definition = $ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $wanted}, $true)
    if (-not $definition) { throw "Missing actual runtime helper: $name" }
    Invoke-Expression $definition.Extent.Text
}
$update = $ast.Find({param($node) $node -is [Management.Automation.Language.IfStatementAst] -and $node.Extent.Text.StartsWith('if ($Install -or $New -or $Latest) {')}, $true)
if (-not $update) { throw 'Actual reviewed update selector not found.' }
$script:UpdateBlock = [scriptblock]::Create($update.Extent.Text)
$remoteSource = [IO.File]::ReadAllText((Join-Path $repo 'deploy/Install-ReparoRemote.ps1'))
$remoteAst = [Management.Automation.Language.Parser]::ParseInput($remoteSource, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'Remote bootstrap source does not parse.' }
foreach ($name in @('ConvertTo-ReparoPowerShellLiteral','New-ReparoRemoteInstallScript')) {
    $wanted = $name
    $definition = $remoteAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $wanted}, $true)
    if (-not $definition) { throw "Missing remote helper: $name" }
    Invoke-Expression $definition.Extent.Text
}
$cmdSource = [IO.File]::ReadAllText((Join-Path $repo 'deploy/install-reparo-windows.cmd'))
$cmdLine = @($cmdSource -split '\r?\n' | Where-Object { $_ -match '^  "\$ErrorActionPreference' })
if ($cmdLine.Count -ne 1) { throw 'Expected exactly one CMD bootstrap PowerShell body.' }
$script:CmdBody = $cmdLine[0].Trim()
if (-not ($script:CmdBody.StartsWith('"') -and $script:CmdBody.EndsWith('"'))) { throw 'CMD bootstrap quoting changed.' }
$script:CmdBody = $script:CmdBody.Substring(1, $script:CmdBody.Length - 2)
[void][Management.Automation.Language.Parser]::ParseInput($script:CmdBody, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'CMD bootstrap PowerShell does not parse.' }

$root = Join-Path ([IO.Path]::GetTempPath()) ('reparo-artifact-mirror-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$script:FixtureRoot = [IO.Path]::GetFullPath($root)
$script:ReparoVersion = [regex]::Match($source, '(?m)^\$script:ReparoVersion = ''([^'']+)''').Groups[1].Value
$script:ReparoIsWindows = $true
$script:ReparoLogPath = Join-Path $root 'inert.log'
$script:Commit = 'a' * 40
$script:GitHubUrl = 'https://raw.githubusercontent.com/16thdoc/Reparo/{0}/Reparo.ps1' -f $script:Commit
$script:MirrorUrl = 'https://file.thetechnologist.io/reparo/{0}/Reparo.ps1' -f $script:Commit
$script:GoodContent = ('$script:ReparoVersion = ''__VERSION__''' + "`n").Replace('__VERSION__', $script:ReparoVersion)
$goodPath = Join-Path $root 'inert-good.ps1'
[IO.File]::WriteAllText($goodPath, $script:GoodContent, [Text.UTF8Encoding]::new($false))
$script:ExpectedHash = (Get-FileHash -LiteralPath $goodPath -Algorithm SHA256).Hash
$script:Manifest = [ordered]@{
    version=$script:ReparoVersion; commit=$script:Commit; reparoUrl=$script:GitHubUrl; sha256=$script:ExpectedHash
    linuxUrl=('https://raw.githubusercontent.com/16thdoc/Reparo/{0}/linux/reparo-linux' -f $script:Commit)
    linuxSha256=('B' * 64)
    linuxInstallerUrl=('https://raw.githubusercontent.com/16thdoc/Reparo/{0}/deploy/install-reparo-linux.sh' -f $script:Commit)
    linuxInstallerSha256=('C' * 64)
}
$script:PayloadRequests = [Collections.Generic.List[object]]::new()
$script:Warnings = [Collections.Generic.List[string]]::new()
$script:ManifestRequests = 0
$script:InstallerExecutions = 0
$script:Mode = 'ok'

function Write-Info { param($Message) }
function Write-Skip { param($Message) }
function Write-Done { param($Message) }
function Write-ReparoLog { param($Message) }
function Write-ReparoEventLog { param($EventId,$EntryType,$Message) }
function Write-Warning { param($Message) [void]$script:Warnings.Add([string]$Message) }
function Get-ReparoInstalledVersion { param($TargetRoot) return $null }
function Complete-ReparoUtilityLog { param($Status) }
function Invoke-ReparoLifecycleReporting { param($Method,$Outcome,$PreviousVersion) }
function Publish-ReparoInstalledNinjaVersion { param($TargetRoot) return $false }
function Protect-ReparoWindowsInstallRoot {
    param($Path,[switch]$WhatIfOnly)
    if (-not $WhatIfOnly -or -not [IO.Path]::GetFullPath($Path).StartsWith($script:FixtureRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture attempted real root protection.' }
}
function Assert-ReparoWindowsPathHasNoReparsePoint {
    param($Path)
    if (-not [IO.Path]::GetFullPath($Path).StartsWith($script:FixtureRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture escaped its root.' }
}
function Install-ReparoCommandShim { param($TargetRoot,[switch]$WhatIfOnly) if (-not $WhatIfOnly) { throw 'Fixture attempted installation.' } }
function powershell.exe { $script:InstallerExecutions++; $global:LASTEXITCODE = 0 }
function Invoke-RestMethod {
    [CmdletBinding()]
    param($Uri,$Headers,[switch]$UseBasicParsing)
    if ([string]$Uri -notmatch '^https://raw\.githubusercontent\.com/16thdoc/Reparo/refs/heads/main/deploy/reparo-release\.json\?x=') { throw 'Reviewed manifest authority changed.' }
    $script:ManifestRequests++
    return [pscustomobject]$script:Manifest
}
function Invoke-WebRequest {
    [CmdletBinding()]
    param($Uri,$Headers,$OutFile,[switch]$UseBasicParsing,[int]$TimeoutSec=0)
    if ([string]$Uri -eq 'https://fixture.invalid/release.json') {
        $script:ManifestRequests++
        [IO.File]::WriteAllText($OutFile, ($script:Manifest | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
        return
    }
    [void]$script:PayloadRequests.Add([pscustomobject]@{ url=[string]$Uri; headers=$Headers; timeout=$TimeoutSec })
    if ($script:Mode -eq 'outage' -and [string]$Uri -eq $script:MirrorUrl) { throw [Net.WebException]::new('Fixture mirror transport outage') }
    if ($script:Mode -eq 'local-failure' -and [string]$Uri -eq $script:MirrorUrl) { throw [IO.IOException]::new('Fixture local output failure') }
    $content = $script:GoodContent
    if ($script:Mode -eq 'tampered' -and [string]$Uri -eq $script:MirrorUrl) { $content += '# tampered mirror bytes' }
    if ($script:Mode -eq 'syntax' -and [string]$Uri -eq $script:MirrorUrl) { $content = 'function {' }
    if ($script:Mode -eq 'wrong-version' -and [string]$Uri -eq $script:MirrorUrl) { $content = $script:WrongVersionContent }
    [IO.File]::WriteAllText($OutFile, $content, [Text.UTF8Encoding]::new($false))
}
function Reset-Probe {
    param([string]$Mode='ok')
    $script:Mode=$Mode; $script:PayloadRequests.Clear(); $script:Warnings.Clear()
    $script:ManifestRequests=0; $script:InstallerExecutions=0
}
function Assert-Requests {
    param([string[]]$Urls,[string]$UserAgent)
    if (($script:PayloadRequests.url -join '|') -cne ($Urls -join '|')) { throw "Unexpected payload requests: $($script:PayloadRequests.url -join ', ')" }
    if ($UserAgent) {
        foreach ($request in $script:PayloadRequests) {
            if ($request.headers['User-Agent'] -cne $UserAgent) { throw 'Missing fixed nonidentifying download User-Agent.' }
            if ($UserAgent -like 'Reparo-Download/*' -and $request.timeout -ne 60) { throw 'Reviewed mirror/fallback payload lacks its 60-second timeout.' }
        }
    }
}
function Invoke-ActualNew {
    $Install=$false; $New=$true; $Latest=$false; $Preview=$true
    $NoBackup=$false; $SkipNinjaPublish=$true; $SourceUrl=$null
    $InstallRoot=Join-Path $script:FixtureRoot 'runtime'
    & $script:UpdateBlock
    if (Test-Path -LiteralPath (Join-Path $InstallRoot 'Reparo.ps1')) { throw 'Preview probe installed a runtime.' }
}
function Invoke-BootstrapProbe {
    param([ValidateSet('remote','cmd')][string]$Kind,[switch]$Custom)
    if ($Kind -eq 'remote') {
        $remoteUrl=''; $remoteHash=''
        if ($Custom) { $remoteUrl='https://fixture.invalid/custom.ps1'; $remoteHash=$script:ExpectedHash }
        $body = New-ReparoRemoteInstallScript -RemoteSourceUrl $remoteUrl -RemoteSourceSha256 $remoteHash -RemoteManifestUrl 'https://fixture.invalid/release.json' -RemoteInstallRoot (Join-Path $script:FixtureRoot 'remote-runtime')
        # The final shim/help probe is unrelated to download trust. Installation
        # itself is intercepted by the inert powershell.exe function above.
        $end = $body.IndexOf('$scriptPath = Join-Path $installRoot')
        if ($end -lt 0) { throw 'Remote bootstrap final-probe boundary changed.' }
        & ([scriptblock]::Create($body.Substring(0,$end)))
    }
    else { & ([scriptblock]::Create($script:CmdBody)) }
}

$oldRelease=$env:REPARO_RELEASE_URL; $oldSource=$env:REPARO_URL; $oldHash=$env:REPARO_SHA256
try {
    if ((Get-ReparoWindowsArtifactMirrorUrl -Commit $script:Commit -SourceUrl $script:GitHubUrl) -cne $script:MirrorUrl) { throw 'Incorrect mirror mapping.' }
    foreach ($foreign in @(
        'https://evil.invalid/Reparo.ps1',
        ('https://raw.githubusercontent.com/16thdoc/Other/{0}/Reparo.ps1' -f $script:Commit),
        ('https://raw.githubusercontent.com/16thdoc/Reparo/{0}/other.ps1' -f $script:Commit),
        ($script:GitHubUrl + '?alternate=1'), ($script:GitHubUrl + '#fragment')
    )) {
        $rejected=$false
        try { Get-ReparoWindowsArtifactMirrorUrl -Commit $script:Commit -SourceUrl $foreign | Out-Null } catch { $rejected=$true }
        if (-not $rejected) { throw 'Foreign/noncanonical source accepted by mirror mapping.' }
    }
    foreach ($badCommit in @('main',('A'*40),('a'*39))) {
        $rejected=$false
        try { Get-ReparoWindowsArtifactMirrorUrl -Commit $badCommit -SourceUrl $script:GitHubUrl | Out-Null } catch { $rejected=$true }
        if (-not $rejected) { throw 'Invalid commit accepted by mirror mapping.' }
    }

    Reset-Probe
    Invoke-ActualNew
    Assert-Requests @($script:MirrorUrl) 'Reparo-Download/Windows/Update'
    if ($script:ManifestRequests -ne 1) { throw 'Normal -New did not resolve reviewed GitHub metadata.' }
    Reset-Probe 'outage'
    Invoke-ActualNew
    Assert-Requests @($script:MirrorUrl,$script:GitHubUrl) 'Reparo-Download/Windows/Update'
    if ($script:Warnings.Count -ne 1 -or $script:Warnings[0] -notmatch 'omitted from mirror analytics') { throw 'Transport fallback was not clearly disclosed.' }
    foreach ($bad in @('tampered','syntax','local-failure')) {
        Reset-Probe $bad
        $rejected=$false
        try { Invoke-ActualNew } catch { $rejected=$true }
        if (-not $rejected) { throw 'Updater accepted bad mirror content.' }
        Assert-Requests @($script:MirrorUrl) 'Reparo-Download/Windows/Update'
        if ($script:InstallerExecutions -or $script:Warnings.Count) { throw 'Content failure executed or hid behind fallback.' }
    }
    $script:WrongVersionContent=$script:GoodContent.Replace($script:ReparoVersion,'9.9.9.9')
    $wrongPath=Join-Path $root 'inert-wrong-version.ps1'
    [IO.File]::WriteAllText($wrongPath,$script:WrongVersionContent,[Text.UTF8Encoding]::new($false))
    $wrongHash=(Get-FileHash -LiteralPath $wrongPath -Algorithm SHA256).Hash
    $script:Manifest.sha256=$wrongHash
    Reset-Probe 'wrong-version'
    $rejected=$false
    try { Invoke-ActualNew } catch { $rejected=$true }
    $script:Manifest.sha256=$script:ExpectedHash
    if (-not $rejected -or $script:Warnings.Count) { throw 'Updater accepted a hash-valid wrong version or retried it.' }
    Assert-Requests @($script:MirrorUrl) 'Reparo-Download/Windows/Update'

    $goodUrl=$script:Manifest.reparoUrl
    $script:Manifest.reparoUrl='https://evil.invalid/Reparo.ps1'
    Reset-Probe
    $rejected=$false
    try { Invoke-ActualNew } catch { $rejected=$true }
    $script:Manifest.reparoUrl=$goodUrl
    if (-not $rejected -or $script:PayloadRequests.Count) { throw 'Invalid reviewed manifest reached a payload request.' }
    $script:Manifest.commit='A'*40
    $script:Manifest.reparoUrl='https://raw.githubusercontent.com/16thdoc/Reparo/{0}/Reparo.ps1' -f $script:Manifest.commit
    Reset-Probe
    $rejected=$false
    try { Invoke-ActualNew } catch { $rejected=$true }
    $script:Manifest.commit=$script:Commit; $script:Manifest.reparoUrl=$goodUrl
    if (-not $rejected -or $script:PayloadRequests.Count) { throw 'Noncanonical uppercase commit reached a payload request.' }

    Reset-Probe
    Invoke-ReparoNew -TargetRoot (Join-Path $root custom) -Url 'https://fixture.invalid/custom.ps1' -ExpectedHash $script:ExpectedHash -WhatIfOnly
    Assert-Requests @('https://fixture.invalid/custom.ps1') ''
    Reset-Probe
    $latest='https://api.github.com/repos/16thdoc/Reparo/contents/Reparo.ps1?ref=main'
    Invoke-ReparoNew -TargetRoot (Join-Path $root latest) -Url $latest -WhatIfOnly
    Assert-Requests @($latest) 'Reparo'
    if ($script:PayloadRequests[0].headers.Accept -cne 'application/vnd.github.raw') { throw 'Latest GitHub API semantics changed.' }

    $env:REPARO_RELEASE_URL='https://fixture.invalid/release.json'; $env:REPARO_URL=''; $env:REPARO_SHA256=''
    foreach ($kind in @('remote','cmd')) {
        Reset-Probe
        Invoke-BootstrapProbe $kind
        Assert-Requests @($script:MirrorUrl) 'Reparo-Download/Windows/Install'
        if ($script:InstallerExecutions -ne 1 -or $script:ManifestRequests -ne 1) { throw 'Bootstrap did not validate and reach the inert install boundary.' }
        Reset-Probe 'outage'
        Invoke-BootstrapProbe $kind
        Assert-Requests @($script:MirrorUrl,$script:GitHubUrl) 'Reparo-Download/Windows/Install'
        if ($script:InstallerExecutions -ne 1 -or $script:Warnings.Count -ne 1) { throw 'Bootstrap outage fallback contract failed.' }
        Reset-Probe 'tampered'
        $rejected=$false
        try { Invoke-BootstrapProbe $kind } catch { $rejected=$true }
        if (-not $rejected -or $script:InstallerExecutions -ne 0 -or $script:Warnings.Count) { throw 'Bootstrap accepted corrupt mirror bytes or hid them behind fallback.' }
        Assert-Requests @($script:MirrorUrl) 'Reparo-Download/Windows/Install'
        Reset-Probe 'local-failure'
        $rejected=$false
        try { Invoke-BootstrapProbe $kind } catch { $rejected=$true }
        if (-not $rejected -or $script:InstallerExecutions -or $script:Warnings.Count) { throw 'Bootstrap hid a local output error behind transport fallback.' }
        Assert-Requests @($script:MirrorUrl) 'Reparo-Download/Windows/Install'
        $script:Manifest.sha256=$wrongHash
        Reset-Probe 'wrong-version'
        $rejected=$false
        try { Invoke-BootstrapProbe $kind } catch { $rejected=$true }
        $script:Manifest.sha256=$script:ExpectedHash
        if (-not $rejected -or $script:InstallerExecutions -or $script:Warnings.Count) { throw 'Bootstrap accepted a hash-valid wrong version or retried it.' }
        Assert-Requests @($script:MirrorUrl) 'Reparo-Download/Windows/Install'
        $script:Manifest.reparoUrl='https://evil.invalid/Reparo.ps1'
        Reset-Probe
        $rejected=$false
        try { Invoke-BootstrapProbe $kind } catch { $rejected=$true }
        $script:Manifest.reparoUrl=$goodUrl
        if (-not $rejected -or $script:PayloadRequests.Count -or $script:InstallerExecutions) { throw 'Bootstrap downloaded/executed a foreign manifest source.' }
        $script:Manifest.commit='A'*40
        $script:Manifest.reparoUrl='https://raw.githubusercontent.com/16thdoc/Reparo/{0}/Reparo.ps1' -f $script:Manifest.commit
        Reset-Probe
        $rejected=$false
        try { Invoke-BootstrapProbe $kind } catch { $rejected=$true }
        $script:Manifest.commit=$script:Commit; $script:Manifest.reparoUrl=$goodUrl
        if (-not $rejected -or $script:PayloadRequests.Count -or $script:InstallerExecutions) { throw 'Bootstrap accepted a noncanonical uppercase commit.' }
        $env:REPARO_URL='https://fixture.invalid/custom.ps1'; $env:REPARO_SHA256=$script:ExpectedHash
        Reset-Probe
        Invoke-BootstrapProbe $kind -Custom
        Assert-Requests @('https://fixture.invalid/custom.ps1') 'Reparo'
        if ($script:ManifestRequests -or $script:PayloadRequests[0].timeout -ne 0 -or $script:InstallerExecutions -ne 1) { throw 'Explicit custom bootstrap semantics changed.' }
        $env:REPARO_URL=''; $env:REPARO_SHA256=''
    }
    Write-Host 'Windows artifact mirror routing, strict trust, outage-only fallback, corruption rejection and unchanged custom/latest lanes passed (isolated, inert HTTPS fixtures).' -ForegroundColor Green
}
finally {
    $env:REPARO_RELEASE_URL=$oldRelease; $env:REPARO_URL=$oldSource; $env:REPARO_SHA256=$oldHash
    $resolved=[IO.Path]::GetFullPath($root)
    if (-not $resolved.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'reparo-artifact-mirror-*') { throw 'Unsafe fixture cleanup.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
}
