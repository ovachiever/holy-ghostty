---
workflow: 2
manna: mn-ba0a11
track: mn-70875b
source: null
base_commit: 439f499e525d1b990f74b86c66334321e48f84e5
scope: '[P1][USAGE] Usage guard: three tiers — notice 75, no new spawns 90, wrap up 95'
inputs: []
binding: sha256:61237f6971be59af3e710ff3d4360a72ae858e384610042ab3e4cc5c1bec671a
---

# Handoff: [P1][USAGE] Usage guard: three tiers — notice 75, no new spawns 90, wrap up 95

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-ba0a11
```

## Scope

[P1][USAGE] Usage guard: three tiers — notice 75, no new spawns 90, wrap up 95

## Inputs

- None declared.

## Work order

Agents over-obeyed the two-tier guard: they slowed at 75 and refused at 90. Redesign: warn (75) informs the user and changes nothing; restrain (90) denies new subagents/workflows/long tasks while the work in hand continues; critical (95, or cap within lead minutes) wraps up now with a PAUSED note, the user re-logs under a lower-usage Fable account. Swift policy gains restrainPercent (defaults key holy.claudeUsage.restrainPercent, JSON restrain_percent); the Python hook mirrors it; both copies of the policy loader clamp warn <= restrain <= critical.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-ba0a11`.
4. Commit with `Manna: mn-ba0a11` and run `agent-do manna done mn-ba0a11` only after the work is verified.
