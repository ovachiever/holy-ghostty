---
workflow: 2
manna: mn-ec34cd
track: mn-9a97cc
source: Erik request 2026-09-08 13:35 ('this is now in holy')
base_commit: 78b6847ac0ff92b707d8f483d96e8996ff22294b
scope: '[P1][BOARD][ACT] One-click ''Claim & build'': the board dispatches the worker itself'
inputs:
- Erik request 2026-09-08 13:35 ('this is now in holy')
binding: sha256:04273b1b0dabc9a29a46f544c2fb50a2a26221b2741f2c81d3e34ea2433db3a6
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

## Implementation receipt (2026-09-08)

Implemented row and inspector Claim & build controls, an explicit confirmation, global Codex/Claude worker selection with a separate saved model for each runtime, and dispatch through HolyWorkspaceStore.createSession. The immutable request captures the board root, remote host, runtime/model, item, and sealed handoff. Confirmation rereads canonical state and refuses a competing claim or changed handoff before opening a session.

The generated brief is one shell-quoted harness startup argument. initialInput remains nil. The worker itself runs the first claim command, reads and verifies the sealed handoff, coordinates paths, runs focused validation, avoids launches/installs/screenshots/push, commits with the Manna trailer, and reports actual checks plus lessons/decisions counts. Dreams explain the promotion prerequisite; claimed items display their claimant. Holy performs no pre-spawn claim, and failed surface creation leaves the board unchanged.

Validation: focused `xcodebuild build-for-testing` succeeded for HolyMannaBoardActionsTests, HolyMannaBoardTests, and HolyMannaBoardPresentationTests. The shared new actions suite has 9 regression cases, including dream/claim refusal, protocol clauses, startup argument quoting, remote transport, confirmation, failed spawn/no claim, and a competing-claim race. These tests were compiled, not executed; no worker was dispatched. ReleaseLocal and core verification receipts are in `.dev/mn-board-actions/report.md`.

Needed next: coordinated synthetic-board acceptance of cancel/confirm, the selected Codex and Claude profiles, local/remote repository placement, initial prompt receipt, worker-owned claim, and failed-start behavior. Execute the focused app-hosted tests only in that coordinated lane. Keep this item in_progress until that acceptance is recorded.
