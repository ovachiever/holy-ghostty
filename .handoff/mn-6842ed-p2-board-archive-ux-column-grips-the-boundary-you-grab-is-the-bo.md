---
workflow: 2
manna: mn-6842ed
track: mn-9a97cc
source: Erik 2026-09-05; reference fix agent-do 7ad4d44 + 5907454
base_commit: 8827922087e9abb78e3a5bff7bf6d164bcd13545
scope: '[P2][BOARD][ARCHIVE][UX] Column grips: the boundary you grab is the boundary that moves'
inputs:
- Erik 2026-09-05; reference fix agent-do 7ad4d44 + 5907454
binding: sha256:851319d6a773c59dc341db068d9d538fe699aecdb8d8cf65ed29654ac9f68d25
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
