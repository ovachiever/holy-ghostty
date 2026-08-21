---
workflow: 2
manna: mn-a320e4
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P3][UX] Heat gauge: session usage intensity over rolling 24h window'
inputs: []
binding: sha256:34bbe9bab986ab98cd6b360e79128866a5a78fc421f7d55ebe5c45e95d25f9fb
---

# Handoff: [P3][UX] Heat gauge: session usage intensity over rolling 24h window

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-a320e4
```

## Scope

[P3][UX] Heat gauge: session usage intensity over rolling 24h window

## Inputs

- None declared.

## Work order

Erik (2026-07-14): 'a heat gauge could be cool (e.g. you use this one a lot in this current 24 hr rolling window)' — explicitly deferred behind the unread indicator, never tracked. Visual cue on roster rows scaled to interaction/activity volume in a rolling day. Data likely derivable from session_events volume or attention metadata timestamps; design must pass the six-state at-a-glance test and not add a seventh operational state.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-a320e4`.
4. Commit with `Manna: mn-a320e4` and run `agent-do manna done mn-a320e4` only after the work is verified.
