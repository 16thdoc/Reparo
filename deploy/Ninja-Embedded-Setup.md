# Set up Reparo in NinjaOne

Use `Ninja-Embedded.ps1`. It is one self-contained PowerShell script, generated
from the reviewed repository `Reparo.ps1`. Import it into a regular Ninja PowerShell
automation; it needs no supporting files or Installer entry.

## Create the Ninja automation

1. In NinjaOne, create or import a **PowerShell** script.
2. Import `Ninja-Embedded.ps1`.
3. Name it `Reparo - Embedded Update`.
4. Set it to run as **SYSTEM**.
5. Use the pilot arguments below, test one device, then use the live arguments.

The embedded script unpacks its reviewed Reparo copy into a temporary folder,
verifies its SHA-256, installs it in `%ProgramData%\Reparo`, tries a GitHub refresh,
and finally runs Reparo. GitHub failure is a warning: the embedded copy still runs.

## Arguments

With no arguments, the script installs or refreshes Reparo and stops. It does not run
maintenance until you explicitly request a Reparo mode.

Pilot first:

```text
-Preview -Update
```

Normal managed-client maintenance:

```text
-Update
```

No GitHub connection at all:

```text
-Offline true -Update
```

`-Offline true` installs the embedded payload and skips the GitHub refresh even if
`RefreshFromGitHub` is also set to `true`.

Update only the Ninja device custom field named `Reparo`; do not install, refresh, or
run Reparo:

```text
-ReportOnly true
```

Install or refresh Reparo only; do not run maintenance:

```text
-InstallOnly true
```

For a completely offline install-only run:

```text
-InstallOnly true -Offline true
```

The default remote refresh URL follows `main`. For a controlled deployment, use a
reviewed commit-pinned URL instead:

```text
-RemoteReparoUrl https://raw.githubusercontent.com/16thdoc/Reparo/5012a1dc68deb6e29e7ec67d86b479f518974ac8/Reparo.ps1 -Update
```

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
   ```

3. Import the freshly generated `deploy\Ninja-Embedded.ps1` into Ninja, replacing
   the prior version.
4. Pilot `-Preview -Update` on a representative endpoint.
5. Promote the live `-Update` automation after reviewing the output.

Do not make `-Force` the default fleet job. It is deliberately broader than the
managed-client `-Update` pass and belongs in an explicit maintenance window.
