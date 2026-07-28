# Reparo release checklist

Use this checklist for every Reparo version bump or release-worthy change.

1. Finish source and deployment changes.
2. Run the signed release workflow:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\deploy\signing\New-SignedReparoRelease.ps1
   ```

3. Confirm the workflow reports the approved signer on Reparo and every generated
   Ninja/ScreenConnect artifact.
4. Review `git status`, `git diff`, and the generated documentation/artifacts.
5. Commit the signed release as one coherent change.
6. Push only when Trenton explicitly requests it.
7. For fleet rollout, deploy internal signing trust first, pilot the signed offline
   Ninja artifact, and verify `Ninja-Reparo-Diagnostic.ps1` reports the expected
   signer and `Valid` signature status.

Never modify a signed target after step 2. Make the change, rerun the workflow, then
commit. The signature is the receipt, not decorative tape.
