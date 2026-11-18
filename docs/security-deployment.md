# Security deployment guidance

## Recommended deployment methods

Use a managed RMM or configuration-management platform for a Windows fleet. Stage
the reviewed `Reparo.ps1` as an RMM artifact, validate its SHA-256 against the
candidate/production manifest, and run the staged file with `-Install`. This keeps
endpoint selection, administrator identity, scheduling, approval, and receipts in
the system already trusted to administer the fleet.

Use `deploy/install-reparo-linux.sh` from a configuration manager for Linux. It
installs per user, validates a commit-pinned runtime hash/version, and preserves
unrelated crontab entries. Do not run a user installation as root unless a separately
designed system-wide deployment is intended.

For a small number of SSH-reachable Windows systems, use
`deploy/Install-ReparoRemote.ps1`. It validates target syntax and generates a quoted,
encoded remote command. SSH host-key policy and credentials remain the operator's
responsibility. The CMD installer is appropriate for an interactive administrator
or an RMM that stages the CMD file, but it is not a substitute for change control.

Avoid `curl | sh`, `Invoke-Expression` on downloaded data, mutable `main` source
execution, and ad hoc remote loops that do not produce a per-host result.

## Release preflight

From a clean reviewed checkout, record the commit and run:

```powershell
git status --short
git rev-parse HEAD
.\Tests\Test-ReparoReleaseParity.ps1
.\Tests\Test-ReparoReleaseManifest.ps1 -ManifestPath .\deploy\reparo-candidate.json
.\Tests\Test-ReparoSecurity.ps1
.\Tests\Test-ReparoSupplyChain.ps1
```

On Linux also run:

```sh
sh -n linux/reparo-linux
sh -n deploy/install-reparo-linux.sh
sh Tests/test-reparo-linux-installer.sh
sh Tests/test-reparo-linux-output.sh
python3 Tests/test-reparo-reliability.py
python3 Tests/test-reparo-wsl-guard.py
```

The candidate manifest must point to a reviewed source commit, not the manifest
commit itself. Confirm required CI passed on the exact pull-request head and that
the repository settings in `docs/github-repository-policy.md` were independently
verified. Do not promote the production manifest merely because local tests pass.

## Verify tagged release evidence

For a tagged production release, find the successful `Release provenance` workflow
run and download its named artifact:

```sh
gh run list --repo 16thdoc/Reparo --workflow release-attestation.yml --limit 20
gh run download RUN_ID --repo 16thdoc/Reparo \
  --name reparo-VERSION-provenance --dir release-evidence
gh attestation verify release-evidence/reparo-VERSION.zip --repo 16thdoc/Reparo
gh attestation verify release-evidence/reparo-VERSION.spdx.json --repo 16thdoc/Reparo
sha256sum -c release-evidence/SHA256SUMS
```

On Windows, use `Get-FileHash` to compare both files to `SHA256SUMS` if `sha256sum`
is unavailable. Inspect the SPDX document and confirm its version and source commit
match the production manifest. Attestation verifies GitHub workflow provenance; it
does not replace source review, manifest hash verification, or the canary gate.
If attestation retrieval or verification is unavailable, ambiguous, or fails, stop.
Do not use a hash-only exception for a new release. A disconnected site may retain
an already approved release and its recorded manifest/hash, but new promotion waits
for online verification.

## Candidate canary

The canary target and maintenance window must be explicitly authorized. Candidate
testing does not authorize package upgrades, reboots, migrations, `-Force`, or any
other maintenance action.

For the Windows CMD installer, open an elevated command prompt in a reviewed checkout:

```bat
set "REPARO_RELEASE_URL=https://raw.githubusercontent.com/16thdoc/Reparo/main/deploy/reparo-candidate.json"
deploy\install-reparo-windows.cmd /verbose
```

For the SSH helper, preview the exact targets first and then repeat without `-Preview`:

```powershell
$candidate = 'https://raw.githubusercontent.com/16thdoc/Reparo/main/deploy/reparo-candidate.json'
.\deploy\Install-ReparoRemote.ps1 -ComputerName 'authorized-canary' `
  -ReleaseManifestUrl $candidate -Preview
.\deploy\Install-ReparoRemote.ps1 -ComputerName 'authorized-canary' `
  -ReleaseManifestUrl $candidate
```

For native Linux:

```sh
REPARO_RELEASE_URL=https://raw.githubusercontent.com/16thdoc/Reparo/main/deploy/reparo-candidate.json \
  sh deploy/install-reparo-linux.sh --verbose
```

For each canary, capture the hostname, execution identity, manifest URL and commit,
start/end time, exit code, installed version/hash, and operator. On Windows, verify:

```powershell
& 'C:\ProgramData\Reparo\bin\reparo.cmd' -Version
Get-FileHash 'C:\ProgramData\Reparo\Reparo.ps1' -Algorithm SHA256
Get-ScheduledTask -TaskName 'Reparo-SelfUpdate-Tuesday-1000'
icacls 'C:\ProgramData\Reparo'
icacls 'C:\ProgramData\Reparo\Logs'
icacls 'C:\ProgramData\Reparo\Backups'
```

The root must not be writable by built-in Users, Authenticated Users, or Everyone.
Logs and Backups must not grant those principals any allow rule. Verify a standard
user can run `reparo -Version` and that their log is written under LocalAppData, not
the protected machine log directory. Review the install log and event record before
advancing. On Linux, verify `reparo --version`, file ownership/mode, the self-update
cron marker, and preservation of unrelated cron entries.

## Rollout rings and stop conditions

1. Required CI and isolated installer fixtures.
2. Disposable Windows and Linux test systems.
3. An explicitly authorized canary representing supported OS versions, RMM identities,
   package managers, and interactive-user/SYSTEM contexts.
4. A limited production ring with receipt and log review.
5. Broad rollout after the observation window has no unresolved failures.

Stop immediately on a hash/version mismatch, unexpected manifest schema, ACL or link
validation failure, missing receipt, installation outside the intended root, loss of
an unrelated cron entry, or an unexplained endpoint failure. Preserve evidence and
do not compensate by using `-Latest`, `--latest`, disabling hash checks, or widening
permissions.

If a release is withdrawn, remove it from the production channel, publish the exact
version and hashes as revoked in the change record, identify the replacement or prior
rollback version, and notify operators. A previously valid GitHub attestation remains
historical evidence and must not override that current revocation decision.

## Rollback and readback

Keep the prior manifest commit and source artifacts available before starting. To
roll back Windows, stage the prior reviewed `Reparo.ps1`, verify its recorded hash,
and run that local file with `-Install`; verify version, installed hash, ACLs, shim,
and scheduled task again. To roll back Linux, set `REPARO_RELEASE_URL` to the raw URL
of the prior reviewed production manifest commit and rerun the installer, then verify
version, hash, ownership, mode, and cron preservation.

Rollback changes the Reparo runner only. It does not undo package, operating-system,
reboot, or migration changes from a separately authorized maintenance run. After any
deployment or rollback, query every targeted endpoint and reconcile the target list
against success/failure receipts; a successful orchestration job with missing hosts
is not a successful deployment.

## Prohibited shortcuts

- Do not use `-Latest`, `--latest`, or an unpinned custom URL in fleet automation.
- Do not grant standard users write access to `C:\ProgramData\Reparo` or read access
  to its machine Logs, Backups, Reporting, or SteamQueue state.
- Do not publish the production manifest or create a release tag without required CI,
  independent review, repository protection, and an authorized canary.
- Do not store API keys, private SSH keys, RMM secrets, or pairing tokens here.
