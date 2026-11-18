# Reparo release checklist

Use this checklist before publishing or deploying a Windows fleet release.

1. Finish and review source and deployment changes. For every user-visible change,
   assess the Windows and native Linux runners and implement parity or document a
   tested platform boundary.
2. Run the relevant test suite, including `Test-ReparoSecurity.ps1`, the executable
   Windows ACL/link integration test, and `Test-ReparoSupplyChain.ps1`. Confirm all
   third-party Actions remain pinned and checkout credentials are not persisted.
3. Test the canonical offline install path: run `Reparo.ps1 -Install` from a staged
   source file and validate the ProgramData runtime, shim, and rollback behavior.
4. Update `deploy\reparo-release.json` to the reviewed release version, immutable
   commit URLs and SHA-256 for Windows source, native runtime and native installer.
   Commit source first, then pin that immutable source commit in a manifest commit;
   no self-referential manifest hash. Both New paths read this release channel.
   Run release parity before pinning, then manifest verification and an isolated
   native HTTPS install/bootstrap pilot with cron mocked before broader deployment.
5. Review `git status` and `git diff` for the source, workflow, generated evidence
   contract, and docs. Obtain independent review through the protected `main` ruleset.
6. Commit the coherent release change, push it, and verify the remote-tracking state.
7. Pilot the candidate on explicitly authorized disposable/canary Windows and Linux
   targets. Capture installed version/hash, ACL/ownership checks, task/cron state,
   logs, receipts, and rollback readiness. A runner pilot does not authorize package
   maintenance or reboot.
8. Only after the canary gate, advance `deploy\reparo-release.json` in a separate
   reviewed change. Tag that production-manifest commit as `vVERSION` and require a
   successful `Release provenance` workflow.
9. Download the release evidence, verify the ZIP and SPDX attestations with
   `gh attestation verify --repo 16thdoc/Reparo`, validate `SHA256SUMS`, and retain
   the prior production manifest as the rollback anchor before broad rollout.
