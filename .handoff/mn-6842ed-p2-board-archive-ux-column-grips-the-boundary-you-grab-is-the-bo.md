---
workflow: 2
manna: mn-6842ed
track: mn-9a97cc
source: Erik 2026-09-05; reference fix agent-do 7ad4d44 + 5907454
base_commit: 8827922087e9abb78e3a5bff7bf6d164bcd13545
scope: '[P2][BOARD][ARCHIVE][UX] Column grips: the boundary you grab is the boundary that moves'
inputs:
- Erik 2026-09-05; reference fix agent-do 7ad4d44 + 5907454
binding: sha256:9e86e8688695042c5f0efe8e5b5f9e01c250ddb58379f70acc0b76ae4a435b49
---

# Handoff: [P2][BOARD][ARCHIVE][UX] Column grips: the boundary you grab is the boundary that moves

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-6842ed
```

## Scope

[P2][BOARD][ARCHIVE][UX] Column grips: the boundary you grab is the boundary that moves

## Inputs

- Erik 2026-09-05; reference fix agent-do 7ad4d44 + 5907454

## Work order

Erik 2026-09-05: native ledger column dividers have 'reverse airplane controls' — dragging some grips resizes the opposite side of the column. The web cockpit had and FIXED this exact bug; port the reference semantics from agent-do commits 7ad4d44 ('columns survive long tracks; boundary drags move the boundary you grab') and 5907454 ('a column layout may not starve the digest — bad stored widths are discarded, and the fit measures content, never the current layout'). Rules: a grip owns exactly the boundary under it (left neighbor grows/shrinks, flexible digest column absorbs the remainder — never a distant column); stored widths that no longer fit are discarded, not clamped into nonsense; content-measured minimums so no column can be starved to zero. Applies to board AND archive ledgers; coordinate with mn-f044d0 (responsive clamp/flex/fold) — same files, likely the same worker lane; add a drag-semantics test per grip position.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-6842ed`.
4. Commit with `Manna: mn-6842ed` and run `agent-do manna done mn-6842ed` only after the work is verified.

## Implementation receipt

Implemented 2026-09-05 as the native port of agent-do commits `7ad4d44` and `5907454`.

- A shared `HolyLedgerColumnBoundary` transaction now models the divider itself. Before the flexible column, the fixed column follows pointer delta. Immediately after the flexible column, the fixed column uses inverse delta. Between right-side fixed columns, width transfers one for one between the two neighbors, with neither side crossing its content/header floor.
- Board mappings are explicit for ID, TRACK, STATE, and priority/age, including the narrow Board without TRACK. Archive mappings are explicit for DATE, HARNESS, PROJECT, and SUB. Right-side grips render on the leading edge, so the visible rule and the modeled divider are the same object.
- Double-click refits every fixed column that participates in the grabbed boundary.
- Stored widths that would starve the flexible digest/summary floor are marked invalid, cleared from `AppStorage`, and recomputed from content-fit widths. If the content fit is still wide, available shrink room is shared proportionally down to semantic floors before the existing last-resort no-overflow scale.

Verification:

- `HolyLedgerColumnOverridesTests`: 7 passed, including a drag-semantics assertion for every Board and Archive grip position, fixed-pair conservation and floors, poisoned width discard, responsive inspector rules, and preference migration.
- `HolyArchiveModeTests` and `HolyArchivePresentationTests`: passed.
- Strict SwiftLint on all six owned source and test files: 0 violations.
- `xcodebuild build-for-testing`: passed.
- `HolyMannaBoardRenderSmokeTests` and `HolyArchiveRenderSmokeTests`: passed. Representative 1280 point and persisted-width-then-narrowed renders were inspected with no clipping, overlap, or displaced column rule.
- `scripts/test-holy-ghostty-build-contract.sh`: passed.

Detailed receipt and render artifacts: `.dev/mn-bf6fe1-mn-6842ed/`.
