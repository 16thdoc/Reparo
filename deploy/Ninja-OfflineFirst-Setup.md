# Set up offline-first Reparo in NinjaOne

This deployment uses two files:

| File | Purpose |
| --- | --- |
| `Ninja-OfflineFirst.ps1` | Ninja execution wrapper: installs the bundled runtime, optionally refreshes it, then runs maintenance. |
| `Reparo.ps1` | Reviewed Reparo runtime payload. It is installed first, so GitHub access is optional. |

`Reparo.payload.sha256` is the SHA-256 value for the bundled runtime. It is not
executed; use its value as a deployment parameter to catch an accidental bad upload.

## 1. Create the Ninja script

1. In NinjaOne, create a **PowerShell** script named `Reparo - Offline First`.
2. Paste in the contents of `Ninja-OfflineFirst.ps1`, or upload that file if your
   Ninja workflow supports uploaded PowerShell scripts.
3. Add `Reparo.ps1` as the script's supporting/uploaded file.
4. Run it as **SYSTEM**. Windows Update, machine PATH registration, and most package
   maintenance are machine-level work; a user-context run is the wrong haunted house.
5. Save the script.

The wrapper looks for `Reparo.ps1` beside the staged Ninja script first. If your
Ninja tenant stages supporting files elsewhere, set `-BundledReparoPath` to its full
staged path. The job output reports the resolved payload path before changing anything.

## 2. Add the baseline deployment arguments

For the normal managed-client pass, use:

```text
-BundledSha256 49C076C29FB5EE551C6997EA3B8B38A432E42B1572CBA94E79E3EEC82310F493 -Update
```

For the pilot group, use preview first:

```text
-BundledSha256 49C076C29FB5EE551C6997EA3B8B38A432E42B1572CBA94E79E3EEC82310F493 -Preview -Update
```

If a device must not contact GitHub at all:

```text
-BundledSha256 49C076C29FB5EE551C6997EA3B8B38A432E42B1572CBA94E79E3EEC82310F493 -RefreshFromGitHub:$false -Update
```

No explicit Reparo mode defaults to `-Update`, but spelling it out in the policy is
less ambiguous when Future Us is tired and under-caffeinated.

## 3. Choose the remote refresh channel

The default remote URL tracks `main`:

```text
https://raw.githubusercontent.com/16thdoc/Reparo/main/Reparo.ps1
```

That is convenient but mutable. For a controlled rollout, set
`-RemoteReparoUrl` to a reviewed commit-pinned raw URL instead:

```text
-RemoteReparoUrl https://raw.githubusercontent.com/16thdoc/Reparo/5012a1dc68deb6e29e7ec67d86b479f518974ac8/Reparo.ps1
```

When GitHub is blocked, unavailable, or its certificate path is being a little
fascist, the wrapper logs a warning and runs the bundled payload. A remote failure
does not fail the maintenance deployment.

## 4. Pilot, then deploy

1. Run the preview arguments against a representative test device.
2. Confirm the output includes:
   - `Installing the bundled Reparo payload.`
   - the expected bundled SHA-256;
   - either `GitHub refresh completed.` or a non-fatal refresh warning;
   - Reparo's preview output and a zero exit code.
3. Run the live `-Update` policy on a small pilot group.
4. Review Ninja output and `%ProgramData%\Reparo\Logs`.
5. Deploy broadly only after the pilot behaves.

Do not use `-Force` as the default fleet policy. It is intentionally a broader
maintenance pass and deserves an explicit maintenance window and a human with coffee.

## 5. Promote a new bundled Reparo version

1. Review and test the new `Reparo.ps1` from the repository.
2. Replace Ninja's uploaded `Reparo.ps1` supporting file.
3. Calculate its new SHA-256:

   ```powershell
   (Get-FileHash .\Reparo.ps1 -Algorithm SHA256).Hash
   ```

4. Update the `-BundledSha256` argument in the Ninja policy.
5. If using a pinned remote channel, update `-RemoteReparoUrl` to the same reviewed
   commit (or the next intentionally promoted one).
6. Pilot it before broad deployment.

The payload hash verifies the uploaded file. It does not make a mutable `main` URL
immutable; use a commit-pinned URL when rollout control matters.
