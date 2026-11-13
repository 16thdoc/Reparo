# Windows Slicer management

Reparo 1.4.5.0 source adds a thin Windows consumer of the standalone Slicer owner.
Public source contains only loader/protocol code and reviewed metadata. It contains
no private Slicer source, ZIP, encoded payload or credential. Source preparation is
not production-pin promotion, installed deployment or fleet acceptance.

## Select an action

```powershell
reparo -Slicer Status -SlicerJson
reparo -Slicer Check -SlicerUnattended -SlicerJson
reparo -Slicer Update -Preview -SlicerJson
reparo -Slicer SelfTest -SlicerJson
```

`-Slicer` accepts Status, Check, Install, Update, Repair and SelfTest. The explicit
mode returns before ordinary Reparo logging/maintenance and rejects conflicting
execution modes or section selection before acquisition. Other Slicer options are
prefixed so they do not silently become general Reparo arguments:

| Option | Meaning |
| --- | --- |
| `-SlicerInstallRoot` | Standalone runtime target; defaults to ProgramData/Slicer |
| `-SlicerOwnerCacheRoot` | Owned private control-code cache; default is LocalAppData/Reparo/SlicerOwner under the immutable owner commit |
| `-SlicerVersion` | Reviewed runtime version; default 0.2.4 |
| `-SlicerPackageZip` | Explicit local runtime ZIP; pair with `-SlicerExpectedSHA256` and an exact version |
| `-SlicerPackagePath` | Explicit trusted local runtime source, delegated to the owner |
| `-SlicerUnattended` | Noninteractive owner operation, subject to its existing gates |
| `-SlicerNoPathUpdate` | Do not update PATH during an authorized isolated/runtime operation |
| `-SlicerJson` | Structured stdout; preserves real owner receipts and exact exit status |

Existing `-Preview` is dry-run. Explicit Slicer mode maps `-Force` to the owner,
which still enforces trust, downgrade, path, elevation and mutation guards. There is
no token argument.

Status without a candidate is offline and reports Currentness Unknown. SelfTest is
local-only and never implies provider authentication, connectivity or scan
acceptance. Neither action acquires missing private code. If a verified owner is
unavailable, the consumer returns its own truthful blocker instead of fabricating
an owner receipt or downloading code. Explicit Preview performs no authentication,
network or cache mutation, including when no owner exists; that case returns an
adapter plan.

Check maps to the owner's Status comparison with the selected published or local
candidate. Online Check and lifecycle actions may acquire the verified portable
owner. Local ZIP/path inputs delegate to Manage-Slicer; the online route delegates
to Bootstrap-Slicer. Bootstrap remains the sole runtime-release acquisition and
lifecycle owner. The Reparo loader is not a second Slicer installer.

## Normal maintenance stays installed-only

Normal Windows `-Update`, `-Force` and explicit `-Include Slicer` select the Slicer
section only for an existing installation. An absent Slicer stays absent without
auth, network or cache acquisition. Invocation with no mode remains Windows Update
only. First installation requires explicit `-Slicer Install`, normal owner
elevation and the applicable authorization; normal Force does not grant an owner
downgrade or trust bypass.

The section retains the original owner receipt and records an honest Reparo
outcome. Current/no-op is not Updated. Same-version repair is not a version change.
Failed rollback and uncertain invocation/capture remain failures with retained
evidence. Independent sections can continue while this backend reports its exact
blocker; an unavailable private credential is not permission to borrow another
execution identity's access.

## Private cache and approved access

The reviewed portable owner is exactly these three files at immutable Slicer commit
`8f363032e6837605e6c91ec866ccc06a45362506` (v0.2.4):

| File | Compiled SHA-256 |
| --- | --- |
| Manage-Slicer.ps1 | `35a257def78bb614a8a0ac8c7440958e8ea3827ef8be7b62ab19082ad4d6c48b` |
| Slicer.Management.psm1 | `e9e2995570bb9590c88dfc8058751d8094066693dd3eb656e4c1e2e0f80da0a8` |
| Bootstrap-Slicer.ps1 | `3a8efa8191f617e2955d6a1cc24b4bf691e72321ea96a00823e13e5189c0200d` |

Fetch only the fixed GitHub Contents/raw endpoints at that commit, bound sizes and
verify exact Git-LF bytes against the compiled pins. Mutable remote metadata does
not replace these expected hashes. Public fixtures must use synthetic owner code;
they must not vendor the real private payload or require private access in CI.

Protect the owned local cache for the current identity, SYSTEM and Administrators
before private bytes are written. It must remain outside Git worktrees and runtime
overlap, with no links, reparse points or unsafe roots. Reject incomplete,
tampered/unverified caches and unexpected file sets/provenance. Stage and publish
atomically with concurrency protection, then recheck hashes before and in the
trusted child so partially replaced bytes cannot execute. Force cannot weaken
these checks.

Access uses an existing GH_TOKEN/GITHUB_TOKEN or noninteractive GitHub CLI
authentication, in memory only. Do not log transport authorization, pass tokens in
argv, persist tokens, prompt for login, unlock a vault or provision credentials.
Do not reuse another user's or SYSTEM's cache/access. Acquisition failures must
retain sanitized evidence without exposing authorization headers or raw secrets.

The trusted native PSHOME child receives encoded request data, never interpolated
code/argument values. The consumer preserves stdout, stderr, exit and capture
uncertainty; it does not force-terminate an active owner transaction. Valid original
schema-1 owner receipts pass through unchanged. Consumer blockers/plans use
`reparo.slicer.adapter.v1`, not a counterfeit owner schema. Check therefore returns
the owner's Action Status when comparison succeeds.

## Native Linux boundary

Slicer has no native Linux backend here. `--slicer`, `-Slicer` and bare `Slicer`
reject in any casing, as does Include Slicer through the native Include aliases.
The runner exits 2 with a clear Windows-only message before maintenance,
authentication, logs, private cache, tasks or privilege operations. Preview, Force,
task and installer combinations do not change that boundary. No PowerShell
dependency is added. Native Windows/Linux release number, quote/source and matching
art remain synchronized.

`Tests/test-reparo-linux-slicer.sh` exercises rejection with isolated HOME/XDG/TEMP
and fail-closed operational executables, checking unchanged filesystem state and
no calls to transport, package, privilege, task or logging tools. Existing native
manager behavior remains governed by its own tests.

## Publication, deployment and acceptance

The canonical single-script offline Reparo `-Install` copies the executing
Reparo.ps1; neither it nor `-Version` requires adjacent private files or acquires
Slicer. Public source publication precedes a separate coherent immutable
production-pin transaction; retain production/candidate/rollback history instead
of publishing self-referential or nonexistent artifact URLs.

[Review and pilot gates](review-pilot.md) still require the applicable merge/release
and separately scoped endpoint authorization after a concrete reviewed result.
Run the disposable canonical offline-install fixture with machine integration
mocked before any selected endpoint pilot. Default ProgramData Reparo installation
can update the shim/PATH and SYSTEM self-update task; preserve exact definitions,
settings, version locks, enrollment and source-integrity state and observe those
effects rather than describing it as a source-only update.

Public source tests, hosted CI, real private acquisition, installed Reparo and
actual Slicer lifecycle acceptance are distinct evidence. Private acceptance uses
external artifacts and already approved access, an isolated runtime/config/PATH,
and no provider/scan or production Slicer change. MaraJade's production Slicer
0.2.2 replacement retains its existing normal-elevation gate. Full fleet rollout,
real provider/scan acceptance and any protected task transition remain outside
source preparation.
