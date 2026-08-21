---
workflow: 2
manna: mn-7e8e0d
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P1][STATE] Verify committed-finish latency vs the 2-second unread criterion'
inputs: []
binding: sha256:2c5c995bf854f7a1f04dca83face86ab291b3054321bf30cd65b495b6482fd12
---

# Handoff: [P1][STATE] Verify committed-finish latency vs the 2-second unread criterion

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-7e8e0d
```

## Scope

[P1][STATE] Verify committed-finish latency vs the 2-second unread criterion

## Inputs

- None declared.

## Work order

mn-8179b6 accepts only if unread appears ≤2s after committed finish, but Claude completion is committed from Notification(idle_prompt), whose upstream delay has NO documented latency guarantee (the spec admits this; if it is the idle nudge it can be tens of seconds). Measure real idle_prompt latency on the installed app; if it breaks the criterion, design the fallback (e.g., Stop + short confirmation window instead of idle_prompt-only). Found by session review; NOT caught by the repo-bound multi-agent review — external-latency issues cannot be verified from source.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-7e8e0d`.
4. Commit with `Manna: mn-7e8e0d` and run `agent-do manna done mn-7e8e0d` only after the work is verified.
