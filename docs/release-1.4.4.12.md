# Prepared Reparo 1.4.4.12

Reviewed Windows/Linux bootstrap and self-update payloads use the public
`file.thetechnologist.io` artifact service so their requests can be observed.
GitHub remains the independently reviewed release manifest and hash/commit anchor.
Old clients remain compatible during the transition. No production channel change
or installed-endpoint rollout has been performed by preparing this candidate.

The mirror URL is derived only from a validated full commit and fixed filename.
Transport failures can use the exact validated GitHub artifact with an explicit
observation-omission warning. Corruption, syntax/version mismatch, invalid commit,
foreign host and local-write failures remain fail-closed.

See [distribution and release order](download-distribution.md) for analytics limits,
immutable mirror publication, cross-platform checks and approval/pilot gates.
