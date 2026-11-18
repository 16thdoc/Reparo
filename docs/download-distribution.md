# Reviewed downloads through the public file service

The prepared 1.4.4.12 bridge uses `file.thetechnologist.io` for reviewed artifact
bytes. The independently reviewed channel remains
`https://raw.githubusercontent.com/16thdoc/Reparo/main/deploy/reparo-release.json`.
Its schema, lowercase full source commit, exact GitHub artifact URLs, uppercase
SHA-256 values and embedded versions remain mandatory. A manifest cannot choose
an arbitrary mirror host or change its artifact path.

After validation, clients derive only these URLs:

```text
https://file.thetechnologist.io/reparo/<40-hex-source-commit>/Reparo.ps1
https://file.thetechnologist.io/reparo/<40-hex-source-commit>/install-reparo-linux.sh
https://file.thetechnologist.io/reparo/<40-hex-source-commit>/reparo-linux
```

Windows `-New`, the standard CMD/SSH bootstraps, native self-update and the native
installer use the mirror. Existing explicit custom-source, offline install and
latest/unpinned lanes retain their existing trust boundaries. Current installed
clients can fetch this bridge from the unchanged GitHub-only manifest; their next
reviewed payload request uses the mirror. No existing client is stranded by a
manifest URL it does not understand.

## Availability and integrity

A transport or HTTP availability failure may retry the **exact original validated
GitHub artifact**. The client warns that the mirror observation was omitted.
Reviewed payload attempts have 60-second bounds (Linux also uses a 10-second
connection bound). If the mirror returns bytes, the existing size/hash/syntax/
version checks run before install or replacement. Bad bytes or local write failures
are fatal; they do not get concealed by a successful fallback. HTTPS certificate
verification is never disabled.

## Reporting interpretation

Requests identify only one fixed client class through User-Agent:
`Reparo-Download/Windows/Update`, `Reparo-Download/Windows/Install`,
`Reparo-Download/Linux/Update`, or `Reparo-Download/Linux/Install`. No device ID,
username, hostname or install-result beacon is added. Client classes are forgeable
and are suitable for coarse request classification only.

The file service can report artifact GET requests, HTTP status, server response
bytes, version/commit and declared platform/action. HTTP 206/range responses and
retries remain separate observations. Manifest/HEAD/site requests, GitHub fallback,
direct GitHub downloads and older/offline clients limit coverage. Counts do not
prove unique devices, people, complete downloads or successful installations.

IP/location reporting, retention and private access are owned by the file service
and the separately governed Analytics lane; this runner change does not enable
optional enrolled installation/maintenance reporting or resume Graylog work.

## Release order

1. Review/test the source, cross-platform flavor and isolated failure fixtures.
2. Commit source first and pin that exact source in a separate candidate manifest
   commit. Keep the production manifest unchanged during PR review.
3. Publish and hash-verify all three candidate artifacts under their full source
   commit on the public file server **before** any production pin promotion.
4. Obtain explicit merge/release authorization under `docs/review-pilot.md`, then
   promote the reviewed production manifest through the usual separate transaction.
5. Obtain separately scoped endpoint pilot/deployment authorization. No fleet
   maintenance, reporting enrollment, package upgrades or reboot is implied.

Keep the prior production manifest/artifacts for rollback. The file service's
operator publisher refuses overwriting an existing immutable commit namespace.

The new version flavor uses Han Solo's “Sorry about the mess.” from
*Star Wars: A New Hope* (1977), with matching DL-44 blaster ASCII art.
[Primary quote reference](https://www.starwars.com/databank/han-solo).
