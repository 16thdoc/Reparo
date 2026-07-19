# Reparo

Reparo is a standalone Windows maintenance runner for RMM deployment.

It updates common package managers and toolchains when they are already present on a machine. The script is intentionally self-contained: it does not depend on profile modules, cloud-synced helper paths, editor sync state, or any other machine-specific automation.

## What it does

By default, Reparo runs Windows Update through `PSWindowsUpdate`. Optional modes can also include `winget`, Microsoft Store updates through `winget`, Chocolatey, PowerShell 7 through winget, developer toolchains such as Scoop, pip, npm, pnpm, Yarn, .NET tools, Rust, Conda, Ruby gems, Composer, Spicetify, and WSL, plus a Chocolatey-to-winget migration pass.

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
reparo -Update -Syslog 192.168.50.31:514
reparo -CheckApp Microsoft.VisualStudioCode -PackageManager Winget
reparo -Preview -LockApp Microsoft.VisualStudioCode -LockVersion 1.125.0 -PackageManager Winget
reparo -Search
reparo -List
reparo -Search git
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
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -Preview -MigrateChocoToWinget -MigrationReportPath "$env:USERPROFILE\Desktop\reparo-choco-winget-preview"
```

Run Chocolatey-to-winget migration:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -MigrateChocoToWinget -ChocoDeregisterOnly -MigrationReportPath "$env:USERPROFILE\Desktop\reparo-choco-winget-live"
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

### Moshi / mosh setup over SSH

`deploy/Install-MoshiRemote.ps1` prepares SSH-reachable Linux hosts for the
[Moshi mobile terminal](https://getmoshi.app). It installs `mosh`, `tmux`, and
their prerequisites through apt, dnf/yum, pacman, or zypper, then installs
`moshi-hook` with Moshi's official installer. Required repositories must already
provide `mosh`; RHEL-family hosts commonly need EPEL enabled. The remote account
must be root or have passwordless sudo when packages, firewall rules, or
systemd lingering need changes.

Preview a batch first:

```powershell
./deploy/Install-MoshiRemote.ps1 -ComputerName devbox,vps01 -Preview
```

The QR-free path is manual key provisioning. In Moshi, create an Ed25519 key
and copy its **public** key, then pass that public key to the helper. Create the
saved connection in Moshi with the same host, SSH user, and private key:

```powershell
$moshiPublicKey = Get-Clipboard
./deploy/Install-MoshiRemote.ps1 -ComputerName devbox -AuthorizedKey $moshiPublicKey
```

This helper does not create the saved phone-side connection, so create that
final connection in the app manually. `moshi-hook host setup` remains the
easiest alternative when scanning its temporary Easy Pair QR is acceptable.

Agent notification pairing is separate from SSH connection pairing. Copy the
hook token from **Moshi -> Settings -> Hooks** and provide it as a secure value:

```powershell
$token = Read-Host 'Moshi hook pairing token' -AsSecureString
$key = Get-Clipboard # Moshi-generated public key, not the private key

./deploy/Install-MoshiRemote.ps1 -ComputerName devbox `
    -AuthorizedKey $key `
    -PairingToken $token `
    -InstallAgentHooks `
    -AgentProjectPath /home/trenton/projects/example `
    -ConfigureService `
    -EnableLinger
```

`-InstallAgentHooks` modifies supported agent configuration. For OpenCode its
plugin is project-local, so use `-AgentProjectPath` for the intended repository
or run `moshi-hook install` separately in each project. `-ConfigureService`
creates and enables a systemd user service; `-EnableLinger` also keeps that user
service alive after logout. Moshi's current pairing CLI accepts its token only
as an argument, so the token is briefly visible in the remote host's process
list; do not pair this way on an untrusted multi-user host.

Mosh bootstraps over the configured SSH TCP port (normally 22) and then uses UDP
60000-61000. Prefer Tailscale or another VPN instead of exposing those ports
publicly. If a host firewall really needs the range, add `-OpenMoshFirewall`;
the helper supports active ufw and firewalld and otherwise reports that a manual
rule is required.

Native Windows can be used as a plain SSH target in Moshi, but upstream
`mosh-server` and `moshi-hook` do not provide a native Windows host build. For
mosh and hooks, use a WSL2 Linux distribution as the actual SSH target (with
reachability and UDP routing into WSL configured), or use a normal Linux VM.

### Private repo note

For client endpoints, a public repo or Ninja-hosted script copy is usually cleaner than embedding GitHub credentials. If the repo is private, avoid hard-coding a personal access token in the Ninja script body. Use Ninja-managed secure variables only if you truly need private GitHub delivery.

## Modes

| Mode | Behavior |
| --- | --- |
| Default | Runs `WindowsUpdate` only. |
| `-Install` / `-New` | Installs or updates `C:\ProgramData\Reparo\Reparo.ps1` from GitHub, with parse validation and backup handling. |
| `-Help` / `-H` / `-h` | Prints Reparo usage and exits without running updates. |
| `-Version` / `-V` / `-v` | Prints the Reparo version, script source path, and version-specific quote, then exits without running updates. |
| `-Kill` | Stops running Reparo PowerShell processes, then sweeps known updater front-end processes such as `winget`, `choco`, `npm`, `pip`, and related package managers. |
| `-KillUpdaterNames <names>` | Adds extra process base names to the `-Kill` updater sweep, for example `-Kill -KillUpdaterNames msiexec`. |
| `-Preview` | Logs what would run without executing package manager commands. |
| `-Update` | Runs the managed-client pass: `Winget`, `Winget(msstore)`, `Choco`, `PowerShell7`, and `WindowsUpdate`. |
| `-11` / `-Win11` / `-Windows11` | Runs a Windows 10 to Windows 11 feature upgrade using Microsoft's Windows 11 Installation Assistant. Requires elevation. Use `-Preview -11` first to log the download URL and installer command without launching the upgrade goblin. |
| `-Winget` | Runs a winget-focused pass that attempts repair/registration if needed, logs discovery output, and then runs the winget sections. In preview mode, discovery still runs so you can refresh the visible upgrade list. |
| `-WingetDiscover` | Repairs/refreshes winget if needed and runs only winget discovery commands. |
| `-Search` / `-List` / `-S` / `-L` | Inventories applications Reparo `-Force` can update and prints installed versions, available versions when known, update method, source, lock status, and a ready-to-copy `LockSpec`. Add terms after the switch to filter, for example `reparo -Search git` or `reparo -List git`. PowerShell switch names are case-insensitive, so lowercase forms work too. |
| `-VersionLock <spec>` | Adds an inline version lock for this run. Format: `method:id=version`, for example `winget:Git.Git=2.51.0`. |
| `-AddVersionLock <spec>` / `-SaveVersionLock <spec>` / `-AVL <spec>` | Persists a Reparo-side version lock to the local workstation lock file, then exits. Use this for machine-specific exclusions such as ScanSnap. |
| `-VersionLockPath <path>` | Reads version locks from JSON. Default: `C:\ProgramData\Reparo\version-locks.json`. |
| `-ListVersionLocks` | Prints resolved locks from the lock file and inline `-VersionLock` specs, then exits. |
| `-MigrateChocoToWinget` | Builds a conservative Chocolatey-to-winget migration plan with package class, risk level, duplicate grouping, ProgramData payload status, shim status, winget availability, and proposed action. Live mode installs/verifies winget replacements. |
| `-ChocoDeregisterOnly` | After winget verification, deregisters safe Chocolatey package records with `--skip-autouninstaller` and `--skip-powershell`. This is not an app uninstall. |
| `-ForceWingetReinstall` | Allows `winget install --force` during migration. Off by default. |
| `-AllowRuntimeDeregister` | Allows runtime package records such as VC++ redistributables and .NET Desktop Runtime to be deregistered after verification. Off by default. |
| `-AllowPortableDeregister` | Allows portable/CLI payload package records to be deregistered after non-Chocolatey command-path verification. Off by default. |
| `-FinalizeChocolateyRemoval` | Separate explicit phase that backs up and removes Chocolatey after safety checks. Uses `$env:ChocolateyInstall` when available, otherwise `C:\ProgramData\chocolatey` / `C:\ProgramData\choco` fallback detection. |
| `-MigrationReportPath <path>` | Exports migration plan/results to CSV and JSON. A bare path writes both `<path>.csv` and `<path>.json`. |
| `-ChocoWingetMapPath <path>` | Adds or overrides Chocolatey-to-winget package mappings from a JSON or CSV file. |
| `-MigrateChocoExclude <ids>` | Skips extra Chocolatey package IDs during migration. Chocolatey infrastructure packages are excluded automatically. |
| `-CheckApp <id/name>` | Shows the installed version of one app through winget or Chocolatey, then exits without running update sections. |
| `-LockApp <id/name>` | Pins one app through the package manager so Reparo and normal package-manager updates do not move it. |
| `-LockVersion <version>` | Version to pin with `-LockApp`. If omitted, Reparo tries to pin the currently installed version. |
| `-PackageManager Auto\|Winget\|Choco` | Selects the app lookup/lock backend for `-CheckApp` and `-LockApp`. Default is `Auto`, which tries winget first, then Chocolatey. |
| `-InstallSpicetify` | Installs or reinstalls Spicetify Marketplace in the logged-on user's context, then runs update and backup/apply. |
| `-Tail` | Follows the active Reparo log when used by itself. When combined with a run mode, it prints the tail of that run's log at the end. |
| `-TailLines <count>` | Controls how many existing log lines `-Tail` prints before following. Default: `400`. |
| `-Syslog <host[:port]>` | Persistently sets and uses a TCP syslog listener. Default port is `514`, so `-Syslog 192.168.50.31` and `-Syslog 192.168.50.31:514` target the same port. Use `-Syslog off` or `-Syslog disable` to clear the saved target. |
| `-Status` | Shows whether Reparo is currently running, points at the active log file, and prints the registry evidence behind any pending reboot flag. |
| `-IgnoreTimeouts` | Disables timeout enforcement even when timeout parameters are supplied. |
| `-AllowReboot` / `-AllowRestart` | Allows the Windows Update section to pass `-AutoReboot`. By default Reparo passes `-IgnoreReboot`. |
| `-Reboot` / `-Restart` / `-R` | Restarts the computer 30 seconds after Reparo completes. |
| `-Shutdown` | Shuts down the computer 30 seconds after Reparo completes. Cannot be combined with `-Reboot`. |
| `-InstallNuGetProvider` | Bootstraps the NuGet provider before PSGallery installs when `true` (default). Set it to `false` only if you want to suppress that bootstrap attempt. |
| `-Include <sections>` | Runs only the named sections, such as `Winget Choco`. |
| `-Force` | Runs the full local-dev-tool pass, includes the per-user Spicetify update/backup/apply section, and enables Windows Update and WSL apt handling. Use carefully. |

### Version quote style

`reparo -Version` should keep the CyberShell-style quote structure whenever the runtime version changes. Do not reuse the previous version's quote just because the format is stable; pick a fresh quote/source pair for the new version and add it to `Get-ReparoVersionFlavor`.

Expected shape:

```text
Reparo 1.1.3
Source: C:\ProgramData\Reparo\Reparo.ps1
  "Never tell me the odds."
  - Star Wars: The Empire Strikes Back
```

The quote body and source can change every release. The indentation, surrounding quote marks, and `  - Source` attribution line should not.

## App version checks and locks

Check an installed version:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -CheckApp Microsoft.VisualStudioCode -PackageManager Winget
```

Preview a version lock without adding or changing package-manager pins:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -Preview -LockApp Microsoft.VisualStudioCode -LockVersion 1.125.0 -PackageManager Winget
```

Apply the lock:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -LockApp Microsoft.VisualStudioCode -LockVersion 1.125.0 -PackageManager Winget
```

Chocolatey works the same way with Chocolatey package IDs:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -CheckApp git -PackageManager Choco
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -LockApp git -LockVersion 2.51.0 -PackageManager Choco
```

Reparo uses native package-manager pins (`winget pin add` or `choco pin add`) instead of maintaining a separate skip list.

## Sections

Available section names:

- `Winget`
- `Winget(source list)`
- `Winget(list upgrades)`
- `Winget(upgrade list)`
- `Winget(msstore)`
- `Scoop`
- `Choco`
- `PowerShell7`
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
- `Spicetify`
- `Wsl`
- `WslApt`
- `WindowsUpdate`
- `Windows11Upgrade`

### Windows 11 feature upgrade

`-11` is an explicit OS-upgrade mode, not part of `-Update` or `-Force`. It only runs from Windows 10, skips Windows 11 or newer builds, downloads Microsoft's Windows 11 Installation Assistant to `C:\ProgramData\Reparo\Cache`, and launches it with quiet upgrade arguments.

```powershell
reparo -Preview -11
reparo -11
```

Use an elevated/admin or SYSTEM context and expect a long-running installer plus reboot behavior from the Windows setup stack.

### PowerShell 7

The `PowerShell7` section installs or updates Microsoft's signed, machine-wide
MSI at `C:\Program Files\PowerShell\7\pwsh.exe`. The stable path is suitable for
OpenSSH Server, scheduled tasks, and other machine-level automation. Reparo
queries the latest stable GitHub release, validates the Authenticode signature,
and skips installation only when the signed executable and Windows Installer
registration confirm that the machine-wide MSI is already current.

The section is included in `-Update` and `-Force`, and can also be run directly
from an elevated session:

```powershell
reparo -Preview -Include PowerShell7
reparo -Include PowerShell7
```

If you need to freeze PowerShell 7 for a machine, use the existing winget lock format:

```powershell
reparo -Force -VersionLock winget:Microsoft.PowerShell=7.5.2
```

When that lock is active, Reparo skips the dedicated `PowerShell7` section.
The general winget pass also excludes `Microsoft.PowerShell` whenever this
dedicated section is selected, preventing an MSIX/MSI installer-technology
knife fight.

### Spicetify

The `Spicetify` section is included in `-Force` and can also be run directly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -Include Spicetify
```

To install or reinstall Spicetify Marketplace for the logged-on user, use:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -InstallSpicetify
```

Spicetify is intentionally handled as a per-user tool. When Reparo is running elevated or as `SYSTEM`, it creates a short-lived hidden interactive scheduled task for the logged-on Explorer user, then runs:

```powershell
spicetify update
spicetify backup apply
```

If `-InstallSpicetify` is present, Reparo first runs the official Spicetify Marketplace PowerShell installer from that same user context. That installer also bootstraps the Spicetify CLI when needed. If Spicetify is not installed or cannot be resolved during ordinary `-Force`, the section is skipped.

If `spicetify backup apply` reports that a backup already exists and asks for `spicetify restore backup` before creating another backup, Reparo treats that as an already-backed-up state and continues. It does not clear or replace the existing Spicetify backup automatically.

### WSL apt

`WslApt` runs Debian/Ubuntu apt maintenance only for WSL distros where `apt` is present and noninteractive privilege escalation is available. Reparo checks `sudo -n` before starting apt work so an RMM or scheduled run does not hang on a Linux password prompt. The apt step also has its own timeout:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -Include WslApt -WslAptTimeoutSeconds 1800
```

Set `-WslAptTimeoutSeconds 0` to disable that timeout, or use `-IgnoreTimeouts` to disable all configured command-step timeouts.

## Chocolatey to winget migration

Use `-MigrateChocoToWinget` when you want to move a workstation away from Chocolatey package ownership and toward winget package ownership. The migration is plan-based and intentionally conservative; final Chocolatey removal is a separate explicit phase.

The migration pass is intentionally conservative:

- It lists locally installed Chocolatey packages with `choco list --local-only --limit-output --no-color`.
- It audits Chocolatey ProgramData payloads and command shims that resolve under the Chocolatey root.
- It classifies packages as normal GUI apps, duplicate clusters, runtime dependencies, portable payloads, infrastructure, prerequisites, unsupported, or manual review.
- It groups duplicate Chocolatey package records that map to the same winget ID and verifies/installs the winget target only once per group.
- It verifies the target winget package with `winget search --id <id> --exact` and checks whether it is already installed.
- Live mode installs or verifies the mapped winget package without `--force` unless `-ForceWingetReinstall` is supplied.
- Chocolatey cleanup is safe record deregistration with skip flags when `-ChocoDeregisterOnly` is supplied, not a blind application uninstall.
- Runtime packages require `-AllowRuntimeDeregister`; portable/CLI payloads require non-Chocolatey command verification and may require `-AllowPortableDeregister`.
- Packages without a map, unavailable winget targets, risky payloads, and manual-review items are reported in the final summary and optional CSV/JSON reports.
- CyberChef and other static/portable payloads are not silently allowed through final Chocolatey removal; preserve them manually or use an explicit override after reviewing the backup/report.

Always start with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -Preview -MigrateChocoToWinget -MigrationReportPath "$env:USERPROFILE\Desktop\reparo-choco-winget-preview"
```

Then run live mode on a pilot machine after reviewing the report:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -MigrateChocoToWinget -ChocoDeregisterOnly -MigrationReportPath "$env:USERPROFILE\Desktop\reparo-choco-winget-live"
```

Handle runtime and portable/CLI payload records only after the normal app migration is boring:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -MigrateChocoToWinget -ChocoDeregisterOnly -AllowRuntimeDeregister
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -MigrateChocoToWinget -ChocoDeregisterOnly -AllowPortableDeregister
```

When reports show no critical Chocolatey-only payloads remain, final removal is explicit and backup-first:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -Preview -FinalizeChocolateyRemoval
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -FinalizeChocolateyRemoval
```

`-FinalizeChocolateyRemoval` respects `$env:ChocolateyInstall` so managed devices with a nonstandard Chocolatey root are handled correctly. If that variable is absent, Reparo falls back to `C:\ProgramData\chocolatey`, with `C:\ProgramData\choco` detection for oddball installs.

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
Use `-AllowReboot` only when Windows Update may auto-reboot before the rest of the Reparo run finishes. Use `-Reboot` to restart, or `-Shutdown` to power off, 30 seconds after Reparo completes. Both post-run power actions honor `-Preview`; `-Reboot` and `-Shutdown` cannot be combined.
Most command timeouts are disabled by default. Use `-WingetTimeoutSeconds`, `-WingetDiscoveryTimeoutSeconds`, and `-WindowsUpdateTimeoutSeconds` only when you explicitly want Reparo to stop a command after a positive number of seconds. `WslApt` defaults to `-WslAptTimeoutSeconds 1800` because unattended sudo/apt sessions can otherwise wait forever.
Use `-InstallNuGetProvider:$false` if a managed environment wants to block NuGet provider bootstrapping, or leave it at the default `true` so Reparo can install it before PSGallery module installs.

At the end of the run, Reparo prints a `REPARO summary` with:

- updated software, current version, target version, and update method where package-level details are available
- skipped sections with reasons
- failed sections with reasons or exit codes
- notes for completed sections that do not expose a clean package-level update list
- the log path

Package-level update details are currently collected for `Winget`, `Winget(msstore)`, `Choco`, `Scoop`, and `MigrateChocoToWinget`. Other ecosystems still report section-level completion and write their raw tool output to the log.

## Search and version locks

Use `-Search` or `-List` to see the software Reparo can update under the broader `-Force` umbrella:

```powershell
reparo -Search
reparo -List
reparo -Search git
reparo -List git
reparo -S vscode
reparo -L vscode
```

The output includes installed `Version`, `AvailableVersion` when the package manager exposes it cleanly, `Method`, `Source`, lock state, and a `LockSpec` you can paste into a lock file or pass inline.

Default lock file:

```text
C:\ProgramData\Reparo\version-locks.json
```

JSON object form:

```json
{
  "winget:Git.Git": "2.51.0",
  "choco:git": "2.51.0"
}
```

JSON array form:

```json
[
  { "Method": "winget", "Id": "Git.Git", "Version": "2.51.0" },
  { "Method": "scoop", "Id": "ripgrep", "Version": "14.1.1" }
]
```

Inline one-run locks are also supported:

```powershell
reparo -Force -VersionLock winget:Git.Git=2.51.0
```

Persist a lock on just one workstation by writing that machine's local lock file:

```powershell
reparo -Search scansnap
reparo -AddVersionLock winget:ScanSnap.PackageId=1.2.3
reparo -ListVersionLocks
```

Use the `LockSpec` from `-Search` when possible. This is the right workflow for client-specific exclusions: the locked workstation skips that app during Reparo runs, while other workstations without the lock continue updating it normally.

Automatic skipping is currently implemented for `winget`, `choco`, `scoop`, `npm`, and global `.NET` tools. Locks for other methods are listed and logged as configured, but Reparo does not yet know how to safely exclude those packages from their bulk updater commands. Tiny goblin with a clipboard, not a package manager miracle worker.

You can override the log location:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -Update -LogRoot C:\Temp\ReparoLogs
```

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Administrative rights for Windows Update operations
- Existing package managers for each selected section
- A logged-on Explorer user for the `Spicetify` section when Reparo is running elevated or as `SYSTEM`
- `choco` and `winget` available in the same execution context for `-MigrateChocoToWinget`
- `PSWindowsUpdate` is auto-installed from PSGallery when possible for the `WindowsUpdate` section

`winget` and Microsoft Store behavior can vary by Windows build, execution context, source agreement state, tenant policy, and device policy. Test from the same context your RMM will use, especially when running as `SYSTEM`.

Spicetify behavior is user-context sensitive because Spotify and Spicetify files live under the interactive user's profile. Do not run the underlying Spicetify commands as admin unless you intentionally want to target the elevated account's profile instead of the desktop user's Spotify install.

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
- WSL apt is skipped when `sudo` would need a password; configure passwordless sudo in the distro first if you want unattended WSL package maintenance.

## Public repo note

This copy is designed to be shareable. Before publishing a fork, review the README wording for organization-specific deployment details.
