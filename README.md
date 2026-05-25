# Reparo

Reparo is a standalone Windows maintenance runner for RMM deployment.

It updates common package managers and toolchains when they are already present on a machine. The script is intentionally self-contained: it does not depend on profile modules, cloud-synced helper paths, editor sync state, or any other machine-specific automation.

## What it does

By default, Reparo runs a conservative `winget` upgrade pass. Optional modes can also include Microsoft Store updates through `winget`, Chocolatey, Windows Update through `PSWindowsUpdate`, and developer toolchains such as Scoop, pip, npm, pnpm, Yarn, .NET tools, Rust, Conda, Ruby gems, Composer, and WSL.

Reparo does not install package managers from scratch. It only uses tools that are already present, then skips the sections that are not available.

## Quick start

Preview the managed-client update pass:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -Preview -Update
```

Run the managed-client update pass:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -Update
```

Run only selected sections:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -Include Winget Choco
```

## RMM deployment

Suggested NinjaOne command:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -Update
```

Recommended rollout pattern:

1. Run `-Preview -Update` on a test device.
2. Pilot `-Update` on a small group of representative endpoints.
3. Review logs and RMM output before broad deployment.
4. Reserve `-Force` for known developer workstations or hands-on maintenance.

### Ninja deployment options

Use one of these patterns depending on how you want to manage updates.

| Pattern | Best for | Tradeoff |
| --- | --- | --- |
| Paste `Reparo.ps1` into Ninja | Maximum simplicity and no external dependency | Updating Reparo means editing the Ninja script body |
| Upload `Reparo.ps1` as a Ninja script/file | Controlled copy inside Ninja | Exact execution path depends on how the Ninja script/file is staged |
| Download from GitHub | Easy updates and version pinning | Requires endpoint access to GitHub raw content |

### Option 1: Paste Reparo into Ninja

Create a Ninja PowerShell script and paste the contents of `Reparo.ps1` directly into the script body.

Recommended arguments for a broad managed-client pass:

```powershell
-Update
```

Recommended pilot arguments:

```powershell
-Preview -Update
```

Use this option when you want the fewest moving parts. The script runs entirely from Ninja, and no endpoint needs to reach GitHub.

### Option 2: Upload Reparo as a Ninja file

Upload `Reparo.ps1` to Ninja and run it from the staged script directory:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -Update
```

If your Ninja file staging path differs, update the `-File` path to match where Ninja places the uploaded file.

For a safer first pass:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -Preview -Update
```

### Option 3: Download from GitHub at runtime

Use this when the repo is public, or when the endpoint has approved access to the raw file URL. The bootstrapper downloads the current `Reparo.ps1` to `C:\ProgramData\Reparo\Reparo.ps1`, then runs it.

Ninja script body:

```powershell
$ErrorActionPreference = 'Stop'

$reparoUrl = 'https://raw.githubusercontent.com/16thdoc/Reparo/main/Reparo.ps1'
$installRoot = "$env:ProgramData\Reparo"
$scriptPath = Join-Path $installRoot 'Reparo.ps1'

if ([Net.ServicePointManager]::SecurityProtocol -notmatch 'Tls12') {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
Invoke-WebRequest -Uri $reparoUrl -OutFile $scriptPath -UseBasicParsing

if (Get-Command Unblock-File -ErrorAction SilentlyContinue) {
    Unblock-File -Path $scriptPath
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Update
exit $LASTEXITCODE
```

For production stability, prefer a tag or commit-pinned raw URL instead of `main`:

```powershell
$reparoUrl = 'https://raw.githubusercontent.com/16thdoc/Reparo/v1.0.0/Reparo.ps1'
```

The same bootstrapper is also included at `deploy/Ninja-GitHub.ps1`.

### Private repo note

For client endpoints, a public repo or Ninja-hosted script copy is usually cleaner than embedding GitHub credentials. If the repo is private, avoid hard-coding a personal access token in the Ninja script body. Use Ninja-managed secure variables only if you truly need private GitHub delivery.

## Modes

| Mode | Behavior |
| --- | --- |
| Default | Runs `Winget` only. |
| `-Preview` | Logs what would run without executing package manager commands. |
| `-Update` | Runs the managed-client pass: `Winget`, `Winget(msstore)`, `Choco`, and `WindowsUpdate`. |
| `-Include <sections>` | Runs only the named sections, such as `Winget Choco`. |
| `-Force` | Runs the full local-dev-tool pass and enables Windows Update and WSL apt handling. Use carefully. |

## Sections

Available section names:

- `Winget`
- `Winget(msstore)`
- `Scoop`
- `Choco`
- `Pip`
- `Pipx`
- `Npm`
- `Pnpm`
- `Yarn`
- `DotNet`
- `Rust`
- `CargoBins`
- `Conda`
- `Gem`
- `Composer`
- `Wsl`
- `WslApt`
- `WindowsUpdate`

## Logging

Logs are written to:

```text
C:\ProgramData\Reparo\Logs
```

Each run creates a timestamped log file that includes the computer name, process ID, selected mode, commands invoked, command output, skipped sections, and errors.

You can override the log location:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparo.ps1 -Update -LogRoot C:\Temp\ReparoLogs
```

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Administrative rights for Windows Update operations
- Existing package managers for each selected section
- `PSWindowsUpdate` installed if using the `WindowsUpdate` section

`winget` and Microsoft Store behavior can vary by Windows build, execution context, source agreement state, tenant policy, and device policy. Test from the same context your RMM will use, especially when running as `SYSTEM`.

## Safety notes

- Start with `-Preview`.
- Use `-Update` for ordinary managed-client maintenance.
- Avoid `-Force` on general client endpoints unless you intentionally want to touch developer toolchains and WSL.
- Review logs after pilot runs.
- Expect package managers to return nonzero exit codes for some "nothing to update" cases; Reparo treats common benign `winget` messages as successful no-op outcomes.

## Public repo note

This copy is designed to be shareable. Before publishing a fork, review the README wording for organization-specific deployment details.
