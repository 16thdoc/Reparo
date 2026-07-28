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

1. Make Reparo source changes.
2. Generate the embedded artifacts.
3. From the signing workstation, run Windows PowerShell 5.1:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\deploy\signing\Sign-ReparoArtifacts.ps1
   ```

4. Verify each artifact with `Get-AuthenticodeSignature`.
5. Commit the signed files. Never export or commit the private key.

The trust deployment must run before endpoint verification can report `Valid`. If the
signing workstation's local root store is policy-managed and rejects private-root
installation, `Get-AuthenticodeSignature` may report `UnknownError` there despite a
correct signer certificate; validate on a fleet-trusted endpoint instead.
