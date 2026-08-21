---
workflow: 2
manna: mn-9eb075
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P1][SYNC] Add opt-in Sync Session Config to menu and Attach All'
inputs: []
binding: sha256:24999c7a365dd967882a49a6fac1b9e8f235e89379a14a449c93a3d739f01719
---

# Handoff: [P1][SYNC] Add opt-in Sync Session Config to menu and Attach All

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-9eb075
```

## Scope

[P1][SYNC] Add opt-in Sync Session Config to menu and Attach All

## Inputs

- None declared.

## Work order

User workflow: when attaching Studio SSH sessions from MacBook, allow one checkbox/menu choice to sync session config; also allow MacBook edits to flow back to Studio by explicit choice.

Done when:
- Menu and Attach All expose Sync Session Config.
- The user can preview and choose push, pull, or merge for Studio <-> MacBook.
- Notes, title, Today pin, and ordering converge idempotently without duplicate sessions.
- Conflicts are explained rather than last-write-wins silently.
- Offline changes retry safely; disabling sync leaves both hosts untouched.
- Provider resume descriptors remain bound to and executed on their owning host.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-9eb075`.
4. Commit with `Manna: mn-9eb075` and run `agent-do manna done mn-9eb075` only after the work is verified.
