# Reparo Repository Workflow

## Versioned releases

Source and Linux-only changes may be reviewed and committed without the internal
signing workflow. Before publishing or deploying a Windows fleet release, run the
workflow on the Windows signing workstation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\deploy\signing\New-SignedReparoRelease.ps1
```

That workflow signs `Reparo.ps1`, regenerates all embedded Ninja/ScreenConnect
artifacts from the signed source, signs the generated artifacts, and verifies the
approved signer thumbprint. Do not edit any signed target after it completes; rerun
the workflow instead.

Then inspect `git status`, `git diff`, and signature output. Commit the signed source,
generated artifacts, and relevant documentation together as the Windows release
change. Do not leave generated deployment artifacts behind.

The signing private key is non-exportable and must never be exported, copied, logged,
or committed. Public trust material and workflow documentation live in
`deploy\signing\`.
