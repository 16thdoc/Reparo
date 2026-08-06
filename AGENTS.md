# Reparo Repository Workflow

## Cross-platform parity

Treat Windows and native Linux as peers. For every user-visible behavior, command,
release/lifecycle change, logging contract, or documentation change in either runner,
assess the equivalent path in the other runner before closing the work. Implement the
same useful outcome where the platform supports it; otherwise record and test a clear
intentional boundary. Do not let one platform silently drift, and keep shared release
identity and version-output flavor synchronized.

## Versioned releases

Before publishing or deploying a Windows fleet release, review the source and
deployment changes, assess Windows/native Linux parity, and run the relevant tests.
After changing `Reparo.ps1`, regenerate the embedded Ninja and ScreenConnect
artifacts with `deploy\New-NinjaEmbeddedDeployment.ps1`.

Inspect `git status` and `git diff` before committing. Commit regenerated artifacts
and relevant documentation with their source change; do not leave stale generated
deployment artifacts behind. Push the reviewed release, then pilot the normal
deployment artifact before broad rollout.
