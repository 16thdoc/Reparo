# Reparo RMM Operator Guide

This is the one operator guide for deploying, running, and troubleshooting
Reparo through **NinjaOne** and **ScreenConnect**.

Repository source of truth:

```text
C:\Users\trent\GitHub\Reparo
```

Desktop upload/reference staging:

```text
Desktop\Reparo\
```

## Short version — do this first

### NinjaOne: pilot

1. Import `Ninja\Ninja-Embedded-Offline.ps1`.
2. Run it as **SYSTEM**, with **no options and no arguments**, on one pilot endpoint.
3. Import/run `Ninja\Ninja-Reparo-Diagnostic.ps1` as SYSTEM.
4. Confirm the runtime is present and inspect its version and SHA-256:

   ```text
   Runtime exists: True
   Runtime version: <expected release>
   Runtime SHA-256: <expected payload hash>
   ```

5. After the pilot succeeds, use `Ninja\Ninja-Embedded.ps1` for normal
   install/refresh-and-report deployment.

### ScreenConnect: normal toolbox use

Upload the wanted file from `ScreenConnect\` into Toolbox and run it as SYSTEM/admin.

| Need | Toolbox file |
| --- | --- |
| First install/update without GitHub | `ScreenConnect-Reparo-Embedded-Offline.ps1` |
| First install / refresh with GitHub | `Install-Reparo.bat` |
| Remove Reparo runtime and diagnostics | `ScreenConnect-Reparo-Uninstall.ps1` |
| Standard managed update | `Run-Reparo-System.cmd` |
| Broad maintenance | `Run-Reparo-Force-System.cmd` |
| Broad maintenance; Windows Update may reboot if required | `Run-Reparo-Force-AllowReboot-System.cmd` |
| Broad maintenance then reboot | `Run-Reparo-Force-Reboot-System.cmd` |
| Refresh installed runtime | `Run-Reparo-New-System.cmd` |
| Windows Update allowed to reboot | `Run-Reparo-AllowReboot-System.cmd` |

## Critical NinjaOne rule

**Do not add Ninja script options or arguments to the fixed Reparo artifacts.**

Ninja previously mapped imported fields positionally, turning `ReportOnly` into an
install path and `true` into a log path. The fixed scripts intentionally expose zero
parameters. Pick the separate script that performs the action you want.

| Ninja file | What it does |
| --- | --- |
| `Ninja-Embedded.ps1` | Installs/refreshes Reparo, then writes the installed version to the Ninja device field `Reparo`. No maintenance run. |
| `Ninja-Embedded-Offline.ps1` | Installs the embedded runtime without contacting GitHub, then writes the version field. |
| `Ninja-Reparo-GitHub.ps1` | Downloads reviewed Reparo 1.2.6.3 from its pinned GitHub commit, installs/refreshes it, then writes the version field. No maintenance run. |
| `Ninja-Reparo-Force.ps1` | Installs/refreshes, updates the version field, then runs `Reparo -Force`. No reboot permission is granted. |
| `Ninja-Reparo-Force-AllowReboot.ps1` | Installs/refreshes, updates the version field, then runs `Reparo -Force -AllowReboot`. Windows Update may reboot only if required. |
| `Ninja-Reparo-Kill.ps1` | Installs/refreshes, updates the version field, then runs `Reparo -Kill` to stop stuck Reparo and known updater processes. No reboot. |
| `Ninja-Reparo-Uninstall.ps1` | Stops Reparo processes, removes its runtime/PATH/logs/diagnostics, then clears the version field. No reboot. |
| `Ninja-Reparo-Diagnostic.ps1` | Read-only inspection of runtime, logs, PATH, execution context, Ninja field support, version, and hash. |
| `Ninja-ScanSnap-Report.ps1` | Read-only ScanSnap inventory. It writes installed ScanSnap product names and versions to the Ninja device text field `scansnapVersion`. |

All Ninja artifacts run as **SYSTEM**. They are suitable for normal RMM deployment;
do not paste extra command-line flags into their Ninja configuration.

## E10 — full operational guide

### 1. Reparo runtime basics

On Windows, an installed runtime lives at:

```text
C:\ProgramData\Reparo\Reparo.ps1
```

The command shim is:

```text
C:\ProgramData\Reparo\bin\reparo.cmd
```

Logs are normally under:

```text
C:\ProgramData\Reparo\Logs
```

In an elevated Command Prompt or PowerShell after installation:

```text
reparo -Version
reparo -Update
reparo -Status
reparo -Tail
```

An already-open terminal may retain an old PATH. In that case use the full shim path
or open a fresh terminal:

```text
C:\ProgramData\Reparo\bin\reparo.cmd -Version
```

### 2. Deployment integrity

Generated Ninja and ScreenConnect artifacts embed a gzip-compressed Reparo payload
and its SHA-256 hash. The artifact verifies the extracted payload before invoking the
transactional installer; a mismatch stops the deployment. The normal refresh path
uses the repository URL configured in the artifact. Review generated artifacts and
pilot an offline deployment before broad rollout.

### 3. NinjaOne deployment details

#### Install/refresh only

Use:

```text
Ninja-Embedded.ps1
```

It installs or refreshes Reparo, creates/repairs the command shim and PATH entry,
backs up the prior runtime, and updates the Ninja `Reparo` custom device field. It
does **not** run Windows Update, winget, or broad maintenance.

#### Offline install only

Use:

```text
Ninja-Embedded-Offline.ps1
```

It installs only the Reparo payload embedded in the artifact. It makes no
GitHub request.

#### GitHub-backed install/refresh only

Use:

```text
Ninja-Reparo-GitHub.ps1
```

It is a compact, parameter-free Ninja script: it downloads the reviewed Reparo 1.2.6.3
source from its pinned GitHub commit, invokes `-New` to install or refresh the
ProgramData runtime, and updates the `Reparo` device text field. It does not run
maintenance. Change its URL only when promoting a reviewed replacement release, then
import that reviewed script into Ninja.

#### Diagnose odd behavior

Use:

```text
Ninja-Reparo-Diagnostic.ps1
```

It is read-only. If installation claims success but the ProgramData runtime is absent,
the diagnostic tells you the actual SYSTEM identity, working directory, runtime/log
presence, PATH state, Ninja custom-field command availability, version, and hash.

For embedded-installer failures, inspect:

```text
C:\ProgramData\Reparo-Ninja-Diagnostics
```

That directory captures the embedded child installer stdout/stderr.

#### Inventory ScanSnap versions

Use:

```text
Ninja-ScanSnap-Report.ps1
```

Create a Ninja device **text** custom field named `scansnapVersion` first (its visible
label may remain `ScanSnap`). The script reads
both uninstall registry views, reports every installed product whose display name
contains `ScanSnap`, and updates that field. It does not update, pin, or otherwise
touch the scanner software.

### 4. ScreenConnect deployment details

ScreenConnect toolbox files live in `ScreenConnect\`.

#### Embedded installer

`ScreenConnect-Reparo-Embedded.ps1` and
`ScreenConnect-Reparo-Embedded-Offline.ps1` are self-contained installers. They
contain a Reparo payload and work without helper-file attachments.

Useful Toolbox arguments:

| Goal | Arguments |
| --- | --- |
| Install only, with GitHub refresh | none |
| Install/update only, no GitHub request | `ScreenConnect-Reparo-Embedded-Offline.ps1` |
| Install and run managed maintenance | `-Update` |
| Install and run maintenance offline | `-Offline true -Update` |
| Version inspection | Run `C:\ProgramData\Reparo\bin\reparo.cmd -Version` from the remote session. |

#### GitHub-backed batch installer

`Install-Reparo.bat` downloads the runtime from GitHub. Use it only when GitHub is
available and you intentionally want that delivery path.

Its `-Offline` mode does not download anything; it can only verify an existing
installation. For an offline first install, use the embedded PowerShell installer.

#### SYSTEM task launchers

The `.cmd` run tools create and start a one-shot SYSTEM scheduled task. The Toolbox
action confirms task start; inspect `%ProgramData%\Reparo\Logs` for Reparo's actual
outcome.

Important reboot distinction:

```text
-Reboot       Reparo schedules a restart after it finishes.
-AllowReboot  Windows Update may reboot only if Windows Update requires it.
```

### 5. Windows fleet release workflow

After changing `Reparo.ps1`, regenerate every embedded artifact with
`deploy\New-NinjaEmbeddedDeployment.ps1`, including the fixed-action Ninja scripts
and the ScreenConnect artifact. Review the source and generated diff, run the
relevant tests, commit the coherent release, push it, then pilot before broad
deployment.

### 6. Current deployment safety rules

- Default RMM deployment is install-only.
- `Ninja-Reparo-GitHub.ps1` installs or refreshes Reparo only; use the explicitly
  named `Ninja-Reparo-Force-AllowReboot.ps1` for broad maintenance.
- `-Force` is a maintenance-window/hands-on tool, not a fleet default.
- `-Force -Reboot` deliberately reboots after completion.
- Do not add Ninja parameters/options to fixed artifacts.
- Pilot the offline embedded installer before broad rollout.
- Keep `Desktop\Reparo\` as convenient staging only; GitHub/repository remains the
  canonical source.
