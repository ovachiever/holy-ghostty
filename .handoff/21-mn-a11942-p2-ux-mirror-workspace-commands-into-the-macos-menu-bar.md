---
workflow: 2
manna: mn-a11942
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P2][UX] Mirror workspace commands into the macOS menu bar'
inputs: []
binding: sha256:ca82649cdf6a2f6184083ce292706a134609dc80b57e182af2ac45c3de30a903
---

# Handoff: [P2][UX] Mirror workspace commands into the macOS menu bar

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-a11942
```

## Scope

[P2][UX] Mirror workspace commands into the macOS menu bar

## Inputs

- None declared.

## Work order

Give sidebar-only commands menu-bar equivalents so Help-menu search finds them and keyboard shortcuts become assignable: File (new session from template/profile), View (roster layout classic/calm/triage/focus), Session (per-selected-session actions from the row … menu). Sidebar menus stay as-is — this is mirroring, not relocation. Ref: HolySessionRosterView.swift moreMenu (~:226), makeMenu (~:1275), MainMenu.xib.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-a11942`.
4. Commit with `Manna: mn-a11942` and run `agent-do manna done mn-a11942` only after the work is verified.
