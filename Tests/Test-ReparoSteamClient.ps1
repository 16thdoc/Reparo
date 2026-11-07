# Reparo Steam desktop integration regression test (no real Steam launch).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$source = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'Reparo.ps1') -Raw
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
foreach ($name in @('Read-ReparoSteamManifestState','Get-ReparoSteamClientPath','Get-ReparoSteamGameInventory','Select-ReparoSteamQueueGames','Invoke-ReparoSteamGameUpdates')) {
    $node = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name },$true)
    if (-not $node) { throw "Missing Steam function: $name" }
    Invoke-Expression $node.Extent.Text
}
if ($source -notmatch '(?s)\$windowsForceSections = @\(.*?''Steam''.*?\)') {
    throw 'Steam was not added to Windows -Force sections'
}
$temp = Join-Path ([IO.Path]::GetTempPath()) ('reparo-steam-fixture-' + [guid]::NewGuid().ToString('N'))
try {
    $root = Join-Path $temp 'Steam'
    $secondary = Join-Path $temp 'Second Library'
    foreach ($path in @((Join-Path $root 'steamapps'),(Join-Path $secondary 'steamapps'))) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
    New-Item -ItemType Directory -Path (Join-Path $root 'steamapps\common\One'),(Join-Path $secondary 'steamapps\common\Two') -Force|Out-Null
    $escapedSecondary = $secondary.Replace('\','\\')
    $folders = @"
"libraryfolders"
{
    "1"
    {
        "path" "$escapedSecondary"
    }
}
"@
    Set-Content -LiteralPath (Join-Path (Join-Path $root 'steamapps') 'libraryfolders.vdf') -Value $folders
    Set-Content -LiteralPath (Join-Path (Join-Path $root 'steamapps') 'appmanifest_100.acf') -Value '"AppState" { "name" "One" "StateFlags" "4" }'
    Set-Content -LiteralPath (Join-Path (Join-Path $secondary 'steamapps') 'appmanifest_200.acf') -Value @'
"AppState"
{
    "name" "Two"
    "installdir" "Two"
    "StateFlags" "6"
}
'@
    # Duplicate manifest in another library must not inflate counts.
    Set-Content -LiteralPath (Join-Path (Join-Path $secondary 'steamapps') 'appmanifest_100.acf') -Value @'
"AppState"
{
    "name" "Duplicate"
    "StateFlags" "4"
}
'@
    # Keep the first fixture multi-line to match Valve's KeyValues format.
    Set-Content -LiteralPath (Join-Path (Join-Path $root 'steamapps') 'appmanifest_100.acf') -Value @'
"AppState"
{
    "name" "One"
    "installdir" "One"
    "StateFlags" "4"
}
'@
    function Write-ReparoLog { param([string]$Message) }
    $games = @(Get-ReparoSteamGameInventory -SteamRoot $root)
    if ($games.Count -ne 2) { throw "Expected two unique installed apps, got $($games.Count)" }
    $one = $games | Where-Object { $_.AppId -eq '100' } | Select-Object -First 1
    $two = $games | Where-Object { $_.AppId -eq '200' } | Select-Object -First 1
    if (-not $one -or $one.Name -ne 'One' -or $one.UpdateFlagged) { throw 'Normal manifest parsed incorrectly' }
    if (-not $two -or $two.Name -ne 'Two' -or -not $two.UpdateFlagged) { throw 'Update-required manifest parsed incorrectly' }

    $script:ReparoIsWindows = $true
    $Preview = $true
    $SteamAppId = @()
    $SteamWaitSeconds = 0
    $script:receipts = New-Object System.Collections.Generic.List[object]
    $script:launches = 0
    $script:queueCalls = 0
    $script:desktopAvailable = $false
    $script:queueStatus = 'Queued'
    function Test-ReparoSectionSelected { param($Section) $Section -eq 'Steam' }
    function Get-ReparoSteamClientPath { Join-Path $root 'steam.exe' }
    function Get-ReparoSteamGameInventory { param($SteamRoot) $games }
    function Write-Step { param($Message) }
    function Write-Info { param($Message) }
    function Write-Skip { param($Message) }
    function Add-ReparoSummaryRecord {
        param($Bucket,$Software,$Method,$Reason)
        [void]$script:receipts.Add([pscustomobject]@{ Bucket=$Bucket; Reason=$Reason })
    }
    function Get-AuthenticodeSignature {
        [CmdletBinding()]
        param([string]$LiteralPath)
        [pscustomobject]@{ Status='Valid'; SignerCertificate=[pscustomobject]@{ Subject='CN=Valve Corp.,O=Valve Corp.,C=US' } }
    }
    function Start-ReparoProcessWithExplorerToken {
        param($ApplicationPath,$Arguments)
        $script:launches++
        return 1234
    }
    function Get-ReparoSteamDesktopContext {
        [pscustomobject]@{Available=$script:desktopAvailable;Reason='no desktop user session';Sid='S-1-5-21-1';SessionId=4}
    }
    function Invoke-ReparoSteamQueue {
        param($SteamPath,$Games,$Desktop,$WaitSeconds)
        $script:queueCalls++
        [pscustomobject]@{Status='Processed';Reason='';Results=@($Games|ForEach-Object {[pscustomobject]@{AppId=$_.AppId;Name=$_.Name;Status=$script:queueStatus;Accepted=$true;Reason='fixture receipt'}})}
    }
    Invoke-ReparoSteamGameUpdates
    if ($script:launches -ne 0 -or $script:queueCalls -ne 0 -or $script:receipts.Count -ne 1 -or $script:receipts[0].Bucket -ne 'Skipped') {
        throw 'Preview had side effects or claimed an update'
    }

    # Simulate a SYSTEM/SSH session with no desktop Explorer. No launch allowed.
    $Preview = $false
    function Get-Process {
        [CmdletBinding()]
        param([string]$Name)
        return
    }
    Invoke-ReparoSteamGameUpdates
    if ($script:launches -ne 0 -or $script:receipts[1].Reason -notmatch 'desktop user session') {
        throw 'Headless/no-desktop guard did not skip safely'
    }

    # A running client receives a queue request, without restart or claimed completion.
    $script:desktopAvailable = $true
    function Get-Process {
        [CmdletBinding()]
        param([string]$Name)
        if ($Name -eq 'explorer') { return [pscustomobject]@{ SessionId=4 } }
        return
    }
    Invoke-ReparoSteamGameUpdates
    if ($script:launches -ne 0 -or $script:queueCalls -ne 1 -or $script:receipts[2].Bucket -ne 'Pending' -or $script:receipts[2].Reason -notmatch 'completion not verified') {
        throw 'Queue request restarted Steam or falsely claimed completion'
    }

    # Only a completed receipt can count as Updated.
    $script:queueStatus = 'Completed'
    function Get-Process {
        [CmdletBinding()]
        param([string]$Name)
        if ($Name -eq 'explorer' -or $Name -eq 'steam') { return [pscustomobject]@{ SessionId=4 } }
    }
    Invoke-ReparoSteamGameUpdates
    if ($script:launches -ne 0 -or $script:queueCalls -ne 2 -or $script:receipts[3].Bucket -ne 'Updated') {
        throw 'Verified completed queue receipt was not classified correctly'
    }
    $SteamAppId = @('999')
    Invoke-ReparoSteamGameUpdates
    if ($script:queueCalls -ne 2 -or $script:receipts[4].Reason -notmatch 'not installed') { throw 'Unknown AppID triggered another game or a new installation' }
    $SteamAppId = @()
    Write-Host 'Steam inventory, cross-library, preview, queue dispatch, receipt and desktop-session safety tests passed.' -ForegroundColor Green
}
finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
