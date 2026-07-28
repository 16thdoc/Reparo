# Reparo in Ninja: the short version

Use **one file per job**:

- `Ninja-Embedded.ps1` = install/refresh and report the version.
- `Ninja-Embedded-Offline.ps1` = install without talking to GitHub.
- `Ninja-Reparo-ReportOnly.ps1` = only update the version field.
- `Ninja-Reparo-Update.ps1` = install/refresh, then do updates.

Import the chosen file as a normal Ninja **PowerShell** script. Do not use Ninja
Installer. Do not add Ninja options or arguments. Ninja only allows installer binaries
there and can scramble imported script options, because it has chosen violence.

Set it to run as **SYSTEM**.

The script already contains a copy of Reparo. It installs that copy, then—unless you
picked the Offline file—tries GitHub for a newer one. Every normal install also updates
the Ninja device custom field called `Reparo`.

## Later, when Reparo changes

1. Make the new Reparo version.
2. Generate the fixed files using the commands in `Ninja-Embedded-Setup.md`.
3. Import the newly made matching file into Ninja.
4. Test one machine.
5. Replace the old Ninja script once the test works.

Leave `-Force` alone unless you mean it. `-Update` is the normal fleet option.
