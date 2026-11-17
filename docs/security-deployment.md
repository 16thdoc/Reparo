# Security deployment guidance

## Recommended order

For a managed Windows fleet, prefer an RMM-hosted reviewed copy of `Reparo.ps1`.
Run that copy with `-Install` to establish the protected ProgramData runtime, then
use `-Preview -Update` and a small representative pilot before broad maintenance.
This keeps the initial trust decision inside the RMM and avoids a network bootstrap.

After the initial install, use `-New` (or the installed weekly self-update task) to
follow `deploy/reparo-release.json`. That channel resolves a commit-pinned artifact
and verifies its SHA-256 and version. Protect publication to the production manifest
with branch protection, required CI, and review by someone other than the author.

Use `deploy/Install-ReparoRemote.ps1` for a small number of SSH-reachable Windows
hosts. Its default follows the reviewed release manifest. A custom `-SourceUrl`
must be paired with `-SourceSha256`; record both in the change ticket or deployment
receipt. The CMD installer is suitable for an interactive administrator or an RMM
that can stage the CMD file as a trusted artifact, but it is not a replacement for
RMM change control.

On Linux, use `deploy/install-reparo-linux.sh` with its default reviewed channel.
It installs per user, verifies the commit-pinned runtime hash/version, and preserves
the existing crontab. Reserve `--latest` for an explicit test environment.

## Rollout rings

1. CI and isolated installer fixtures.
2. One disposable Windows endpoint and one disposable Linux endpoint.
3. A canary ring representing OS versions, RMM execution identities, package
   managers, and interactive-user/SYSTEM contexts.
4. A limited production ring with receipt and log review.
5. Broad rollout only after the canary window has no unresolved failures.

Do not combine a runner deployment with `-Force`, reboot, package migration, or a
wide maintenance pass. Installation success proves the runner transaction only.
Keep the previous production manifest as the rollback anchor; rollback changes the
runner, not package or operating-system changes already made.

## Avoid

- Do not bootstrap `Reparo.ps1` directly from mutable `main` and execute it.
- Do not use `-Latest`, `--latest`, or an unpinned custom URL in fleet automation.
- Do not grant standard users write access to `C:\ProgramData\Reparo`.
- Do not publish a source commit and production manifest without CI and a pilot.
- Do not place API keys, private SSH keys, or pairing tokens in the repository.
