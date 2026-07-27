# Ninja offline-first Reparo deployment

Upload these two files together as Ninja script assets:

1. `Ninja-OfflineFirst.ps1` — the Ninja execution script.
2. `Reparo.ps1` — the bundled, reviewed runtime payload from the repository root.

The deployer finds `Reparo.ps1` beside itself (or accepts its staged location through
`-BundledReparoPath`). It installs that payload into `%ProgramData%\Reparo` first,
then attempts a GitHub refresh. A failed or blocked GitHub request is logged as a
warning and does not stop the maintenance run.

The default run is `-Update`. Pass normal Reparo arguments after the deployer
arguments; for example, `-Preview -Update` or `-Winget`.

## Deployment parameters

- `-BundledSha256 <hash>`: Optional SHA-256 of the uploaded `Reparo.ps1`. Use this
  in production to detect an accidental or tampered payload upload.
- `-RefreshFromGitHub:$false`: Use only the bundled payload; no GitHub attempt.
- `-RemoteReparoUrl <url>`: Remote candidate for the post-install refresh.

`main` is the default remote channel so the deployer can obtain the newest upstream
runtime. For a controlled rollout, replace it with a reviewed commit-pinned raw URL:

```text
https://raw.githubusercontent.com/16thdoc/Reparo/5012a1dc68deb6e29e7ec67d86b479f518974ac8/Reparo.ps1
```

When promoting a new payload, upload the new `Reparo.ps1` and update its SHA-256
deployment parameter. Generate the hash locally with:

```powershell
(Get-FileHash .\Reparo.ps1 -Algorithm SHA256).Hash
```
