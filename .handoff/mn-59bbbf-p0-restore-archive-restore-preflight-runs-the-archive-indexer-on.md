---
workflow: 2
manna: mn-59bbbf
track: mn-eb7a80
source: hang report 2026-09-26 11:25; diags 09-24 18:50, 09-25 03:44; memory resolve-reindex-cost-asymmetry
base_commit: 962f13ad23c8f022a2b5d44d29de8085c36339de
scope: '[P0][RESTORE][ARCHIVE] Restore preflight runs the archive indexer on the main thread: 26 s hang, and the same path rewrites the archive DB'
inputs:
- hang report 2026-09-26 11:25; diags 09-24 18:50, 09-25 03:44; memory resolve-reindex-cost-asymmetry
binding: sha256:12349ed18706bceebed14985c84ac1036de7abf3022716851fde80bc4ce90a51
---

# Handoff: [P0][RESTORE][ARCHIVE] Restore preflight runs the archive indexer on the main thread: 26 s hang, and the same path rewrites the archive DB

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-59bbbf
```

## Scope

[P0][RESTORE][ARCHIVE] Restore preflight runs the archive indexer on the main thread: 26 s hang, and the same path rewrites the archive DB

## Inputs

- hang report 2026-09-26 11:25; diags 09-24 18:50, 09-25 03:44; memory resolve-reindex-cost-asymmetry

## Work order

Receipt: /Library/Logs/DiagnosticReports/holy-ghostty_2026-09-26-112545_<host>.hang (26 s, main thread, 11 of 11 samples): HolyWorkspaceStore.presentRestore() (HolyWorkspaceStore.swift:1895) -> HolyRestoreEngine.runPreflight() (HolyRestoreEngine.swift:427) -> resolvePendingRowsInOneBatch() (:631) -> HolyArchiveRestoreResolver.resolveBatch (HolyArchiveRestoreResolver.swift:85) -> refreshStaleScopes (:192) -> HolyArchiveIndexer.indexPaths (HolyArchiveIndexing.swift:438) -> index (:492) -> persist (:560) -> HolyArchiveRepository.finishReplacement (HolyArchiveRepository.swift:155,157) -> HolyDatabase.withTransaction (HolyDatabase.swift:211) -> execute (:133). HolyRestoreEngine is @MainActor; the resolver and repository run inline on it although HolyArchiveIndexer is an actor. Also holy-ghostty_2026-09-26-112756 cpu_resource.diag: 72 percent CPU for 124 s in the same window. Disk: holy-ghostty_2026-09-24-185011 diag reports 2147 MB of file-backed memory dirtied in 2732 s (786 KB/s) starting at the 18:04 relaunch, and holy-ghostty_2026-09-25-034426 diag reports 8590 MB over 32055 s (268 KB/s) from 18:50 to 03:44; the archive DB is 1.12 GB and the workspace DB 1.52 GB. Deliver: (1) resolveBatch never executes indexing or SQLite writes on the main actor; the engine keeps calling await batchResolver.resolveBatch(_:) with the same signature and the sheet appears at once with rows in a resolving state and progress; (2) the restore path never triggers a whole-provider re-index (the needsWholeProvider claim path walks every session of a provider; OpenCode has 71,761 in the live archive) and refreshes only the scoped paths of rows being resolved; (3) a stale live transcript is indexed incrementally (append what grew) instead of finishReplacement rewriting the whole session, and an unchanged content hash is a no-op write; (4) attribute the steady 268 KB/s write rate with a measurement (a write-accounting log of statements and rows per table per minute behind a defaults key is acceptable) and fix the top writer if it is in Archive/, otherwise report it with the table named. Tests: a MainActor caller of resolveBatch with a stale multi-megabyte transcript fixture keeps a main-actor timer ticking during the call; the stale-file refresh writes only the appended rows. Own only macos/Sources/HolyGhostty/Archive/ and the HolyArchive test files. Memory: resolve reindex cost asymmetry (7.23 s floor for codex and opencode) and mn-b775ac (archive moved to its own DB for the same starvation).

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-59bbbf`.
4. Commit with `Manna: mn-59bbbf` and run `agent-do manna done mn-59bbbf` only after the work is verified.

## Report

Lane worker, worktree `worktree-agent-a972e50f4b723f022` off main 3cf78d258, 2026-09-26. Xcode 26.4.1 (17E202), Swift 6.3.1.

### What the receipts actually say (before the changes)

- Hang report `holy-ghostty_2026-09-26-112545.hang`: the archive frames (resolveBatch → refreshStaleScopes → indexPaths → index → persist → finishReplacement → HolyDatabase.execute at HolyArchiveRepository.swift:157 → sqlite3_step) sit on **Thread 0x2fcac, a `com.apple.root.user-initiated-qos.cooperative` Swift Task thread**, 11 of 11 samples, with the leaf in `sqlite3BtreeNext → moveToChild → getAndInitPage → readDbPage → pread` (a B-tree scan reading pages from disk). The **main thread (0x3811)** holds 11 of 11 samples in SwiftUI `NSHostingView.beginTransaction → GraphHost.flushTransactions → LazyVStack layout`, every leaf marked running. The archive work was not on the main thread; the main thread was continuously re-laying out the sheet while the archive call was slow. HolyRestoreEngine is `@MainActor`, but the app target compiles without `SWIFT_APPROACHABLE_CONCURRENCY` (only GhosttyTests and GhosttyUITests have it), so the resolver's nonisolated async body already hopped off main.
- Statement 157 is `DELETE FROM archive_messages WHERE session_id = ?`. Discriminating test on a read-only copy of the live archive (1,200,922,624 bytes; 73,869 sessions: claude-code 721, codex 625, droid 762, opencode 71,761; 231,683 messages; 223,389 chunks, 149,520 with a message_id): `EXPLAIN QUERY PLAN` → `SEARCH archive_messages USING COVERING INDEX archive_messages_session_sequence_idx` **+ `SCAN archive_chunks`**. `archive_chunks.message_id` is a foreign key with ON DELETE SET NULL and had no index, so SQLite scanned all 223,389 chunks once per deleted message. Deleting one 207-message codex session: **39.780 s** (13.4 s user, 25.2 s sys). `CREATE INDEX archive_chunks_message_idx ON archive_chunks(message_id)`: **0.221 s**, 12,697,600 bytes. The same delete with the index: **0.006 s**; the biggest session (3,195 messages): 0.192 s. The cpu_resource diag 09-26-112756 has 21 of 38 resolveBatch samples in the same DELETE. That is the 26 s.
- FTS also churns on every rewrite: `archive_messages_ad` runs an FTS5 'delete' per deleted message row and `archive_sessions_au` rewrote the session FTS row on any column update.

### 268 KB/s attribution (measured, table named)

Disk-write diags are byte-weighted microstackshots (10.49 MB per step). Shares of samples:

| diag | samples | `HolyWorkspacePersistence.save` → `Data.write(to: workspace-state.json, .atomic)` (Persistence/HolyWorkspacePersistence.swift:31) | `HolyWorkspaceDatabasePersistence.save(…in:)` commit (Persistence/HolyWorkspaceDatabasePersistence.swift:194; tables `sessions`, `app_state`, `templates`, `git_snapshots`) | `HolyDatabase.deinit` → `sqlite3WalClose` checkpoint + `walLimitSize` (Database/HolyDatabase.swift:47) | `HolyDatabase.open/configure` | Archive/ |
|---|---|---|---|---|---|---|
| 09-24 18:50 (786 KB/s over 2,732 s) | 180 | 115 (64%) | 11 (6%) | 9 (5%) | 0 | 0 |
| 09-25 03:44 (268 KB/s over 32,055 s) | 560 | 411 (73%) | 58 (10%) | 48 (9%) | 19 (3%) | 0 |
| 09-26 11:41 (183 KB/s over 11,762 s) | 138 | 55 (40%) | 6 (4%) | 12 (9%) | 0 | ≈10 (7%): the 11:25 preflight's finishReplacement |

Every one of those stacks descends from `HolySessionSupervisor.schedulePersistence → flushScheduledPersistence` (Supervisor/HolySessionSupervisor.swift:922-977; 350 ms mutation debounce, 10 s routine interval) → `HolyWorkspaceRepository.save` (Supervisor/HolyWorkspaceRepository.swift), which writes both the legacy JSON snapshot and the workspace database on every flush, and closes the connection each time (the close checkpoints the WAL into the 1.52 GB main file: `holy-ghostty.sqlite3` has no -wal file between flushes). Live cadence, read-only `stat` at 1 Hz, 12:08:30–12:10:32 with 39 tmux sessions on socket holy: `workspace-state.json` (1,338,677 bytes) rewritten **83 times in 120 s = 111,110,415 bytes = 926 KB/s** from the JSON file alone; `holy-ghostty.sqlite3` mtime changed 85 times. Coordinator's idle measurement: 0 KB in 60 s. Verdict: the steady writer is the whole-file atomic rewrite of `workspace-state.json` per debounced mutation, in Persistence/, not Archive/; reported, not fixed. Archive's contribution is a burst during restore preflight, which this lane removes.

### What changed, file by file

- `macos/Sources/HolyGhostty/Archive/HolyArchiveRestoreResolver.swift` (rewritten). `HolyArchiveRestoreResolver` keeps `init(databaseURL:legacyDatabaseURL:registry:)` (two new defaulted parameters: `progress:` and `accounting:`), `resolve(_:)`, and `resolveBatch(_:)` with today's signatures. Every lookup, staleness check, provider read, claim, and index run executes on `HolyArchiveRestoreResolutionWorker`, an actor created per call, so nothing inherits the caller's actor under either nonisolated-async default. New `resolveBatch(_:progress:)`. `refreshStaleScopes` refreshes only the files of the candidates being resolved whose mtime changed, plus, for a provider that can narrow discovery to one project, that project's files; keyed by canonical path with the archive's stored spelling preferred; the `needsWholeProvider` walk is gone. Candidates are looked up once and re-looked-up only for requests that were refreshed. Progress emits `.discovering` → the indexer's `.indexing` per file → `.finishing`.
- `macos/Sources/HolyGhostty/Archive/HolyArchiveIndexing.swift`. `IndexWork` carries the row the archive already holds. `indexPaths` looks rows up by path (`indexRows(rawPaths:)`, canonical-keyed) instead of loading every row of the harness. `index()` calls `ensureDeletionIndexes()` on the actor before any write, and recomputes project stats only for touched projects (`ProjectStatsScope.touched`; full reindex keeps `.all`); a pass that indexed nothing writes no stats. `persist`: same ingest digest and content hash → `touchSession` (one UPDATE of file_mtime/indexed_at); stored messages are a prefix of the parsed ones → `appendIncrementally` (INSERT only the new messages, `chunkReconciliation` deletes gone/changed chunks, inserts new ones, moves unchanged ones, then `replaceMetadata(ingestDigest:)` last so a crash mid-way is retried idempotently); otherwise the staged whole-session replacement, now storing the digest. `ingestDigest(of:)` is SHA-256 over (id, role, content) of the storage messages. Chunker tool-chunk ids are `"<session>:tool:<messageSequence>:<ordinal>"` so appends never rename existing tool chunks.
- `macos/Sources/HolyGhostty/Archive/HolyArchiveRepository.swift`. `accounting: HolyArchiveWriteAccounting` (default `.shared`) and a private `write(_:bindings:table:verb:in:)` funnel that every write statement uses, reporting changed rows. `HolyArchiveIndexRow` gains `projectPath`, `contentHash`, `ingestDigest`, `messageCount`. New: `indexRows(rawPaths:)`, `touchSession`, `appendMessages`, `chunkFingerprints`, `reconcileChunks`, `ensureDeletionIndexes`, `replaceProjectStats(projectPaths:)`, `sessions(projectPaths:)`. `finishReplacement` and `replaceMetadata` take `ingestDigest:` (defaulted) and `finishReplacement` creates the deletion index before its DELETE. `upsert` writes `ingest_digest`.
- `macos/Sources/HolyGhostty/Archive/HolyArchiveDatabase.swift`. Schema user_version 3: `ALTER TABLE archive_sessions ADD COLUMN ingest_digest TEXT`; `archive_sessions_au` recreated as `AFTER UPDATE OF first_prompt_preview, project_name, auto_tags_json` so bookkeeping updates stop rewriting the FTS row; `archive_chunks_message_idx` created at creation for a fresh archive (chunk table empty) and by the indexer actor for an existing one. `columns(of:schema:in:)` / `columnExists`. The legacy copier names columns instead of `SELECT *` so the added column cannot break it.
- `macos/Sources/HolyGhostty/Archive/HolyArchiveProviders.swift`. OpenCode: `discoverSessionFiles(forProjectPath:)` via `SELECT id FROM session WHERE directory = ?` (nil without the database); `modificationDate` and `parseSession` use a one-row `SELECT time_updated FROM session WHERE id = ?` instead of loading all 71,761 rows per call.
- `macos/Sources/HolyGhostty/Archive/HolyArchiveModels.swift`. `HolyArchiveFilePath.canonical(_:)` (`contentsOfDirectory(at:)` returns `/private/var/...` for a `/var/...` directory; measured with a probe).
- `macos/Sources/HolyGhostty/Archive/HolyArchiveWriteAccounting.swift` (new). Statements, rows, and main-thread statements per table and verb, bucketed per minute, logged through os.Logger category `HolyArchiveWrites` when `defaults write org.holyghostty.app holy.archive.writeAccounting -bool true`; `snapshot()`/`reset()`/`flush()` for tests.
- `macos/Tests/HolyGhostty/HolyArchiveRestoreRefreshTests.swift` (new, 11 tests).

### xcresult counts

- `/tmp/mn-59bbbf-5.xcresult`, `GhosttyTests/HolyArchiveRestoreRefreshTests`: total 11, passed 11, failed 0, skipped 0. The timer test (`mainActorKeepsTickingWhileResolveBatchRefreshesAStaleTranscript`, `@MainActor`, a 4.5 MB Claude JSONL through the production provider, 1,400 then +100 message pairs) ran 8 s; it asserts ticks > 0, longest main-actor gap < 250 ms (Apple, "Understanding hangs in your app": tools report unresponsiveness of the main run loop above 250 ms), 0 SQLite write statements on the main thread, 0 provider calls on the main thread. `staleTranscriptRefreshWritesOnlyTheAppendedRows`: 200 message inserts, 0 deletes, 0 staged rows, 200 chunk inserts, 0 chunk deletes, 1 session update, original rowids intact, FTS count equal to messages. `unchangedTranscriptWithANewModificationDateWritesNoContentRows`: 0 rows on messages, chunks, and staging; 1 session update (mtime bookkeeping). `restoreRefreshTouchesOnlyTheCandidatesOfTheRowsBeingResolved`: 0 whole-provider discoveries, 4 modificationDate calls for 33 sessions, 1 parse.
- `/tmp/mn-59bbbf-6.xcresult`, pre-existing `HolyArchiveModeTests`, `HolyArchivePresentationTests`, `HolyArchiveFederationTests`, `HolyArchiveRenderSmokeTests`, `HolyArchiveRetentionCoverageTests`, `HolyArchiveDatabaseSoakTests`, against the final build: total 52, passed 51, failed 0, skipped 1 (the opt-in soak, `HOLY_ARCHIVE_SOAK` unset).
- `/tmp/mn-59bbbf-1.xcresult`, earlier run (before the canonical-path fix) of the five HolyArchive suites plus `HolyModeClipboardTests`: total 62, passed 56, failed 6; all six in `HolyModeClipboardTests` with "Clipboard keyboard host unavailable: active=false, keyWindow=false" (the non-frontmost test host, mn-76e6f0); none in Archive.

### Contract for the Restore lane

- `HolyArchiveRestoreResolver()` and `await batchResolver.resolveBatch(_:)` are unchanged, positional results unchanged, `HolyRestoreBatchResolving` untouched. The call is safe to await from `@MainActor`: the worker actor owns everything.
- Progress, when wanted: `HolyArchiveRestoreResolver(progress:)` or `resolveBatch(_:progress:)`, a `@Sendable (HolyArchiveIndexProgress) async -> Void`; phases `.discovering` (detail "Checking N archived conversations", total = request count), `.indexing` (completed/total per file, detail "Claude Code: <file>"), `.finishing` ("Archive ready"). Hop to the main actor inside the closure to update rows.
- The sheet should be on screen before the await (presentRestore already sets `restorePresented` before the Task). During the 09-26 hang the main thread spent all 11 samples in LazyVStack layout of the sheet; with the archive call now fast that window closes, but whatever republishes the sheet continuously during preflight is worth a look on that side.
- The per-(harness, project) 120 s reindex claim still applies: a second preflight within 120 s returns the candidates the first refresh produced.
- Discovery of a session the archive has never seen: Claude (project directory listing) and OpenCode (`session.directory = cwd`) yes; Codex cannot narrow its date tree, so a never-indexed Codex session waits for the startup incremental pass. Stale candidates already in the archive are always refreshed.

### Risks and what is left

- Existing archives build `archive_chunks_message_idx` on the first indexer run after upgrade (first preflight or the startup incremental pass), on the actor; 0.22 s on the live-size copy with a warm page cache.
- The tool-chunk id format changed; the first incremental pass over a session with tool chunks deletes the old-id rows and inserts new ones once (today's full rewrite already dropped their embeddings). Chunks rewritten by an append (the summary line when tools change, the last partial pack) lose their embedding until the embedding worker refills; unchanged chunks keep theirs, which the old path never did.
- `HolyArchiveIndexReceipt.messagesIndexed` and `chunksCreated` now count rows written (appended), not the session totals; the Archive status line reflects that.
- `limit: 120` at HolyArchiveRestoreResolver.swift (candidate preview width) is pre-existing, carried over verbatim; the quantity hook flagged it.
- Sealing (`agent-do manna handoff seal mn-59bbbf`) and `manna claim/done` are left to the orchestrator per lane rules; this file's `binding:` hash is stale until resealed.
- zpc lessons recorded in the primary checkout's store (the worktree has no `.zpc`): les-a08cd1 (FK scan / read the thread in the stackshot), les-c3b58f (write-rate attribution).
- Build inputs used and removed: `macos/GhosttyKit.xcframework` symlink (ignored) and a `zig-out` symlink (removed before commit).
