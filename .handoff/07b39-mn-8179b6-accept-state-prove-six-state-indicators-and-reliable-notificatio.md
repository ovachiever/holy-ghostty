---
workflow: 2
manna: mn-8179b6
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[ACCEPT][STATE] Prove six-state indicators and reliable notifications'
inputs: []
binding: sha256:5e3b8de9a58dfb51330013a8bc871feed6c7d5bb05582cb57091f8250c463f2e
---

# Handoff: [ACCEPT][STATE] Prove six-state indicators and reliable notifications

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-8179b6
```

## Scope

[ACCEPT][STATE] Prove six-state indicators and reliable notifications

## Inputs

- None declared.

## Work order

Canonical product vocabulary from .handoff/INDICATORS-FIRST-PRINCIPLES-2026-07-14.md:
- spinner = working
- question mark = genuinely needs the user, including approval
- white dot = unread finished work
- blue dot = seen/used today
- muted grey dot = inactive 24-48 hours
- sleeping Z plus grey = inactive 48+ hours
The hand and grey checkmark are banned; unread replaces recency.

Commit 537c0a567 is implementation evidence. Done when Tier-3 screen text cannot create an operational state, unread appears within 2 seconds of committed finish, notification tokens dedupe across restart/reconnect, missed events replay exactly once, every alert has auditable evidence, and a 24-hour installed-app soak with dev servers has zero sustained false spinners.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-8179b6`.
4. Commit with `Manna: mn-8179b6` and run `agent-do manna done mn-8179b6` only after the work is verified.
