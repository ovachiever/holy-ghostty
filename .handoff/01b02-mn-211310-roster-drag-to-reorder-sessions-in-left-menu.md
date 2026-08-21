---
workflow: 2
manna: mn-211310
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: 'Roster: drag-to-reorder sessions in left menu'
inputs: []
binding: sha256:6aba21e1363d6b07fbf04b6830bde558f6560c3b75c8b8fb7b9fddfe5a632689
---

# Handoff: Roster: drag-to-reorder sessions in left menu

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-211310
```

## Scope

Roster: drag-to-reorder sessions in left menu

## Inputs

- None declared.

## Work order

Erik wants to manually reorder sessions in the roster (left menu) by drag-and-drop — e.g. with two sessions both named 'Aldebaran Group', put one 'first, on top' as a reminder of which is which. PARKED 2026-07-05 while SSH-resilience plan executes. Possibly superseded by cheaper alternatives (see companion issue on notes/pin persistence). UI lives in macos/Sources/HolyGhostty/Workspace/HolySessionRosterView.swift.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-211310`.
4. Commit with `Manna: mn-211310` and run `agent-do manna done mn-211310` only after the work is verified.
