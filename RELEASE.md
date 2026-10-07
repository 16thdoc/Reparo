# Reparo release checklist

Use this checklist before publishing or deploying a Windows fleet release.

1. Finish and review source and deployment changes. For every user-visible change,
   assess the Windows and native Linux runners and implement parity or document a
   tested platform boundary.
2. Run the relevant test suite.
3. Test the canonical offline install path: run `Reparo.ps1 -Install` from a staged
   source file and validate the ProgramData runtime, shim, and rollback behavior.
4. Update `deploy\reparo-release.json` to the reviewed release version, immutable
   commit URLs and SHA-256 for Windows source, native runtime and native installer.
   Commit source first, then pin that immutable source commit in a manifest commit;
   no self-referential manifest hash. Both New paths read this release channel.
   Run release parity before pinning, then manifest verification and an isolated
   native HTTPS install/bootstrap pilot with cron mocked before broader deployment.
5. Review `git status` and `git diff` for the source, generated artifacts, and docs.
6. Commit the coherent release change, push it, and verify the remote-tracking state.
7. Pilot the normal deployment artifact before broad fleet rollout.
