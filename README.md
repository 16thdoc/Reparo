# Reparo

Standalone client-safe Reparo runner for RMM deployment.

This copy is intentionally detached from CyberShell profile state. It does not require the `Marauders.*` modules, Dropbox paths, `cast`, `gitstorm`, or VS Code sync helpers.

## Suggested Ninja command

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -Update
```

## Modes

- Default: `Winget` only.
- `-Update`: curated managed-client pass: `Winget`, Microsoft Store winget source, Chocolatey if present, and Windows Update if `PSWindowsUpdate` is installed.
- `-Force`: full local-dev-tool gauntlet. Use carefully on clients because it can touch WSL, language package managers, and developer toolchains.
- `-Include Winget,Choco`: run only selected sections.
- `-Preview`: log what would run without executing package manager commands.

Logs are written to:

```text
C:\ProgramData\Spectral\Reparo\Logs
```

## Client rollout notes

Start with `-Preview -Update` or a small pilot group before scheduling broad deployment. `Winget` and Store updates can still behave differently across Windows builds, SYSTEM context, source agreements, and tenant/device policy. That is RMM-shaped nonsense, not magic.
