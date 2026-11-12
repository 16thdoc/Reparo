# Reliability contract 1.4.4.8

The production manifest pins reviewed 1.4.4.8 artifacts. Release publication does
not itself update an installed runner or enroll its new hash with a controller.
See [review-pilot.md](review-pilot.md) before deployment or maintenance.

## Decision: receipts precede presentation

`reparo-command/1` retains the literal child-host argv, command text, PID and
creation time where observed, start/end, nullable exit, launch/capture errors and
separate raw stdout/stderr files. Windows drains both pipes even if a spool fails;
it retains up to 16 MiB per stream in memory as an emergency display fallback.
Successful spools are retained. A spool/render failure cannot turn exit 0 into a
package failure or erase an already observed nonzero exit. A failure before launch
has a null native exit. These are child-host receipts: grandchildren launched by
manager scripts do not acquire invented process identities or exits.

Windows commits per-package Winget receipts before the next package or deferred
launch can fail. Immutable event files and the terminal command receipt survive
independently of summary rendering. The in-memory ledger stores the latest state
by stable backend/package/scope/phase ID. Replaying receipts does not add a second
package row. A late orchestration failure is a separate outcome.

Native POSIX commands retain separate raw streams and their actual `wait` status
before `tee`, logging, renaming or telemetry. A real command failure returns parent
exit 1 and a FAILED log. Capture-only degradation remains independently visible.
Strict native JSON export uses Python 3's standard library; if unavailable, the
runner explicitly reports missing JSON evidence and retains shell/log evidence.
The runner does not install Python to satisfy reporting.

Native receipts and terminal summaries are synchronous. Windows user workers have
their own `reparo-worker/1` terminal receipt and an independent fallback path. The
parent never waits for a deferred worker that is waiting for the parent to exit.
Parent PID **and creation time** bind that wait. A parent wait deadline stops a
worker from starting the package operation; it is not an installer kill deadline.
Synchronous deadlines request safe boundaries and continue waiting for indivisible
operations. No timeout kills an active installer.

## Decision: one ledger, two views

`reparo-repair/1` has these independent dimensions:

| Field | Meaning |
| --- | --- |
| `source` | Originating runner version and SHA-256, nullable if unavailable. |
| `parent` | Reported status, requested exit, nullable observed OS exit, execution boundary. |
| `commands` | Actual captured child-host execution; exit is not a version delta. |
| `records` | Stable ID, backend/package/scope/phase, outcome, reason, code, delta, capture and evidence. |
| `workers` | Exact expected worker ID and primary/fallback terminal references. |
| `coverage` | Selected/excluded lanes and expected absence/preview or unsupported coverage. |
| `evidence_health` | Complete, degraded or unavailable, independently of maintenance. |
| `consequences` | OS reboot provenance, installer restart, app activation, observed service restart. Unknown stays unknown. |
| `telemetry` | Delivery failure/unverified independently of local results. |
| `finality` | Parent finished separately from settled maintenance evidence. |
| `attention`, `counts` | Derived from that same ledger for both displayed summaries. |

An observed OS parent exit remains null inside that still-running process. Its
intended exit is separately labeled. Later status never rewrites the historical
parent exit or snapshot. The proposed new aggregate exit 0/1/2/3 interface is **not
introduced** here. Windows parent exit conventions and Ninja callbacks retain their
existing interface. Native failed commands stop returning an accidental success.

The human panel is eight plain-text lines. The separate manual AI block has a
version marker, up to two attention records and explicit overflow, plus the actual
repair-file reference. It preserves signed, unsigned and hexadecimal error values;
unknown codes remain null. Display normalization does not rewrite raw bytes.
Optional absences collapse into coverage. No automatic upload, task intake or
repair is attached to either view.

Confirmed package changes require an observed installed-version delta. Legacy
`Updated` rows hold advertised targets/command receipts, so the new view does not
promote those to confirmed changes. Successful child commands and legacy success
receipts have separate counters. dpkg before/after evidence supports apt version
deltas; zero deltas is a no-op. Same-version npm replacement and dependency changes
are not counted as version upgrades. Other managers can retain unknown effects
until they have a reliable installed-state adapter.

Windows `-Status` selects a genuine terminal maintenance log, then derives a new
read-only as-of view from its saved ledger and worker receipts. It does not queue
updates or change Steam downloads. Corrupt, delayed or mismatched new worker
receipts remain unresolved. Explicitly designated legacy exit-only worker files
retain their code with degraded identity/capture evidence. Historical runs without
a ledger retain the log view; missing evidence is not reconstructed.

Atomic JSON publication first uses the run directory. Windows reports a real
temporary fallback if that directory is blocked; native terminal export has an
independent temporary fallback. If both fail, output says unavailable rather than
advertising a nonexistent JSON file. These are durability boundaries, not a promise
against abrupt power loss, disk loss or termination of the parent itself.

## Identity and maintenance policy

Explorer-token launching accepts exactly one Explorer in the caller's positive
session, with the caller's SID, medium integrity and no elevation. The process
handle binds token inspection to its process instance. No active-console or
arbitrary-Explorer fallback remains. Native token checks fail closed on inaccessible
identity. The generated worker verifies its own SID/session/integrity/elevation
before starting maintenance, and records its process identity and observed native
child result. SYSTEM/cross-session user launching is an intentional unsupported
boundary, not an implicit user broker. Steam retains its existing separate desktop
validation, exact-title, running-game and queue mutex protections.

Generic deferred PowerShell upgrades are blocked pending refreshed channel,
registration and installer-technology evidence. No owner migration, uninstall or
reinstall is a reporting repair. Native apt preserves its configured feed/channel.
Absent OpenCode stays absent; V1 migration is blocked in ordinary maintenance.
Existing locks and active-session protection remain in force.

Ordinary npm updates do not write `.profile`, `.bashrc` or npmrc. Process-local PATH
adjustment remains explicit. Malformed discovery JSON and exhausted self-update
targets are failures. Engine/script-policy warnings are retained as warnings, not
proof of a broken addon and not permission to broaden trust. Compound pnpm, Conda,
Gem and Composer commands preserve the first failure instead of accepting a later
success. Relevant active npm consumers or unavailable ownership visibility block
mutation rather than stopping services or deleting shims.

Windows Update normalizes batched logical records, retains phase output and exact
identity-scoped installs, and does not start install after an unknown download
terminal phase. Accepted-only and missing terminal results are unresolved. An
InstalledWithErrors result is not clean success. These fixtures do not reproduce
an independently reported pending-update incident.

Steam manifest reads are bounded, shared and non-mutating. The reader rejects
unstable/incomplete snapshots after bounded retries. It does not issue another
download or interpret one read failure as an absent installation. Queue acceptance,
downloading and completion retain their existing distinctions.

## Consumers and remaining acceptance

Legacy Ninja/event/reporting row counts remain compatibility fields, not confirmed
package-change counts. The new panel is for people and manual diagnosis; consumers
should parse the versioned ledger instead of scraping its decoration. Existing
Ninja wrapper classification and any WatchCode parser/source-integrity enrollment
need review against the candidate before a pilot. No controller, enrollment hash,
lease, mutex, scheduled task or sync setting is changed by this source work.

No new universal cross-controller maintenance lock is claimed. Existing scheduler
IgnoreNew/flock and Steam's local mutex retain their scopes; they do not serialize
every manual invocation or independent installer. Worker IDs prevent duplicate
launch within a run. Cross-run overlap and coordinated controller ownership remain
pilot/review gates. Unknown package ownership, missing backend delta evidence,
AppX activation, native service-restart attribution and host-specific registration
problems are explicit remaining acceptance, not reasons to repair a host here.

Release flavor: Yoda, *Star Wars: The Empire Strikes Back* (1980), with matching
Yoda text art on Windows/native Linux. Quote attribution was checked against
[StarWars.com](https://www.starwars.com/news/8-great-life-teachings-from-yoda).
