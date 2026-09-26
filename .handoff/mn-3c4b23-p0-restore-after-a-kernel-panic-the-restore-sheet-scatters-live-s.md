---
workflow: 2
manna: mn-3c4b23
track: mn-eb7a80
source: Erik 2026-09-26 11:37 with screenshot; zone-watch samples; sessions table
base_commit: 962f13ad23c8f022a2b5d44d29de8085c36339de
scope: '[P0][RESTORE] After a kernel panic the restore sheet scatters live sessions into older groups, hides some, and records no restore run'
inputs:
- Erik 2026-09-26 11:37 with screenshot; zone-watch samples; sessions table
binding: sha256:5d240af3f88009f11dc80522f56b72cfb6cc91aabb27029c5421c1ff8735125a
---

# Handoff: [P0][RESTORE] After a kernel panic the restore sheet scatters live sessions into older groups, hides some, and records no restore run

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-3c4b23
```

## Scope

[P0][RESTORE] After a kernel panic the restore sheet scatters live sessions into older groups, hides some, and records no restore run

## Inputs

- Erik 2026-09-26 11:37 with screenshot; zone-watch samples; sessions table

## Work order

Receipt 2026-09-26 11:25 after the 06:16 kernel panic (boot epoch 1790421414): the sheet showed 5 interrupted by the last shutdown plus 38 older in 11 shutdown groups, while the fleet at the panic held 39 tmux sessions (zone-watch samples.tsv, tmux_process_count at 05:47). Egora, SubDub, and Yed Prior were live at the panic and appeared nowhere in the fresh section; Erik re-created them by hand at 16:34Z (sessions A3A93E22, 8202FBC3, F338E42E). The 12-session group two days ago is the 09-24 18:04 relaunch (installer kill); rows adopted from tmux after that relaunch never got a new interruption record, so the panic left them in the old group. Freshness is decided by the adapter that builds rows (HolyRestoreEngine.swift:349-384 plannedRow isFresh) and HolyRestoreCrashGrouping.groups(from:) only subdivides older. Deliver: (1) freshness keyed on reality: every session whose tmux server died with the last boot, or that was live at the last app exit, is interrupted by the last shutdown, whatever its last interruption record says; kern.boottime or an equivalent boot identity is the authority for a panic; (2) a session live at any relaunch gets its interruption record renewed so adoption never strands it; (3) a restore run is recorded as a history entry (when, how many rows, which ids, outcomes and errors) and the Session History sheet shows it; Erik restored about 38 sessions today and history shows nothing; (4) a row whose working directory no longer exists names the source of the path and still offers restore into the last known valid directory from resume metadata when that exists (row 985BC829 today: /Users/erik/Custom-Coding/Research Comprehensive App Security | Custom-Coding). Tests: grouping fixtures for panic, clean quit, and installer relaunch; history entry written and rendered. Own macos/Sources/HolyGhostty/Restore/, macos/Sources/HolyGhostty/Workspace/HolySessionHistorySheet.swift, the restore-related regions of macos/Sources/HolyGhostty/Workspace/HolyWorkspaceStore.swift, and their tests; do not touch Archive/ or Board/. Related open items mn-569b91, mn-12801a, mn-56f896.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-3c4b23`.
4. Commit with `Manna: mn-3c4b23` and run `agent-do manna done mn-3c4b23` only after the work is verified.

## Report

Lane worker, worktree of main at 3cf78d258, 2026-09-26. Boot identity of the panicked machine, read with `sysctl` at 12:0x: `kern.boottime: { sec = 1790421415, usec = 985376 } Sat Sep 26 06:16:55 2026`, `kern.bootsessionuuid: 40962879-B7EE-4F13-AF6E-E7266EF5E732`. The live database was not read (the tool classifier refused the copy), so the 09-26 mechanism is the work order's, not re-derived here.

### What changed, file by file

New, `macos/Sources/HolyGhostty/Restore/`:

- `HolyBootIdentity.swift`: `kern.bootsessionuuid` (the identity: minted once per boot) and `kern.boottime` (the instant) read from the kernel; `isSameBoot` compares the UUID, falling back to the boot second only when a side lacks the UUID; unknown is never "same boot".
- `HolyRestoreLivenessLedger.swift`: the ledger the app writes of what it last saw live (source id, title, local/remote, tmux socket and session name), the boot it ran under, `recordedAt`, `cleanExitAt` (orderly quit only), and `lastInterruptionBatchID` (carried across relaunches in one boot). `HolyRestoreLivenessLedgerStore` keeps it as `restore-liveness-ledger.json` next to the database, written temp-file + `F_FULLFSYNC` + rename, deliberately outside SQLite. `HolyRestoreFileCoding` is the shared coder (epoch-second dates, exact round trip) and durable-write primitive.
- `HolyRestoreFreshness.swift`: `HolyRestoreShutdownKind` (reboot / cleanQuit / appRelaunch), `HolyRestoreShutdownEvent` (kind, both boots, last-seen-live time, clean-exit time, live count, the interruption batch, interrupted source ids, renewed archive ids, a `summary` for the header), and the law `HolyRestoreFreshness.reconcile(...)` described below.
- `HolyRestoreRunLog.swift`: `HolyRestoreRunRecord` (id, startedAt, finishedAt, trigger, attach, one `RowResult` per requested row: archive id, source id, title, runtime, working directory, resumed provider session id, outcome restored(attached)/failed(reason)/skipped(reason); derived counts and `errors`). `HolyRestoreRunLogStore` keeps `restore-runs.json`, newest first, no cap.
- `HolyRestoreWorkingDirectory.swift`: `HolyRestoreWorkingDirectoryResolution`: every recorded directory in evidence order (last known directory from resume metadata, launch directory, git worktree, repository root; only when all are gone, the parent of the last known / launch directory), existence checked, first existing one chosen, `displayLine` naming the source and the path that no longer exists, `missingReason` naming every source.

Edited:

- `Restore/HolyRestoreModels.swift`: `HolyRestoreRowState.skipSummary` (why a pass left a row alone, for the run record); `HolyRestorePreflightContext.workingDirectoryResolution` (optional, defaulted, so existing callers and tests keep compiling).
- `Restore/HolyRestorePreflight.swift`: the missing-directory verdict names every recorded source when a resolution is present; the single-path message stays for contexts without one.
- `Restore/HolyRestoreEngine.swift`: adapter protocol gains `lastShutdown` and `recordRestoreRun` (protocol-extension defaults keep other fakes compiling); `HolyRestoreRow.workingDirectoryResolution` + `workingDirectoryDisplay`; plan computes the resolution, preflight re-resolves each pass and passes it into the context; `restore(rowIDs:attach:trigger:)` carries a trigger (restoreAll / restoreSelected / restoreShutdownGroup / retry / attach) and after the bounded pass calls `recordRun`, which builds one `HolyRestoreRunRecord` from every requested row's phase and state and hands it to the adapter (nothing recorded when nothing was requested); `restoreExact`/`recreate` launch into the resolution's path; `resolvedWorkingDirectory` replaced by `workingDirectoryResolution(archived:plannedLaunchSpec:directoryExists:)`; `engine.lastShutdown` passthrough.
- `Restore/HolyWorkspaceRestoreAdapter.swift`: forwards `lastShutdown` and `recordRestoreRun` to the store.
- `Restore/HolyRestoreSheet.swift`: fresh section header is `freshSectionTitle(shutdown:)`: "Interrupted by the last shutdown · rebooted Sep 26, 2026 at 6:16 AM" / "· quit cleanly …" / "· app relaunched without a clean quit"; the row's directory line shows the resolution (warning hue and two lines when a fallback was used or nothing exists, tooltip with the full line).
- `Workspace/HolySessionHistorySheet.swift`: a "N restore runs" disclosure under the restore callout with the latest run inline; each run opens to one line per row (title · outcome · conversation id · directory), failed rows in danger, skipped in tertiary; pure signage `restoreRunsHeader`, `restoreRunTitle`, `restoreRunRowLine`.
- `Workspace/HolyWorkspaceStore.swift` (restore regions + one init parameter), `init(..., restoreStateDirectory: URL = HolyDatabasePaths.containerDirectory)`; `restore()` calls `reconcileRestoreFreshnessAtLaunch(launchStartedAt:)` right after `applySessionStoreState` and before the launch persist; new region: `@Published lastShutdown`, `@Published restoreRuns`, `reconcileRestoreFreshnessAtLaunch` (loads the previous ledger once, seeds the observed-live set from the roster, reconciles, loads the run log, writes this boot's ledger, installs observers), idempotent `reconcileRestoreFreshness()` (also run by `presentRestore()` before `buildPlan`, persisting when it changed anything), the ledger writer (from the published session array, `@Published` delivers the new value in `willSet`), observers on roster membership changes (rewrite only when the id set changed) and on `NSApplication.willTerminateNotification` (writes `cleanExitAt`), `recordRestoreRun`, `applySessionStoreStateForTesting`; `crashRestoreBatch(from:freshBatchID:)`, fresh is exactly the known batch, possibly empty, never an older group promoted by recency; the instance property uses `lastShutdown?.interruptionBatchID`.

Tests (new, `macos/Tests/HolyGhostty/`): `HolyRestoreFreshnessTests.swift` (reconcile fixtures for panic, clean quit, installer relaunch, no ledger, observed-live exclusion, remote exclusion, idempotence, empty reboot, header title; batch scoping; boot identity; ledger file round trip; one app-hosted store test), `HolyRestoreRunLogTests.swift` (engine records restoreAll/restoreSelected/retry/attach/shutdown-group runs with outcomes and errors; file round trip; history signage), `HolyRestoreWorkingDirectoryTests.swift` (row 985BC829 shape, evidence order, parent fallback, dedupe, preflight messages, engine restores into the fallback and the row names it).

### xcresult counts

Run 1, `/tmp/mn-3c4b23-1.xcresult` (serial, `xcrun xcresulttool get test-results summary`): result Passed, 149 passed, 0 failed, 0 skipped (169 runs counting parameterized cases). Per suite from `get test-results tests`: HolyCrashRestoreBatchScopingTests 8, HolyRestoreBootIdentityTests 3, HolyRestoreCrashGroupEngineTests 12, HolyRestoreCrashPartitionTests 5, HolyRestoreEngineTests 35, HolyRestoreFreshnessBatchScopingTests 2, HolyRestoreFreshnessReconcileTests 9, HolyRestoreFreshnessStoreTests 1, HolyRestoreIntegrationTests 6, HolyRestoreLivenessLedgerFileTests 2, HolyRestorePreflightTests 16, HolyRestoreProvenanceTests 16, HolyRestoreRunLogFileTests 1, HolyRestoreRunRecordingTests 4, HolyRestoreRunSignageTests 3, HolyRestoreSelectionLawTests 7, HolyRestoreWorkingDirectoryEngineTests 2, HolyRestoreWorkingDirectoryPreflightTests 3, HolyRestoreWorkingDirectoryResolutionTests 7, HolySessionHistorySignageTests 7, all 0 failed.

Two suites were then renamed for swiftlint `type_name` (over 40 characters) and rerun: run 2, `/tmp/mn-3c4b23-2.xcresult`: Passed, 12 passed, 0 failed (HolyRestoreWorkingDirResolutionTests 7, HolyRestoreWorkingDirPreflightTests 3, HolyRestoreWorkingDirectoryEngineTests 2). `build-for-testing` clean; the only lint finding in touched files (an implicit-optional init) was fixed before run 1.

### How freshness is decided now

At every roster membership change and at an orderly quit, the store writes the liveness ledger: the boot it is running under and every live session. At launch, after the supervisor's sweep, the store reads the previous run's ledger once and runs the law: the shutdown kind is `reboot` when `kern.bootsessionuuid` differs from the ledger's boot, `cleanQuit` when the boot is the same and the ledger carries `cleanExitAt`, `appRelaunch` otherwise. Every local session the ledger saw live that is not in the roster now and has an archive row, whatever that row's reason or batch id says, is interrupted by the last shutdown: its `recoveryBootBatchID` becomes this launch's batch (the sweep's own id when the sweep archived anything, else a new one), its reason becomes the cold-boot prefix plus "interrupted by the last shutdown (kind)", the boot time and both sysctl values for a reboot, when it was last seen live, and the previous non-cold-boot reason as history; its `archivedAt` becomes launch time (the sweep's convention; `lastActivityAt`, the resolver anchor, is untouched). Rows already in that batch are left alone; sessions observed live at any point in this run are never renewed. The fresh section is exactly that batch. When the shutdown interrupted nothing, the ledger's carried batch id keeps naming the last real event, so a clean quit never promotes an older group to fresh. Opening the sheet re-runs the law (idempotent, same batch) before the plan is built. With no ledger (first launch of this build), the sweep's newest-batch law stands unchanged.

- Kernel panic: boot UUID changed → `reboot`; every session live at the ledger's last write that is archived now, swept, stranded in an old group, archived without a cold-boot reason, or archived by the validator, is fresh under one batch; the header reads "Interrupted by the last shutdown · rebooted Sep 26, 2026 at 6:16 AM"; sessions dead before the panic stay older.
- Clean quit (Cmd-Q): same boot, `cleanExitAt` set → `cleanQuit`; tmux survived, the sessions are live again, nothing is renewed, fresh stays the carried batch (whatever of the last real shutdown is still unrestored, possibly empty); header "· quit cleanly <time>".
- Installer relaunch (pkill/SIGTERM, no `applicationWillTerminate`): same boot, no clean-exit mark → `appRelaunch`; sessions still on tmux are live and untouched; any session that was live at the kill and is archived now (for example by the validator with no batch id) is renewed into this launch's batch and is the fresh section; header "· app relaunched without a clean quit".

### What the history entry contains

One `HolyRestoreRunRecord` per restore pass: when it started and finished, the trigger (Restore All / Restore Selected / Restore this shutdown / Retry / Attach), whether it attached, and for every requested row the archive id, source session id, title, runtime, the directory it restored into, the exact provider conversation id it resumed when it resumed one, and the outcome, restored and attached, restored headless, failed with the engine's reason, or skipped with the verdict that made it non-actionable (blocked reason naming directory sources, ambiguity count, conflict, remote). Stored in `restore-runs.json` beside the database, newest first, loaded at launch, published on the store, and shown in Session History as "N restore runs · Latest: Sep 26, 2026 at 11:31 AM · Restore All · 36 of 38 restored · 2 failed", each run opening to one line per row.

### Risks and what is left

- Sessions in the roster at launch whose pane is already dead and that converge archives minutes later are "observed live this run" and are not renewed; that gap mirrors today's validator behaviour and is the one Egora/SubDub/Yed Prior case this cannot prove either way without the sessions table.
- The first launch of this build has no ledger, so that one launch keeps today's freshness; the ledger exists from then on.
- Each ledger write is an `F_FULLFSYNC`; writes happen only on membership change, at launch, and at quit.
- The discovery-inferred working directory (HolyRemoteTmuxDiscoveryService / HolySession) is fixed by another lane; this row-level handling names the source and falls through to the launch directory, git evidence, or the parent.
- Not done by this lane, by rule: no installer run, no push, no board commands; `macos/GhosttyKit.xcframework` and `zig-out` were linked for the build and are not committed.
