---
workflow: 2
manna: mn-6160c9
track: mn-9a97cc
source: Erik live report 2026-09-10 15:22; companion defect to mn-ec34cd's dispatch flow
base_commit: b74e8fc7d4fb43f8cfcb48135cf59435920cf42e
scope: '[P1][BOARD][UX] Claim & build leaves the row frozen in next: no feedback until navigation forces a refresh'
inputs:
- Erik live report 2026-09-10 15:22; companion defect to mn-ec34cd's dispatch flow
binding: sha256:a3547a9c5d6d7342e7b34e7ce4296d74be841bfbf3394ccba5a13134e3bd80fb
---

# Handoff: [P1][BOARD][UX] Claim & build leaves the row frozen in next: no feedback until navigation forces a refresh

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-6160c9
```

## Scope

[P1][BOARD][UX] Claim & build leaves the row frozen in next: no feedback until navigation forces a refresh

## Inputs

- Erik live report 2026-09-10 15:22; companion defect to mn-ec34cd's dispatch flow

## Work order

Erik 2026-09-10: clicking Claim & build dispatches fine, but the item stays in $ manna next looking untouched until he leaves the page or dispatches something else — the board only picks up the claim on its next incidental refresh. Root cause shape: the worker performs the claim AFTER it boots (by design — a failed spawn must leave the board untouched, mn-ec34cd law), so there is nothing synchronous for the view to read; the view also runs no post-action refresh. Fix in two honest layers: (1) OPTIMISTIC CHROME, not optimistic state — the instant dispatch is confirmed, the clicked row shows a transient 'dispatched · worker booting' chip (and the Claim & build affordance disables) WITHOUT moving the row: the row moves only when the real claim lands; (2) CONVERGENCE — after a confirmed dispatch, the board refreshes immediately and then on a short cadence (a few seconds, bounded ~60s) until the claim appears (row moves to $ manna now with the claimant) or the window expires — expiry clears the chip and surfaces 'worker did not claim within 60s' with the session link, because a silent revert is how this bug feels today. Never mark in_progress locally before the board says so (the board is the only truth; optimistic STATE would recreate the paper-open we just outlawed). Same treatment for the inspector's other mutation verbs if any share the fire-and-forget shape. Tests: chip appears on dispatch and clears on claim-seen; convergence poll stops on claim or expiry; a spawn failure clears the chip and reports; the row never moves without board evidence. Acceptance: Erik clicks Claim & build and within seconds watches the row wear the chip, then slide to $ manna now on its own.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-6160c9`.
4. Commit with `Manna: mn-6160c9` and run `agent-do manna done mn-6160c9` only after the work is verified.
