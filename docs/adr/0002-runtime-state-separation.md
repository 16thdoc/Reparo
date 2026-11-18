# ADR 0002: Separate readable runtime from private machine state

- Status: Accepted
- Date: 2026-11-17

## Context

Standard users need to execute the installed Windows runner, but machine logs,
backups, receipts, and reporting records can reveal host details or contain rollback
code. Giving all ProgramData descendants the runtime's read permission exposes more
information than required and makes legacy broad ACLs persist across upgrades.

## Decision

Keep the ProgramData runtime and command shim readable/executable by built-in Users,
but writable only by SYSTEM and Administrators. Give `Logs`, `Backups`, `Reporting`,
and `SteamQueue` protected ACL roots with access only for SYSTEM and Administrators,
and normalize existing descendants during elevated install/update operations. Reject
reparse points before changing those trees. Non-admin Windows runs write logs under
LocalAppData; native Linux continues to use per-user state.

## Consequences

- Standard users can invoke Reparo without reading machine-private state.
- Elevated upgrades perform extra ACL traversal, which is intentional and bounded
  to Reparo-owned trees.
- Tools that ingest machine logs require an Administrator/SYSTEM collection identity
  or an explicit, separately secured export.
