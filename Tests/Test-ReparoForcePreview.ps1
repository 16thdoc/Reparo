# Execute the real CLI normalization and dispatch against harmless boundaries.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path (Split-Path -Parent $PSScriptRoot) 'Reparo.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors | Out-String)}
$normalization=$ast.Find({param($n) $n -is [Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -eq '$PowerShell7Only'},$true)
foreach($name in 'Invoke-ReparoCommandStep'){
    $node=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    Invoke-Expression $node.Extent.Text
}
function Write-ReparoDebug {param($Message)}
function Write-ReparoLog {param($Message) $script:logs += $Message}
function Write-Step {param($Message)}
function Write-Skip {param($Message)}
function Write-Fail {param($Message) throw $Message}
function Get-ReparoPendingUpdates {param($Section) return @()}
function Test-ReparoSectionSelected {param($Section) return $Section -in $Include}
function Resolve-ReparoShell {throw 'Preview attempted to resolve an execution shell.'}
function Invoke-ReparoTimedCommand {throw 'Preview attempted to execute a command.'}
function Add-ReparoSummaryRecord {param($Bucket,$Software,$Version,$Method,$Reason) $script:records += [pscustomobject]@{Bucket=$Bucket;Reason=$Reason}}
$PowerShell7Only=$false; $SevenZip=$false; $Force=$true; $Task=$false; $Update=$false; $WindowsFeatureUpdate=$false
$windowsSelection=$ast.Find({param($n)$n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$windowsForceSections'},$true)
if(-not $windowsSelection){throw 'Windows Force selection is unavailable.'}
Invoke-Expression $windowsSelection.Extent.Text
$linuxForceSections=@('Apt','Pip'); $script:ReparoDebug=$false
foreach($platform in @($true,$false)){
    foreach($previewMode in @($true,$false)){
        $script:ReparoIsWindows=$platform; $Preview=$previewMode; $Include=@(); $WindowsUpdate=$false; $WslApt=$false
        Invoke-Expression $normalization.Extent.Text
        if([bool]$Preview -ne $previewMode){throw 'Force normalization changed the explicit Preview selection.'}
        if(($Include -contains 'Slicer') -ne $platform){throw 'Slicer Force selection crossed the Windows-only management boundary.'}
        if($Preview){
            $script:logs=@(); $script:records=@()
            Invoke-ReparoCommandStep -Section Pip -Command 'throw "maintenance must never execute"'
            if(@($script:logs | Where-Object {$_ -match '^\[DRY-RUN\]'}).Count -ne 1 -or $script:records[0].Reason -ne 'preview only'){throw 'Preview did not stop at the dry-run boundary.'}
        }
    }
}
Write-Host 'Force preserves Preview on Windows and the legacy Linux selection path; dry-run never launches maintenance.'
