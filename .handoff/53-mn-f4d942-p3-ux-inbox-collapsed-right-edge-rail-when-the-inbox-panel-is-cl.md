---
workflow: 2
manna: mn-f4d942
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P3][UX][INBOX] Collapsed right-edge rail when the inbox panel is closed'
inputs: []
binding: sha256:8b5c09f0c5a4688f451562797e4c84ce509d591d48c64c5f14f1e723e9cfbb83
---

# Handoff: [P3][UX][INBOX] Collapsed right-edge rail when the inbox panel is closed

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-f4d942
```

## Scope

[P3][UX][INBOX] Collapsed right-edge rail when the inbox panel is closed

## Inputs

- None declared.

## Work order

Erik 2026-08-10: "there is also no collapsed roster rail on the right, which could be nice." The left roster collapses to a slim rail with affordances; the right panel just vanishes, leaving only the bottom tray button and menu/⌘P. Idea: a symmetric slim right-edge rail when the panel is closed — panel toggle, badge, and future tab affordances (mn-fe1b48 adds the second panel case). Rides the existing HolyWorkspaceRightPanel enum host; one right-hand region, ever.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-f4d942`.
4. Commit with `Manna: mn-f4d942` and run `agent-do manna done mn-f4d942` only after the work is verified.
