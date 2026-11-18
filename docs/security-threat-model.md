# Reparo security threat model

## Scope and security objectives

This model covers the Windows and native Linux runners, release manifests,
bootstrap and remote-install helpers, GitHub Actions release evidence, local
state, and the boundary between Reparo and operating-system package managers.

The primary objectives are:

- only reviewed, immutable Reparo bytes become a privileged runtime;
- a standard local user cannot replace privileged code or write machine logs,
  backups, receipts, or reporting state;
- a link or path-redirection attack cannot turn an update into an arbitrary
  privileged file write;
- operators can identify, verify, stage, and roll back a specific release;
- Reparo never silently expands into a secret-management or package-signing
  authority.

Availability of third-party package repositories and correctness of packages
selected by administrators are operational dependencies, not guarantees Reparo
can provide.

## Assets, actors, and trust boundaries

| Asset or boundary | Trusted writers | Readers | Main concern |
| --- | --- | --- | --- |
| `C:\ProgramData\Reparo\Reparo.ps1` and `bin` | SYSTEM, Administrators | local users | privileged code replacement |
| ProgramData `Logs`, `Backups`, `Reporting`, `SteamQueue` | SYSTEM, Administrators | SYSTEM, Administrators | host details, receipts, rollback code |
| Per-user Linux state and non-admin Windows logs | owning user | owning user | cross-user disclosure or modification |
| `deploy/reparo-release.json` | reviewed GitHub change | public | redirecting installers to attacker bytes |
| Candidate manifest | reviewed GitHub change | test operators | accidental production use |
| GitHub workflow and release evidence | protected repository workflow | public/operator | workflow tampering or false provenance |
| SSH/RMM deployment channel | authorized operator and endpoint | authorized operator | target confusion or credential exposure |
| OS package managers and repositories | their configured authorities | Reparo process | upstream compromise or unsafe operator policy |

The expected adversaries are an unprivileged local user, a network attacker, a
malicious or compromised upstream artifact, and an attacker who can propose a
repository change but cannot satisfy protected review and CI. An attacker with
Administrator/SYSTEM on the endpoint or unrestricted write access to protected
repository settings is outside the prevention boundary; audit and rapid rollback
remain relevant in those cases.

## Principal data and control flows

1. A reviewed source commit is created first.
2. CI validates Windows/Linux parity, installers, ACL/link behavior, mutable URL
   rejection, and workflow pinning.
3. A later manifest commit names the exact source commit and its SHA-256 values.
4. Installers retrieve the manifest over HTTPS, require commit-pinned raw URLs,
   download to a random temporary directory, validate size/hash/version/syntax,
   and only then replace the runtime.
5. Windows machine installs reject reparse points, unlink an existing destination
   before replacement, and enforce protected ACLs. Linux installs use private
   per-user state and atomic file replacement.
6. A tag can produce a deterministic SPDX document, checksums, and GitHub keyless
   build/SBOM attestations. These are operator-verifiable evidence; the runtime
   manifest hash remains the installer's authorization mechanism.

## Threats and controls

### Mutable or substituted network source

An attacker may change `main`, poison a cache, redirect a custom URL, or return a
different file after review. Fleet paths use a manifest that requires a 40-character
commit, exact raw GitHub URLs derived from that commit, uppercase SHA-256 values,
and a matching embedded version. Custom network sources require an explicit digest.
HTTPS is mandatory and embedded URL credentials are rejected.

Residual risk: control of both protected repository publication and GitHub-hosted
content can authorize malicious bytes. Independent review, protected settings,
attestation verification, and retaining the previous manifest reduce that risk.

### Privileged path or link redirection

An unprivileged user may pre-create a directory junction, symlink, or hard link so
an elevated update writes elsewhere. Windows validates every existing path component
and private-tree descendant for reparse points. Runtime replacement removes the
old directory entry before copying, which breaks a hard link rather than writing
through it. Executable Windows integration tests exercise junction and hard-link
cases on the ProgramData volume.

Residual risk: Administrator/SYSTEM can still change ACLs and links. Endpoint
security must protect those identities and alert on ProgramData changes.

### Over-broad local access

The Windows runtime root has protected inheritance: SYSTEM and Administrators have
full control while built-in Users receive read/execute only. Machine logs, backups,
reporting custody, and desktop-queue receipts have separate protected ACLs granting
access only to SYSTEM and Administrators. Existing descendants are normalized during
an elevated lifecycle operation. Standard-user logs go to LocalAppData. Linux state
is created under the invoking user's private data root.

Residual risk: files deliberately exported from these roots inherit the destination's
policy. Operators must treat copied logs and backups as potentially sensitive.

### Workflow or dependency compromise

All third-party GitHub Actions references are pinned to full commit SHAs, checkout
credentials are not persisted, job permissions are explicit and minimal, and jobs
have timeouts. Dependabot proposes reviewed action-pin updates. The release job alone
receives `id-token: write` and `attestations: write` for keyless GitHub attestations.
It does not store a signing key.

Residual risk: a compromised pinned action or GitHub-hosted runner can affect a
build. Attestations describe where an artifact came from; they do not prove source
correctness. Review pin updates and verify release hashes against the manifest. A
withdrawn release's historical attestation may still verify cryptographically, so
current production-manifest authorization and revocation records are also required.

### Target confusion and command injection in remote deployment

SSH targets are syntax-validated, argument boundaries use `--`, and the generated
remote bootstrap quotes PowerShell literals. A custom source and hash must be
provided together. Host-key policy, SSH credentials, RMM identities, and endpoint
selection remain operator responsibilities and must not be stored in this repository.

### Destructive maintenance or unsafe rollout

Installing a runner is separate from authorizing package changes, reboots, `-Force`,
or broad maintenance. Rollouts use isolated CI, disposable hosts, an explicitly
authorized canary ring, a limited ring, then production. Receipts and logs are
reviewed at each gate, and the prior manifest/source remain the rollback anchor.

## Required review triggers

Revisit this model when adding a network origin, a new privileged writable path, a
new remote execution mechanism, secrets, a new GitHub Action, a different release
authority, or a package-manager behavior that bypasses its native trust validation.
