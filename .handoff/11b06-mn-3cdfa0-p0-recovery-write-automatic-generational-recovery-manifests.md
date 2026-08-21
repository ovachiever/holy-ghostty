---
workflow: 2
manna: mn-3cdfa0
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P0][RECOVERY] Write automatic generational recovery manifests'
inputs: []
binding: sha256:c705e7c746238f9bd5cd3d29df0de51d7dc07fcdc783e6393b13641460450566
---

# Handoff: [P0][RECOVERY] Write automatic generational recovery manifests

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-3cdfa0
```

## Scope

[P0][RECOVERY] Write automatic generational recovery manifests

## Inputs

- None declared.

## Work order

Continuously capture enough metadata to recover after reboot without relying on a shutdown hook.

Each mode-0600, atomic, checksummed, versioned generation records stable Holy ID, execution host, exact provider session ID, adapter/schema, cwd/repo/worktree, tmux socket/name, launch metadata, title/note/Today pin/order, confirmed model/profile, capture provenance, and timestamps. Retain multiple generations and mirror the narrow descriptor into SQLite/cross-host metadata sync. Never store prompt, response, transcript, secret, or environment content. The helper must still persist identity when the Holy UI is detached.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-3cdfa0`.
4. Commit with `Manna: mn-3cdfa0` and run `agent-do manna done mn-3cdfa0` only after the work is verified.
