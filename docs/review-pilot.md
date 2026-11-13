# Review, release and rollback gates

Release 1.4.4.9 promotes reviewed source to `deploy/reparo-release.json` in a
separate immutable pin transaction. `deploy/reparo-candidate.json` retains the
earlier review pin. Ordinary installed `-New` uses the production manifest;
publication does not itself run an installer or maintenance. Review and test
future source/pin transactions using the same sequence below. Endpoint deployment,
controller reenrollment and maintenance remain separate scoped actions.

1. Review the exact source/test/doc commits and platform receipts. Confirm no
   private evidence or host data entered the public diff. Existing PR CI uses
   hosted disposable Windows/Ubuntu runners and isolated fixtures; it does not
   publish a release, install on a live endpoint or run real maintenance.
2. Review schema/exit/console compatibility with Ninja and WatchCode. Keep local
   enrollment state and source-integrity settings unchanged. Prepare explicit
   reenrollment for reviewed final artifact bytes; never bypass enrollment.
3. Obtain explicit merge/release authorization. Merge reviewed commits, verify the
   immutable source commit and all three artifact SHA-256 values, then promote a
   coherent production manifest in a separate pin transaction. Source commits
   precede the pin; do not publish a self-referential hash or a nonexistent URL.
   Confirm both platforms' version, fresh attributed quote and matching art.
4. Obtain a separate scoped pilot/deployment authorization. Retain the installed
   runtime, manifest, settings, version locks, shim and exact task definitions.
   Test the canonical Windows offline transaction in a disposable root with
   machine PATH/task effects mocked before using the normal offline installer on
   an explicitly selected endpoint. Native HTTPS installation uses isolated
   HOME/XDG/TEMP and mocked cron. An installation fixture is not a live pilot.
5. Pilot the selected Windows lane and a separately authorized native lane with
   literal argv, execution owner, source hash, actual exits, stream health,
   installed-version deltas, restart/activation consequences and deferred terminal
   evidence. Preserve running sessions and remote access. Other hosts can remain
   offline until their own scoped pilot. Do not rerun a full batch for evidence.
6. Accept only independently observed results. Keep missing exits, unknown owner,
   unverified capture and pending downloads/workers visible. No reboot, service
   restart, feed/channel/trust change, package reinstall or host repair is implied.

For runner rollback, retain and select the previously reviewed immutable manifest
and use the supported installation transaction after reconciling newer settings.
Keep new-schema evidence and worker receipts even if the reader is rolled back.
Do not reset a controller or restore somebody else's lock. The rollback artifact
for 1.4.4.9 is the retained published 1.4.4.8 manifest/source pair.
Do not confuse the current production pin with that previous rollback anchor.

Runner rollback does **not** undo installed OS/driver/npm/apt changes or Steam
downloads. Those require their own owner-specific recovery and approval. Killing
an installer, stopping a service, reinstalling a package or rebooting is not a
rollback shortcut. Fleet rollout remains separately gated after narrow pilots.
