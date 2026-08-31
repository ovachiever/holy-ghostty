---
workflow: 2
manna: mn-330752
track: mn-9a97cc
source: Erik ratified inline 2026-08-31 (One Ledger Two Faces); see track mn-9a97cc
base_commit: 0c6ba8bc635e3fcd76909c5e163e48fa53fa6e85
scope: 'Board mode: native full-screen manna cockpit in the workspace'
inputs:
- Erik ratified inline 2026-08-31 (One Ledger Two Faces); see track mn-9a97cc
binding: sha256:ad4865c74115ff36aaa9da4ede43c376fb66e4dea3bef15cf03c71035cbc9d08
---

# Handoff: Board mode: native full-screen manna cockpit in the workspace

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-330752
```

## Scope

Board mode: native full-screen manna cockpit in the workspace

## Inputs

- Erik ratified inline 2026-08-31 (One Ledger Two Faces); see track mn-9a97cc

## Work order

The workspace's second face: a full-screen native (SwiftUI) board view — one key to enter, Escape returns the terminal — plus the estate strip on top (every registered board, needs-you first). Sheets: now / next / waiting-in-waves / asks / coordination / dreams / decisions; inspector with AI digest, body, track, claimant, commits, handoff path. Data: agent-do 'manna state --json' and 'manna estate --json' (tickets filed on agent-do's board — cross-repo dependency; until they land, do not build on manna list --json, which is a retired contract). Every mutation is a real CLI verb (claim/done/unblock/close/sync/fix/promote) run under Holy's own manna actor identity + claim proof, confirm-gated: a glance never moves the board. Digests/summaries via Holy's fast model-routing role, content-hash cached in Holy's SQLite. One badge: gh your-move + board asks + sessions needing a human, deduplicated by harness_session_id. Claimant rows join to roster sessions via the keystone — click a peer, focus its session. Remote: run the CLI where the session lives over Holy's existing bridge.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-330752`.
4. Commit with `Manna: mn-330752` and run `agent-do manna done mn-330752` only after the work is verified.
