# Reparo 1.4.4.13

This release adds automatic device/update reporting during install, self-update
and normal maintenance on Windows and native Linux. No enrollment command or
token entry is required. Each installation creates a random identity and its
own protected credential; no fleet secret is distributed in public source.

The private registry records supported device facts, versions, update results,
schedule observations and maintenance summaries. Unknown or unsupported values
stay unknown. A fresh successful installation records its first-install date
once, while existing installations without reliable history keep that date
unknown. Server first-seen/last-seen and Cloudflare-observed network metadata
remain separate from self-reported facts. See [the30field reference](automatic-registry.md).

Reports are bounded, queued briefly offline, and best effort. They cannot block
successful installation/update/maintenance, execute server commands, create a new
heartbeat service or change updater trust. Utility/version/help/preview commands
do not report. Set `REPARO_REGISTRY_DISABLE=1` to opt out; isolated test suites use
`REPARO_REPORT_SKIP=1` and synthetic data.

The normal updater continues to validate the reviewed GitHub manifest and exact
immutable commit/hash/version, prefers the file-server payload mirror, and uses
the exact approved GitHub artifact on availability failures. GitHub releases and
the file-server version directory must contain identical downloadable bytes.
Bad bytes/syntax/version still stop the update.

Release flavor: “I can bring you in warm, or I can bring you in cold.” — Din Djarin,
*The Mandalorian*, Season1, Chapter1 (2019). Matching art uses the Mandalorian
helmet/T-visor. Attribution checked against [Lucasfilm's official quote list](https://www.starwars.com/news/20-favorite-quotes-the-mandalorian-season-one).

Publishing does not install on a live endpoint or run maintenance. The previous
1.4.4.12 source/manifest remains the rollback anchor after this separate reviewed
production-pin promotion. Local Windows/Linux checks are the default; hosted
GitHub workflows remain available as optional manual runs.
