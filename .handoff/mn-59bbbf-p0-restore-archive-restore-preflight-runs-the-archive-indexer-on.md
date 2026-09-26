---
workflow: 2
manna: mn-59bbbf
track: mn-eb7a80
source: hang report 2026-09-26 11:25; diags 09-24 18:50, 09-25 03:44; memory resolve-reindex-cost-asymmetry
base_commit: 962f13ad23c8f022a2b5d44d29de8085c36339de
scope: '[P0][RESTORE][ARCHIVE] Restore preflight runs the archive indexer on the main thread: 26 s hang, and the same path rewrites the archive DB'
inputs:
- hang report 2026-09-26 11:25; diags 09-24 18:50, 09-25 03:44; memory resolve-reindex-cost-asymmetry
binding: sha256:7092adde134aa16d20fc9b5eff924f12aaf1aec382271e372add2037bf4d4cb7
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

Receipt: /Library/Logs/DiagnosticReports/holy-ghostty_2026-09-26-112545_Eriks-Mac-Studio.hang (26 s, main thread, 11 of 11 samples): HolyWorkspaceStore.presentRestore() (HolyWorkspaceStore.swift:1895) -> HolyRestoreEngine.runPreflight() (HolyRestoreEngine.swift:427) -> resolvePendingRowsInOneBatch() (:631) -> HolyArchiveRestoreResolver.resolveBatch (HolyArchiveRestoreResolver.swift:85) -> refreshStaleScopes (:192) -> HolyArchiveIndexer.indexPaths (HolyArchiveIndexing.swift:438) -> index (:492) -> persist (:560) -> HolyArchiveRepository.finishReplacement (HolyArchiveRepository.swift:155,157) -> HolyDatabase.withTransaction (HolyDatabase.swift:211) -> execute (:133). HolyRestoreEngine is @MainActor; the resolver and repository run inline on it although HolyArchiveIndexer is an actor. Also holy-ghostty_2026-09-26-112756 cpu_resource.diag: 72 percent CPU for 124 s in the same window. Disk: holy-ghostty_2026-09-24-185011 diag reports 2147 MB of file-backed memory dirtied in 2732 s (786 KB/s) starting at the 18:04 relaunch, and holy-ghostty_2026-09-25-034426 diag reports 8590 MB over 32055 s (268 KB/s) from 18:50 to 03:44; the archive DB is 1.12 GB and the workspace DB 1.52 GB. Deliver: (1) resolveBatch never executes indexing or SQLite writes on the main actor; the engine keeps calling await batchResolver.resolveBatch(_:) with the same signature and the sheet appears at once with rows in a resolving state and progress; (2) the restore path never triggers a whole-provider re-index (the needsWholeProvider claim path walks every session of a provider; OpenCode has 71,761 in the live archive) and refreshes only the scoped paths of rows being resolved; (3) a stale live transcript is indexed incrementally (append what grew) instead of finishReplacement rewriting the whole session, and an unchanged content hash is a no-op write; (4) attribute the steady 268 KB/s write rate with a measurement (a write-accounting log of statements and rows per table per minute behind a defaults key is acceptable) and fix the top writer if it is in Archive/, otherwise report it with the table named. Tests: a MainActor caller of resolveBatch with a stale multi-megabyte transcript fixture keeps a main-actor timer ticking during the call; the stale-file refresh writes only the appended rows. Own only macos/Sources/HolyGhostty/Archive/ and the HolyArchive test files. Memory: resolve reindex cost asymmetry (7.23 s floor for codex and opencode) and mn-b775ac (archive moved to its own DB for the same starvation).

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-59bbbf`.
4. Commit with `Manna: mn-59bbbf` and run `agent-do manna done mn-59bbbf` only after the work is verified.
