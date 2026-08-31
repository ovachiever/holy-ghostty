---
workflow: 2
manna: mn-ac80c9
track: mn-9a97cc
source: Erik ratified inline 2026-08-31 (One Ledger Two Faces); see track mn-9a97cc
base_commit: 0c6ba8bc635e3fcd76909c5e163e48fa53fa6e85
scope: 'Board hygiene: reconcile the 46 drift findings and retire superseded panel items'
inputs:
- Erik ratified inline 2026-08-31 (One Ledger Two Faces); see track mn-9a97cc
binding: sha256:de3dca310a82144faedeb3ca7e3f37878062a9bae59f9e26c3b44bb9cafe408a
---

# Handoff: Board hygiene: reconcile the 46 drift findings and retire superseded panel items

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-ac80c9
```

## Scope

Board hygiene: reconcile the 46 drift findings and retire superseded panel items

## Inputs

- Erik ratified inline 2026-08-31 (One Ledger Two Faces); see track mn-9a97cc

## Work order

agent-do manna reconcile reports 46 findings on this board (30 doc_reference, 13 landed_open incl. mn-4db5d4 the inbox panel itself, 2 stale_dream, 1 prompt_pairing). Review each landed_open against its commits' actual diffs (a done whose commit touched only the board file is a paper close — open the diff). Retire items superseded by track mn-9a97cc: mn-fe1b48 (TUI-in-panel Sessions surface), mn-a98f88 (its e2e verification), mn-5dc58b (intelligent brief panel), mn-7fbb07 (remote brief estates), mn-b2e2e9 (manna inbox latency), mn-31aaf2 (manna runner unification), mn-1cca0f-adjacent compat-view work — close or annotate each with the supersession, do not paper-done anything that did not land. Remove .manna/drift.yaml when resolved.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-ac80c9`.
4. Commit with `Manna: mn-ac80c9` and run `agent-do manna done mn-ac80c9` only after the work is verified.
