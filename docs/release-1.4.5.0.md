# Reparo 1.4.5.0 source candidate

This capability source adds a Windows thin consumer of the private standalone
Slicer owner. It does not itself promote the production manifest, install Reparo
on an endpoint, upgrade production Slicer or complete fleet acceptance. Existing
production/candidate/rollback pins remain separate until an approved coherent pin
transaction; see [review and pilot gates](review-pilot.md).

## Behavior

- Explicit `-Slicer Status|Check|Install|Update|Repair|SelfTest` has dedicated
  prefixed options and returns before normal maintenance/logging. It preserves
  real owner receipts/exits and distinguishes consumer plans/failures.
- Normal Windows `-Update`, `-Force` and `-Include Slicer` maintain only an
  already installed Slicer. No-mode invocation stays Windows Update only; first
  Slicer installation requires its explicit action and applicable owner gates.
- Public Reparo contains loader code and fixed immutable metadata, never the
  private three-file portable payload, runtime ZIP, embedded code or credentials.
  Approved private access acquires the complete hash-verified owner into a
  protected local private cache. Offline Status/SelfTest do not acquire missing
  code; Preview does not authenticate, download or mutate the owner cache.
- Native Linux explicitly rejects Slicer selectors/Include before operational
  work. There is no Linux Slicer implementation or new PowerShell dependency.
  Both platforms retain the same release identity and version-output flavor.
- Single-script offline Reparo Install and Version stay independent of adjacent
  private files and do not acquire Slicer.

Details and constraints: [Slicer management](slicer-management.md).

## Release flavor

Quote: "Always in motion is the future."

Source: Star Wars: The Empire Strikes Back (1980), Yoda.

Matching art: `  <(-_-)>  YODA ~ future in motion`.

Attribution was checked against the [official Yoda teaching collection](https://www.starwars.com/news/8-great-life-teachings-from-yoda).
The existing Windows/native Linux parity regression checks version, quote, source
and art; historical release entries remain available.

## Verification and remaining gates

Public validation must use synthetic protocol/acquisition/cache fixtures and cover
both supported Windows engines, early native rejection, argument/receipt/exit
truth, preview/offline behavior, credential/path/link/hash/concurrency failures,
normal selection/ledger behavior and canonical single-script offline install with
host integration mocked. Run relevant existing regressions and hosted CI against
the reviewed source; fixtures are not installed or fleet acceptance.

Only after the source and immutable pin transactions have their applicable
authorization may a separately scoped endpoint pilot use the canonical offline
installer. Preserve installed runtime, settings, shim/PATH, exact schedules,
enrollment and source-integrity boundaries, and retain rollback/evidence. Actual
private-owner acceptance belongs in external private artifacts; no public fixture
may depend on that access or contain those bytes. No provider, scan, new
credential provisioning, broad rollout or protected completion is claimed here.
