# Reparo RMM Operator Guide

This is the one operator guide for deploying, trusting, running, and troubleshooting
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

### NinjaOne: signed pilot

1. Import `Internal-Code-Signing\Install-ReparoInternalSigningTrust.ps1` as a
   PowerShell automation.
2. Run it as **SYSTEM**, with **no options and no arguments**, on one pilot endpoint.
3. Import `Ninja\Ninja-Embedded-Offline.ps1`.
4. Run it as **SYSTEM**, with **no options and no arguments**, on that same endpoint.
5. Import/run `Ninja\Ninja-Reparo-Diagnostic.ps1` as SYSTEM.
6. Confirm:

   ```text
   Runtime signature status: Valid
   Runtime signer thumbprint: 93CE2552E5C7F90600C36BDB83541921FCC97ED1
   ```

7. After the pilot succeeds, use `Ninja\Ninja-Embedded.ps1` for normal
   install/refresh-and-report deployment.

### ScreenConnect: normal toolbox use

Upload the wanted file from `ScreenConnect\` into Toolbox and run it as SYSTEM/admin.

| Need | Toolbox file |
| --- | --- |
| First install without GitHub | `ScreenConnect-Reparo-Embedded.ps1` with `-Offline true` |
| First install / refresh with GitHub | `Install-Reparo.bat` |
| Standard managed update | `Run-Reparo-System.cmd` |
| Broad maintenance | `Run-Reparo-Force-System.cmd` |
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
| `Ninja-Embedded-Offline.ps1` | Installs the embedded signed runtime without contacting GitHub, then writes the version field. |
| `Ninja-Reparo-ReportOnly.ps1` | Reads the installed runtime and updates only the Ninja `Reparo` field. |
| `Ninja-Reparo-Update.ps1` | Installs/refreshes, updates the version field, then runs `Reparo -Update`. |
| `Ninja-Reparo-Diagnostic.ps1` | Read-only inspection of runtime, logs, PATH, execution context, Ninja field support, and runtime signature. |

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

### 2. Internal code signing and trust

Reparo uses a free, private fleet-only PKI. It is not publicly trusted on random
computers, by design. Managed endpoints trust it after the trust deployment script
runs.

| Identity | Thumbprint |
| --- | --- |
| Internal root CA | `1C44A46033EF4BB52695208ACF4455823A64BE57` |
| Approved Reparo signer | `93CE2552E5C7F90600C36BDB83541921FCC97ED1` |

The trust script installs only public certificates:

- root CA → `LocalMachine\Root`
- signing certificate → `LocalMachine\TrustedPublisher`

The signing private key is non-exportable and remains on the signing workstation. It
must never be copied, exported, committed, or uploaded to Ninja/ScreenConnect.

#### Pilot trust procedure

1. Deploy the trust script through Ninja as SYSTEM with no options/arguments.
2. Deploy the signed **offline** artifact. Offline avoids any ambiguity while proving
   the embedded signed payload, endpoint trust, and SYSTEM context work together.
3. Run the Ninja diagnostic.
4. Do not broadly deploy until the diagnostic reports `Valid` and the approved signer
   thumbprint.

The signed GitHub release is current, but Reparo's runtime update logic does not yet
hard-refuse an unsigned/wrong-signer remote candidate. Keep the signed offline pilot
as the trust proof until that enforcement gate is completed.

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

It installs only the signed Reparo payload embedded in the artifact. It makes no
GitHub request.

#### Run managed-client maintenance

Use:

```text
Ninja-Reparo-Update.ps1
```

This runs Reparo's deliberate `-Update` lane after installation/refresh. It is not
the fleet default; pilot it before broad use.

#### Refresh only the version custom field

Use:

```text
Ninja-Reparo-ReportOnly.ps1
```

It sets Ninja's device text custom field named `Reparo` to the installed runtime
version. It does not install, refresh, or run Reparo.

#### Diagnose odd behavior

Use:

```text
Ninja-Reparo-Diagnostic.ps1
```

It is read-only. If installation claims success but the ProgramData runtime is absent,
the diagnostic tells you the actual SYSTEM identity, working directory, runtime/log
presence, PATH state, Ninja custom-field command availability, and signature state.

For embedded-installer failures, inspect:

```text
C:\ProgramData\Reparo-Ninja-Diagnostics
```

That directory captures the embedded child installer stdout/stderr.

### 4. ScreenConnect deployment details

ScreenConnect toolbox files live in `ScreenConnect\`.

#### Trust first

Before treating ScreenConnect deployment as signed/trusted, run the same:

```text
Internal-Code-Signing\Install-ReparoInternalSigningTrust.ps1
```

from Toolbox under SYSTEM/admin.

#### Embedded installer

`ScreenConnect-Reparo-Embedded.ps1` is the self-contained installer. It contains a
signed Reparo payload and works without helper-file attachments.

Useful Toolbox arguments:

| Goal | Arguments |
| --- | --- |
| Install only, with GitHub refresh | none |
| Install only, no GitHub request | `-Offline true` |
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

### 5. Future Reparo version/release workflow

Every Reparo version bump or release-worthy change follows this workflow on the
signing workstation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\deploy\signing\New-SignedReparoRelease.ps1
```

The workflow:

1. Signs `Reparo.ps1`.
2. Generates all embedded Ninja and ScreenConnect artifacts from that signed source.
3. Signs the generated artifacts.
4. Verifies each artifact carries the approved signer.
5. Stops before commit/push/deploy.

Then:

```text
Review diff → commit signed release → push intentionally → pilot → deploy
```

Never edit a signed script after the workflow finishes. Make the change, rerun the
workflow, then commit. The signature is evidence of exact bytes, not a participation
trophy.

### 6. Current deployment safety rules

- Default RMM deployment is install-only.
- `Ninja-Reparo-Update.ps1` is the explicit maintenance tool.
- `-Force` is a maintenance-window/hands-on tool, not a fleet default.
- `-Force -Reboot` deliberately reboots after completion.
- Do not add Ninja parameters/options to fixed artifacts.
- Pilot trust and signed offline install before broad signed rollout.
- Keep `Desktop\Reparo\` as convenient staging only; GitHub/repository remains the
  canonical source.
