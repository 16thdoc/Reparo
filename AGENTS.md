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
After changing `Reparo.ps1`, update the release manifest and test the canonical
single-script offline install path; RMM wrapper artifacts are intentionally retired.

Inspect `git status` and `git diff` before committing. Commit the source, release
manifest, and relevant documentation together. Push the reviewed release, then pilot
the canonical `Reparo.ps1 -Install` path before broad rollout.
