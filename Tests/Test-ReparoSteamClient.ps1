# Reparo Steam desktop integration regression test (no real Steam launch).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$source = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'Reparo.ps1') -Raw
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
foreach ($name in @('Get-ReparoSteamClientPath','Get-ReparoSteamGameInventory','Invoke-ReparoSteamGameUpdates')) {
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
    $script:receipts = New-Object System.Collections.Generic.List[object]
    $script:launches = 0
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
    function Start-ReparoProcessWithExplorerToken {
        param($ApplicationPath,$Arguments)
        $script:launches++
        return 1234
    }
    Invoke-ReparoSteamGameUpdates
    if ($script:launches -ne 0 -or $script:receipts.Count -ne 1 -or $script:receipts[0].Bucket -ne 'Skipped') {
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

    # One desktop session with no Steam: startup can be requested, not certified.
    function Get-Process {
        [CmdletBinding()]
        param([string]$Name)
        if ($Name -eq 'explorer') { return [pscustomobject]@{ SessionId=4 } }
        return
    }
    Invoke-ReparoSteamGameUpdates
    if ($script:launches -ne 1 -or $script:receipts[2].Bucket -ne 'Skipped' -or $script:receipts[2].Reason -notmatch 'not verified') {
        throw 'Desktop startup did not preserve unverified outcome'
    }

    # A running Steam client should not be restarted, killed, or duplicated.
    function Get-Process {
        [CmdletBinding()]
        param([string]$Name)
        if ($Name -eq 'explorer' -or $Name -eq 'steam') { return [pscustomobject]@{ SessionId=4 } }
    }
    Invoke-ReparoSteamGameUpdates
    if ($script:launches -ne 1 -or $script:receipts[3].Reason -notmatch 'already running') {
        throw 'Steam already-running guard failed'
    }
    Write-Host 'Steam inventory, cross-library, preview and desktop-session safety tests passed.' -ForegroundColor Green
}
finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
