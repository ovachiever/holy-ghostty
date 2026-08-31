---
workflow: 2
manna: mn-26e29e
track: mn-9a97cc
source: Erik ratified inline 2026-08-31 (One Ledger Two Faces); see track mn-9a97cc
base_commit: 0c6ba8bc635e3fcd76909c5e163e48fa53fa6e85
scope: 'Keystone: store harness_session_id from hooks; join everything on it'
inputs:
- Erik ratified inline 2026-08-31 (One Ledger Two Faces); see track mn-9a97cc
binding: sha256:2df3ea9f1d0bfc355653531368261a46bf289155bf047ac64f82249d3aedb136
---

# Handoff: Keystone: store harness_session_id from hooks; join everything on it

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-26e29e
```

## Scope

Keystone: store harness_session_id from hooks; join everything on it

## Inputs

- Erik ratified inline 2026-08-31 (One Ledger Two Faces); see track mn-9a97cc

## Work order

Holy's agent-state hook currently publishes lifecycle wire strings and never reads hook stdin. Change: read the hook payload's session_id on every event, carry it in the pane-option wire, and persist it as sessions.harness_session_id in Holy's SQLite. Acceptance: a roster row, a manna claimant (claude-<hex> label), a coord peer (session-<hex>), an archive transcript, and a restore target resolve to the same session via the shared UUID/hex-tail join (the same scheme manna serve uses in board.py claimant matching). Built FIRST and alone — every other lane's click-throughs, badge dedup, and attention join depend on this column.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-26e29e`.
4. Commit with `Manna: mn-26e29e` and run `agent-do manna done mn-26e29e` only after the work is verified.
