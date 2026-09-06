---
workflow: 2
manna: mn-f044d0
track: mn-9a97cc
source: Erik report 2026-09-05 20:58 (MacBook screenshot in his Downloads; TCC blocked remote read — attach via iCloud Screen Shots for pixel triage if needed)
base_commit: 5466c2fada020da9fef58752e955d6caf68d7332
scope: '[P1][BOARD][ARCHIVE][UX] Ledger layouts must fit any window: clamp, flex, and fold like the web cockpit'
inputs:
- Erik report 2026-09-05 20:58 (MacBook screenshot in his Downloads; TCC blocked remote read — attach via iCloud Screen Shots for pixel triage if needed)
binding: sha256:3f41cfcf1be36940b065224baf7cb48311e1656297e4c5bcf38a7a2dabaabf84
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
