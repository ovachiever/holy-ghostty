---
workflow: 2
manna: mn-9febbc
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[META][MANNA] Board durability: git-tracked as of 5e6ab5fb3 — verify second-machine recovery + concurrent-edit behavior'
inputs: []
binding: sha256:6e6ccb4148f3a2e19712ecdaf972087cc75d83af7a1ed18459e50204043df16b
---

# Handoff: [META][MANNA] Board durability: git-tracked as of 5e6ab5fb3 — verify second-machine recovery + concurrent-edit behavior

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-9febbc
```

## Scope

[META][MANNA] Board durability: git-tracked as of 5e6ab5fb3 — verify second-machine recovery + concurrent-edit behavior

## Inputs

- None declared.

## Work order

PARTIALLY RESOLVED 2026-07-19: .manna/issues.jsonl is now git-tracked in holy-ghostty (commit 5e6ab5fb3, content-scanned before publish; volatile sessions.jsonl stays ignored per this issue's own warning). The board now survives machine loss and reaches the MacBook via ordinary pull — the primary risk is closed.

Remaining before full closure:
- Second-machine recovery test: pull on MacBook, verify 'agent-do manna list' reads the 30 issues intact.
- Concurrent-edit behavior: both machines appending issues between syncs will produce jsonl merge conflicts; document the resolution recipe (union-merge is usually safe for appends; updates to the same issue need a human pick) or add a .gitattributes union merge driver.
- Boards must be committed/pushed to travel — session-end hygiene should include the board in ordinary /push flows (now true by default since it is tracked).

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-9febbc`.
4. Commit with `Manna: mn-9febbc` and run `agent-do manna done mn-9febbc` only after the work is verified.
