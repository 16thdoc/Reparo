# Reparo release checklist

Use this checklist before publishing or deploying a Windows fleet release.

1. Finish and review source and deployment changes. For every user-visible change,
   assess the Windows and native Linux runners and implement parity or document a
   tested platform boundary.
2. Run the relevant test suite.
3. After changing `Reparo.ps1`, regenerate every embedded Ninja and ScreenConnect
    artifact with `deploy\New-NinjaEmbeddedDeployment.ps1`.
4. Update the GitHub source pins in `deploy\Ninja-Reparo-GitHub.ps1` and
   `deploy\Ninja-GitHub.ps1` to the reviewed release commit before importing a fleet
   deployment artifact.
5. Review `git status` and `git diff` for the source, generated artifacts, and docs.
6. Commit the coherent release change, push it, and verify the remote-tracking state.
7. Pilot the normal deployment artifact before broad fleet rollout.
