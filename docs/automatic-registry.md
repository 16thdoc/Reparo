# Automatic device and update registry

Reparo reports a small, allowlisted device snapshot during installation,
self-update and normal maintenance runs. There is no enrollment command, token
to paste, separate setup wizard, background heartbeat or additional schedule.
The fixed collector is `https://file.thetechnologist.io/api/reparo/v1/report`.
The owner reads the registry behind Cloudflare Access at
`https://file.thetechnologist.io/private/reparo-registry/`.

Each installation and execution-owner scope creates a random ID and a separate random reporting credential
in protected local state. The first valid report creates an **unverified,
self-reported** registry entry. Later reports require that installation's
credential. This prevents another caller from overwriting an existing entry by
knowing its ID; it does not attest hardware or prove a hostname/domain claim.
Windows machine and ordinary-user contexts can have separate protected identities;
native Linux state belongs to its executing user. The reporting scope is shown
explicitly. One physical machine can therefore have multiple records: this is
not a unique physical-device counter. Do not distribute the local identity file in a golden image: copies of that
state share the same identity. A reinstall with new state creates a new entry.

Reporting is best effort. An unavailable collector, unsupported probe, invalid
local state or reporting error cannot turn successful maintenance or an update
into a failure. Missing facts are `null`, rather than a fabricated value or an
unsupported `false`. Offline receipts are bounded; reporting is not a durable
audit trail or evidence that a package installation completed.

Set `REPARO_REGISTRY_DISABLE=1` to disable this reporting. Existing
`REPARO_REPORT_SKIP=1` also suppresses it for isolated fixtures. See the public
[privacy notice](https://file.thetechnologist.io/privacy.html). The older optional
Node reporting prototype is separate and remains compatible with its own config.

## The 30 useful records

| # | Record | Source and interpretation |
| --- | --- | --- |
| 1 | Installation ID | Random per-install identity; no hardware fingerprint. |
| 2 | Machine name and FQDN | Local device reports; not independently confirmed. |
| 3 | Organization/customer | Unknown unless explicitly supplied by an existing supported configuration. A domain is not automatically a customer. |
| 4 | Site and asset label | Unknown unless known; no prompt during a run. IP labels remain separately editable in the private traffic-label UI. |
| 5 | First successful Reparo install | Recorded only after a genuinely fresh successful installation. |
| 6 | Server first seen | First accepted report, not a recovered installation date. |
| 7 | Server last seen | Last accepted report; offline machines do not send heartbeats. |
| 8 | Installed version | Version read from the local installed runtime, when available. |
| 9 | Last version executed | Version of the reporting runtime. |
| 10 | Source commit and SHA-256 | Actual source digest; commit only when supported by matching local integrity metadata. |
| 11 | Version history | Retained accepted events and version transitions; gaps remain possible. |
| 12 | Last self-update attempt | Accepted update-attempt event. |
| 13 | Last successful self-update | Accepted successful update result, separate from a download request. |
| 14 | Update outcome and failure stage | Structured result; no raw installer logs. |
| 15 | Update duration | Measured operation duration where supported, otherwise unknown. |
| 16 | Download source/channel | Observed mirror, exact GitHub fallback, offline or latest path; unknown when not measured. |
| 17 | OS family and edition/distro | Local OS facts. |
| 18 | OS version and build | Local OS facts; Windows OS install date is not Reparo install date. |
| 19 | Architecture | Reported runtime/system architecture. |
| 20 | AD/realm join state | Local supported probe; unsupported/failed probes stay unknown. |
| 21 | Domain or workgroup | Self-reported local membership, not authentication to that domain. |
| 22 | Entra join state | Windows device state where readable; unsupported on native Linux. |
| 23 | Public IP and network label | IP and coarse country/region/city observed at Cloudflare, separate from device facts. Existing exact-IP Home/Work labels can annotate it. |
| 24 | Last boot and uptime | Local boot/uptime observations. |
| 25 | Pending reboot | Supported local evidence; not a universal cross-platform guarantee. |
| 26 | Self-update schedule health | Supported schedule presence/state, next due and last result where available. |
| 27 | Last maintenance run | Accepted maintenance-result event and client time. |
| 28 | Maintenance results | Supported manager counts; unavailable counts remain unknown, not zero. |
| 29 | Reporting health | Bounded local queue/retry/last-success facts when available; automatic identity, no enrollment task. |
| 30 | Install/system volume free space | Available and total bytes from the local supported volume. |

Client UTC event times and server receive times are stored separately. Incorrect
client clocks and delayed delivery can affect ordering. The earliest **observed**
event is not evidence of a machine's original installation date.

Windows maintenance counts describe Reparo summary result records, rather than a
guaranteed number of packages. Native Apt counts use observed package-version
deltas only when capture is complete; unsupported manager counts stay unknown.

## Installation date and retained history

A new successful fresh install records its first-install timestamp and provenance
once. Updating Reparo preserves that date. Existing copies with no trustworthy
metadata report unknown first-install date; their new server first-seen date is
still useful. Runtime file timestamps, the current update time and Windows OS
installation date must never be substituted for Reparo's original install date.

Registry event retention is separate from the 30-day download-request reports.
The collector retains bounded event history for 90 days and keeps the latest
device snapshot until explicit deletion/capacity handling. History is incomplete
when clients are offline, reporting is disabled, queues expire or capacity/rate
limits reject reports. The protected operator documentation defines storage,
backup and deletion procedures.

## Distribution stays coherent

GitHub retains the current release and all three directly downloadable runtime /
installer assets. The normal updater obtains the reviewed GitHub manifest,
validates its immutable commit, fixed paths and SHA-256 values, then prefers
`file.thetechnologist.io/reparo/<full-source-commit>/<artifact>` for payloads.
Availability failures may use the exact validated GitHub artifact. Incorrect
bytes, syntax or version fail closed. Reporting does not change those gates.

Publish and verify source-commit mirror files **before** promoting a production
manifest. Publish the same bytes in the GitHub release and human-version mirror,
including the manifest and checksum list. Verify both distributions against the
same immutable source and preserve the preceding release for rollback.
