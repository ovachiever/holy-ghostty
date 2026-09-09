---
workflow: 2
manna: mn-eb6b3e
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: 'Pre-existing test failure: HolyBriefTriageTests/needsMeThreadsLeadAndCalmThreadsStayOut fails on clean main'
inputs: []
binding: sha256:fccbe721244f4974ab4fc9fe419d76ef715babdb8754aa4ee4ee151ed0194b93
---

# Handoff: Pre-existing test failure: HolyBriefTriageTests/needsMeThreadsLeadAndCalmThreadsStayOut fails on clean main

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-eb6b3e
```

## Scope

Pre-existing test failure: HolyBriefTriageTests/needsMeThreadsLeadAndCalmThreadsStayOut fails on clean main

## Inputs

- None declared.

## Work order

Found 2026-08-18 during the codex-PATH fix lane: fails identically on clean main (verified via stash + isolation rerun; 40 others in the suite pass). Inbox/brief-triage code, unrelated to Restore. Filed so gates stop tripping on it; fix or fold into tolerated set.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-eb6b3e`.
4. Commit with `Manna: mn-eb6b3e` and run `agent-do manna done mn-eb6b3e` only after the work is verified.
