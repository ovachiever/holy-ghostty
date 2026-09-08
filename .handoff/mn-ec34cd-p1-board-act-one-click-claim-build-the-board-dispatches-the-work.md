---
workflow: 2
manna: mn-ec34cd
track: mn-9a97cc
source: Erik request 2026-09-08 13:35 ('this is now in holy')
base_commit: 78b6847ac0ff92b707d8f483d96e8996ff22294b
scope: '[P1][BOARD][ACT] One-click ''Claim & build'': the board dispatches the worker itself'
inputs:
- Erik request 2026-09-08 13:35 ('this is now in holy')
binding: sha256:15546101e394b7ae0d462623bd04b02abc425421c6ba27b26db87f390846a9f5
---

# Handoff: [P1][BOARD][ACT] One-click 'Claim & build': the board dispatches the worker itself

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-ec34cd
```

## Scope

[P1][BOARD][ACT] One-click 'Claim & build': the board dispatches the worker itself

## Inputs

- Erik request 2026-09-08 13:35 ('this is now in holy')

## Work order

Erik 2026-09-08: replace the copy-command affordance with a single 'Claim & build' action on any claimable item — Holy hosts the sessions, so the board should dispatch the worker directly instead of making Erik paste commands. Behavior: the action (confirm-gated like every board mutation — an explicit named verb, not a glance) spawns a NEW session in the item's board root via the existing launch machinery: runtime from a per-board or global worker profile (codex/claude, model), cwd = board root, and the worker brief delivered as the session's opening prompt. The brief is GENERATED, not hand-pasted, and bakes in the house protocol Erik currently types by hand every time: claim <id> first; read the sealed handoff at its path; coord focus + claims; focused suites only; keep the tree buildable; no app launches, installs, or screenshots mid-lane; the live/visual pass is coordinated at close; commit with the Manna trailer; never push; report in the standard format with lessons/decisions counts. Safety rails: refuses dreams (claim exits 2 — surface the refusal honestly), refuses already-claimed items (shows the claimant instead), and the initialInput safety law holds — the brief arrives as a prompt the harness receives at start, never as shell input that executes board-mutating commands before the worker exists (the worker itself runs the claim, so a failed spawn leaves the board untouched). Row and inspector both carry the action; disabled state explains why when unavailable. Tests: dream refusal, claimed refusal, generated-brief content pinned (protocol clauses present), spawn failure leaves no claim.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-ec34cd`.
4. Commit with `Manna: mn-ec34cd` and run `agent-do manna done mn-ec34cd` only after the work is verified.
