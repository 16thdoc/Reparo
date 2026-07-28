# Reparo internal code signing

Reparo uses an internal root CA and a leaf code-signing certificate. This is free and
appropriate for managed endpoints where NinjaOne can deploy trust; it is not publicly
trusted outside that fleet.

- Root CA thumbprint: `1C44A46033EF4BB52695208ACF4455823A64BE57`
- Approved signer thumbprint: `93CE2552E5C7F90600C36BDB83541921FCC97ED1`
- Signing certificate expiry: 2029-07-28

## Fleet trust deployment

Import `Install-ReparoInternalSigningTrust.ps1` into Ninja and run it as SYSTEM with
no options or arguments. It adds only public certificates: the root to
`LocalMachine\Root` and signer to `LocalMachine\TrustedPublisher`.

## Signing a release

After any Reparo source or deployment-source change, run the complete release workflow
from the signing workstation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\deploy\signing\New-SignedReparoRelease.ps1
```

It signs `Reparo.ps1`, regenerates all embedded Ninja/ScreenConnect artifacts from the
signed source, signs those artifacts, and verifies the expected signer. It does **not**
commit, push, or deploy; review the diff, commit it, then choose rollout deliberately.

`Sign-ReparoArtifacts.ps1` remains the lower-level signer for an already-generated
artifact set. Normal maintenance should use `New-SignedReparoRelease.ps1`.

Never export or commit the private key.

The trust deployment must run before endpoint verification can report `Valid`. If the
signing workstation's local root store is policy-managed and rejects private-root
installation, `Get-AuthenticodeSignature` may report `UnknownError` there despite a
correct signer certificate; validate on a fleet-trusted endpoint instead.
