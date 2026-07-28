# Reparo Repository Workflow

## Versioned releases

Any Reparo version bump or release-worthy source/deployment change must use the
internal signing workflow before review and commit:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\deploy\signing\New-SignedReparoRelease.ps1
```

That workflow signs `Reparo.ps1`, regenerates all embedded Ninja/ScreenConnect
artifacts from the signed source, signs the generated artifacts, and verifies the
approved signer thumbprint. Do not edit any signed target after it completes; rerun
the workflow instead.

Then inspect `git status`, `git diff`, and signature output before committing. Commit
the signed source, generated artifacts, and relevant documentation together. Do not
push unless Trenton explicitly asks.

The signing private key is non-exportable and must never be exported, copied, logged,
or committed. Public trust material and workflow documentation live in
`deploy\signing\`.
