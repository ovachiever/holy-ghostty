---
workflow: 2
manna: mn-2c8f51
track: mn-eb7a80
source: lane mn-59bbbf report; diags 09-24 18:50 and 09-25 03:44; live cadence 12:08-12:10
base_commit: 5149da47279fa060aaa9357f218a18069a1827b1
scope: '[P1][PERSISTENCE] The app rewrites the whole 1.3 MB workspace-state.json and closes the database on every 350 ms flush: 926 KB/s of writes while sessions are active'
inputs:
- lane mn-59bbbf report; diags 09-24 18:50 and 09-25 03:44; live cadence 12:08-12:10
binding: sha256:bc9a1f4687329fed83394f148daede224df30be366513de7dcecb7078d8677ed
---

# Handoff: [P1][PERSISTENCE] The app rewrites the whole 1.3 MB workspace-state.json and closes the database on every 350 ms flush: 926 KB/s of writes while sessions are active

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-2c8f51
```

## Scope

[P1][PERSISTENCE] The app rewrites the whole 1.3 MB workspace-state.json and closes the database on every 350 ms flush: 926 KB/s of writes while sessions are active

## Inputs

- lane mn-59bbbf report; diags 09-24 18:50 and 09-25 03:44; live cadence 12:08-12:10

## Work order

Receipts, lane mn-59bbbf on 2026-09-26. Byte-weighted microstackshots in the app's disk-write diags: holy-ghostty_2026-09-25-034426 (268 KB/s over 9 h) has 560 samples of which 411 (73 percent) are HolyWorkspacePersistence.save writing workspace-state.json with Data.write(to:options:.atomic) (Persistence/HolyWorkspacePersistence.swift:31), 58 (10 percent) HolyWorkspaceDatabasePersistence.save commits to sessions, app_state, templates, git_snapshots (Persistence/HolyWorkspaceDatabasePersistence.swift:194), 48 (9 percent) HolyDatabase.deinit WAL close checkpoint plus walLimitSize (Database/HolyDatabase.swift:47), 0 archive; the 09-24 diag (786 KB/s) splits 115 JSON, 11 DB, 9 checkpoint of 180. All descend from HolySessionSupervisor.schedulePersistence and flushScheduledPersistence (Supervisor/HolySessionSupervisor.swift:922-977, 350 ms debounce) into HolyWorkspaceRepository.save, which rewrites the JSON, writes the DB, and closes the connection every flush. Live read-only cadence 12:08:30 to 12:10:32 with 39 tmux sessions: workspace-state.json (1,338,677 bytes) rewritten 83 times in 120 s, 926 KB/s; DB mtime changed 85 times; idle fleet 0 KB in 60 s. The CPU diags on 09-24 (50 to 72 percent for minutes) sit on the same path. Deliver: (1) a flush writes workspace-state.json only when the durable state it encodes changed, never for volatile per-poll fields (latest preview text, runtime telemetry, budget samples), which live in the database rows or in memory with their own cadence; (2) the database connection stays open across flushes so no per-flush close checkpoint occurs, with WAL checkpointing on its own measured schedule; (3) crash restore inputs stay durable: everything the restore engine, the liveness ledger, and the restore run log read must be on disk at least as promptly as today, proven by the existing HolyRestore suites and a new test that kills the writer mid-flush and restores; (4) a before and after measurement with the same method (file mtime count and bytes over 120 s with a live fleet is the orchestrator's to run; give the exact command and expected ratio) and a unit test that feeds N sessions M runtime updates and asserts zero JSON rewrites and at most one row write per changed row. Own macos/Sources/HolyGhostty/Persistence/, macos/Sources/HolyGhostty/Supervisor/HolySessionSupervisor.swift (persistence scheduling only), macos/Sources/HolyGhostty/Database/HolyDatabase.swift (connection lifetime and checkpoint policy only), and their tests; do not touch Archive/, Restore/, Workspace/, Board/, Remote/, Session/, Tmux/, Automation/. Related: mn-ca1805 (session_events retention), mn-b775ac (archive moved to its own DB for the same writer contention).

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-2c8f51`.
4. Commit with `Manna: mn-2c8f51` and run `agent-do manna done mn-2c8f51` only after the work is verified.
