---
workflow: 2
manna: mn-ac0b36
track: mn-9a97cc
source: Erik live pass 2026-09-06 12:17 + direct code read of HolyLedgerColumns.swift this session
base_commit: 4295f14118dafe493a1fa04eec8a83b460c99623
scope: '[P1][LEDGER] Drags are strictly local: uniform adjacent-pair boundaries, zero mid-drag refit'
inputs:
- Erik live pass 2026-09-06 12:17 + direct code read of HolyLedgerColumns.swift this session
binding: sha256:c91e0e06e00d1a8a4e1269d1c47dcf10c58a7a0984230c63eb0d0cea5530c24b
---

# Handoff: [P1][LEDGER] Drags are strictly local: uniform adjacent-pair boundaries, zero mid-drag refit

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-ac0b36
```

## Scope

[P1][LEDGER] Drags are strictly local: uniform adjacent-pair boundaries, zero mid-drag refit

## Inputs

- Erik live pass 2026-09-06 12:17 + direct code read of HolyLedgerColumns.swift this session

## Work order

Erik's live pass 2026-09-06: resizing STATE on the board visibly moves TRACK into DIGEST, and grips/inspector 'shake violently while resizing'. Humans solved table resizing decades ago; the port over-thought it. Receipts from HolyLedgerColumns.swift:219-291: the boundary model has THREE behaviors (fixedBeforeFlexible, fixedAfterFlexible with inverse delta, fixedPair) — any boundary that routes compensation through the flexible DIGEST column causes distant columns to translate mid-drag, and the responsive re-fit (columns(...) at :153) renormalizes widths DURING the drag, so even honest pair exchanges get re-laid out per frame (the shake, per the live-pass-shake coord drop of 12:02). Replace with the boring standard, uniformly: (1) EVERY grip is an adjacent-pair exchange between the two columns physically touching that divider — including pairs where DIGEST is a member (id|digest, digest|track) with digest's floor honored; one case, no inverse-delta special forms; delete fixedBeforeFlexible/fixedAfterFlexible. (2) While a drag is active, NO renormalization, no re-fit, no proportion writes — raw pair math against bounds captured at drag start; persist and renormalize exactly once on release; epsilon-guard width writes. (3) Window resize (not drags) remains the only place DIGEST flexes to absorb. (4) Tests: per-grip cases asserting ONLY the divider's two neighbors change and every other column's frame is identical before/after each intermediate drag frame; a monotonicity test (no width ever reverses against pointer direction); one-normalization-per-drag-lifecycle. Same model for archive. Relates to mn-f044d0 (still open for the overall visual pass) and supersedes the drag portions of mn-6842ed's implementation.

## Worker implementation, 2026-09-06

- Replaced the three-case boundary enum with one adjacent-pair value. Every
  Board and Archive grip now names the actual leading and trailing columns
  under the divider, including `digest` and `summary`.
- Captured the complete column widths, order, gap, available width, content
  floors, and global pointer origin once at gesture start. Pointer events run
  raw pair exchange against that snapshot and never rebase on a moving view.
- Added an explicit transient flexible width to the shared responsive layout.
  During a drag the renderer consumes the captured pixel snapshot and bypasses
  stored proportions, content fitting, poisoned-width discard, and responsive
  normalization. Window-driven responsive fitting resumes after release.
- Release emits at most one commit. The views normalize only the fixed members
  of the pair into one JSON preference write; `digest` and `summary` remain the
  resize-responsive remainder. Epsilon guards suppress duplicate previews and
  no-op persistence.
- Preserved the separate inspector drag-session work already present for
  `mn-f044d0`; this worker changed only its missing compile-time return in the
  Board width accessor.

## Worker verification

- Strict SwiftLint on the three production files and
  `HolyArchivePresentationTests.swift`: 0 violations.
- Debug arm64 Xcode `build-for-testing` with isolated DerivedData: passed.
- `HolyLedgerColumnOverridesTests`: 9 tests passed. The suite covers every
  visible wide and narrow grip in both ledgers, both pointer directions,
  fractional starting geometry, content floors, transient-layout bypass, and
  exactly one release commit. At six intermediate positions per grip it
  compares the raw floating-point bits of every non-neighbor frame.
- `HolyMannaBoardRenderSmokeTests` and `HolyArchiveRenderSmokeTests`: passed
  offscreen after the production wiring change.
- `git diff --check`: passed.
- ZPC captured lessons `les-2d9ac2`, `les-75a44f`, and decision
  `dec-26d5eb`. Repository totals after capture: 156 lessons, 18 decisions.

## Integration verification, 2026-09-06

- The integration review extended the inspector divider to the same static
  global-origin transaction as column drags. Its regression asserts monotonic
  movement, epsilon no-ops, and exactly one release commit.
- A fresh Debug arm64 `build-for-testing` passed with isolated DerivedData at
  `.dev/DerivedData-mn-f044d0-ac0b36`.
- `HolyLedgerColumnOverridesTests`: 10 tests passed. Every visible Board and
  Archive grip was exercised in wide and narrow modes. At every intermediate
  frame, each non-neighbor frame was compared by raw floating-point bit pattern.
- `HolyMannaBoardRenderSmokeTests` and `HolyArchiveRenderSmokeTests`: passed
  offscreen.
- `HolyArchivePresentationTests`, `HolyMannaBoardPresentationTests`,
  `HolyArchiveModeTests`, and `HolyMannaBoardTests`: passed.
- Strict SwiftLint on all four changed Swift files: 0 violations.
- `scripts/test-holy-ghostty-build-contract.sh`: passed.
- `git diff --check`: passed.
- No app was launched or installed. `mn-f044d0` stays open for Erik's fresh
  live visual pass, the final ledger-feel acceptance boundary.
- This build captured four ZPC lessons and one decision in total. Integration
  added `les-276780` and `les-b6b365` to the worker's two lessons and one
  decision.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-ac0b36`.
4. Commit with `Manna: mn-ac0b36` and run `agent-do manna done mn-ac0b36` only after the work is verified.
