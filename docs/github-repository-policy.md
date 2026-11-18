# GitHub repository protection policy

Apply these settings to `16thdoc/Reparo` before treating a release as production.
They require repository-administration access and must be verified in GitHub after
configuration.

## Protect `main`

Create a branch ruleset targeting the default branch with these controls:

- require a pull request and at least one approval from someone other than the
  change author;
- dismiss stale approvals when new commits are pushed and require all review
  conversations to be resolved;
- require the latest reviewed commit to pass these checks:
  - `Steam and Headless safety checks / powershell`
  - `Steam and Headless safety checks / native-installer`
- require the branch to be current before merge;
- block force pushes and branch deletion;
- restrict bypass to a named emergency administrator role and audit every bypass;
- permit merge commits because the immutable source commit named by the later
  manifest must remain reachable.

Create a tag ruleset for `v*` that blocks updates and deletion and restricts tag
creation to the release role. A tag must identify the reviewed production-manifest
commit whose version matches the tag.

## Restrict Actions

- Set the default `GITHUB_TOKEN` permission to read repository contents.
- Do not allow workflows to create or approve pull requests.
- Require approval for workflows from first-time and external contributors.
- Allow GitHub-authored actions only when pinned to a reviewed full commit SHA;
  review Dependabot pin updates like source changes.
- Do not add repository signing secrets. The release workflow receives scoped
  `id-token: write` and `attestations: write` only in its attestation job.

## Verify settings

After an administrator applies the rules, test them rather than relying on the UI
summary:

1. Open a draft pull request and confirm both named checks report.
2. Confirm the author cannot supply the independent approval.
3. Push another commit and confirm the prior approval becomes stale.
4. Attempt a force push and deletion with a non-bypass identity; both must fail.
5. Create a disposable `v0.0.0-policy-test` tag with a non-release identity and
   confirm creation is blocked, then delete any local-only tag.
6. Record screenshots or API output and the verifying administrator in the change
   record.

If repository administration cannot read or change these settings, release source
and candidate manifests may still be prepared and tested, but production promotion
must remain blocked until an authorized administrator verifies the policy.
