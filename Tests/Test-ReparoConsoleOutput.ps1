Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$source=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'Reparo.ps1') -Raw
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
foreach ($name in @('Test-ReparoConsoleColor','Write-ReparoConsole','Write-Info','Write-Step','Write-Skip','Write-Done','Write-Fail','Write-ReparoSummaryTable')) {
    $node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    Invoke-Expression $node.Extent.Text
}
$oldNoColor=[Environment]::GetEnvironmentVariable('NO_COLOR')
try {
    $env:NO_COLOR='1'
    if (Test-ReparoConsoleColor) { throw 'NO_COLOR ignored' }
    $script:captured=New-Object System.Collections.Generic.List[object]
    function Write-Host { param($Object,$ForegroundColor,[switch]$NoNewline) [void]$script:captured.Add([pscustomobject]@{ Text=[string]$Object; Color=$ForegroundColor; Joined=[bool]$NoNewline }) }
    function Write-ReparoLog { param($Message) if ($Message.Contains([string][char]27)) { throw 'ANSI leaked to structured log' } }
    Write-Step 'fixture'
    if ($script:captured[0].Color) { throw 'Plain output requested a foreground color' }
    function Test-ReparoConsoleColor { $true }
    $script:captured.Clear()
    Write-ReparoSummaryTable -Title 'Updated' -Rows @([pscustomobject]@{ Software='fixture package'; CurrentVersion='1'; Version='2'; Method='fixture'; Reason='-' })
    $red=@($script:captured | Where-Object { $_.Text -eq 'fixture package' -and $_.Color -eq 'Red' })
    if ($red.Count -ne 1) { throw 'Interactive package name is not distinctly red' }
    $plainText=($script:captured | ForEach-Object { $_.Text }) -join ''
    if ($plainText -notmatch 'fixture package 1 -> 2 \[fixture\]') { throw 'Color rendering changed the informative text' }
    function Test-ReparoConsoleColor { $false }
    $script:captured.Clear(); Write-Info 'fixture'; Write-Fail 'fixture'
    if (@($script:captured | Where-Object { $_.Color }).Count) { throw 'Redirected/plain output requested color' }
}
finally { [Environment]::SetEnvironmentVariable('NO_COLOR',$oldNoColor) }
Write-Output 'Console palette, red package emphasis, NO_COLOR and plain/log output tests passed.'
