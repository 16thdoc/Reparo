# Reparo

Reparo has separate native maintenance runners for Windows and Linux. Windows uses
the PowerShell runner for RMM deployment; Linux uses a portable POSIX `sh`
runtime and does not require PowerShell.

It updates common package managers and toolchains when they are already present on a machine. The script is intentionally self-contained: it does not depend on profile modules, cloud-synced helper paths, editor sync state, or any other machine-specific automation.

## Linux quick start

Install or update the native Linux runtime from a clone of this repository:

```sh
sh ./deploy/install-reparo-linux.sh --verbose
```

The installer reads `deploy/reparo-release.json`, downloads commit-pinned
`linux/reparo-linux`, verifies its SHA-256/version and POSIX syntax, and installs it
at `~/.local/share/reparo/reparo-linux` (respecting `XDG_DATA_HOME`), and creates a
shell-neutral `reparo` shim at `~/.local/bin/reparo`. It works from Bash, Zsh, Fish,
Dash, or any shell that can launch a POSIX command. Add `~/.local/bin` to `PATH` if
your distribution has not already done so.

```sh
reparo --preview                 # show exactly what an update pass would do
reparo --update                  # native packages plus installed common tools
reparo --force --preview         # include installed developer toolchains, dry-run
reparo --include Apt Flatpak     # restrict the pass to named sections
reparo --status                  # other Reparo Linux processes and latest log
reparo --tail                    # follow the newest log
reparo -Version                  # runtime version; see alias lexicon below
reparo -New                      # verify immutable installer/runtime release pins
reparo -Install                  # same native install/update action
reparo --latest                  # explicitly unreviewed main, not the release pin
```

Linux detects its native manager from `/etc/os-release`: Apt (Debian, Ubuntu, Mint,
Pop!_OS, Kali), Dnf (Fedora/RHEL-family), Pacman (Arch/Manjaro), or Zypper
(openSUSE/SLES). It also updates installed Flatpak, Snap, fwupd, npm, and OpenCode;
`--force` adds installed pipx, pnpm, Yarn, .NET tools, Rust, Conda, gems, and
Composer. Logs live under `~/.local/state/reparo/logs` (respecting `XDG_STATE_HOME`).

Reparo also emits concise lifecycle events to the local syslog/journal facility with
the `reparo-linux` tag. Events are key-value messages (`event`, `run_id`, `version`,
`section`, `result`, `log`, and so on), deliberately excluding the full package-tool
output. Forward that tag from rsyslog, syslog-ng, or Graylog Sidecar to Graylog; do
not put a Graylog credential or collector address in the runner. For a local check:

```sh
journalctl -t reparo-linux -n 50 --no-pager
```

Use `run_id` to correlate the Graylog event stream with the complete local logfile.

Native package operations require root or passwordless `sudo -n`; Reparo skips them
rather than summon an unattended password prompt from the abyss. `--kill` sends
SIGTERM only to other Reparo Linux processes, never a broad updater-process sweep.
When npm's global prefix is system-owned (for example `/usr/local`), Reparo runs
`npm update -g` through that same root/passwordless-sudo path instead of detonating
on `EACCES` during a package rename. User-owned npm prefixes still update as the
calling user.

### Linux host scope

Reparo is supported on ordinary GNU/Linux hosts with one of its native managers:
Debian/Ubuntu-family systems (including **Proxmox VE**), Fedora/RHEL-family systems,
Arch/Manjaro, and openSUSE/SLES. On Proxmox, run `reparo --preview` first and use the
native Proxmox subscription/repository policy before an Apt pass; Reparo must never be
used to “fix” a deliberately managed appliance repo.

**QNAP QTS/QuTS hero and UniFi OS are appliance operating systems, not supported
package-manager targets.** Their vendor update mechanisms own the base OS. Do not run
Reparo package maintenance or CyberShell deployment there; use the vendor UI/CLI and
run Reparo on a normal VM, container, or supported host adjacent to the appliance.

### Linux command lexicon

Every native Linux command accepts double-dash, single-dash, and bare long forms in
any casing, plus an unambiguous short form with or without a dash. The short forms
are Update/U, Force/F, Preview/P, Include/C, Status/S, Kill/K, Tail/T,
TailLines/TL, Version/V, New/N, Install/I, and Help/H; `Log` is another name for
Tail. Thus `-Version`, `version`, `-V`, and `v` are equivalent, as are mixed-case
forms such as `--VeRsIoN`. `New` and `Install` both run the native installer, so they
update Reparo itself; `--update` updates the machine's installed packages and tools
instead. Windows-only commands are identified plainly rather than pretending they
work on Linux. The native and Windows runners share the Reparo release number and
the same CyberShell-style version quote/source flavor.

As of 1.4.1.3, native New/Install verify both the installer and runtime against one
manifest snapshot, with no silent main fallback. Python 3 (standard library only)
validates bounded JSON, unique keys, four-part version, full commit, exact GitHub
artifact URLs and digests; `sha256sum` verifies bytes before code execution/replacement.
HTTPS certificate validation remains enabled; downloads have 10-second connection
and 60-second total limits. The mutable manifest is a reviewed channel pointer,
not a signed trust root or rollback-prevention mechanism. Keep a prior verified
manifest/artifacts for rollback. `--latest` and explicit `REPARO_URL` or
`REPARO_INSTALLER_URL` overrides are labeled unpinned; never use them to claim
reviewed-release provenance. `REPARO_RELEASE_URL` can select a protected HTTPS mirror;
artifact URLs remain strictly GitHub/commit-bound. A clone's standalone installer
is operator-trusted bootstrap code; an installed native runner verifies the downloaded
bootstrap first. Windows Install remains offline and Windows Latest/N remains
unpinned; native N retains its historical New meaning, with Latest spelled out.

## Unattended run repairs - 1.4.4.5

Windows workers retain terminating exceptions (including HRESULT, error identity
and location), direct stderr and startup/parse failures in the final log. A failed
section's summary includes its captured exception. stderr alone never changes a
successful exit into a failure.

Windows Update's download/install APIs can reject SSH/WinRM callers with
`0x80070005`, even when the shell is elevated. Use the existing local worker:

```powershell
reparo -Include WindowsUpdate -Headless
reparo -Status
reparo -Tail
```

Check the worker's completed log: the scheduling command only confirms
registration. The SYSTEM worker bootstraps NuGet before consulting PSGallery,
without prompting in a noninteractive session. No reboot is requested unless
explicitly selected. See Microsoft's [WUA remote-call restrictions](https://learn.microsoft.com/en-us/windows/win32/wua_sdk/using-wua-from-a-remote-computer).

Steam opens its Downloads page when an existing window has no scheduled-download
controls, then waits up to 20 seconds for the controls. Desktop identity,
cancellation and running-game checks remain enforced. This fixes minimized or
non-Downloads windows without changing game update policy.

The Windows pip worker disables pip's advisory about script locations using
`--no-warn-script-location` on each install call. This avoids a pip PATH-warning
failure when an unrelated PATH entry is a restricted mount; installation errors
still fail normally. PATH, pip configuration and installation scope are preserved.
Native Linux retains its existing pipx/virtual-environment boundary; Windows
Update and Steam desktop automation are Windows-only. Native command diagnostics
already retain stdout/stderr and exit status.

Release flavor: Yoda's lesson in *The Empire Strikes Back* (1980), directed by
Irvin Kershner; [quote reference](https://www.starwars.com/news/8-great-life-teachings-from-yoda).

## Steam queue progress reporting - 1.4.4.3

Queued and downloading Steam requests now appear under **Pending updates**, with
`Result: PENDING` and a separate Pending count. They are not counted as skipped,
failed, or installed updates. A request whose acknowledgment was not observed is
also pending/unconfirmed, not a confirmed failure. Reparo revisits delayed Steam
UI acknowledgments during the bounded wait. Confirmed execution errors still fail;
only fresh completed-install evidence counts as Updated. Steam continues its queue
after Reparo exits; pending requests do not instruct the user to update manually.

Local Ninja receipts include pending work. The existing allowlisted reporting
schema is preserved, with unknown final outcome while Steam work remains pending.
The final COMPLETE log means Reparo finished observing/dispatching, not that Steam
finished every download. Native Linux has no desktop-Steam queue; its maintenance
counts/behavior remain unchanged with matching release identity and flavor.

Release flavor: "Punch it!" - Han Solo to Chewbacca, *Star Wars: The Empire Strikes
Back* (1980), with Falcon departure art
([official reference](https://www.starwars.com/news/40-quotes-star-wars-the-empire-strikes-back)).

## Steam updates without certificate gating - 1.4.4.2

Steam updates use the discovered desktop client without an Authenticode or
publisher-certificate gate. Certificate validation is deferred at the operator's
request. Library discovery, exact game-title matching, window process/path/session
checks, unlocked desktop checks, running-game protection and evidence-based update
receipts remain. No per-machine certificate setup is required.

The Windows PowerShell command-shim module-path fix from 1.4.4.1 remains: this
host's core modules take precedence without rewriting profiles or saved environment.
Native Linux shares release identity/flavor; its maintenance behavior is unchanged.

Release flavor: "Laugh it up, fuzzball." - Han Solo to Chewbacca,
*Star Wars: The Empire Strikes Back* (1980), with Chewbacca art
([official reference](https://www.starwars.com/news/40-quotes-star-wars-the-empire-strikes-back)).

## Steam desktop update queue and SSH-detached maintenance - 1.4.4.0

Windows `-Include Steam` inventories installed apps in the primary Steam library
and every configured `libraryfolders.vdf` location, including C: and D:. It requests
pending updates through the discovered desktop client's **Downloads > Download now**
controls. An already-running client is reused. A closed client can be opened in the
verified desktop user's session; account sign-in remains a manual step.

```powershell
reparo -Include Steam -Preview
reparo -Include Steam -Headless
reparo -Include Steam -SteamAppId 720620 -SteamWaitSeconds 60 -Headless
reparo -Status
reparo -Tail
```

`-SteamAppId` limits requests to installed AppIDs (comma-separated IDs are accepted).
Without it, all locally update-required, eligible installed apps are considered.
Unknown AppIDs cannot trigger a new installation. `-SteamWaitSeconds` bounds the
post-request observation window to 0-180 seconds (default 15); queued downloads
continue in Steam after Reparo finishes. Both options require `-Include Steam` or
Windows `-Force`. Preview reads inventory without opening Steam, creating a queue
worker, or requesting downloads. Windows `-Force` also includes Steam.

Queue control requires exactly one logged-in Explorer desktop session, an unlocked
desktop, and a Steam client exposing the supported English Downloads controls.
The Windows PowerShell worker uses native UI Automation 8, including offscreen rows.
Locked, ambiguous, signed-out or unsupported client states are reported as blocked
or skipped. Reparo never automates account authentication or the Windows lock screen.
It skips running games, missing installation directories, duplicate game names, and
games configured to update only on launch. Steam still owns downloads, disk checks,
network behavior and persistent automatic-update preferences.

Each request produces a `[STEAM-QUEUE]` record and a receipt under
`C:\ProgramData\Reparo\SteamQueue`. **Queued**, **Downloading**, **Completed**,
**Unconfirmed**, **Blocked** and **Failed** are distinct outcomes. The summary counts
an app as updated only after its update-required flag clears and its build or
last-updated timestamp advances. Client startup, a successful button invocation,
and scheduling-command exit code do not prove download completion. Local manifests
are evidence about this run, not a remote check that every installed game is current.

`-Headless` registers a one-shot SYSTEM maintenance task for about five seconds
later and returns to SSH. The Steam section bridges to a separate, limited-privilege
interactive-user task and validates its identity and receipt. Both tasks remove
themselves after a completed run; logs and receipts remain available. A timed-out
desktop worker receives a cancellation marker before any later request, and its
diagnostic task/receipt location is retained. Reparo does not terminate Steam or
games to enforce a deadline. Inspect the completed worker log and Reparo Application
events after disconnecting SSH. Headless requires an explicit maintenance selector
and rejects `-Time`, `-Task`, `-Preview` and administrative modes.

Reparo reads Steam manifests and invokes desktop download controls. It does not
rewrite manifests or preferences, launch games, install duplicate copies, or use
SteamCMD against desktop libraries. No per-drive Reparo configuration is needed.

Steam desktop control and Windows Task Scheduler are intentional Windows-only
features. The native Linux runner keeps its existing maintenance behavior and shares
the 1.4.4.0 release identity and flavor. Tests cover this platform boundary, selector
binding, UTF-8 inventory, exact title matching, protected running games, lock/session
checks, limited-user task receipts, and evidence-based completion. Relevant suites:
`Test-ReparoSteamHeadless`, `Test-ReparoSteamClient`, `Test-ReparoSteamQueue`,
`Test-ReparoOneShotWorkerBinding`, and `Test-ReparoFlexibleScheduling` under `Tests`.

Release flavor: "Chewie, we're home." - Han Solo, *Star Wars: The Force Awakens*
(2015), written by Lawrence Kasdan, J. J. Abrams and Michael Arndt
([official scene reference](https://www.starwars.com/news/from-a-certain-point-of-view-what-is-the-best-scene-in-star-wars-the-force-awakens),
[film credits](https://www.starwars.com/films/star-wars-episode-vii-the-force-awakens)).

## Detached Steam maintenance — 1.4.3.1

Fixes `reparo -Include Steam -Headless` losing its selected sections in the
scheduled worker. A completed worker log must now include the Steam inventory
and its explicit outcome; task registration alone does not prove maintenance ran.
One-shot workers preserve named parameters, arrays, switches and quoted values,
and remove their scheduled task after completion or failure.

Steam discovery includes the primary library and every configured library in
`libraryfolders.vdf`, including games on both C: and D: when configured there.
No per-drive Reparo configuration is needed. In 1.4.3.1, Steam retained control of automatic
updates and downloads; an already-running client is left alone, and update
completion is not inferred from client startup or local update-required flags.

Steam desktop integration and the one-shot Task Scheduler mode remain Windows-only.
The native Linux runner shares the 1.4.3.1 release identity and version flavor;
its maintenance and scheduling behavior is unchanged. Regression coverage includes
`Tests/Test-ReparoOneShotWorkerBinding.ps1`, which runs generated workers against
a harmless parameter probe with all Task Scheduler operations stubbed.

Release flavor: "Your focus determines your reality." — Qui-Gon Jinn,
*Star Wars: Episode I - The Phantom Menace* (1999), written and directed by George
Lucas ([official quote reference](https://www.starwars.com/news/15-star-wars-quotes-to-use-in-everyday-life)).

## Windows Update details and graceful skip requests — 1.4.3.0

In a real interactive Windows console, **Esc requests a skip**, not a process kill.
Supported boundaries are before a worker's first command, between pip/npm/.NET package
updates, and between Windows Update scan/download/install operations and individual
updates. The active indivisible operation must finish before Reparo acknowledges
`REPARO-STEP-SKIPPED`, records remaining work as skipped and moves on. Already
completed work and Windows Update receipts are retained. Requests use a unique
per-worker signal file, removed after exit; repeated presses do not queue later
skips. Redirected/headless/RMM runs never poll the keyboard or prompt.

There is **no universal safe cancel API** for package installers. During an
unsupported backend, Esc reports that cancellation is unavailable and waits for
completion; it does not detach, kill a wrapper, manufacture success or claim an
installer stopped. A hung indivisible operation may still require separate
diagnosis. After an interactive skip request, an expired deadline also waits
safely rather than escalating that request into a process kill.

Windows Update now emits explicit scan/applicable-count, download and installation
phases, update titles/KBs/sizes/backend results and available HRESULT values.
Backend-reported size is metadata, not measured network bytes or a download estimate.
It pins each phase to a discovered UpdateID and lets PSWindowsUpdate revalidate
that identity (phase calls can rescan and add latency). Only a terminal `Installed`
result without any failure is counted as Updated; empty scans are explicit and
missing/failed/aborted results are not called success. Per-update receipts join the
final software summary, including partial success before a skip. Percentage is
explicitly unavailable when PSWindowsUpdate does not expose one; the existing
heartbeat reports liveness, not invented progress. Default `-IgnoreReboot` and
explicit `-AllowReboot` policy are preserved.

`-WindowsUpdateTimeoutSeconds` is now a **cooperative safe-boundary deadline**, not
a hard servicing kill: after the deadline Reparo requests the next boundary and
waits for the active operation to finish, which can exceed the configured time.
It never abandons an installer or starts the next section while servicing remains
inside its worker. `-IgnoreTimeouts` disables deadline requests.

Native Linux intentionally does not implement Windows Update or Esc cancellation:
its POSIX package-manager path has no portable cooperative-cancel adapter. This
boundary is documented in native help and regression-tested; no unsafe keyboard
or wrapper-kill imitation was added. Shared version/quote/source/art stay aligned.

Regression fixtures: `Test-ReparoGracefulSkip.ps1` and
`Test-ReparoWindowsUpdateDetails.ps1` (no real installation or power action).

## OpenCode V2 updater compatibility — 1.4.2.1

The dedicated `Opencode` section recognizes npm-owned OpenCode V2
(`@opencode/cli`) and V1 (`opencode-ai`) and updates the package in the prefix
that owns the active command, not npm's possibly different configured prefix.
An npm-owned V1 installation is migrated to V2: Reparo records the installed
V1 version, removes `opencode-ai` before installing `@opencode/cli`, and attempts
to reinstall the exact original V1 version if migration fails. Rollback needs
working npm registry/cache access; rollback failure is reported, never hidden.
Mixed installs where V1 owns the command but V2 is already installed are skipped
for manual resolution rather than risking the other package. Windows' existing install-if-missing behavior
now installs `@opencode/cli`; native Linux remains update-installed-only.

Both runners skip OpenCode while a client or background service is running.
Close clients and, for V2, run `opencode service stop` before rerunning Reparo
outside OpenCode. Reparo never stops that service or terminates sessions to
perform an upgrade. Native Linux requires `pgrep` (procps) to establish that
OpenCode is stopped. Unrecognized/standalone installations are skipped; update
them through their owning installer. No interactive `opencode upgrade` or
legacy `oc -s` synchronization is invoked.

The general `Npm` section excludes both OpenCode packages, so it cannot bypass
these safeguards. Select `Opencode` as well if you want those packages updated.
Windows npm version locks apply to the dedicated updater too. Native Linux's
general npm section enumerates installed packages explicitly and refuses a
broad update when that inventory fails.

Regression coverage: `Tests/Test-ReparoOpencodeUpdate.ps1` and
`Tests/test-reparo-linux-opencode.sh`. An opt-in real npm migration pilot is
available as `REPARO_OPENCODE_LIVE_PROBE=1 sh Tests/test-reparo-linux-opencode-live.sh`;
it uses a disposable prefix and never starts a service. See the official
[V2 installation](https://opencode.ai/v2/docs/) and
[migration guide](https://opencode.ai/v2/docs/migrate-v1).

### OpenCode npm script permissions

The dedicated OpenCode updater grants install-time script permission only to
`@opencode/cli` (or `opencode-ai` during a V1 rollback), with scripts enabled for
that command. It does not change the user's npm configuration or allow all
dependency scripts. npm warnings stay in the log; nonzero npm exits and a failed
`opencode --version` still fail the section. Windows PowerShell stderr handling
is isolated to native calls; native Linux uses the same scoped permissions and
verifies the executable after installation.

Release 1.4.4.4 version flavor: Obi-Wan Kenobi's training-remote lesson from
*Star Wars* (1977), written and directed by George Lucas;
[quote reference](https://www.starwars.com/news/15-star-wars-quotes-to-use-in-everyday-life).


## Optional authenticated reporting — 1.4.2.0

**Off by default.** Ordinary public installs require no Node/client bundle and send
no added identity, inventory or reports. This is separate from local logs/syslog
and from a download-request gateway. Reporting requires one-time authorized
operator setup of a protected, reviewed client bundle and device-scoped credential.
Configured clients report during existing runs; no consent popups, service,
heartbeat, remote command channel, credential redirects or raw-log upload.

The isolated collector is intended to feed **Graylog**, not an operator workstation.
No production collector/feed is activated by this release. Owner/placement, public
TLS/non-bypassable origin, private administration/export, capacity/retention and
independent recovery acceptance still precede any real-data pilot.

### Client setup and protected files

- Optional client implementation/artifact is maintained separately in private
  `16thdoc/Reparo-Analytics`; `scripts/build-client-bundle.js` produces a dependency-free
  Node24 client manifest with immutable SHA-256 for every included source file.
  Select an explicitly reviewed Node24 executable/publisher and artifact. Do not
  treat a tool's bundled Node, PATH discovery, mutable source or a dirty snapshot
  as an approved fleet runtime. Node is never installed by ordinary Reparo.
- Windows runner uses `<InstallRoot>\Reporting`, normally ProgramData/Reparo:
  machine ACL grants only SYSTEM/Administrators; root/config must be protected,
  owned by those principals, with no reparse path. Code hashes and binary hash are
  checked inside the disposable reporting child before execution. Standard-user
  access is intentionally unsupported for this machine credential, not silently
  changed into sharing it with all users.
- Native runner uses `$XDG_STATE_HOME/reparo/reporting` (default
  `~/.local/state/reparo/reporting`): own UID, 0700 directories, 0600 regular
  single-link files, no symlink paths. It needs Python3/timeout only when configured,
  plus the approved Node24 client. Ordinary native maintenance remains self-contained.
- `state.json` contains private per-install config/credential/queue, `disabled.json`
  is the retained opt-out fence, `client/` contains only pinned code/artifact manifest.
  `reporting-client.json` is written **last** after enrollment/persistence and contains
  exactly `schema=reparo-reporting-client-1`, boolean `enabled`, absolute `nodePath`,
  uppercase 64-hex `nodeSha256` and `manifestSha256`. It contains no fleet/collector
  admin secret. `scripts/enroll-client-cli.js` accepts protected stdin JSON with
  `root`, HTTPS `/ingest/v1` `endpoint`, one-use `token`, boolean `inventoryConsent`;
  it returns status/installation ID, never a credential. Never put tokens in shell
  arguments, source, Proton, logs or this documentation.
- Source/runtime state and real telemetry/keys/databases belong outside Git/Proton.
  Opt-out removes activation/credential/queue after retaining the disabled-ID fence;
  keep the latest fence across uninstall/restore and revoke/delete privately on the
  collector. Old/whole-root restore without current independent authority is unsafe.

### Outcomes, bounds and deliberate boundaries

Windows Install/New/Latest report after replacement, shim, publication and eligible
self-update scheduling/finalization; late failure wins over early replacement.
Native New/Install owns the installer transaction and suppresses its nested report;
standalone native installer reports only after downloaded runtime verification has
made reporting code available. Earlier failures in a first bootstrap have no verified
reporting runtime; they remain local diagnostics, not fabricated receipts. Native
New/Install + Preview now performs no download/replacement/scheduling and can report
an explicitly configured preview outcome.

Windows built-in Ninja and the updated reference persistent automation report one
outer lifecycle result. Environment suppression is understood by new runners and
safely ignored by old ones while upgrading. Update/verify the controller before
enrollment. Direct SYSTEM New/Install/Latest reporting is deliberately suppressed
because older RMM wrappers can nest those calls without a transaction owner: use
the built-in `-Ninja` or updated correlated reference automation. Its final-only
`-ReportLifecycle -ReportingOutcome ...` API cannot be mixed with maintenance,
scheduling/power/other controls. This does not resume deferred SYSTEM/user-session
WinGet orchestration, replace a Ninja portal script or prove an actual agent pilot.

Completed maintenance reports Windows summary counts. Native batched managers do
not provide equivalent verified per-package counts: report null/unknown counts,
known failure/preview or unknown completion outcome rather than invented totals.
No hardware inventory collection or IP/GeoIP enrichment is silently enabled.

The optional client uses <=48 receipts/1 MiB, seven-day expiry, ten-attempt cap,
persisted jitter/backoff and stable event IDs/occurrence timestamps on lost replies.
One aggregate HTTP budget is <=2 seconds; isolated client work has a ten-second
deadline. The runner bounds the **entire reporting process tree**, including private
file/hash checks and interruption cleanup, to 25 seconds (plus at most a two-second
Windows tree-stop or one-second native kill grace). Certificate validation stays
on; missing client, bad pins/permissions, revoked auth, full queue, TLS or reporting
failure never changes the installation/maintenance outcome. These are bounded
best-effort self-reports, not hardware attestation, exactly-once installation or
proof of Graylog indexing.

### Steam desktop game updates (Windows)

Use `reparo -Include Steam` for Steam-only maintenance. Version 1.4.4.0 can request
pending installed-game updates and observe their progress through the desktop client.
See [Steam desktop update queue and SSH-detached maintenance](#steam-desktop-update-queue-and-ssh-detached-maintenance---1440)
for selectors, desktop requirements, result semantics and safe unattended execution.

### What it does

By default, Reparo runs Windows Update through `PSWindowsUpdate`. Optional modes can also include `winget`, Microsoft Store updates through `winget`, Chocolatey, PowerShell 7 through Microsoft's machine-wide MSI, 7-Zip deployment through winget, developer toolchains such as Scoop, pip, npm, pnpm, Yarn, .NET tools, Rust, Conda, Ruby gems, Composer, and WSL, plus a Chocolatey-to-winget migration pass.

On Windows, the Pip section repairs Pip metadata missing its `RECORD` file by
reinstalling the exact damaged Pip version in the same user or machine scope, then
retries the normal upgrade. Other Pip failures remain fatal and are reported without
being disguised as metadata damage.

Reparo uses tools already present, then skips unavailable sections. For a missing WinGet it re-registers App Installer, repairs it through `Microsoft.WinGet.Client` when PowerShell 7 is present, and—only when elevated/SYSTEM—installs the official PowerShell 7 MSI directly as the next repair rung before retrying. NuGet bootstrap/import and every repair child host are forced noninteractive. A normal ProgramData install also performs Winget repair/discovery after installing Reparo. Use `-7Zip` only when you explicitly want Reparo to install the `7zip.7zip` winget package if it is missing, or update it when present.

Winget packages whose publisher changes installer technology are reported as pending a
manual uninstall/reinstall; Reparo will not blindly remove user software. If Winget
cannot replace a package because its files are running or access is denied, Reparo
continues the remaining queue and reports that package with a close/stop-and-retry next
step instead of failing the whole Winget section. Chocolatey
updates are queued from `choco outdated` rather than `choco upgrade all`, so stale
local package records whose source package has been removed do not fail the entire
maintenance pass.

The final summary uses stable one-line records rather than width-dependent PowerShell
tables. Accumulated next steps print once at the end of the run, after updated, skipped,
and failed counts; successful sections without package-level inventory do not generate
warning noise. Winget packages excluded by a Reparo version lock are listed explicitly,
and any discovered package that returns neither an update nor skip receipt is reported
as a failure instead of silently disappearing.

Install the currently staged `Reparo.ps1` into ProgramData without a network request:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -Install
```

`-Install` also creates a `reparo` command shim at:

```text
C:\ProgramData\Reparo\bin\reparo.cmd
```

On Windows, a normal ProgramData `-Install` also creates or updates the `Reparo-SelfUpdate-Tuesday-1000` SYSTEM task. It uses the `ScheduledTasks` module when available and falls back to native `schtasks.exe` on legacy Windows hosts. The task runs `reparo -New` every Tuesday at 10:00 AM, fetching only the reviewed release pinned in the release manifest. On native Linux, the installer creates the equivalent current-user cron entry when `crontab` is available. Custom install roots and preview installs do not create this schedule.

Reparo tries to add that folder to machine `PATH`, falling back to user `PATH` if machine `PATH` cannot be changed. New PowerShell sessions can then run:

```powershell
reparo -Update
reparo -7
reparo -7Zip
reparo -Install
reparo -Help
reparo -Version
reparo -Kill
reparo -Tail
reparo -Force -Time 11:45pm
reparo -Update -Time 5h
reparo -Update -Syslog 192.168.50.31:514
reparo -CheckApp Microsoft.VisualStudioCode -PackageManager Winget
reparo -Preview -LockApp Microsoft.VisualStudioCode -LockVersion 1.125.0 -PackageManager Winget
reparo -Search
reparo -List
reparo -Search git
```

Lifecycle commands are deliberately distinct: `reparo -Install` installs the currently
executing file offline; `reparo -New` downloads the reviewed immutable release pinned in
`deploy/reparo-release.json`; `reparo -N` / `reparo -Latest` downloads the current `main`
copy intentionally without a release pin.

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

Install or update 7-Zip explicitly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -7Zip
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

## Deployment integrity

Reparo's canonical deployment is the single `Reparo.ps1` source file followed by
`-Install`; retired Ninja and ScreenConnect wrappers are intentionally absent. Follow
`RELEASE.md` when publishing a pinned release for `-New`.

### Ninja deployment options

Use one of these patterns depending on how you want to manage updates.

| Pattern | Best for | Tradeoff |
| --- | --- | --- |
| Paste `Reparo.ps1` into Ninja | Maximum simplicity and no external dependency | Updating Reparo means editing the Ninja script body |
| Upload `Reparo.ps1` as a Ninja script/file | Controlled copy inside Ninja | Exact execution path depends on how the Ninja script/file is staged |
| `Reparo.ps1 -Ninja` from GitHub | Pinned transactional refresh plus Ninja field publication | Requires endpoint access to GitHub raw content |

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

### Option 3: Refresh from GitHub with `-Ninja`

Use this when the endpoint can reach GitHub. `-Ninja` stages a temporary bootstrap away from the installed target, enables TLS 1.2 before resolving the reviewed release on legacy Windows PowerShell/.NET hosts, downloads the immutable release pinned by `deploy/reparo-release.json` to `C:\ProgramData\Reparo\Reparo.ps1`, validates it, and publishes the installed version plus saved WinGet health to Ninja's `Reparo` device text field. Staging prevents the updater child process from executing the same file it must replace. Runtime replacement clears a stale read-only bit and retries transient file access before rollback; if deployment and rollback both fail, Reparo preserves both errors. SYSTEM deployments deliberately skip post-install WinGet/App Installer discovery so they do not overwrite an interactive-user `WG:OK` with the known SYSTEM context limitation. It publishes `Update Failed | Installed:<version>` if the refresh transaction fails and rollback leaves a readable runtime in place.

When Ninja launches Reparo, Ninja captures the concise Reparo activity receipt from standard output in that automation's Activity details. Maintenance receipts include Reparo version, mode, result, updated/skipped/failed counts, bounded package details, and the finalized local log path. `-Ninja` self-update receipts include the previous and installed versions, source, failure reason when applicable, and log path. Reparo still returns exit code `1` for a failed maintenance or self-update run so Ninja marks the automation failed instead of recording a false green success.

Reparo runs started by its own scheduled task do not inherit Ninja's script helpers and cannot create an arbitrary Ninja Activity without API credentials. Do not put Ninja API credentials in Reparo. For those autonomous maintenance runs, configure a Ninja Windows Event Log condition for `Application / Reparo`: event `1001` is complete, `1002` is failed, and `1003` is preview. Those events include the runtime version, mode, counts, failed-item summary, and final log path.

Ninja script body:

```powershell
$ErrorActionPreference = 'Stop'

$installRoot = "$env:ProgramData\Reparo"
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

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $bootstrapPath -Ninja -InstallRoot $installRoot
exit $LASTEXITCODE
```

Use `-N` / `-Latest` only when you intentionally want the current, unreviewed `main` copy rather than the reviewed release pin:

```powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -N
```

`-Ninja` replaces the former standalone Ninja version-check payload; no separate wrapper
is needed. Upload or paste a current `Reparo.ps1` into Ninja and invoke it with `-Ninja`.

### Persistent Ninja operator automation

`examples/Reparo-Ninja-Persistent-Automation.ps1` is a source-controlled reference for
one dropdown-driven Ninja automation against an already installed
`C:\ProgramData\Reparo\Reparo.ps1`. It provides named maintenance, lifecycle, WinGet
health, scheduling, kill, reboot, and safely parsed custom actions. It is not an
embedded Reparo deployment payload and does not replace the canonical single-script
install path.

For lifecycle actions, the wrapper enables TLS 1.2 inside the staged child PowerShell
process before invoking even an older installed Reparo runtime; this lets legacy
Windows PowerShell/.NET hosts reach GitHub and bootstrap into the fixed reviewed
release. The `New` action then performs a local offline-install finalization with the
fresh runtime so the weekly self-update task is created even when the old runtime
lacked compatible task-scheduling support. It then publishes persisted WinGet health from Ninja's parent automation
session. It prefers `Set-NinjaProperty` and falls
back to `Ninja-Property-Set`. Both require the Ninja agent CLI at
`C:\ProgramData\NinjaRMMAgent\ninjarmm-cli.exe` (or the path in `NINJARMMCLI`). A missing
CLI produces a warning without converting successful Reparo maintenance into a false
failure; repair or update the Ninja agent to restore custom-field publication.

The reference wrapper now emits an explicit automation outcome: deployment,
discovery-only, scheduled-only, utility-only, no-changes, no-changes-with-skips,
maintenance-reported-changes, or maintenance failure. A blocked WinGet-only check
or missing maintenance receipt returns **2**, not a claim of successful maintenance.
Failures name the operation (launch preparation, child execution or custom-field
publication) and error type/ID. This improves future diagnostics; it does not establish
the historical FABIAN-WS denied operation or prove PUCK-MAN provisioning.

### Standalone WinGet SYSTEM provisioning

Before attempting repair, Reparo can now discover an **existing** registered
Microsoft App Installer runtime when the WinGet alias is missing. It restricts
the candidate to the WindowsApps package root, validates Microsoft Authenticode
and `--version`, then prepends only the current process PATH so child workers inherit
it. No permanent PATH/AppX registration/provisioning change. Preview never runs that
probe. Endor's read-only SYSTEM pilot demonstrated missing alias, runnable signed
direct binary and successful process-local discovery. This is not proof of another
user's package maintenance or a diagnosis of PUCK-MAN.

Runtime health now requires a successful executable `--version` probe, not merely
an alias existing. If SYSTEM still lacks a runnable runtime after the validated
package lookup, Reparo bypasses unsupported AppX/module repair. It preserves prior
validated health (explicitly historical, not a current maintenance result), or marks
USER with separate provisioning/user-validation guidance. Interactive-user repair
retains its existing path. This avoids downloading repair modules for an operation
SYSTEM is not allowed to perform.

`deploy/Deploy-WinGet-System.ps1` is independently usable from 64-bit Windows
PowerShell as SYSTEM/elevated administrator on x64 Windows client build 17763+.
Use `-Preview` for a no-network/no-change plan. Actual provisioning selects the
stable Microsoft WinGet release, requires asset SHA-256 digests and allowed GitHub
URLs, checks bundle identity/publisher, supplies its release license/x64 dependencies,
and lets Windows/DISM enforce package trust. Existing target/newer provisioning is
not downgraded. Verification failure returns nonzero; failed staging and transcript
logs are retained. `-ReleaseMetadata` plus `-AssetDirectory` supports a previously
trusted offline release set; offline metadata itself must come from a reviewed
GitHub release, not arbitrary third-party JSON. Optional `-Proxy` accepts an
HTTP(S) endpoint without embedded credentials. Downloads have explicit timeouts.

Outside Preview, exit 0 proves **provisioning only**, not user registration, WinGet executable/source
health, or user/machine maintenance. Sign-out/sign-in may be needed for user
registration. The artifact never reboots and does not call `Add-AppxPackage` under
SYSTEM. Actual Ninja/SYSTEM endpoint provisioning, proxy/policy/partial-failure
pilots and PUCK-MAN/FABIAN-WS diagnosis remain open; local helper/guard tests are
not substitutes. Inspect provisioning and DISM logs before a rollout.

### Option 4: Install/update over SSH

For personal Windows machines that are reachable over OpenSSH, use the remote helper:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\deploy\Install-ReparoRemote.ps1 -ComputerName marajade
```

Pass multiple SSH aliases or hosts to install the same ProgramData runtime on several machines:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\deploy\Install-ReparoRemote.ps1 -ComputerName marajade,laptop
```

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

Reparo delegates hook generation to upstream `moshi-hook`; it does not ship an
OpenCode plugin. OpenCode V2 changes the plugin API, so treat Moshi's generated
plugin as a separate compatibility check before enabling it on V2. This release
does not certify that upstream integration or rewrite existing project plugins.

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
| `-Install` / `-New` | Installs or updates `C:\ProgramData\Reparo\Reparo.ps1` transactionally: it stages and validates the candidate, retains a rollback copy even with `-NoBackup`, verifies the installed runtime, and restores the prior runtime if post-install validation fails. Native Linux applies the equivalent POSIX syntax/runtime rollback validation. |
| `-Help` / `-H` / `-h` | Prints Reparo usage and exits without running updates. |
| `-Version` / `-V` / `-v` | Prints the Reparo version, script source path, and version-specific quote, then exits without running updates. |
| Linux `--version` | Native Linux reports the same release number, quote, and source as the Windows PowerShell runner. |
| `-Kill` | Stops running Reparo PowerShell processes, then sweeps known updater front-end processes such as `winget`, `choco`, `npm`, `pip`, and related package managers. |
| `-KillUpdaterNames <names>` | Adds extra process base names to the `-Kill` updater sweep, for example `-Kill -KillUpdaterNames msiexec`. |
| `-Preview` | Logs what would run without executing package manager commands. |
| `-Update` | Runs the managed-client pass: `Winget`, `Winget(msstore)`, `Choco`, `PowerShell7`, and `WindowsUpdate`. |
| `-FU` / `-FeatureUpdate` / `-11` / `-Win11` | Uses Microsoft's Windows 11 Installation Assistant to move Windows 10 or Windows 11 to the latest applicable Windows 11 feature release. Requires elevation. Automatic reboot is suppressed unless `-AllowReboot` is explicit. Use `-Preview -FU` first to inspect the signed-installer path and arguments without launching the upgrade goblin. |
| `-7` / `-PowerShell7` | Runs only the machine-wide PowerShell 7 MSI section. It is intended to be launched from Windows PowerShell 5.1 and does not update the host process. |
| `-Winget` | Runs a winget-focused pass that attempts repair/registration if needed, logs discovery output, and then runs the winget sections. In preview mode, discovery still runs so you can refresh the visible upgrade list. |
| `-WingetDiscover` | Repairs/refreshes winget if needed and runs only winget discovery commands. |
| `-WG` | Windows only. Repairs/checks App Installer and winget without package upgrades, records `OK`, `USER`, `OLD`, or `FAIL` in `C:\ProgramData\Reparo\winget-health.json`, and when run through Ninja publishes `<Reparo version> \| WG:<status>` to its `Reparo` custom field. `OK` is healthy; `USER` requires an interactive user session rather than Ninja/SYSTEM; `OLD` means Windows 8.1, Server 2012 R2, or an older build where current App Installer/WinGet is unsupported; `FAIL` needs investigation. |
| `-Search` / `-List` / `-L` | Inventories applications Reparo `-Force` can update and prints installed versions, available versions when known, update method, source, lock status, and a ready-to-copy `LockSpec`. Add terms after the switch to filter, for example `reparo -Search git` or `reparo -List git`. |
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
| `-Tail` | Follows the active Reparo log when used by itself. When combined with a run mode, it prints the tail of that run's log at the end. |
| `-TailLines <count>` | Controls how many existing log lines `-Tail` prints before following. Default: `400`. |
| `-Time <when>` / `-At <when>` | Windows only. Creates a one-shot Task Scheduler task that runs the requested Reparo invocation as `SYSTEM` with highest privileges, then deletes itself. Clock inputs (`11:45pm`, `11pm`, `23:00`, `23:00:30`) use the next local occurrence. Delay inputs accept compact/long forms (`30s`, `30m`, `5h`, `2d`, `90min`) and positive decimals such as `1.5h`. Requires elevation. It rejects `-Preview`, `-Status`, `-Tail`, `-Kill`, `-Sweep`, and `-DeleteStale`. |
| `-Task <recurrence>` | Named specific-run scheduling, with maintenance flags kept separate. Windows uses SYSTEM/highest Task Scheduler; native Linux uses current-user cron. Default maintenance is `-Update`. `-Preview` shows the exact command/identity/power behavior without registering. Existing owned names require explicit `-TaskReplace`; use `-TaskAction List/Show/Enable/Disable/Remove`. See scheduling semantics below. |
| `-Syslog <host[:port]>` | Persistently sets and uses a TCP syslog listener. Default port is `514`, so `-Syslog 192.168.50.31` and `-Syslog 192.168.50.31:514` target the same port. Use `-Syslog off` or `-Syslog disable` to clear the saved target. |
| `-Status` | Shows whether Reparo is currently running, points at the active log file, and prints the registry evidence behind any pending reboot flag. |
| `-IgnoreTimeouts` | Disables timeout enforcement even when timeout parameters are supplied. |
| `-AllowReboot` / `-AllowRestart` | Allows `WindowsUpdate` to pass `-AutoReboot`. The disabled feature-update transport never stages or reboots. |
| `-Reboot` / `-Restart` / `-R` | Restarts the computer 30 seconds after Reparo completes. |
| `-Shutdown` / `-S` | Shuts down the computer 30 seconds after Reparo completes. Cannot be combined with `-Reboot`; `-S` is **not** a silent-mode switch. |
| `-InstallNuGetProvider` | Bootstraps the NuGet provider before PSGallery installs when `true` (default). Set it to `false` only if you want to suppress that bootstrap attempt. |
| `-Include <sections>` | Runs only the named sections, such as `Winget Choco`. |
| `-Force` | Runs the full local-dev-tool pass and enables Windows Update, the guarded Windows feature-update lane, and WSL apt handling. It deliberately excludes PowerShell 7; run `-7` explicitly for that MSI update. Use carefully. |

### Version quote style

`reparo -Version` should keep the CyberShell-style quote structure whenever the runtime version changes. Runtime releases use `major.feature.minor.hotfix`: routine fixes increment `hotfix`; a planned capability release increments `minor` and resets `hotfix` to zero. Do not reuse the previous version's quote just because the format is stable; pick a fresh quote/source pair for the new version and add it to `Get-ReparoVersionFlavor`.

Expected shape:

```text
Reparo 1.2.7.0
Source: C:\ProgramData\Reparo\Reparo.ps1
  "The future is not set. There is no fate but what we make."
  - Terminator 2: Judgment Day
```

The quote body and source can change every release. The indentation, surrounding quote marks, and `  - Source` attribution line should not.

## App version checks and locks

### ScanSnap protection

Reparo skips package-manager updates whose package ID or display name matches
`ScanSnap`, regardless of installed version. This protects mixed ScanSnap Home fleets
from Reparo-managed Winget or Chocolatey updates; it does not suppress ScanSnap's own
vendor updater or updates initiated by another management tool. This is intentionally
Windows-only because ScanSnap is not part of the native Linux runner's package scope.

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
- `Wsl`
- `WslApt`
- `WindowsUpdate`
- `WindowsFeatureUpdate`

### Flexible specific-run scheduling (1.4.1.0)

```powershell
reparo -Task -Force -Preview 5am Mondays
reparo -Task "5am First Monday" -TaskName monthly -Preview
reparo -Task "15th at 5am" -Include Winget,WindowsUpdate -TaskName midmonth -Preview
reparo -Task "weekdays at 5am,5pm" -Preview
reparo -Task "last day of month at 23:00" -Preview
reparo -Task "every 6 hours" -TaskStart 2026-11-04T06:00:00 -Preview
reparo -Task "every 2 days at 5am" -TaskStart 2026-11-04T00:00:00 -Preview
reparo -Task -TaskAction List
reparo -Task -TaskName monthly -TaskAction Show
reparo -Task -TaskName monthly -TaskAction Disable
reparo -Task -TaskName monthly -TaskAction Enable
reparo -Task -TaskName monthly -TaskAction Remove
```

`-R` / `-r` **still means reboot**. In the originally requested `-Task -f -r 5am Mondays` spelling, `5am Mondays` is the recurrence and `-r` is an actual scheduled power action. It is not an alternate recurrence parameter. Preview prominently reports REBOOT, SHUTDOWN or automatic-reboot permission. Do not register those flags unless you intend the power action. No reboot-capable schedule was created or executed during the implementation pilots.

Supported Windows calendars: case-insensitive day names/plurals; optional `at`; 12/24-hour clocks; daily; selected weekly days; weekdays/weekends; multiple clock times; monthly selected dates; first/second/third/fourth/last named weekday; last day of month. Every-N hours/days requires `-TaskStart YYYY-MM-DDTHH:mm:ss` to establish an explicit local anchor. Legacy `Daily 6am` and `Hourly 12hr` spellings remain accepted; legacy Hourly anchors at today's local midnight. Task names use 1–64 alphanumeric/underscore/hyphen characters, beginning alphanumeric.

Windows policy: local machine timezone, SYSTEM/highest account (creation/changes require elevation), Task Scheduler's native DST/calendar semantics, no invented exactly-once guarantee around clock changes. Explicit anchors in ambiguous/nonexistent DST hours are rejected. Nonexistent monthly dates are skipped rather than shifted. Missed runs use `StartWhenAvailable`; overlap uses `IgnoreNew`; execution is bounded to four hours with no automatic restart-on-failure. Maintenance arrays/boolean values are preserved through a quoted hashtable splat, not repeated flags or evaluated user code. Lifecycle/administrative/migration operations cannot be scheduled. Changing the machine timezone changes local-time interpretation; inspect schedules after timezone/OS policy changes. Preview needs no elevation and never registers. Registration defaults to the current script path: schedule from the installed runtime, not a temporary staging file.

Management is limited to root-folder `Reparo-Managed-<name>` tasks bearing the scheduler's exact ownership description. It refuses collisions/unowned names, leaves the separate `Reparo-SelfUpdate-Tuesday-1000` task alone, and does **not** silently migrate/delete old `Reparo-Managed-Daily` or `Reparo-Managed-EveryNHours` jobs. Review and retire obsolete old schedules deliberately to avoid duplicate runs.

Overlap guards apply to the **same named task**, not a global fleet/host lock. Different names, legacy schedules, manual commands and RMM runs can still overlap; coordinate those maintenance windows instead of assuming `IgnoreNew` or a per-name flock serializes unrelated jobs.

As of 1.4.1.1, native management fails closed on crontab access/tool errors; only
the explicit C-locale “no crontab for” result means empty. Reparo task-manager
mutations share a nonblocking lock and recheck the original snapshot before writing.
This serializes Reparo writers and detects observed external changes; the external
crontab CLI does not provide atomic compare-and-swap against arbitrary other writers.

The 1.4.1.2 native installer uses the same fail-closed read and manager-lock policy
for its separate self-update entry. It preflights before replacing runtime/shim,
quotes paths (including spaces/quotes), rejects cron percent/newline hazards,
verifies runtime release identity and the resulting crontab, and returns nonzero
for incomplete scheduling instead of printing a successful full installation.
Reruns replace only the exact self-update marker; unrelated jobs remain intact.

CLI legacy spellings are retained, but the PowerShell parameter API deliberately
changes `Task` from a string array to a selector switch so flags can precede recurrence
words. Script callers that used `@{Task=@('Daily','6am')}` must instead use
`@{Task=$true; RemainingInclude=@('Daily','6am')}`. Task controls without `-Task`, and
administrative/lifecycle flags combined with it, fail before initialization; they do
not fall through into maintenance or persist settings.

Native Linux uses the same useful named preview/management and maintenance-selection contract:

```sh
reparo --task 'weekdays at 5am,5pm' --task-name work --force --include Apt Npm --preview
reparo --task '1st,15th at 05:00' --task-name monthly --preview
reparo --task --task-name work --task-action show
```

Place the recurrence before the native Include list. Linux supports daily, weekly selected days, weekdays/weekends, monthly dates and multiple times. Cron cannot faithfully express anchored every-N days/hours, ordinal weekdays or last-day-of-month, so those forms fail explicitly instead of approximating them. Legacy Hourly Nhr remains a midnight-reset cron pattern, not an elapsed interval across days. Native jobs run as the registering user; privilege is still root/passwordless sudo where required. `flock -n` prevents overlapping runs; missed cron runs are not replayed and the cron implementation governs local-time/DST behavior. Named marker matching preserves unrelated jobs and legacy v1 entries. Percent/newline paths/arguments are rejected because cron interprets those before shell quoting. Native scheduling does not provide power actions or a Windows-style four-hour execution limit.

### Terminal output

Interactive package names are red; headings/progress/success/warnings/errors keep explicit text with a restrained palette. `NO_COLOR` (set) or `TERM=dumb` disables Reparo color; redirected Windows/native Linux output is plain. Log files and Ninja activity remain plain, not ANSI copies of screen output. Native package managers expose section-level names rather than Windows' individual discovered package rows.

### Windows feature updates

Legacy Windows Update Agent searches do not expose every opt-in seeker offer shown by the Settings app, including some annual Windows 11 releases with a separate **Download & install** button. As of **1.4.0.0**, `WindowsFeatureUpdate` is excluded from ordinary `-Force` and `-Update`. Explicit `-FU` and `-Include WindowsFeatureUpdate` remain accepted but emit an actionable **SKIPPED** receipt: the standalone Assistant transport is unverified for existing Windows 11 seeker offers and separately unverified for Windows 10-to-11 upgrades. No payload is downloaded, no process is launched, and no feature staging or reboot is attempted, including with `-AllowReboot` or `-Preview`. Use **Settings > Windows Update**, review compatibility and the offered **Download & install** action, and choose restart timing manually. A process exiting successfully is not proof of staging; Reparo does not claim it installed a feature release.

Windows-only boundary: native Linux has no Windows feature-update/WinGet lane; its package-manager maintenance selection is unchanged. Windows worker receipts retain actionable access-denied/sharing-violation causes and unsigned hexadecimal exit codes rather than only signed numbers. An access-denied message alone does not prove a service/file lock. Reparo does not automatically stop services or kill apps. Moonlight's applicability fallback is a deliberate non-elevated upgrade followed by install only when that upgrade reports **not applicable**; worker logs now identify action/source explicitly, and other worker failures do not trigger an install retry.

The old `-11`, `-Win11`, `-Windows11`, `-UpgradeToWindows11`, and `-Windows11Upgrade` spellings remain aliases for the same safe skip. An explicit Include can select the lane even alongside `-Force`; ordinary Force never selects it implicitly.

```powershell
reparo -Preview -FU
reparo -FU
reparo -FU -AllowReboot
```

These commands return promptly with the unsupported/unverified receipt, regardless of elevation. They do not perform a compatibility scan or stage an upgrade. Separate explicit end-of-run `-Reboot` / `-Shutdown` commands retain their documented behavior; do not add those flags to a diagnostic request unless you intend that power action.

### PowerShell 7

The `PowerShell7` section installs or updates Microsoft's machine-wide
MSI at `C:\Program Files\PowerShell\7\pwsh.exe`. The stable path is suitable for
OpenSSH Server, scheduled tasks, and other machine-level automation. Reparo
queries the latest stable GitHub release and skips installation only when the
executable version and Windows Installer registration confirm that the machine-wide
MSI is already current. HTTPS release provenance, version checks, MSI registration,
and embedded-payload SHA-256 verification remain in place.

The section is included in `-Update` but deliberately excluded from `-Force`, so
an unattended full pass cannot update the PowerShell host beneath itself. Run it
explicitly from an elevated Windows PowerShell 5.1 session:

```powershell
reparo -Preview -7
reparo -7
```

If you need to freeze PowerShell 7 for a machine, use the existing winget lock format:

```powershell
reparo -Force -VersionLock winget:Microsoft.PowerShell=7.5.2
```

When that lock is active, Reparo skips the dedicated `PowerShell7` section.
The general winget pass also excludes `Microsoft.PowerShell` whenever this
dedicated section is selected, preventing an MSIX/MSI installer-technology
knife fight.

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

For a Ninja/GitHub bootstrap deployment, use the staged Reparo script directly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -Preview -MigrateChocoToWinget
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
Long-running child commands emit `[CMD-WAIT]` heartbeat lines in the log while they are still alive. Windows Update also prints a console heartbeat every 60 seconds while it scans, downloads, or stages updates, because Windows Update otherwise has the bedside manner of a grave. Child command output is copied into the main log during execution with `[CMD-OUT]` prefixes, so `-Tail` can show winget and Windows Update progress while they are still running.

Use `-Tail` or its alias `-Log` to follow the active log when used by itself. When combined with a run mode, it prints the tail of the current run's log file at the end of execution.
Use `-TailLines` to increase or reduce the initial tail window.
Use `-Status` to see whether Reparo is currently running and which log file it is writing. The status probe excludes its own helper process so it does not report itself as the active run, and it will show stale `_RUNNING.log` files when a run ended before finalization.
Use `-Debug` when you want extra trace lines in the log for mode selection, command launch details, and bootstrap behavior. In Ninja, the wrapper now forwards `-Debug` through to Reparo.
Use `-WingetDiscover` when you want to refresh the winget discovery list without running live upgrades.
Use `-Kill` when a run is stuck; it stops matched Reparo process trees and then sweeps known updater front ends so orphaned `winget.exe` or similar package-manager processes are not left running. Reparo does not kill generic shells or installer engines by default; add extra process base names with `-KillUpdaterNames` when you intentionally want that broader cleanup.
Use `-IgnoreTimeouts` when you explicitly want to suppress timeout enforcement even if timeout values are supplied.
Use `-AllowReboot` only when Windows Update may auto-reboot before the rest of the Reparo run finishes. Use `-Reboot` to restart, or `-Shutdown` / `-S` to power off, 30 seconds after Reparo completes. Both post-run power actions honor `-Preview`; `-Reboot` and `-Shutdown` cannot be combined.
Winget upgrades default to `-WingetTimeoutSeconds 1800`; set it to `0` or use `-IgnoreTimeouts` only when indefinite execution is intentional. Discovery and Windows Update deadlines remain opt-in; Windows Update waits for a safe boundary rather than killing servicing, and an interactive Esc request never escalates to a timeout kill. `WslApt` defaults to `-WslAptTimeoutSeconds 1800` because unattended sudo/apt sessions can otherwise wait forever.
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
- `choco` and `winget` available in the same execution context for `-MigrateChocoToWinget`
- `PSWindowsUpdate` is auto-installed from PSGallery when possible for the `WindowsUpdate` section

`winget` and Microsoft Store behavior can vary by Windows build, execution context, source agreement state, tenant policy, and device policy. Test from the same context your RMM will use, especially when running as `SYSTEM`.

## Troubleshooting

If a section reports that a tool is present but cannot run, the most common cause is an execution-context mismatch. This is especially common with `winget` and Microsoft Store/App Installer paths under RMM, ScreenConnect, or `SYSTEM`; Windows can resolve `winget.exe` but still refuse to execute it in that context.

Reparo probes known package managers before running them and skips sections that cannot launch cleanly. For `Winget`, Reparo also attempts repair before skipping: it tries App Installer re-registration, `Repair-WinGetPackageManager` when present, and the latest Microsoft `winget-cli` App Installer MSIX bundle. If `Winget` is still skipped under a remote tool but works in an interactive admin shell, run Reparo from the same user/admin context where App Installer is available, or use a package manager that is installed machine-wide, such as Chocolatey.

For the live `Winget` upgrade path, Reparo now uses `--disable-interactivity`, `--silent`, and `--force` so Ninja runs are treated like non-interactive automation instead of desktop sessions waiting for UI.

For `WindowsUpdate`, Reparo will try to install `PSWindowsUpdate` from PSGallery first. If that bootstrap fails because the session cannot reach PSGallery or cannot install modules, the section is skipped with a logged reason instead of failing silently.

`WindowsFeatureUpdate` is intentionally separate from `WindowsUpdate`: Settings-only seeker offers can be absent from the legacy WUA/PSWindowsUpdate result set, but unattended feature staging is currently unsupported. Explicit selection skips safely with manual Settings guidance rather than using the unverified Assistant.

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
