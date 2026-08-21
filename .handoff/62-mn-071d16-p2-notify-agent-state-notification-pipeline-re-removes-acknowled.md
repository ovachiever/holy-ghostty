---
workflow: 2
manna: mn-071d16
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P2][NOTIFY] Agent-state notification pipeline re-removes acknowledged notifications 1-3x/sec continuously'
inputs: []
binding: sha256:79c911ec8b16f0dc5828445891a6a61e2b2e11f1503e2d61bfcfd4c70197f396
---

# Handoff: [P2][NOTIFY] Agent-state notification pipeline re-removes acknowledged notifications 1-3x/sec continuously

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-071d16
```

## Scope

[P2][NOTIFY] Agent-state notification pipeline re-removes acknowledged notifications 1-3x/sec continuously

## Inputs

- None declared.

## Work order

Observed 2026-08-12 08:55-09:25 (log show, process holy-ghostty, UserNotifications): 'Removing 1 pending notification requests' + delivered-removal pairs for the same identifier (e.g. 4C30-8F95) at 19-166 removals/minute, sustained. Source: HolyWorkspaceStore.completeAuthoritativeAgentNotification (~:4106) — the focus-acknowledged branch re-issues removePendingNotificationRequests/removeDeliveredNotifications on EVERY completed envelope while agentNotificationRetryEventIDs mismatches, i.e. once per agent-state event for an active focused session. Async XPC so panes are not blocked, but it spams the notification center and the log, and burns CPU in both processes. Fix shape: remember the last-removed identifier per session and skip when unchanged, or only remove when a delivered/pending request can actually exist (scheduling result says it was added). Found while chasing the paste-freeze report; not established as its cause.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-071d16`.
4. Commit with `Manna: mn-071d16` and run `agent-do manna done mn-071d16` only after the work is verified.
