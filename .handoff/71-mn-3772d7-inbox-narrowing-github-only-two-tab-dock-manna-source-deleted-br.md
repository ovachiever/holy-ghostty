---
workflow: 2
manna: mn-3772d7
track: mn-9a97cc
source: Erik ratified inline 2026-08-31 (One Ledger Two Faces); see track mn-9a97cc
base_commit: 0c6ba8bc635e3fcd76909c5e163e48fa53fa6e85
scope: 'Inbox narrowing: GitHub-only two-tab dock; manna source deleted; brief and compat views retired'
inputs:
- Erik ratified inline 2026-08-31 (One Ledger Two Faces); see track mn-9a97cc
binding: sha256:f8c29bcdba31e74571f62a6f70c4da521f068b3f1c6655e26d8bdd9b5fc3b44e
---

# Handoff: Inbox narrowing: GitHub-only two-tab dock; manna source deleted; brief and compat views retired

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-3772d7
```

## Scope

Inbox narrowing: GitHub-only two-tab dock; manna source deleted; brief and compat views retired

## Inputs

- Erik ratified inline 2026-08-31 (One Ledger Two Faces); see track mn-9a97cc

## Work order

The right dock becomes GitHub only: two tabs — this project / all. Delete HolyMannaInboxSource.swift (~959 lines) + its three test files + registration in HolyWorkspaceStore; re-anchor the project tab label and the lens working directory on ownership.repositoryRoot (they currently come from the manna board locator). Alerts surface scrapped — alerts keep firing where they already fire; the alerts DB table stays. Retire the dormant brief-for-Holy surface (HolyBriefFeed + HolyBriefViews render path; the agent-do brief CLI is not Holy's concern) and the agent_sessions_*_v1 compatibility views + their planned provider (superseded: Holy owns its archive natively). Manna items mn-b2e2e9 (manna latency) and mn-31aaf2 (manna process runner unification) die with the source; mn-5dc58b and mn-7fbb07 are superseded by board mode; reconcile those as part of the drift item on this track.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-3772d7`.
4. Commit with `Manna: mn-3772d7` and run `agent-do manna done mn-3772d7` only after the work is verified.
