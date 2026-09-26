---
workflow: 2
manna: mn-8a90ee
track: mn-eb7a80
source: .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 2
base_commit: 74e8e8b0daa88cf1681b19ce560068c684fac4a5
scope: '[P1][ROSTER] Done-done indicator: a distinct mark when the agent has sealed its item'
inputs:
- .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 2
binding: sha256:69b565e446734a73b12b9f9cb7e88b80e650d190cd1148eba1014b39a7d92bbe
---

# Handoff: [P1][ROSTER] Done-done indicator: a distinct mark when the agent has sealed its item

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-8a90ee
```

## Scope

[P1][ROSTER] Done-done indicator: a distinct mark when the agent has sealed its item

## Inputs

- .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 2

## Work order

Green currently means the turn ended. Add a distinct check mark meaning manna done executed for the item this session claimed, so a fleet of quick spawns can be scanned for finished work. Not blue, cyan, or magenta (Erik, 09-22 and 09-23). Source of truth is the board (manna state or the trailer commit), never pane text. Done when a session whose item reaches done shows the mark within one Sync and a session that merely idles never does.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-8a90ee`.
4. Commit with `Manna: mn-8a90ee` and run `agent-do manna done mn-8a90ee` only after the work is verified.
