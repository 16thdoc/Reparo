# Set up Reparo in NinjaOne

Use one of the fixed self-contained PowerShell scripts below. They are generated from
the reviewed repository `Reparo.ps1`, import into regular Ninja PowerShell automations,
and intentionally expose **no Ninja script options or arguments**. Ninja can map
imported options positionally and corrupt paths; fixed tools avoid that entire cursed
mechanism.

| File | Action |
| --- | --- |
| `Ninja-Embedded.ps1` | Install or refresh Reparo, then update the `Reparo` custom field. |
| `Ninja-Embedded-Offline.ps1` | Install embedded Reparo without any GitHub request, then update the field. |
| `Ninja-Reparo-ReportOnly.ps1` | Update only the `Reparo` custom field from the installed runtime. |
| `Ninja-Reparo-Update.ps1` | Install/refresh Reparo, update the field, then run `-Update`. |
| `Ninja-Reparo-Diagnostic.ps1` | Read-only runtime/log/PATH/Ninja setter inspection; use when a job result and filesystem disagree. |

## Create the Ninja automation

1. In NinjaOne, create or import a **PowerShell** script.
2. Import the one fixed script matching the action you want.
3. Name it `Reparo - Embedded Update`.
4. Set it to run as **SYSTEM**.
5. Leave Ninja's arguments/options blank.

If a prior imported-option run showed `Install root: ReportOnly` or a log path under
`true\`, remove its Ninja options and re-import the current fixed artifact. Its first
run removes the exact malformed `ReportOnly\bin` machine/user PATH entry before it
installs Reparo correctly. It intentionally does not delete unknown relative folders.

The embedded script unpacks its reviewed Reparo copy into a temporary folder,
verifies its SHA-256, installs it in `%ProgramData%\Reparo`, tries a GitHub refresh,
and finally runs Reparo. GitHub failure is a warning: the embedded copy still runs.
Likewise, a normal install remains successful if Ninja rejects the version-field write;
the output records a warning and `Ninja-Reparo-ReportOnly.ps1` remains available to
diagnose/retry that field update directly.

If the embedded child installer fails before `%ProgramData%\Reparo` exists, its stdout
and stderr are retained under `%ProgramData%\Reparo-Ninja-Diagnostics`. The parent
automation prints those streams and the directory path in its failure output.

`Ninja-Embedded.ps1` is the normal install-only deployment. It installs/refreshes the
runtime and updates the field, but does not run maintenance. Use the offline artifact
when GitHub should not be contacted. For an update pilot, clone the fixed Update
artifact and replace its generated `-Update` setting with `-Preview -Update` locally,
then import that separate fixed artifact; never add Ninja options to the script.

## What to expect in job output

Successful jobs show:

- `=== Ninja Reparo Embedded Deployer ===`
- the embedded payload SHA-256;
- `Installing the embedded Reparo payload.`;
- either `GitHub refresh completed.` or a non-fatal refresh warning;
- Reparo's own output and exit code.

If the output reports a hash mismatch, stop: the imported script was corrupted or
modified. Re-import the reviewed `Ninja-Embedded.ps1`.

## Promote a new Reparo version

1. Update and test `Reparo.ps1` in this repository.
2. Run:

   ```powershell
   .\deploy\New-NinjaEmbeddedDeployment.ps1
   .\deploy\New-NinjaEmbeddedDeployment.ps1 -OutputPath .\deploy\Ninja-Embedded-Offline.ps1 -FixedAction OfflineInstallOnly
   .\deploy\New-NinjaEmbeddedDeployment.ps1 -OutputPath .\deploy\Ninja-Reparo-ReportOnly.ps1 -FixedAction ReportOnly
   .\deploy\New-NinjaEmbeddedDeployment.ps1 -OutputPath .\deploy\Ninja-Reparo-Update.ps1 -FixedAction Update
   ```

3. Import the appropriate freshly generated artifact into Ninja, replacing its prior
   version.
4. Pilot on a representative endpoint before broad deployment.

Do not make `-Force` the default fleet job. It is deliberately broader than the
managed-client `-Update` pass and belongs in an explicit maintenance window.
