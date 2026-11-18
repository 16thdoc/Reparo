# ADR 0003: Incremental extraction of privileged runner boundaries

- Status: Accepted
- Date: 2026-11-17

## Context

The Windows runner is a large single PowerShell file. A one-shot rewrite would make
security review and Windows/native Linux behavior comparison harder, and it would
change deployment mechanics at the same time as privileged-path controls.

## Decision

Keep the shipped entry point self-contained for this release, but treat these as
explicit future module seams:

1. release-manifest retrieval and artifact validation;
2. privileged installation, ACLs, replacement, rollback, and scheduled self-update;
3. package-manager adapters and native command execution;
4. scheduling, queue/receipt handling, and reporting;
5. presentation, summaries, and diagnostics.

Extract one seam at a time behind the existing CLI, preserve Windows/Linux parity,
and require fixture coverage before moving the next seam. The installer must stage
all required module files atomically before the entry point starts importing them.

## Consequences

- Security changes remain reviewable and the current offline single-file install
  keeps working.
- The monolith is not immediately smaller; this ADR defines an ordered migration,
  not a claim that modularization is complete.
- Future module loading introduces new integrity and partial-install risks, so it
  must not ship until the manifest and rollback transaction cover the full module set.
