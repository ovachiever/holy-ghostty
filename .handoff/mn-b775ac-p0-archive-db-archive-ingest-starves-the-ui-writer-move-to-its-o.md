---
workflow: 2
manna: mn-b775ac
track: mn-eb7a80
source: Erik live report 2026-09-02 16:13 + this session's diagnosis (WAL single-writer, DB growth receipts, prepare() trigger)
base_commit: 2f443748353ce105266f4696ea4e07b4315b7a36
scope: '[P0][ARCHIVE][DB] Archive ingest starves the UI writer: move to its own database file with chunked, backpressured writes'
inputs:
- Erik live report 2026-09-02 16:13 + this session's diagnosis (WAL single-writer, DB growth receipts, prepare() trigger)
binding: sha256:5c496612717645bc69ce6c32c6a911d5ac50d1f58af2b46da958d9f8ef5016b1
---

# Handoff: [P0][ARCHIVE][DB] Archive ingest starves the UI writer: move to its own database file with chunked, backpressured writes

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-b775ac
```

## Scope

[P0][ARCHIVE][DB] Archive ingest starves the UI writer: move to its own database file with chunked, backpressured writes

## Inputs

- Erik live report 2026-09-02 16:13 + this session's diagnosis (WAL single-writer, DB growth receipts, prepare() trigger)

## Work order

Live regression 2026-09-02 (Erik: app fine 10-20 min after relaunch, then freeze/thaw cycles, unusable). Diagnosis: HolyArchiveRepository opens its own FULLMUTEX connection but to the SAME sqlite file as session persistence; SQLite WAL allows ONE writer at a time, so the initial ~79k-session ingest (FTS inserts + embedding blobs; DB grew 846MB->1.34GB in hours) holds the write lock in long transactions while the UI's constant session/event writes stall against the 5s busy timeout — the freeze/thaw metronome. Ingest auto-started from HolyArchiveModeStore.prepare() -> incrementalIndex() whenever Archive mode opened. HOTFIX SHIPPED with this filing: auto-ingest is opt-in behind UserDefaults holy.archive.autoIndex (default off); browsing already-indexed content is unaffected; manual 'incremental update' still available. REAL FIX (this item): (1) move archive tables (archive_* + their FTS) to their OWN database file with an independent WAL — zero writer contention with session persistence by construction; migrate existing archive rows across; note this amends the ratified 'new tables in Holy's SQLite' wording and the item's completion ratifies the amendment; (2) chunked transactions with explicit yields and a write-rate budget; backpressure so ingest slows when the app is foreground-active; (3) resume-safe ingest with progress surfaced in Archive mode; WAL checkpoint management sized to the corpus; (4) embeddings generation decoupled from ingest (its own queue + rate limit; keys VOYAGE/COHERE/OPENAI from env per mn-767817); (5) soak acceptance: full corpus ingest on a copy of the real stores while a scripted UI-write workload runs — no main-thread stall >100ms attributable to DB contention, measured, and the freeze/thaw repro from today demonstrably gone. Related: peer item mn-fe97c2 (embedding token fix) touches the same pipeline — coordinate, do not collide.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-b775ac`.
4. Commit with `Manna: mn-b775ac` and run `agent-do manna done mn-b775ac` only after the work is verified.
