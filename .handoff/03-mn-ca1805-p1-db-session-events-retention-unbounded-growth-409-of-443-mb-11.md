---
workflow: 2
manna: mn-ca1805
track: mn-5db142
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P1][DB] session_events retention: unbounded growth (409 of 443 MB, ~11 MB/day); snapshot dedup verified fixed'
inputs: []
binding: sha256:2dadccff49ed8e0a8ac2b2a9bcd5a5e5b317d769f48ab2557a59552367d895d4
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

## Build return, 2026-09-29

Status: implementation committed and build-verified. Required executed and installed acceptance is still pending; this item remains `in_progress` and has not been marked done.

- Claimed successfully as `codex-01a0ef089d397650`. Before edits, canonical `manna state --json`, the handoff frontmatter, the work-order body, and the normalized contents all matched the supplied binding `sha256:6592184c8b1a420b5df2c8a6c30d1eda613486a3be658894a0d45f8e76574091`.
- Read `/Users/erik/Custom-Coding/AGENTS.md`, the supplied global instructions, README, Xcode scheme/project, and repository validation contract. No nearer repository AGENTS.md or CLAUDE.md was present.
- Source and builds were isolated in `/Users/erik/Custom-Coding/holy-ghostty-mn-ca1805`, branch `fix/mn-ca1805-event-retention`, based on `38643dcf483c9338fc15d00469e2cc696dfeed56`. Manna and Coord operations stayed in the primary checkout. Exact source/handoff path claims were established before editing.
- Implementation commit: `11b6cdba1de098dde961f42e6094c0535a9cdf63`, `fix(database): bound session event retention and validate compaction`, trailer `Manna: mn-ca1805`. This is the primary-checkout cherry-pick of isolated commit `50ea739d1`. Before integration, all seven primary paths were confirmed byte-equivalent to the build base and the primary index was empty. Other workers' changes were preserved.

### Changes

1. `HolyWorkspaceRetentionPolicy.swift`: events expire after 30 days, with at most 512 retained per session and a 12-event floor. The retained sequence tail preserves the recent timeline and prevents sequence reuse. Each pass deletes at most 256 events, 1,000 old git snapshots and eight retired sessions. Event candidate selection runs before the write transaction. Session deletion requires event history to be drained first, preventing an unbounded event cascade. Tombstone eligibility is rechecked before deletion.
2. A utility-queue retention worker starts at launch after migration, runs independently every 60 seconds, and continues saturated batches after a 250 ms yield. Saves may request a coalesced pass. The long-lived maintenance connection has a zero busy timeout and yields to an existing writer; the timer retries without needing another save.
3. Archive retention independently protects `recoveryReason` and `recoveryBootBatchID`, even without live tmux evidence. An active session still supersedes its stale archive. A regression preserves reason-only, boot-only and combined recovery metadata through persistence, pruning and compaction.
4. Startup no longer runs whole-file VACUUM. The existing explicit menu action uses `HolyDatabaseMaintenance` to validate integrity, foreign keys, schema and every enumerated business-table row count before and after in-place compaction. Unknown disk capacity, incomplete checkpoints and concurrent writes refuse a successful preservation receipt. The copy-export path uses the same validation.
5. Ten regression tests cover event age/cap/sequence preservation, bounded parent retirement, recovery metadata, repeated production-save growth, independent timer retry, unknown disk capacity, foreign-key failure, row-count mismatch and writer contention.

No schema migration or dependency was added. Event retention bounds history per session, not the number of user-owned recovery records. A foreground save can still briefly wait for an in-flight bounded SQLite write transaction; the required installed soak must measure that latency. Deliberate whole-file compaction remains an exclusive operation and should run while session writes are quiet.

### Verification receipts

All commands below ran in the isolated worktree. Receipt copies are in primary `.dev/mn-ca1805/`; that ignored directory is evidence storage, not committed source. `verification.json` contains structured Xcode results.

```bash
scripts/build-holy-ghostty-core.sh verify

xcodebuild build-for-testing -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .dev/mn-ca1805/DebugDerivedData \
  -resultBundlePath .dev/mn-ca1805/retention-build.xcresult \
  -only-testing:GhosttyTests/HolyWorkspacePersistenceRetentionTests \
  -only-testing:GhosttyTests/HolyDatabaseCompactorTests \
  -only-testing:GhosttyTests/HolyWorkspacePersistenceWriteChurnTests \
  -only-testing:GhosttyTests/HolyArchiveRetentionCoverageTests \
  SYMROOT=/Users/erik/Custom-Coding/holy-ghostty-mn-ca1805/.dev/mn-ca1805/debug-products \
  CODE_SIGNING_ALLOWED=NO

xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -configuration ReleaseLocal -destination 'generic/platform=macOS' \
  -derivedDataPath .dev/mn-ca1805/ReleaseDerivedData \
  -resultBundlePath .dev/mn-ca1805/release-build.xcresult \
  SYMROOT=/Users/erik/Custom-Coding/holy-ghostty-mn-ca1805/.dev/mn-ca1805/release-products build

swiftlint lint --strict --quiet \
  macos/Sources/HolyGhostty/Persistence/HolyWorkspaceRetentionPolicy.swift \
  macos/Sources/HolyGhostty/Persistence/HolyWorkspaceDatabasePersistence.swift \
  macos/Sources/HolyGhostty/Database/HolyDatabaseCompactor.swift \
  macos/Sources/HolyGhostty/Database/HolyDatabaseMaintenance.swift \
  macos/Sources/App/macOS/AppDelegate.swift \
  macos/Tests/HolyGhostty/HolyWorkspacePersistenceRetentionTests.swift \
  macos/Tests/HolyGhostty/HolyDatabaseCompactorTests.swift

git diff --check
codesign --verify --deep --strict --verbose=2 \
  '.dev/mn-ca1805/release-products/ReleaseLocal/Holy Ghostty.app'
lipo -archs '.dev/mn-ca1805/release-products/ReleaseLocal/Holy Ghostty.app/Contents/MacOS/holy-ghostty'
```

- Core provenance: passed, ReleaseFast, Zig 0.15.2, input fingerprint `df28bebb6ebfe4a473978513324c78da1f5148e4952f7f59d53e3806f7781141`. The complete existing receipt-bound core/resources were copied to the isolated worktree and verified against its source.
- Focused Debug test build: **TEST BUILD SUCCEEDED**, exit 0, zero errors. Xcode result bundle reports 533 warnings, zero in the seven touched files. Test action status is **notRequested**.
- Universal ReleaseLocal build: **BUILD SUCCEEDED**, exit 0, zero errors. Xcode reports 59 warnings, zero in the seven touched files. Binary architectures: `x86_64 arm64`.
- Strict SwiftLint, diff check and deep strict code-signature verification: passed.
- Ten added tests compiled. **Zero tests executed.** The simulated growth test was compiled, not run. No installed database was mutated or measured by this lane.
- No app launches, installations, screenshots, live session spawning, pushes or pull requests occurred.

### Required coordinated acceptance

Coord dependency: `mn-ca1805-executed-installed-soak`. The lane's no-launch boundary prevents completing these checks here.

1. Execute the four focused suites named above through the repository's app-hosted Xcode path in the coordinated acceptance window. Record executed counts and failures separately from these compile receipts. The broader release green-run belongs to its own gate.
2. Use the supported installation path for the integrated candidate. Verify the actual running bundle and workspace database. Do not substitute fixture results or the archive database for the installed workspace database.
3. Under the normal session fleet and production save/timer paths, capture time-stamped total/per-session event counts, database page count, freelist count, main/WAL bytes and save latency before drain, during drain and after warm-up. Required evidence is a flat retained-row and used-page curve after policy settles, with bounded physical main/WAL growth and responsive foreground saves. Preserve the denominator and sampling interval in the receipt. A quiescent database alone is not the requested workload.
4. Verify recovery reason and boot-batch metadata before and after retention/restart, including dead crash-restore archives beyond age and count limits. Check installed integrity and foreign keys. Exercise deliberate compaction only in a coordinated quiet interval and retain its before/after validation receipt.
5. Only after these receipts pass should this item be marked done. Installed performance, live recovery behavior and compaction UX remain unverified.

Lessons logged: 5 (new) | Decisions logged: 2 (new). ZPC harvest completed with no format issues.
