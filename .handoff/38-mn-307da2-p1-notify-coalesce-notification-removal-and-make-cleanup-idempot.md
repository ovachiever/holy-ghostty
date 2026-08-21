---
workflow: 2
manna: mn-307da2
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P1][NOTIFY] Coalesce notification removal and make cleanup idempotent'
inputs: []
binding: sha256:164cc703bbc53c8d390f0fe2d6efdc88f00e9dd9456720d0df7f346ea6aaabaf
---

# Handoff: [P1][NOTIFY] Coalesce notification removal and make cleanup idempotent

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-307da2
```

## Scope

[P1][NOTIFY] Coalesce notification removal and make cleanup idempotent

## Inputs

- None declared.

## Work order

Independent finding from the July 17 read-only selection audit. The damaged-mouse root cause invalidates the selection complaint but does not invalidate the notification telemetry.

Evidence:
- Logs since the July 16 installed build contained 19,419 pending-removal plus 19,419 delivered-removal calls, with peaks around 238 pairs per minute.
- Live sampling showed notification and persistence work repeatedly reaching the main thread during rapid session mutations.
- This churn directly threatens the existing exactly-once notification acceptance gate even if it did not cause the drag failure.

Invariant:
Notification state transitions are semantic and idempotent. Re-observing the same state must do no notification-center work, no durable mutation, and no user-visible duplicate or missed alert.

Done when:
- Removal is keyed by stable semantic notification identity and occurs only on a real transition.
- Repeated title, render, focus, roster, restart, and reconnect events produce no redundant removal calls.
- Missed-event replay remains exactly once and notification-click ownership still works.
- Counters expose scheduled, delivered, removed, deduplicated, and replayed operations.
- A 24-hour installed-app soak meets a documented low churn ceiling while passing mn-8179b6 acceptance.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-307da2`.
4. Commit with `Manna: mn-307da2` and run `agent-do manna done mn-307da2` only after the work is verified.
