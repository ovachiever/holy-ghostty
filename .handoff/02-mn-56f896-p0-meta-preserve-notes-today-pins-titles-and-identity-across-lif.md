---
workflow: 2
manna: mn-56f896
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P0][META] Preserve notes, Today pins, titles, and identity across lifecycle'
inputs: []
binding: sha256:b6d91465b8e90b73a7e5c8242424d4a74171f94c7f130a1dcf5ae8e3919d20d2
---

# Handoff: [P0][META] Preserve notes, Today pins, titles, and identity across lifecycle

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-56f896
```

## Scope

[P0][META] Preserve notes, Today pins, titles, and identity across lifecycle

## Inputs

- None declared.

## Work order

User-visible bug: session notes disappeared after Clear plus Attach All; Today pin must survive the same transition. Commit 00e4194e8 is partial implementation evidence, not acceptance.

Scope:
- Bind user-authored metadata to stable logical/session and remote tmux identity, not disposable roster rows.
- Preserve note, explicit title, Today pin, roster order, and source Holy UUID across Clear, Attach All, restart, archive, readoption, relaunch, and recovery.
- Define the Today pin date/expiration rule explicitly.
- Prevent duplicate records and stale rows from overwriting newer user edits.

Done when:
- Transition-matrix tests cover local and SSH sessions across every lifecycle path.
- Studio and MacBook installed builds preserve edits through Clear plus Attach All.
- Conflicts fail visibly; no silent metadata loss.
- Current drag-to-reorder issue mn-211310 can then be re-evaluated.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-56f896`.
4. Commit with `Manna: mn-56f896` and run `agent-do manna done mn-56f896` only after the work is verified.
