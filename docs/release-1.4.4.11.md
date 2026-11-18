# Reparo 1.4.4.11 candidate

This candidate deepens the security and release controls introduced in 1.4.4.10.

- Windows machine Logs, Backups, Reporting, and SteamQueue state now use private
  SYSTEM/Administrators ACL roots; existing descendants are normalized during an
  elevated install or update while standard-user logs remain in LocalAppData.
- Executable Windows CI creates real ProgramData ACL fixtures and validates broad-ACL
  repair, nested-junction rejection before mutation, hard-link-safe replacement,
  runtime read-only access for Users, and private machine-state access.
- GitHub workflows disable persisted checkout credentials, declare bounded timeouts,
  and keep third-party Actions pinned to immutable commit SHAs. Dependabot proposes
  reviewed updates to those pins.
- A deterministic SPDX 2.3 generator and tagged release workflow publish checksums,
  a release bundle, and keyless GitHub build/SBOM attestations.
- The threat model, repository-protection policy, rollout/canary/rollback runbook,
  and architectural decisions are now explicit and version controlled.

Windows and native Linux share release identity and flavor. The native Linux runner
continues to use private per-user state and pinned manifest verification; the Windows
ACL controls have no privileged native-Linux equivalent.

This remains a candidate until required CI, repository protection, an explicitly
authorized endpoint canary, and production-manifest promotion are complete.
