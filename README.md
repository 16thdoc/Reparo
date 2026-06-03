# Reparo

Reparo is a standalone Windows maintenance runner for RMM deployment.

It updates common package managers and toolchains when they are already present on a machine. The script is intentionally self-contained: it does not depend on profile modules, cloud-synced helper paths, editor sync state, or any other machine-specific automation.

## What it does

By default, Reparo runs Windows Update through `PSWindowsUpdate`. Optional modes can also include `winget`, Microsoft Store updates through `winget`, Chocolatey, developer toolchains such as Scoop, pip, npm, pnpm, Yarn, .NET tools, Rust, Conda, Ruby gems, Composer, and WSL, plus a Chocolatey-to-winget migration pass.

Reparo does not install package managers from scratch. It only uses tools that are already present, then skips the sections that are not available.

## Quick start

Install or update the live ProgramData copy from GitHub:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -Install
```

`-Install` also creates a `reparo` command shim at:

```text
C:\ProgramData\Reparo\bin\reparo.cmd
```

Reparo tries to add that folder to machine `PATH`, falling back to user `PATH` if machine `PATH` cannot be changed. New PowerShell sessions can then run:

```powershell
reparo -Update
reparo -Install
reparo -Help
reparo -Version
reparo -Kill
reparo -Tail
```

Preview the managed-client update pass:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -Preview -Update
```

Run the managed-client update pass:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -Update
```

Run only selected sections:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -Include Winget Choco
```

Preview Chocolatey-to-winget migration:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -Preview -MigrateChocoToWinget
```

Run Chocolatey-to-winget migration:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -MigrateChocoToWinget
```

## RMM deployment

Suggested NinjaOne command:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\Reparo\Reparo.ps1 -Update
```

Recommended rollout pattern:

1. Run `-Preview -Update` on a test device.
2. Pilot `-Update` on a small group of representative endpoints.
3. Review logs and RMM output before broad deployment.
4. Reserve `-Force` for known developer workstations or hands-on maintenance.

### Ninja deployment options

Use one of these patterns depending on how you want to manage updates.

| Pattern | Best for | Tradeoff |
| --- | --- | --- |
| Paste `Reparo.ps1` into Ninja | Maximum simplicity and no external dependency | Updating Reparo means editing the Ninja script body |
| Upload `Reparo.ps1` as a Ninja script/file | Controlled copy inside Ninja | Exact execution path depends on how the Ninja script/file is staged |
| `Reparo.ps1 -New` from GitHub | Easy updates and version pinning | Requires endpoint access to GitHub raw content |

When pasting PowerShell parameters into Ninja, use the actual switch token with the leading dash. For example, type `-Update`, not `Update`.

### Option 1: Paste Reparo into Ninja

Create a Ninja PowerShell script and paste the contents of `Reparo.ps1` directly into the script body.

Recommended arguments for a broad managed-client pass:

```powershell
-Update
```

Recommended pilot arguments:

```powershell
-Preview -Update
```

Use this option when you want the fewest moving parts. The script runs entirely from Ninja, and no endpoint needs to reach GitHub.

### Option 2: Upload Reparo as a Ninja file

Upload `Reparo.ps1` to Ninja and run it from the staged script directory:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -Update
```

If your Ninja file staging path differs, update the `-File` path to match where Ninja places the uploaded file.

For a safer first pass:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -Preview -Update
```

### Option 3: Install/update from GitHub with `-New`

Use this when the repo is public, or when the endpoint has approved access to the raw file URL. The first command downloads the current `Reparo.ps1` to `C:\ProgramData\Reparo\Reparo.ps1` with parse validation and backup handling, then the second command runs the installed ProgramData copy.

Ninja script body:

```powershell
$ErrorActionPreference = 'Stop'

$installRoot = "$env:ProgramData\Reparo"
$scriptPath = Join-Path $installRoot 'Reparo.ps1'
$bootstrapUrl = 'https://raw.githubusercontent.com/16thdoc/Reparo/main/Reparo.ps1'
$bootstrapPath = Join-Path $installRoot 'Reparo.bootstrap.ps1'

if ([Net.ServicePointManager]::SecurityProtocol -notmatch 'Tls12') {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
Invoke-WebRequest -Uri $bootstrapUrl -OutFile $bootstrapPath -UseBasicParsing

if (Get-Command Unblock-File -ErrorAction SilentlyContinue) {
    Unblock-File -Path $bootstrapPath
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $bootstrapPath -New -InstallRoot $installRoot -SourceUrl $bootstrapUrl
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Update
exit $LASTEXITCODE
```

For production stability, prefer a tag or commit-pinned raw URL instead of `main`:

```powershell
$bootstrapUrl = 'https://raw.githubusercontent.com/16thdoc/Reparo/v1.0.0/Reparo.ps1'
```

The same bootstrapper is also included at `deploy/Ninja-GitHub.ps1`.

### Option 4: Install/update over SSH

For personal Windows machines that are reachable over OpenSSH, use the remote helper:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\deploy\Install-ReparoRemote.ps1 -ComputerName marajade
```

Pass multiple SSH aliases or hosts to install the same ProgramData runtime on several machines:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\deploy\Install-ReparoRemote.ps1 -ComputerName marajade,laptop
```

### Option 5: ScreenConnect / Backstage tools

ScreenConnect-ready command files are included under `deploy\ScreenConnect`.

| Tool | Purpose |
| --- | --- |
| `Install-Reparo.bat` | Installs or updates the ProgramData runtime from GitHub, repairs the `reparo.cmd` shim, and checks `reparo -Version`. |
| `Run-Reparo-System.cmd` | Creates and starts a one-shot SYSTEM scheduled task that runs `C:\ProgramData\Reparo\Reparo.ps1 -Update`. |
| `Run-Reparo-Force-System.cmd` | Creates and starts a one-shot SYSTEM scheduled task that runs `C:\ProgramData\Reparo\Reparo.ps1 -Force`. |

Run these from an elevated/admin or SYSTEM context. The installer is intentionally idempotent: if Reparo is already installed, it downloads the current GitHub script and updates the existing runtime in place.

### Private repo note

For client endpoints, a public repo or Ninja-hosted script copy is usually cleaner than embedding GitHub credentials. If the repo is private, avoid hard-coding a personal access token in the Ninja script body. Use Ninja-managed secure variables only if you truly need private GitHub delivery.

## Modes

| Mode | Behavior |
| --- | --- |
| Default | Runs `WindowsUpdate` only. |
| `-Install` / `-New` | Installs or updates `C:\ProgramData\Reparo\Reparo.ps1` from GitHub, with parse validation and backup handling. |
| `-Help` | Prints Reparo usage and exits without running updates. |
| `-Version` | Prints the Reparo version, a version-selected movie-ish quote, and exits without running updates. |
| `-Kill` | Stops running Reparo PowerShell processes, then sweeps known updater front-end processes such as `winget`, `choco`, `npm`, `pip`, and related package managers. |
| `-KillUpdaterNames <names>` | Adds extra process base names to the `-Kill` updater sweep, for example `-Kill -KillUpdaterNames msiexec`. |
| `-Preview` | Logs what would run without executing package manager commands. |
| `-Update` | Runs the managed-client pass: `Winget`, `Winget(msstore)`, `Choco`, and `WindowsUpdate`. |
| `-Winget` | Runs a winget-focused pass that attempts repair/registration if needed, logs discovery output, and then runs the winget sections. In preview mode, discovery still runs so you can refresh the visible upgrade list. |
| `-WingetDiscover` | Repairs/refreshes winget if needed and runs only winget discovery commands. |
| `-MigrateChocoToWinget` | Inventories local Chocolatey packages, matches known or mapped winget IDs, installs the winget package, then uninstalls the Chocolatey package after winget succeeds. |
| `-ChocoWingetMapPath <path>` | Adds or overrides Chocolatey-to-winget package mappings from a JSON or CSV file. |
| `-MigrateChocoExclude <ids>` | Skips extra Chocolatey package IDs during migration. Chocolatey infrastructure packages are excluded automatically. |
| `-Tail` | Follows the active Reparo log when used by itself. When combined with a run mode, it prints the tail of that run's log at the end. |
| `-TailLines <count>` | Controls how many existing log lines `-Tail` prints before following. Default: `400`. |
| `-Status` | Shows whether Reparo is currently running and points at the active log file. |
| `-IgnoreTimeouts` | Disables timeout enforcement even when timeout parameters are supplied. |
| `-AllowReboot` / `-Reboot` | Allows the Windows Update section to pass `-AutoReboot`. By default Reparo passes `-IgnoreReboot`. |
| `-InstallNuGetProvider` | Bootstraps the NuGet provider before PSGallery installs when `true` (default). Set it to `false` only if you want to suppress that bootstrap attempt. |
| `-Include <sections>` | Runs only the named sections, such as `Winget Choco`. |
| `-Force` | Runs the full local-dev-tool pass and enables Windows Update and WSL apt handling. Use carefully. |

## Sections

Available section names:

- `Winget`
- `Winget(source list)`
- `Winget(list upgrades)`
- `Winget(upgrade list)`
- `Winget(msstore)`
- `Scoop`
- `Choco`
- `Pip`
- `Pipx`
- `Npm`
- `Pnpm`
- `Yarn`
- `DotNet`
- `Rust`
- `CargoBins`
- `Conda`
- `Gem`
- `Composer`
- `Wsl`
- `WslApt`
- `WindowsUpdate`

## Chocolatey to winget migration

Use `-MigrateChocoToWinget` when you want to move a workstation away from Chocolatey package ownership and toward winget package ownership.

The migration pass is intentionally conservative:

- It lists locally installed Chocolatey packages with `choco list --local-only --limit-output --no-color`.
- It skips Chocolatey infrastructure packages such as `chocolatey` and Chocolatey extension packages.
- It migrates only packages with a built-in mapping or a mapping supplied by `-ChocoWingetMapPath`.
- It verifies the target winget package with `winget search --id <id> --exact`.
- In live mode, it installs the mapped winget package first.
- It uninstalls the Chocolatey package only after the winget install command succeeds.
- Packages without a map, unavailable winget targets, failed installs, and failed uninstalls are reported in the final summary and log.

Always start with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -Preview -MigrateChocoToWinget
```

Then run live mode on a pilot machine:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -MigrateChocoToWinget
```

For Ninja/GitHub bootstrap deployments, use:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\deploy\Ninja-GitHub.ps1 -Preview -MigrateChocoToWinget
```

Custom maps can be JSON:

```json
{
  "git": "Git.Git",
  "vscode": "Microsoft.VisualStudioCode",
  "example-choco-id": {
    "WingetId": "Vendor.Package",
    "Source": "winget"
  }
}
```

Or CSV:

```csv
ChocoId,WingetId,Source
git,Git.Git,winget
vscode,Microsoft.VisualStudioCode,winget
```

## Logging

Logs are written to:

```text
C:\ProgramData\Reparo\Logs
```

Each run creates a timestamped log file that includes the computer name, process ID, selected mode, commands invoked, command output, skipped sections, errors, and the final run summary.
While Reparo is running, the log is named with a `_RUNNING.log` suffix. After completion, it is renamed to `_COMPLETE.log`, `_FAILED.log`, or `_PREVIEW.log` so the final artifact is obvious.
The log also prints an exhaustive parameter block at startup so you can see every switch, timeout, path, and include list value that Reparo resolved for that run.
Long-running child commands emit `[CMD-WAIT]` heartbeat lines while they are still alive. Child command output is copied into the main log during execution with `[CMD-OUT]` prefixes, so `-Tail` can show winget progress while winget is still running.

Use `-Tail` or its alias `-Log` to follow the active log when used by itself. When combined with a run mode, it prints the tail of the current run's log file at the end of execution.
Use `-TailLines` to increase or reduce the initial tail window.
Use `-Status` to see whether Reparo is currently running and which log file it is writing. The status probe excludes its own helper process so it does not report itself as the active run, and it will show stale `_RUNNING.log` files when a run ended before finalization.
Use `-Debug` when you want extra trace lines in the log for mode selection, command launch details, and bootstrap behavior. In Ninja, the wrapper now forwards `-Debug` through to Reparo.
Use `-WingetDiscover` when you want to refresh the winget discovery list without running live upgrades.
Use `-Kill` when a run is stuck; it stops matched Reparo process trees and then sweeps known updater front ends so orphaned `winget.exe` or similar package-manager processes are not left running. Reparo does not kill generic shells or installer engines by default; add extra process base names with `-KillUpdaterNames` when you intentionally want that broader cleanup.
Use `-IgnoreTimeouts` when you explicitly want to suppress timeout enforcement even if timeout values are supplied.
Use `-AllowReboot` or `-Reboot` only when you want Windows Update to be allowed to auto-reboot. Default runs still suppress reboot with `-IgnoreReboot`.
Timeouts are disabled by default. Use `-WingetTimeoutSeconds`, `-WingetDiscoveryTimeoutSeconds`, and `-WindowsUpdateTimeoutSeconds` only when you explicitly want Reparo to stop a command after a positive number of seconds.
Use `-InstallNuGetProvider:$false` if a managed environment wants to block NuGet provider bootstrapping, or leave it at the default `true` so Reparo can install it before PSGallery module installs.

At the end of the run, Reparo prints a `REPARO summary` with:

- updated software, current version, target version, and update method where package-level details are available
- skipped sections with reasons
- failed sections with reasons or exit codes
- notes for completed sections that do not expose a clean package-level update list
- the log path

Package-level update details are currently collected for `Winget`, `Winget(msstore)`, `Choco`, `Scoop`, and `MigrateChocoToWinget`. Other ecosystems still report section-level completion and write their raw tool output to the log.

You can override the log location:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -Update -LogRoot C:\Temp\ReparoLogs
```

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Administrative rights for Windows Update operations
- Existing package managers for each selected section
- `choco` and `winget` available in the same execution context for `-MigrateChocoToWinget`
- `PSWindowsUpdate` is auto-installed from PSGallery when possible for the `WindowsUpdate` section

`winget` and Microsoft Store behavior can vary by Windows build, execution context, source agreement state, tenant policy, and device policy. Test from the same context your RMM will use, especially when running as `SYSTEM`.

## Troubleshooting

If a section reports that a tool is present but cannot run, the most common cause is an execution-context mismatch. This is especially common with `winget` and Microsoft Store/App Installer paths under RMM, ScreenConnect, or `SYSTEM`; Windows can resolve `winget.exe` but still refuse to execute it in that context.

Reparo probes known package managers before running them and skips sections that cannot launch cleanly. For `Winget`, Reparo also attempts repair before skipping: it tries App Installer re-registration, `Repair-WinGetPackageManager` when present, and the latest Microsoft `winget-cli` App Installer MSIX bundle. If `Winget` is still skipped under a remote tool but works in an interactive admin shell, run Reparo from the same user/admin context where App Installer is available, or use a package manager that is installed machine-wide, such as Chocolatey.

For the live `Winget` upgrade path, Reparo now uses `--disable-interactivity`, `--silent`, and `--force` so Ninja runs are treated like non-interactive automation instead of desktop sessions waiting for UI.

For `WindowsUpdate`, Reparo will try to install `PSWindowsUpdate` from PSGallery first. If that bootstrap fails because the session cannot reach PSGallery or cannot install modules, the section is skipped with a logged reason instead of failing silently.

For `Winget`, Reparo now tries a repair/registration path when `winget` is missing. It logs `winget source list` and `winget list --upgrade-available` when you run `-Winget` so you can see what the client can actually discover before the upgrade pass starts.

Some winget upgrades, including `Microsoft.PowerShell`, may require an uninstall/reinstall instead of an in-place upgrade when the installer technology changes. Reparo logs that message explicitly and leaves the package for manual handling rather than pretending the upgrade succeeded.

## Safety notes

- Start with `-Preview`.
- Use `-Update` for ordinary managed-client maintenance.
- Avoid `-Force` on general client endpoints unless you intentionally want to touch developer toolchains and WSL.
- Review logs after pilot runs.
- Expect package managers to return nonzero exit codes for some "nothing to update" cases; Reparo treats common benign `winget` messages as successful no-op outcomes.

## Public repo note

This copy is designed to be shareable. Before publishing a fork, review the README wording for organization-specific deployment details.
