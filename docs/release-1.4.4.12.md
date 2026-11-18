# Reparo 1.4.4.12

Reviewed Windows/Linux bootstrap and self-update payloads use the public
`file.thetechnologist.io` artifact service so their requests can be observed.
GitHub remains the independently reviewed release manifest and hash/commit anchor.
Old clients remain compatible during the transition. The production manifest pins
reviewed source `a20b1ac5e06802591a7b4f10fa7a10b50f674ca0` after the separate
source/candidate review in PR #9. All three mirror payloads match its hashes.
Endpoint pilots and deployment remain separately authorized; publishing this
release does not itself run maintenance or install on a live endpoint.

The mirror URL is derived only from a validated full commit and fixed filename.
Transport failures can use the exact validated GitHub artifact with an explicit
observation-omission warning. Corruption, syntax/version mismatch, invalid commit,
foreign host and local-write failures remain fail-closed.

See [distribution and release order](download-distribution.md) for analytics limits,
immutable mirror publication, cross-platform checks and approval/pilot gates.

Validation passed in hosted Windows/Ubuntu CI, isolated Windows PowerShell5.1/7
and native Linux mirror/failure fixtures, release parity, security/TLS and offline
installation/rollback tests. Counts are request observations, not successful
installation receipts. Existing 1.4.4.11 Windows clients fetch this bridge from
GitHub first; later reviewed payload requests use the mirror. An old native
runner fetches the new installer from GitHub, then that installer can already
fetch the reviewed runtime from the mirror during the same update. Cached old
installers keep their previous behavior until refreshed.

Rollback anchor: retained production1.4.4.11 source
`88683359c0b311f17b831938daca3e5e0e51c02b` and its original manifest/artifacts.
