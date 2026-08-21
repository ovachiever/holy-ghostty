---
workflow: 2
manna: mn-943f71
track: mn-70875b
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[INBOX] Visual-pass fixes: retire collision alerts, GitHub first, manna focused-only'
inputs: []
binding: sha256:239876c09035c5407cf1cfd7fbd38e8947ddd067a256bbeeffdda8b6ed859f33
---

# Handoff: [INBOX] Visual-pass fixes: retire collision alerts, GitHub first, manna focused-only

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-943f71
```

## Scope

[INBOX] Visual-pass fixes: retire collision alerts, GitHub first, manna focused-only

## Inputs

- None declared.

## Work order

Erik 2026-08-10, first real pass over the live panel (mn-4db5d4): (1) "105 session collision detected... pure noise remove that completely" — the supervisor collision branch (HolySessionSupervisor.swift:1440-1449) stops delivering (banner + persisted row), and the existing backlog is bulk-acknowledged once at startup (store philosophy is never-delete, history stays); coordination UI (bottom-rail collision count, pane chrome) untouched. (2) GitHub section renders first — reorder engine sources to [GitHub, Manna, Alerts]; coverage is already global (agent-do gh inbox sweeps owned + org repos — verified live: 38 items incl. Versova-Intelligence-Division), it was buried under the alert noise. (3) Manna rows scope to the FOCUSED session repo only — repositoryRoots(sessions:focused:) stops merging every live session root; umbrella climb stays for projects without their own board.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-943f71`.
4. Commit with `Manna: mn-943f71` and run `agent-do manna done mn-943f71` only after the work is verified.
