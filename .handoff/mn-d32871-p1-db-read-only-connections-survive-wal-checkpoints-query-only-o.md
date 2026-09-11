---
workflow: 2
manna: mn-d32871
track: mn-9a97cc
source: null
base_commit: 065ff58584b5ce1b3b1515a589998982f0185148
scope: '[P1][DB] Read-only connections survive WAL checkpoints: query_only over SQLITE_OPEN_READONLY'
inputs: []
binding: sha256:fcf672bc97f03d2ff87e99255468f232864d652d13158d4b1bfdcdb9823d303d
---

# Handoff: [P1][DB] Read-only connections survive WAL checkpoints: query_only over SQLITE_OPEN_READONLY

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-d32871
```

## Scope

[P1][DB] Read-only connections survive WAL checkpoints: query_only over SQLITE_OPEN_READONLY

## Inputs

- None declared.

## Work order

Erik 2026-09-11 (board inspector): AI SUMMARY shows 'Failed to prepare SQL (SQLite 14): unable to open database file' from board_digest_cache. REPRODUCED live: sqlite3 mode=ro on the app DB fails the same way — the DB is WAL-mode, a checkpoint removed -wal/-shm, and a READONLY connection cannot create the -shm, so every prepare fails until the next write recreates companions. ~30 readOnly: true call sites share the disease (archive repository, tasks, events, budget, remote hosts, persistence, digest cache). Central fix in HolyDatabase.open: readOnly opens the connection SQLITE_OPEN_READWRITE (no CREATE) so SQLite can build WAL infrastructure, with PRAGMA query_only=ON enforcing the read-only contract at the SQL layer; on open failure (e.g. write-permission denied on a federated foreign archive file) fall back to true SQLITE_OPEN_READONLY. Regression tests: WAL db with companions removed opens readOnly and SELECTs; writes refused under query_only; chmod-readonly file still readable via fallback. Verification: suites executed green.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-d32871`.
4. Commit with `Manna: mn-d32871` and run `agent-do manna done mn-d32871` only after the work is verified.
