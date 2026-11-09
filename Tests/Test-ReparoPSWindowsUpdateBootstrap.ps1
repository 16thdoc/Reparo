# Isolated module/provider stubs: no downloads, module installs or repository changes.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path (Split-Path -Parent $PSScriptRoot) 'Reparo.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors | Out-String)}
foreach($name in 'Ensure-ReparoNuGetProvider','Ensure-ReparoPSWindowsUpdate'){
    $node=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    Invoke-Expression $node.Extent.Text
}
$InstallNuGetProvider=$true
$script:ReparoLogPath='fixture'; $script:ready=$false; $script:providerReady=$false; $script:steps=@()
function Write-ReparoLog {param($Message)}
function Write-ReparoDebug {param($Message)}
function Write-ReparoEventLog {param($EventId,$EntryType,$Message)}
function Import-ReparoBootstrapModule {param($Name) $script:steps += "module:$Name"}
function Get-Command {
    param($Name,$ErrorAction)
    if($Name -eq 'Get-WindowsUpdate'){if($script:ready){return [pscustomobject]@{Name=$Name}}; return}
    return [pscustomobject]@{Name=$Name}
}
function Get-PackageProvider {
    [CmdletBinding()]param([switch]$ListAvailable,$Name)
    if(-not $ListAvailable -or $Name){throw 'Provider lookup must not trigger named bootstrap prompts.'}
    if($script:providerReady){[pscustomobject]@{Name='NuGet';Version=[version]'2.8.5.208'}}
}
function Install-PackageProvider {
    [CmdletBinding(SupportsShouldProcess)]param($Name,$MinimumVersion,[switch]$Force,[switch]$ForceBootstrap,$Scope)
    if(-not $Force -or -not $ForceBootstrap -or $Scope -ne 'AllUsers' -or $PSBoundParameters.Confirm -ne $false){throw 'Provider bootstrap must be explicitly noninteractive.'}
    $script:steps += 'provider'; $script:providerReady=$true
}
function Import-PackageProvider {[CmdletBinding()]param($Name,$MinimumVersion,[switch]$Force)}
function Set-PSRepository {
    [CmdletBinding()]param($Name,$InstallationPolicy)
    if(-not $script:providerReady){throw 'Repository access before NuGet causes an unattended prompt.'}
    $script:steps += 'repository'
}
function Install-Module {
    [CmdletBinding()]param($Name,[switch]$Force,[switch]$AllowClobber,$Scope,$Repository)
    if(-not $script:providerReady){throw 'Module install before provider.'}
    $script:steps += 'install'
}
function Import-Module {[CmdletBinding()]param($Name,[switch]$Force) $script:ready=$true}
if(-not (Ensure-ReparoPSWindowsUpdate)){throw 'Fresh SYSTEM bootstrap failed.'}
if(($script:steps -join '|') -notmatch 'provider\|module:PowerShellGet\|repository\|install'){throw 'Bootstrap ordering was lost.'}
$script:steps=@(); $script:ready=$false
if(-not (Ensure-ReparoPSWindowsUpdate) -or 'provider' -in $script:steps){throw 'Existing provider was unnecessarily reinstalled.'}
$script:steps=@()
if(-not (Ensure-ReparoPSWindowsUpdate) -or $script:steps.Count){throw 'Available module should bypass bootstrap.'}
Write-Host 'Noninteractive SYSTEM provider/module bootstrap order and existing-install bypass passed.'
