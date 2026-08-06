<#
.SYNOPSIS
Removes Reparo from a ScreenConnect endpoint.

.DESCRIPTION
Run from ScreenConnect Toolbox as SYSTEM/admin. Stops only processes using the
ProgramData Reparo runtime, removes Reparo runtime/logs/backups and diagnostics, and
removes only the exact Reparo bin PATH entry. No reboot.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$installRoot = Join-Path $env:ProgramData 'Reparo'
$binRoot = Join-Path $installRoot 'bin'
$diagnosticRoot = Join-Path $env:ProgramData 'Reparo-Ninja-Diagnostics'

function Remove-ReparoPathEntry {
    param([ValidateSet('Machine', 'User')][string]$Scope)

    $current = [Environment]::GetEnvironmentVariable('Path', $Scope)
    if ([string]::IsNullOrWhiteSpace($current)) { return }
    $parts = @($current -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $updated = @($parts | Where-Object { $_ -ine $binRoot })
    if ($updated.Count -ne $parts.Count) {
        [Environment]::SetEnvironmentVariable('Path', ($updated -join ';'), $Scope)
        Write-Host "Removed Reparo PATH entry from $Scope PATH: $binRoot"
    }
}

$reparoProcesses = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*$installRoot*" })
foreach ($process in $reparoProcesses) {
    try {
        Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
        Write-Host "Stopped Reparo process: $($process.ProcessId)"
    }
    catch {
        Write-Warning "Could not stop Reparo process $($process.ProcessId): $($_.Exception.Message)"
    }
}

Remove-ReparoPathEntry -Scope Machine
Remove-ReparoPathEntry -Scope User

foreach ($path in @($installRoot, $diagnosticRoot)) {
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
        Write-Host "Removed: $path"
    }
}

Write-Host 'Reparo uninstall complete. No reboot was scheduled.'
