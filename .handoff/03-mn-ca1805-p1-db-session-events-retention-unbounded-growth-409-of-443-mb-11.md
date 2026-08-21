---
workflow: 2
manna: mn-ca1805
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P1][DB] session_events retention: unbounded growth (409 of 443 MB, ~11 MB/day); snapshot dedup verified fixed'
inputs: []
binding: sha256:bf4acfd0d911cadbb022a266a81ff6384c26a6e5c1551495655e574f2b207fad
---

# Handoff: [P1][DB] session_events retention: unbounded growth (409 of 443 MB, ~11 MB/day); snapshot dedup verified fixed

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-ca1805
```

## Scope

[P1][DB] session_events retention: unbounded growth (409 of 443 MB, ~11 MB/day); snapshot dedup verified fixed

## Inputs

- None declared.

## Work order

RETARGETED 2026-08-07 (Erik, /board audit decision). The original incident is solved and verified live: git_snapshots = 104 rows in the installed 443 MB DB (was 31.5M rows / ~50 GB); an unchanged poll inserts zero rows (value-compare at HolyWorkspaceDatabasePersistence.swift:583, captured_at excluded from the compared value). That half is accepted.

THE LIVE PROBLEM: session_events has no retention path at all. Measured 2026-08-07 on the installed DB: 126,497 rows / ~409 MB plus ~21 MB indexes, growing ~2,900 rows (~11 MB) per day over 39 days; 115,495 of those rows are session_runtime_updated. The only DELETE FROM statements in macos/Sources cover app_state, git_snapshots, launch_profiles, remote_hosts, sessions, tasks, templates — never session_events (rows die only by FK cascade; 0 of 265 sessions pending purge). Retention is save-triggered, so an abandoned DB never drains (debug-bundle DB: 1,036,662 git_snapshots rows / 1.33 GB, untouched since 07-13).

Done when:
- session_events carries an explicit bounded retention policy (age and/or per-session cap), drained in bounded batches without blocking foreground writes.
- Prune preserves recovery-owned metadata: protectedArchiveIDs (HolyWorkspaceRetentionPolicy.swift:24-33) currently protects only tmux-discovery-evidenced rows, so a dead crash-restore archive drops recoveryReason/recoveryBootBatchID with it — same gap as mn-569b91 criterion 5; a test must pin it.
- The validating maintenance path is wired or deleted: HolyDatabaseMaintenance (integrity_check, foreign_key_check, per-table row equality) has zero production callers; the wired compactor validates page accounting only, and launch compaction runs synchronously on the main thread (AppDelegate.swift:226).
- A production-shaped soak shows a flat growth curve on the installed database.

--- original text below for provenance ---
Original incident: git_snapshots reached 31.5M live rows and roughly 50 GB. Commits dd1b7f955 and 1f73f70ae add dedup/retention and gated compaction; treat them as evidence, not automatic acceptance.

Done when:
- An unchanged git poll inserts zero rows and a meaningful change inserts exactly one.
- Bounded maintenance drains legacy rows without blocking foreground writes.
- Archive/session retention preserves user-visible recovery metadata.
- Compaction checks free disk, is deliberate/gated, and validates sessions/events before and after.
- A production-shaped soak demonstrates a flat growth curve and the installed database remains bounded.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-ca1805`.
4. Commit with `Manna: mn-ca1805` and run `agent-do manna done mn-ca1805` only after the work is verified.
