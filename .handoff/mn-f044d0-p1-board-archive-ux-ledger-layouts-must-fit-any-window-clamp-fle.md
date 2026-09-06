---
workflow: 2
manna: mn-f044d0
track: mn-9a97cc
source: Erik report 2026-09-05 20:58 (MacBook screenshot in his Downloads; TCC blocked remote read — attach via iCloud Screen Shots for pixel triage if needed)
base_commit: 5466c2fada020da9fef58752e955d6caf68d7332
scope: '[P1][BOARD][ARCHIVE][UX] Ledger layouts must fit any window: clamp, flex, and fold like the web cockpit'
inputs:
- Erik report 2026-09-05 20:58 (MacBook screenshot in his Downloads; TCC blocked remote read — attach via iCloud Screen Shots for pixel triage if needed)
binding: sha256:db95d86fd9bf5104ff52212894ee6127908b933e7120a4a148fc2640e9a29c67
---

# Handoff: [P1][BOARD][ARCHIVE][UX] Ledger layouts must fit any window: clamp, flex, and fold like the web cockpit

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-f044d0
```

## Scope

[P1][BOARD][ARCHIVE][UX] Ledger layouts must fit any window: clamp, flex, and fold like the web cockpit

## Inputs

- Erik report 2026-09-05 20:58 (MacBook screenshot in his Downloads; TCC blocked remote read — attach via iCloud Screen Shots for pixel triage if needed)

## Work order

Erik 2026-09-05, MacBook: board columns clip off the right edge — persisted grip widths and pinned column sizes from a large monitor exceed a smaller window's width, and the table clips instead of compressing. Mirror the reference stylesheet's responsive law natively, in BOTH board and archive modes (shared ledger layout): (1) FLEX: the DIGEST/title column is the flexible one (minmax semantics — it absorbs all width changes and truncates with ellipsis); ID, STATE, and # stay content-sized; TRACK truncates first and hides entirely below a narrow threshold. (2) CLAMP: user grip widths persist as PROPORTIONS clamped so the sum of columns never exceeds the available pane width — a layout dragged on a 27-inch monitor must render un-clipped on a 14-inch without touching the grips; per-window recompute on resize and on screen change. (3) FOLD: the inspector width becomes min(persisted, ~35% of window), shrinks below ~1100pt, and collapses below ~860pt behind a toggle, exactly as styles.css does at its breakpoints; the estate strip scrolls horizontally within itself rather than widening the page. (4) Never a horizontal window scroll and never clipped glyphs at any width >= ~900pt; degrade explicitly below that (the left-rail footer degradation pattern is the house precedent). Verify with view snapshots at 1000/1280/1512/1728pt widths plus a grip-dragged-then-narrowed case; no app launches — previews and snapshot rendering only, visual pass with Erik at close. Applies to: board list + estate strip + inspector, archive list + detail + chat rows.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-f044d0`.
4. Commit with `Manna: mn-f044d0` and run `agent-do manna done mn-f044d0` only after the work is verified.

## Implementation receipt

- `HolyLedgerResponsiveLayout` is the shared Board and Archive width-budget
  authority. It reserves the flexible text floor, shrinks the secondary column
  first, and resolves every row to the current pane width.
- Grip preferences now use a versioned proportional payload. Existing flat
  pixel payloads migrate against the 1440-point reference measure.
- Board DIGEST and Archive SUMMARY own the flexible remainder. TRACK and PROJECT
  truncate first and hide at 1100 points or below.
- Both inspectors cap at 35 percent of window width, narrow to 260 points at
  1100 points or below, and fold behind `[detail]` at 860 points or below.
- Board estate owns its horizontal scroll and no longer widens the page.

## Verification receipt

- Strict SwiftLint over the six changed Swift files: 0 violations.
- Board, Archive, presentation, and render suites: 69 passed, 0 failed, 0
  skipped. Result bundle:
  `/Users/erik/Library/Developer/Xcode/DerivedData/Ghostty-evzhqzgwedstedhkeiqpqvomarls/Logs/Test/Test-Ghostty-2026.09.05_21-49-24--0500.xcresult`.
- `scripts/test-holy-ghostty-build-contract.sh`: passed.
- Offscreen visual matrix: 22 PNGs under `.dev/mn-f044d0/`, including Board
  and Archive at 900/1000/1280/1512/1728 points, dragged-then-narrowed at 1120,
  compact fold at 840, Board estate at 1000, and the remaining Board/Archive
  faces. No app was ordered on screen.
- Local visual inspection found no horizontal window overflow or clipped glyphs
  in the required matrix. Human close gate remains Erik's requested visual pass.
- The 23-file receipt bundle is mirrored to iCloud Transfer at
  `Transfer/mn-f044d0/`.
- The completion note exists at
  `Erkverse/+/2026-09-05 mn-f044d0 Responsive Ledgers.md`. Its post-write local
  index refresh remains blocked by a macOS TCC `Operation not permitted` error
  on the vault root; the note contents were verified directly.
- ZPC received 7 error-resolution lessons and 0 decisions for this build.
