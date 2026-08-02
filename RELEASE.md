# Reparo release checklist

Use this checklist before publishing or deploying a Windows fleet release. Routine
source work and Linux-only changes do not require the Windows signing identity to
be committed.

1. Finish, review, and commit source and deployment changes.
   For every user-visible change, assess and update both the Windows and native Linux
   runners, or document a tested intentional platform boundary before proceeding.
2. On the Windows signing workstation, run the signed release workflow:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\deploy\signing\New-SignedReparoRelease.ps1
   ```

3. Confirm the workflow reports the approved signer on Reparo and every generated
   Ninja/ScreenConnect artifact.
4. Review `git status`, `git diff`, and the generated documentation/artifacts.
5. Commit the signed release artifacts as one coherent release change.
6. Push the committed release and verify its remote-tracking state.
7. For fleet rollout, deploy internal signing trust first, pilot the signed offline
   Ninja artifact, and verify `Ninja-Reparo-Diagnostic.ps1` reports the expected
   signer and `Valid` signature status.

Never modify a signed target after step 2. Make the change, rerun the workflow, then
commit the regenerated release artifacts. The signature is the receipt, not decorative
tape.
