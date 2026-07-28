# Reparo ScreenConnect Toolbox pack

Upload these command files to ScreenConnect Toolbox. They check for the installed
runtime, create a one-shot SYSTEM scheduled task, and start it. The Toolbox action
reports that the task started; Reparo's detailed outcome is in
`C:\ProgramData\Reparo\Logs`.

| Tool | Exact Reparo command | Use |
| --- | --- | --- |
| `Install-Reparo.bat` | `-New` from GitHub | GitHub-backed first install or runtime refresh; `-Offline` only verifies an existing installation. |
| `ScreenConnect-Reparo-Embedded.ps1` | embedded install-only by default | Self-contained first install; pass `-Offline true` to skip GitHub refresh. |
| `Run-Reparo-Force-System.cmd` | `-Force` | Broad maintenance pass as SYSTEM. |
| `Run-Reparo-Force-Reboot-System.cmd` | `-Force -Reboot` | Broad maintenance, then intentional restart. |
| `Run-Reparo-New-System.cmd` | `-New` | Refresh an already installed runtime from its configured source. |
| `Run-Reparo-AllowReboot-System.cmd` | `-AllowReboot` | Windows Update-only run; permits Windows Update to reboot if necessary. |
| `Run-Reparo-System.cmd` | `-Update` | Managed-client update pass as SYSTEM. |

`-Reboot` schedules a restart after Reparo completes. `-AllowReboot` is different:
it lets the Windows Update provider reboot only when it requires it.

For an offline first install, use `ScreenConnect-Reparo-Embedded.ps1 -Offline true`.
`Install-Reparo.bat -Offline` intentionally does not download and therefore cannot
install a missing runtime.
