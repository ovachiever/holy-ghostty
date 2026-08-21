---
workflow: 2
manna: mn-a0406e
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P0][STATE] Launch-time focus churn marks every session seen+used — all dots blue after every restart'
inputs: []
binding: sha256:7804668ab5de80ee1b7ec51c5f34fa77392eb63b9173360fec3e327d7d5e5a99
---

# Handoff: [P0][STATE] Launch-time focus churn marks every session seen+used — all dots blue after every restart

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-a0406e
```

## Scope

[P0][STATE] Launch-time focus churn marks every session seen+used — all dots blue after every restart

## Inputs

- None declared.

## Work order

Evidence 2026-07-16: after each app relaunch, persisted attention_metadata shows lastSeenAt == lastUsedAt for 22/25 sessions with timestamps spread across the launch window (18:06–18:13Z for a 18:06Z relaunch). Decode/versioning are NOT the cause (verified: HolyPersistenceCoders symmetric ISO8601; seenTrackingVersion round-trips at v1; persistence reads attention_metadata at HolyWorkspaceDatabasePersistence.swift:159). Mechanism: during window/pane restoration every session's SurfaceView transiently satisfies markSessionSeenIfNeeded's guards (NSApp.isActive + key window + surfaceView.focused, HolyWorkspaceStore.swift:2099) as surfaces initialize, so programmatic focus churn masquerades as the user reading every session. Result: restart erases the entire recency axis — everything reads used-today (blue) for the next 24h.

Fix direction: seen/used marking requires REAL attention, not instantaneous focus — e.g., a dwell requirement (surface focused continuously for 1–2s) and/or a post-restore quiescence window before seen-marking arms. Belongs with mn-596f61's markSeenBaseline/genuine-use split; fix together and verify by relaunching twice and confirming old sessions keep old lastUsedAt.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-a0406e`.
4. Commit with `Manna: mn-a0406e` and run `agent-do manna done mn-a0406e` only after the work is verified.
