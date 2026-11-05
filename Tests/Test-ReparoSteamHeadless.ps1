# No game downloads, Steam launches, Task Scheduler mutations, or reboots.
# Run in Windows PowerShell 5.1 or PowerShell 7 on Windows:
# powershell.exe -NoProfile -File .\Tests\Test-ReparoSteamHeadless.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$sourcePath=Join-Path $root 'Reparo.ps1'
$source=Get-Content -LiteralPath $sourcePath -Raw
$tokens=$null
$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count) { throw "Reparo syntax failed: $($parseErrors | Out-String)" }
if ($source -notmatch '(?s)\$windowsForceSections = @\(.*?''Steam''.*?\)') { throw 'Steam missing from Windows Force section.' }
if ($source -notmatch '(?m)^Invoke-ReparoSteamGameUpdates$') { throw 'Steam updater not invoked in maintenance dispatch.' }
if ($source -notmatch '\$script:ReparoBoundParameters\[''Time''\] = \$Time') { throw '-Headless is not scheduling a one-shot task.' }
if ($source -notmatch "if \(\`$entry.Key -in @\('Time', 'Task', 'Headless'\)\)") { throw 'Scheduled worker leaks Headless flag.' }
if ($source -match 'steamcmd.*app_update|app_update.*steamcmd') { throw 'Unsafe SteamCMD in-place desktop updates detected.' }
$functions=@('Get-ReparoSteamGameInventory','Get-ReparoScheduledArgumentTokens')
foreach ($fn in $functions) {
    $node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $fn},$true)
    if (-not $node) { throw "Missing function $fn" }
    Invoke-Expression $node.Extent.Text
}
function Write-ReparoLog { param($Message) }
$temp=Join-Path $env:TEMP ('reparo-steam-test-'+[guid]::NewGuid().ToString('N'))
try {
    $rootApp=Join-Path $temp 'Steam'
    $library=Join-Path $temp 'Additional Library'
    $steamApps=Join-Path $rootApp 'steamapps'
    $otherApps=Join-Path $library 'steamapps'
    New-Item -ItemType Directory -Force -Path $steamApps,$otherApps | Out-Null
    # Valve KeyValues Windows escapes backslashes in libraryfolders.vdf.
    $escaped=$library.Replace('\','\\')
    ('"libraryfolders" { "1" { "path" "'+$escaped+'" } }') | Set-Content -LiteralPath (Join-Path $steamApps 'libraryfolders.vdf')
    @'
"AppState"
{
    "appid" "100"
    "name" "Fixture A"
    "StateFlags" "4"
}
'@ | Set-Content -LiteralPath (Join-Path $steamApps 'appmanifest_100.acf')
    @'
"AppState"
{
    "appid" "200"
    "name" "Fixture B"
    "StateFlags" "2"
}
'@ | Set-Content -LiteralPath (Join-Path $otherApps 'appmanifest_200.acf')
    $games=@(Get-ReparoSteamGameInventory -SteamRoot $rootApp)
    if ($games.Count -ne 2) { throw "Expected two games across two libraries; got $($games.Count)" }
    if (@($games|Where-Object {$_.AppId -eq '200' -and $_.UpdateFlagged}).Count -ne 1) { throw 'Update flag parsing failed.' }
    if (@($games|Where-Object {$_.AppId -eq '100' -and -not $_.UpdateFlagged}).Count -ne 1) { throw 'Installed-state parsing failed.' }

    $script:ReparoBoundParameters=@{
        Headless=[Management.Automation.SwitchParameter]::new($true)
        Force=[Management.Automation.SwitchParameter]::new($true)
        Time='5s'
    }
    $args=@(Get-ReparoScheduledArgumentTokens)
    if ($args -contains '-Headless' -or $args -contains '-Time') { throw 'Headless/time escaped into scheduled worker.' }
    if ($args -notcontains '-Force') { throw 'Force did not reach scheduled worker.' }
    Write-Host 'Steam inventory, scheduler flags, and PowerShell AST checks passed.' -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
