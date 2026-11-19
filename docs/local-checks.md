# Local checks

Routine verification runs locally. The optional hosted workflow is started manually.
`Tests/run-local-checks.py` reads the runnable steps directly from
`.github/workflows/test-steam-headless.yml`; there is no second hand-maintained
list of tests. Unsupported workflow syntax or shells stop the runner for review.

Use Python 3.10 or newer. The runner uses the standard library and does not install
Python packages or change the host toolchain.

## Windows

Windows requires Windows PowerShell 5.1, PowerShell 7 (`pwsh`), and Git. Run from
this checkout with a new private output directory:

```powershell
python .\Tests\run-local-checks.py --profile windows --output-dir "$env:LOCALAPPDATA\ReparoChecks\windows-13"
```

This runs the existing Windows PowerShell workflow groups, plus the two existing
PowerShell 7 boundaries. Windows PowerShell child processes use the machine
`PSModulePath`; PowerShell 7 prioritizes its own core modules before the machine
paths. It does not inherit another runtime's user module configuration.

Production manifest verification uses `git archive` of the production manifest's
immutable source commit in an owned temporary directory. The candidate manifest
is checked against the current source. The pinned commit must be available in the
local Git history. The existing isolated offline-install fixture mocks machine
PATH, schedules, events and Ninja; it does not install into the real host runtime.

## Native Linux

Linux requires Bash, POSIX sh, Python 3, Git, curl, and the normal coreutils/util-linux
tools used by the existing Ubuntu fixtures. Use a native Linux checkout:

```bash
python3 Tests/run-local-checks.py --profile linux --output-dir "$HOME/.local/state/reparo-checks/linux-13"
```

The HTTPS step defaults to the production manifest at the checkout's full Git
`HEAD` on public GitHub. Publish that reviewed commit before running this profile.
The remote manifest bytes must match the local production manifest. An explicit
published pin can be selected with:

```bash
python3 Tests/run-local-checks.py --profile linux \
  --output-dir "$HOME/.local/state/reparo-checks/linux-13" \
  --manifest-url https://raw.githubusercontent.com/16thdoc/Reparo/REPLACE_WITH_FULL_PUBLIC_COMMIT/deploy/reparo-release.json
```

Only the fixed repository's production-manifest path at a full lowercase commit
is accepted. An unpublished commit, redirected URL or different local manifest
stops verification.

The first Linux group runs the workflow's syntax, version and isolated fixture
checks. The second performs real HTTPS installation and installed-shim self-update
inside disposable HOME/XDG/TMP directories, with cron mocked and an unrelated cron
entry preserved. TLS and artifact hash verification remain enabled. A fixture-only
curl wrapper identifies these public download observations as
`Reparo-Artifact-Verification/1.0`; the product download clients are unchanged.
No real maintenance or host scheduler configuration is requested.

## Logs and results

Both profiles set `REPARO_REPORT_SKIP=1` for child checks. The registry tests may
clear it internally only for their existing synthetic, mocked-transport fixtures.
The disposable HTTPS lane verifies that it creates no registry identity.

The output directory must be empty and either outside Git or explicitly ignored.
The runner refuses Git metadata and nonempty result directories. It gives newly
created Windows results a private current-user ACL; Linux results use mode 0700.
Logs and receipts are not uploaded or committed by the runner.

Each workflow step gets its own log and records its actual exit, duration and log
SHA-256 in `receipt.json`. The receipt also records Git HEAD/status, the workflow
hash, source/manifest hashes and the selected HTTPS manifest. A passing run also
verifies that the source/workflow bytes remained unchanged and records the ending
Git HEAD. A failing step stops
the profile. Inspect its log before deciding whether a retry is appropriate; use
a new output directory to preserve the earlier evidence. Owned temporary source
archives and script files are removed after the run.

List the actual workflow groups without executing checks or writing output:

```bash
python3 Tests/run-local-checks.py --profile linux --list
```

Use `--profile windows --list` for the Windows groups. Local fixture success is
separate from an authorized live endpoint pilot, release publication or fleet
rollout.
