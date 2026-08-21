---
workflow: 2
manna: mn-573ec9
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P2][CONTROL] Add brokered leases, human preemption, quotas, and audit'
inputs: []
binding: sha256:5c1fb13ad612f0016fc11d15a0d99d587c9ab97573ba0999b820217281959a39
---

# Handoff: [P2][CONTROL] Add brokered leases, human preemption, quotas, and audit

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-573ec9
```

## Scope

[P2][CONTROL] Add brokered leases, human preemption, quotas, and audit

## Inputs

- None declared.

## Work order

Implement Holy as the broker; never grant direct peer-to-pane control.

Done when there is one controller lease per target, immediate human preemption, expiry, action quotas/rate limits, permission scoping, and complete session_events audit. Integrate with or explicitly respect agent-do coord claims/focus so there are not two mutually blind ownership systems. Expired, preempted, over-quota, busy, or unknown controllers cannot send input.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-573ec9`.
4. Commit with `Manna: mn-573ec9` and run `agent-do manna done mn-573ec9` only after the work is verified.
