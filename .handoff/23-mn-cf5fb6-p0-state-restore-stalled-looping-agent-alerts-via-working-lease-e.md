---
workflow: 2
manna: mn-cf5fb6
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P0][STATE] Restore stalled/looping agent alerts via working-lease expiry'
inputs: []
binding: sha256:2ee77982431559fde3b5245f7e01388d323ac2b39b1fe6f75f3e7d8091da61e6
---

# Handoff: [P0][STATE] Restore stalled/looping agent alerts via working-lease expiry

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-cf5fb6
```

## Scope

[P0][STATE] Restore stalled/looping agent alerts via working-lease expiry

## Inputs

- None declared.

## Work order

xhigh review finding (CONFIRMED, HolySessionSupervisor.swift:1453): the screen-derived 'may be stalled/looping' notifications were deleted and the wire contract (working|needs-user|finished|failed|idle|ended) has no stalled lifecycle — a wedged agent that never emits finished/needs-user is now silent and decays to age dots while burning budget. Design: the working-claim lease expiry (envelope timestamps already bound working claims) should raise an 'agent may be stalled' alert through HolyAgentNotificationPolicy with auditable evidence. This is a hole in mn-8179b6's own acceptance ('every alert has auditable evidence' — a wedged agent produces no alert at all).

P0 2026-08-07 (Erik, /board audit decision): mn-8cec74's lease-extension work made this strictly worse — a wedged agent whose TUI keeps redrawing satisfies producerProcessAlive + fresh producerLastOutputAt and extends the working claim indefinitely (HolyModels.swift:421-441); the 30-minute cutoff no longer bites for exactly the wedged-agent case this issue exists to catch. Note also producerLastOutputAt is window-scoped (tmux window_activity), so a chatty neighbor pane in the same window can hold a dead claim alive.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-cf5fb6`.
4. Commit with `Manna: mn-cf5fb6` and run `agent-do manna done mn-cf5fb6` only after the work is verified.
