# ScreenConnect Toolbox: self-contained Reparo

Upload `ScreenConnect-Reparo-Embedded.ps1` to ScreenConnect Toolbox as a PowerShell
tool. It is self-contained: no companion files, GitHub bootstrap, or user profile
paths are needed. The tool installs Reparo into `%ProgramData%\Reparo`, optionally
refreshes from GitHub, then runs the selected mode.

ScreenConnect Toolbox commands normally execute through the ScreenConnect service,
which is SYSTEM. Keep that context: Reparo needs it for Windows Update and other
machine-level maintenance.

## Toolbox arguments

| Use | Arguments |
| --- | --- |
| Pilot | `-Preview -Update` |
| No arguments | Install or refresh Reparo only; no maintenance |
| Normal maintenance | `-Update` |
| Install only | `-InstallOnly true` |
| Install only, never contact GitHub | `-InstallOnly true -Offline true` |
| Maintenance, never contact GitHub | `-Offline true -Update` |

With no arguments, it installs or refreshes Reparo and stops; it does not run
maintenance.

GitHub refresh failures are warnings. The embedded Reparo payload is always installed
and used if the refresh cannot complete.
