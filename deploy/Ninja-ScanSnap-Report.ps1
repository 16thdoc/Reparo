<#
.SYNOPSIS
Reports installed ScanSnap software and versions to a NinjaOne device field.

.DESCRIPTION
Parameter-free NinjaOne inventory automation. It reads the 32-bit and 64-bit
machine uninstall registries, finds products whose display name contains ScanSnap,
and sets the Ninja device text custom field named ScanSnap. It makes no changes to
ScanSnap or Reparo.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$customFieldName = 'scansnapVersion'
$uninstallPath = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
$records = New-Object System.Collections.Generic.List[object]

foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
    try {
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
        try {
            $uninstallKey = $baseKey.OpenSubKey($uninstallPath)
            if (-not $uninstallKey) { continue }
            try {
                foreach ($subKeyName in $uninstallKey.GetSubKeyNames()) {
                    $subKey = $uninstallKey.OpenSubKey($subKeyName)
                    if (-not $subKey) { continue }
                    try {
                        $displayName = [string]$subKey.GetValue('DisplayName')
                        if ([string]::IsNullOrWhiteSpace($displayName) -or $displayName -notmatch '(?i)\bScanSnap\b') { continue }

                        $displayVersion = [string]$subKey.GetValue('DisplayVersion')
                        $publisher = [string]$subKey.GetValue('Publisher')

                        [void]$records.Add([pscustomobject]@{
                            Name      = $displayName.Trim()
                            Version   = $displayVersion.Trim()
                            Publisher = $publisher.Trim()
                            Registry  = $view.ToString()
                        })
                    }
                    finally {
                        if ($subKey) { $subKey.Dispose() }
                    }
                }
            }
            finally {
                if ($uninstallKey) { $uninstallKey.Dispose() }
            }
        }
        finally {
            $baseKey.Dispose()
        }
    }
    catch {
        Write-Warning "Could not inspect the $view uninstall registry: $($_.Exception.Message)"
    }
}

$installed = @($records | Group-Object Name, Version | ForEach-Object { $_.Group | Select-Object -First 1 } | Sort-Object Name, Version)
$fieldValue = if ($installed.Count -eq 0) {
    'Not installed'
}
else {
    ($installed | ForEach-Object {
        if ([string]::IsNullOrWhiteSpace($_.Version)) { $_.Name } else { '{0} {1}' -f $_.Name, $_.Version }
    }) -join '; '
}

# Ninja text custom fields are commonly capped at 255 characters. Preserve a useful,
# deterministic prefix instead of making the field update fail on an unusual install.
if ($fieldValue.Length -gt 255) {
    $fieldValue = $fieldValue.Substring(0, 252) + '...'
}

Write-Host '=== Ninja ScanSnap Inventory ==='
Write-Host "Computer: $env:COMPUTERNAME"
foreach ($entry in $installed) {
    Write-Host ('Installed: {0} | Version: {1} | Publisher: {2} | Registry: {3}' -f $entry.Name, $entry.Version, $entry.Publisher, $entry.Registry)
}
Write-Host "Ninja field value: $fieldValue"

$propertySetter = Get-Command -Name Ninja-Property-Set -ErrorAction SilentlyContinue
if (-not $propertySetter) {
    throw "Ninja-Property-Set is unavailable; cannot update the '$customFieldName' custom field."
}

& $propertySetter.Name -Name $customFieldName -Value $fieldValue
if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    throw "Ninja-Property-Set failed with exit code $LASTEXITCODE while setting '$customFieldName'."
}

Write-Host "Ninja custom field '$customFieldName' set to: $fieldValue"
