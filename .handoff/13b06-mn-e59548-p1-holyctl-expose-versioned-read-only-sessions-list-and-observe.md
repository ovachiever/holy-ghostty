---
workflow: 2
manna: mn-e59548
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P1][HOLYCTL] Expose versioned read-only sessions list and observe'
inputs: []
binding: sha256:25aeeb297f41aa06db46394a326b9c763d9cecdc61ab43a94b1e976267559325
---

# Handoff: [P1][HOLYCTL] Expose versioned read-only sessions list and observe

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-e59548
```

## Scope

[P1][HOLYCTL] Expose versioned read-only sessions list and observe

## Inputs

- None declared.

## Work order

Ship the eyes before the hands: holyctl sessions list and holyctl sessions observe with no input capability.

Done when stable machine-readable output covers Holy/session identity, runtime/adapter, confirmed model, cwd/repo/worktree, authoritative lifecycle state, evidence freshness, git snapshot, and session_events deltas for local and remote sessions. It survives detach/restart, is permission-scoped, versioned, and omits prompt/transcript content.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-e59548`.
4. Commit with `Manna: mn-e59548` and run `agent-do manna done mn-e59548` only after the work is verified.
