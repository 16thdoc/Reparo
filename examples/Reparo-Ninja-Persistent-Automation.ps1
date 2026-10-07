param(
    [string]$Action = $env:reparoAction,
    [string]$CustomArguments = $env:reparoArguments
)

$ErrorActionPreference = 'Stop'

$InstallRoot = 'C:\ProgramData\Reparo'
$Reparo = Join-Path $InstallRoot 'Reparo.ps1'
$script:ReparoOperation = 'initialization'
$script:ReparoAutomationOutcome = 'unverified'

function Get-ReparoAutomationOutcome {
    param([string[]]$Arguments, [object[]]$Output)
    $text=(@($Output) | ForEach-Object { [string]$_ }) -join "`n"
    if ($Arguments -match '^-(?:Time|At|Task)$') { return 'scheduled-only' }
    if ($Arguments -match '^-(?:WG|WingetHealth|WingetDiscover|WD)$') {
        if ($text -match '(?i)requires an interactive user|unsupported legacy|WinGet/App Installer is unsupported|winget unavailable|could not be repaired|WG:(?:USER|FAIL|OLD)') { return 'blocked-no-work' }
        return 'discovery-only'
    }
    if ($Arguments -match '^-(?:New|Install|N|Latest|Ninja)$') { return 'deployment' }
    $summary=[regex]::Match($text,'Updated:\s*(?<updated>\d+)\s*\|\s*Skipped:\s*(?<skipped>\d+)\s*\|\s*Failed:\s*(?<failed>\d+)')
    if ($summary.Success) {
        if ([int]$summary.Groups['failed'].Value -gt 0) { return 'maintenance-failed' }
        if ([int]$summary.Groups['updated'].Value -gt 0) { return 'maintenance-reported-changes' }
        if ([int]$summary.Groups['skipped'].Value -gt 0) { return 'no-changes-with-skips' }
        return 'no-changes'
    }
    if ($Arguments -match '^-(?:Force|F|Update|U|Winget)$') { return 'unverified-maintenance-receipt' }
    return 'utility-only'
}

function Invoke-Reparo {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [switch]$StageRuntime
    )

    $launchPath = $Reparo
    $launchArguments = $Arguments
    $stageRoot = $null

    try {
        $script:ReparoOperation = 'launch preparation'
        # Update commands run from a temporary copy so Reparo can safely
        # replace the installed runtime.
        if ($StageRuntime) {
            $stageRoot = Join-Path $env:TEMP (
                'ReparoNinja_{0}_{1}' -f $PID, [guid]::NewGuid()
            )
            $stagedRuntimePath = Join-Path $stageRoot 'Reparo.bootstrap.ps1'
            $launchPath = Join-Path $stageRoot 'Invoke-ReparoTlsBootstrap.ps1'

            New-Item -ItemType Directory -Path $stageRoot -Force |
                Out-Null

            Copy-Item `
                -LiteralPath $Reparo `
                -Destination $stagedRuntimePath `
                -Force `
                -ErrorAction Stop

            # This launcher runs in the same child process as the staged runtime.
            # That lets an older installed Reparo enable TLS 1.2 before its first
            # GitHub request and bootstrap into the fixed reviewed release.
            $commandTokens = New-Object System.Collections.Generic.List[string]
            [void]$commandTokens.Add(
                "'" + $stagedRuntimePath.Replace("'", "''") + "'"
            )
            foreach ($argument in $Arguments) {
                if ($argument -match '^-[A-Za-z0-9][A-Za-z0-9]*(?::\$(?:true|false))?$') {
                    [void]$commandTokens.Add($argument)
                }
                else {
                    [void]$commandTokens.Add(
                        "'" + $argument.Replace("'", "''") + "'"
                    )
                }
            }

            $launcherContent = @'
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
'@
            $launcherContent += [Environment]::NewLine
            $launcherContent += '& ' + ($commandTokens -join ' ')
            $launcherContent += [Environment]::NewLine
            $launcherContent += 'if ($null -ne $LASTEXITCODE) { exit $LASTEXITCODE }'
            Set-Content `
                -LiteralPath $launchPath `
                -Value $launcherContent `
                -Encoding UTF8 `
                -Force
            $launchArguments = @()

            if (Get-Command Unblock-File -ErrorAction SilentlyContinue) {
                foreach ($path in $stagedRuntimePath, $launchPath) {
                    Unblock-File `
                        -LiteralPath $path `
                        -ErrorAction SilentlyContinue
                }
            }

            Write-Host "Staged lifecycle bootstrap: $stagedRuntimePath"
        }

        Write-Host ('Command: reparo {0}' -f ($Arguments -join ' '))

        $script:ReparoOperation = 'Reparo child execution'
        $childOutput = New-Object System.Collections.Generic.List[string]
        & powershell.exe `
            -NoProfile `
            -NonInteractive `
            -ExecutionPolicy Bypass `
            -File $launchPath `
            @launchArguments 2>&1 | ForEach-Object { [void]$childOutput.Add([string]$_); Write-Host $_ }

        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0) {
            throw (
                'Reparo {0} failed with exit code {1}' -f
                ($Arguments -join ' '),
                $exitCode
            )
        }
        $script:ReparoAutomationOutcome = Get-ReparoAutomationOutcome -Arguments $Arguments -Output $childOutput.ToArray()
        Write-Host "Reparo child outcome: $script:ReparoAutomationOutcome (exit=$exitCode)."
        if ($script:ReparoAutomationOutcome -eq 'maintenance-failed') { throw 'Child summary reports maintenance failures despite its exit code.' }
    }
    finally {
        if ($stageRoot -and (Test-Path -LiteralPath $stageRoot)) {
            Remove-Item `
                -LiteralPath $stageRoot `
                -Recurse `
                -Force `
                -ErrorAction SilentlyContinue
        }
    }
}

function Publish-ReparoNinjaField {
    $script:ReparoOperation = 'Ninja custom-field publication'
    $healthPath = Join-Path $InstallRoot 'winget-health.json'
    $health = $null
    $status = 'UNKNOWN'

    if (Test-Path -LiteralPath $healthPath -PathType Leaf) {
        try {
            $health = Get-Content -LiteralPath $healthPath -Raw |
                ConvertFrom-Json -ErrorAction Stop

            if ($health.Status -in @('OK', 'USER', 'FAIL', 'OLD')) {
                $status = [string]$health.Status
            }
        }
        catch {
            Write-Warning (
                'Unable to read persisted WinGet health: {0}' -f
                $_.Exception.Message
            )
        }
    }

    $versionOutput = @(
        & powershell.exe `
            -NoProfile `
            -NonInteractive `
            -ExecutionPolicy Bypass `
            -File $Reparo `
            -Version `
            2>&1
    )

    $versionText = $versionOutput -join "`n"
    $versionMatch = [regex]::Match(
        $versionText,
        '(?m)^Reparo\s+(?<version>\d+(?:\.\d+)+)\s*$'
    )

    $version = if ($versionMatch.Success) {
        $versionMatch.Groups['version'].Value
    }
    elseif ($health -and $health.Reparo) {
        [string]$health.Reparo
    }
    else {
        'UNKNOWN'
    }

    $value = '{0} | WG:{1}' -f $version, $status
    $cliCandidates = @(
        $env:NINJARMMCLI
        'C:\ProgramData\NinjaRMMAgent\ninjarmm-cli.exe'
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $cliPath = $cliCandidates |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1

    if (-not $cliPath) {
        Write-Warning (
            'Ninja custom field was not updated because ninjarmm-cli.exe ' +
            'is missing or inaccessible. Reparo health is still persisted ' +
            "locally as $value. Repair or update the Ninja agent."
        )
        return $false
    }

    $modernSetter = Get-Command Set-NinjaProperty -ErrorAction SilentlyContinue
    $legacySetter = Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue

    try {
        if ($modernSetter) {
            & $modernSetter.Name -Name 'Reparo' -Value $value -Type 'Text'
        }
        elseif ($legacySetter) {
            & $legacySetter.Name -Name 'Reparo' -Value $value
        }
        else {
            Write-Warning (
                'Ninja custom field command is unavailable; would publish: ' +
                $value
            )
            return $false
        }

        Write-Host "Ninja Reparo field updated: $value"
        return $true
    }
    catch {
        Write-Warning (
            'Ninja custom field update failed: {0}. Reparo health remains ' +
            'persisted locally as {1}.' -f
            $_.Exception.Message,
            $value
        )
        return $false
    }
}

function Test-PendingReboot {
    $rebootMarkers = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )

    foreach ($marker in $rebootMarkers) {
        if (Test-Path -LiteralPath $marker) {
            Write-Host "Pending reboot evidence: $marker"
            return $true
        }
    }

    return $false
}

function Request-ReparoReboot {
    param(
        [Parameter(Mandatory)]
        [string]$Reason,

        [ValidateRange(30, 3600)]
        [int]$DelaySeconds = 90
    )

    Write-Host (
        'Scheduling restart in {0} seconds so Ninja can receive the result.' -f
        $DelaySeconds
    )

    & shutdown.exe `
        /r `
        /t $DelaySeconds `
        /c $Reason `
        /d p:4:1

    if ($LASTEXITCODE -ne 0) {
        throw (
            'Unable to schedule reboot; shutdown.exe exited with code {0}' -f
            $LASTEXITCODE
        )
    }
}

function ConvertFrom-ReparoArgumentString {
    param(
        [Parameter(Mandatory)]
        [string]$ArgumentString
    )

    $commandText = $ArgumentString.Trim()

    if ([string]::IsNullOrWhiteSpace($commandText)) {
        throw 'Custom was selected, but reparoArguments is empty.'
    }

    # Accept either "Reparo -Status" or "-Status".
    if ($commandText -notmatch '(?i)^reparo(?:\.cmd|\.ps1)?(?:\s|$)') {
        $commandText = "reparo $commandText"
    }

    $tokens = $null
    $parseErrors = $null

    $ast = [System.Management.Automation.Language.Parser]::ParseInput(
        $commandText,
        [ref]$tokens,
        [ref]$parseErrors
    )

    if ($parseErrors.Count -gt 0) {
        throw (
            'Unable to parse custom Reparo arguments: {0}' -f
            (($parseErrors.Message | Select-Object -Unique) -join '; ')
        )
    }

    $statements = @($ast.EndBlock.Statements)

    if (
        $statements.Count -ne 1 -or
        $statements[0] -isnot
            [System.Management.Automation.Language.PipelineAst]
    ) {
        throw 'Custom arguments must contain exactly one Reparo command.'
    }

    $pipeline = $statements[0]

    if (
        $pipeline.PipelineElements.Count -ne 1 -or
        $pipeline.PipelineElements[0] -isnot
            [System.Management.Automation.Language.CommandAst]
    ) {
        throw (
            'Pipelines, command separators, and additional commands ' +
            'are not allowed.'
        )
    }

    $elements = @(
        $pipeline.PipelineElements[0].CommandElements
    )

    if ($elements.Count -lt 1) {
        throw 'No Reparo command was supplied.'
    }

    $commandName = if (
        $elements[0] -is
            [System.Management.Automation.Language.StringConstantExpressionAst]
    ) {
        $elements[0].Value
    }
    else {
        $elements[0].Extent.Text
    }

    if ($commandName -notmatch '(?i)^reparo(?:\.cmd|\.ps1)?$') {
        throw "Only Reparo may be invoked; received: $commandName"
    }

    $arguments = New-Object System.Collections.Generic.List[string]

    foreach ($element in $elements | Select-Object -Skip 1) {
        if (
            $element -is
                [System.Management.Automation.Language.CommandParameterAst]
        ) {
            [void]$arguments.Add($element.Extent.Text)
            continue
        }

        if (
            $element -is
                [System.Management.Automation.Language.StringConstantExpressionAst]
        ) {
            [void]$arguments.Add($element.Value)
            continue
        }

        if (
            $element -is
                [System.Management.Automation.Language.ConstantExpressionAst]
        ) {
            [void]$arguments.Add([string]$element.Value)
            continue
        }

        throw (
            'Unsupported custom argument expression: {0}' -f
            $element.Extent.Text
        )
    }

    if ($arguments.Count -eq 0) {
        throw 'No Reparo parameters were supplied.'
    }

    return $arguments.ToArray()
}

$reportingAction = @('new','latest','ninja','winget health + ninja') -contains ([string]$Action).Trim().ToLowerInvariant()
$previousReportSkip = $env:REPARO_REPORT_SKIP
$reportingOutcome = 'failed'
$reportingPreviousVersion = $null
try {
    if (Test-Path -LiteralPath $Reparo -PathType Leaf) {
        $match = [regex]::Match([IO.File]::ReadAllText($Reparo), '(?m)^\$script:ReparoVersion\s*=\s*''(?<v>\d+\.\d+\.\d+\.\d+)''')
        if ($match.Success) { $reportingPreviousVersion = $match.Groups['v'].Value }
    }
} catch {}
if ($reportingAction) { $env:REPARO_REPORT_SKIP = '1' }
try {
    if (-not (Test-Path -LiteralPath $Reparo -PathType Leaf)) {
        throw "Reparo is not installed: $Reparo"
    }

    if ([string]::IsNullOrWhiteSpace($Action)) {
        throw 'No action was selected in the reparoAction dropdown.'
    }

    $normalizedAction = $Action.Trim().ToLowerInvariant()

    Write-Host '=== Reparo Ninja automation ==='
    Write-Host "Action: $Action"
    Write-Host "Runtime: $Reparo"
    Write-Host "Computer: $env:COMPUTERNAME"
    Write-Host ''

    switch ($normalizedAction) {
        'new' {
            Write-Host '=== Installing reviewed pinned release ==='
            Invoke-Reparo -Arguments @('-New', '-InstallRoot', $InstallRoot) -StageRuntime

            Write-Host ''
            Write-Host '=== Finalizing local install and self-update schedule ==='
            Invoke-Reparo -Arguments @('-Install', '-InstallRoot', $InstallRoot) -StageRuntime
            Publish-ReparoNinjaField
        }

        'force' {
            Write-Host '=== Running full maintenance pass ==='
            Invoke-Reparo -Arguments @('-Force')
        }

        'force at 7 pm' {
            Write-Host '=== Scheduling full maintenance for 7:00 PM ==='
            Invoke-Reparo -Arguments @('-Force', '-Time', '7pm')
        }

        'force + reboot if needed' {
            Write-Host '=== Running full maintenance pass ==='

            # Do not use -AllowReboot. Reparo and Ninja must finish first.
            Invoke-Reparo -Arguments @('-Force')

            if (Test-PendingReboot) {
                Write-Host ''
                Write-Host 'Pending reboot detected.'
                Request-ReparoReboot `
                    -Reason 'Reparo completed successfully and detected a pending reboot.' `
                    -DelaySeconds 90
            }
            else {
                Write-Host ''
                Write-Host 'No pending reboot detected; restart not scheduled.'
            }
        }

        'force + reboot' {
            Write-Host '=== Running full maintenance pass with post-run reboot ==='
            Invoke-Reparo -Arguments @('-Force', '-Reboot')
        }

        'kill' {
            Write-Host '=== Stopping active Reparo and updater processes ==='
            Invoke-Reparo -Arguments @('-Kill')
        }

        'version' {
            Write-Host '=== Reporting installed version ==='
            Invoke-Reparo -Arguments @('-Version')
        }

        'latest' {
            Write-Host '=== Installing current unpinned main version ==='
            Invoke-Reparo -Arguments @('-N', '-InstallRoot', $InstallRoot) -StageRuntime
            Publish-ReparoNinjaField
        }

        'winget' {
            Write-Host '=== Checking WinGet health ==='
            Invoke-Reparo -Arguments @('-WG')
            Publish-ReparoNinjaField
        }

        'winget health' {
            Write-Host '=== Checking WinGet health ==='
            Invoke-Reparo -Arguments @('-WG')
            Publish-ReparoNinjaField
        }

        'ninja' {
            Write-Host '=== Running Ninja lifecycle update ==='
            Invoke-Reparo -Arguments @('-Ninja', '-InstallRoot', $InstallRoot) -StageRuntime
            Publish-ReparoNinjaField
        }

        'winget health + ninja' {
            Write-Host '=== Checking WinGet health ==='
            Invoke-Reparo -Arguments @('-WG')

            Write-Host ''
            Write-Host '=== Publishing to Ninja ==='

            # -WG and -Ninja require separate Reparo invocations.
            Invoke-Reparo -Arguments @('-Ninja', '-InstallRoot', $InstallRoot) -StageRuntime
            Publish-ReparoNinjaField
        }

        'custom' {
            Write-Host '=== Running custom Reparo parameters ==='

            $customReparoArguments = @(
                ConvertFrom-ReparoArgumentString -ArgumentString $CustomArguments
            )

            Write-Host (
                'Custom command: reparo {0}' -f
                ($customReparoArguments -join ' ')
            )

            if ($customReparoArguments -icontains '-Install') {
                Write-Warning (
                    '-Install is an offline self-install of the current runtime; ' +
                    'use the New action to download the reviewed release first.'
                )
            }

            $lifecycleArguments = @('-Install', '-New', '-N', '-Latest', '-Ninja')
            $requiresStaging = $false

            foreach ($argument in $customReparoArguments) {
                if ($argument -in $lifecycleArguments) {
                    $requiresStaging = $true
                    break
                }
            }
            if ($requiresStaging) { $reportingAction = $true; $env:REPARO_REPORT_SKIP = '1' }

            if ($customReparoArguments -icontains '-AllowReboot') {
                Write-Warning (
                    '-AllowReboot may restart Windows before Ninja receives ' +
                    'the final result.'
                )
            }

            Invoke-Reparo `
                -Arguments $customReparoArguments `
                -StageRuntime:$requiresStaging

            if (
                $customReparoArguments -icontains '-WG' -or
                $customReparoArguments -icontains '-WingetHealth' -or
                $requiresStaging
            ) {
                Publish-ReparoNinjaField
            }
        }

        default {
            throw "Unsupported Reparo action: $Action"
        }
    }

    Write-Host ''
    Write-Host "=== Reparo automation outcome: $script:ReparoAutomationOutcome ==="
    if ($script:ReparoAutomationOutcome -in @('blocked-no-work','unverified-maintenance-receipt')) {
        Write-Warning 'Automation did not prove runnable maintenance; review operation diagnostics and execution identity.'
        exit 2
    }
    $reportingOutcome = 'succeeded'
    exit 0
}
catch {
    Write-Error ('Reparo automation failed during {0}: {1} (type={2}; error-id={3})' -f $script:ReparoOperation, $_.Exception.Message, $_.Exception.GetType().FullName, $_.FullyQualifiedErrorId)
    exit 1
}
finally {
    $env:REPARO_REPORT_SKIP = $previousReportSkip
    if ($reportingAction) {
        $savedExitCode = $global:LASTEXITCODE
        try {
            $match = [regex]::Match([IO.File]::ReadAllText($Reparo), '(?m)^\$script:ReparoVersion\s*=\s*''(?<v>\d+\.\d+\.\d+\.\d+)''')
            # Older installed runtimes ignore the environment suppression safely;
            # do not pass a new parameter before the reviewed upgrade succeeds.
            if ($match.Success -and [version]$match.Groups['v'].Value -ge [version]'1.4.2.0') {
                $finalOutcome = if ($reportingOutcome -eq 'succeeded' -and $reportingPreviousVersion -eq $match.Groups['v'].Value) { 'unchanged' } else { $reportingOutcome }
                & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Reparo -ReportLifecycle -ReportingOutcome $finalOutcome -ReportingPreviousVersion $reportingPreviousVersion -InstallRoot $InstallRoot *> $null
            }
        } catch {} finally { $global:LASTEXITCODE = $savedExitCode }
    }
}
