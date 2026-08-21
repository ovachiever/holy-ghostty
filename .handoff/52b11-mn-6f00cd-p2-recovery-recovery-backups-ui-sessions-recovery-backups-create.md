---
workflow: 2
manna: mn-6f00cd
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P2][RECOVERY] Recovery Backups UI: Sessions > Recovery Backups + Create Recovery Point Now'
inputs: []
binding: sha256:c39374f874b66283632ce00b0ca2d62192c3da636c2b5208f2107470e56f4230
---

# Handoff: [P2][RECOVERY] Recovery Backups UI: Sessions > Recovery Backups + Create Recovery Point Now

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-6f00cd
```

## Scope

[P2][RECOVERY] Recovery Backups UI: Sessions > Recovery Backups + Create Recovery Point Now

## Inputs

- None declared.

## Work order

Split out of mn-9a6145 on 2026-08-07 (Erik, /board audit decision): that issue's title promised this surface, and zero code exists (grep for Recovery Backup / Recovery Point / recoveryBackup / recoveryPoint across Sources, Tests, and docs returns nothing). Deliverable: a Sessions > Recovery Backups browser over recovery points, plus a 'Create Recovery Point Now' action. Belongs with generational recovery manifests — mn-3cdfa0 supplies the recovery-point substrate this UI browses, so this is blocked on it (mn-9a6145's own 2026-08-03 shipped notes made the same assignment).

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-6f00cd`.
4. Commit with `Manna: mn-6f00cd` and run `agent-do manna done mn-6f00cd` only after the work is verified.
