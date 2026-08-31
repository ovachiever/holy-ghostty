---
workflow: 2
manna: mn-7a8cae
track: mn-9a97cc
source: Erik ratified inline 2026-08-31 (One Ledger Two Faces); see track mn-9a97cc
base_commit: 0c6ba8bc635e3fcd76909c5e163e48fa53fa6e85
scope: 'Attention: one record — roster and board read coord, Holy writes its verdict back; Now Card'
inputs:
- Erik ratified inline 2026-08-31 (One Ledger Two Faces); see track mn-9a97cc
binding: sha256:5e9ae7857e8827a64ab5518905392adf8420783b9c0a59f11417563f951745b4
---

# Handoff: Attention: one record — roster and board read coord, Holy writes its verdict back; Now Card

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-7a8cae
```

## Scope

Attention: one record — roster and board read coord, Holy writes its verdict back; Now Card

## Inputs

- Erik ratified inline 2026-08-31 (One Ledger Two Faces); see track mn-9a97cc

## Work order

Unify the two hook-fed attention pipelines at the data level (both hooks stay registered; agent-do's pulse hook is a standalone requirement). Holy reads coord pulse (latest_prompt, todo{done,total,current}, status) keyed by harness_session_id and writes its six-state verdict back through the coord pulse non-hook write path (ticket filed on agent-do's board — cross-repo dependency). Result: the roster orb and any board's needs-you read the same fact and cannot disagree. Ship the Now Card: hover sidecar on a roster row showing Erik's last ask + the agent's current todo step, display-only, never feeding the six authoritative states, row titles stay project names (standing ruling).

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-7a8cae`.
4. Commit with `Manna: mn-7a8cae` and run `agent-do manna done mn-7a8cae` only after the work is verified.
