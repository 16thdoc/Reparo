Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$source=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'Reparo.ps1') -Raw
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
foreach ($name in @('Get-ReparoRegisteredWingetPath','Initialize-ReparoRegisteredWingetPath')) {
    $node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    Invoke-Expression $node.Extent.Text
}
function Test-Path { param($LiteralPath,$PathType) return $LiteralPath -match '\\winget\.exe$' }
$root=Join-Path $env:ProgramFiles 'WindowsApps'
$good=[pscustomobject]@{ Name='Microsoft.DesktopAppInstaller'; Publisher='CN=Microsoft Corporation, O=Microsoft Corporation'; Version='1.29.380.0'; InstallLocation=(Join-Path $root 'Microsoft.DesktopAppInstaller_fixture') }
$badPublisher=[pscustomobject]@{ Name=$good.Name; Publisher='CN=Fixture'; Version='9.0.0.0'; InstallLocation=$good.InstallLocation }
$badPath=[pscustomobject]@{ Name=$good.Name; Publisher=$good.Publisher; Version='9.0.0.0'; InstallLocation=$env:TEMP }
$badSibling=[pscustomobject]@{ Name=$good.Name; Publisher=$good.Publisher; Version='9.0.0.0'; InstallLocation=($root+'-untrusted') }
$actual=Get-ReparoRegisteredWingetPath -Packages @($badPublisher,$badPath,$badSibling,$good)
if ($actual -ne (Join-Path $good.InstallLocation 'winget.exe')) { throw 'Validated package path resolution failed' }
if (Get-ReparoRegisteredWingetPath -Packages @($badPublisher,$badPath,$badSibling)) { throw 'Untrusted package/path accepted' }
$initializer=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Initialize-ReparoRegisteredWingetPath'},$true)
if ($initializer.Extent.Text -match 'SetEnvironmentVariable|Add-Appx|Repair-WinGet|Install-Module') { throw 'Discovery fallback must not provision, register or permanently alter PATH' }
if (-not $initializer.Extent.Text.Contains('Get-AuthenticodeSignature') -or -not $initializer.Extent.Text.Contains("`$signature.Status -ne 'Valid'")) { throw 'Registered runtime requires Microsoft Authenticode validation' }
if ($source -notmatch '-not \$hasWinget -and -not \$Preview') { throw 'Preview must not probe the registered executable' }
$ensure=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Ensure-ReparoWinget'},$true)
Invoke-Expression $ensure.Extent.Text
function Test-ReparoExecutable { param($Name,$Arguments) $false }
function Test-ReparoSystemIdentity { $true }
function Test-ReparoValidatedWingetOk { $script:validated }
function Set-ReparoWingetHealth { param($Status,$Detail) $script:health=$Status; $script:ReparoWingetHealthStatus=$Status }
function Write-ReparoLog { param($Message) }
function Write-ReparoDebug { param($Message) }
function Get-Command { throw 'SYSTEM repair tried command discovery/registration instead of skipping' }
foreach ($validated in @($true,$false)) {
    $script:validated=$validated; $script:health=$null
    if (Ensure-ReparoWinget) { throw 'Unavailable SYSTEM runtime falsely reported healthy' }
    if ($validated -and $script:ReparoWingetHealthStatus -ne 'OK') { throw 'Existing validated health was lost' }
    if (-not $validated -and $script:health -ne 'USER') { throw 'Missing SYSTEM runtime lacks blocked-user/provisioning classification' }
}
Write-Host 'Microsoft registered-package identity/path checks and non-provisioning process-PATH boundary passed.' -ForegroundColor Green
