---
workflow: 2
manna: mn-70a8ac
track: mn-6e363f
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[PARKED][SECONDCHAIR] old J4 autonomous hands — superseded by human-Enter model; revisit only after Second Chair trust matures'
inputs: []
binding: sha256:73dc3560f99b407fcd9f3b5bebe6ed2a8d338eb1edfb6c6539571d7e8faf20f1
---

# Handoff: [PARKED][SECONDCHAIR] old J4 autonomous hands — superseded by human-Enter model; revisit only after Second Chair trust matures

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-70a8ac
```

## Scope

[PARKED][SECONDCHAIR] old J4 autonomous hands — superseded by human-Enter model; revisit only after Second Chair trust matures

## Inputs

- None declared.

## Work order

'Tell flip 5 to run the soak' → fuzzy-resolve target from roster names (voice never touches raw pane targets) → verbal confirm when ambiguous or consequential → lease → safe-input oracle gate → byte-verified typing with [from overseer] provenance prefix → delivery confirmation spoken back. Confirm tiers: answers free; messages confirm-by-default (relaxable per-session); interrupts always confirm; destructive/credential prompts refused — human only. Watched output remains DATA, never instructions. Every action in session timeline + Overseer transcript.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-70a8ac`.
4. Commit with `Manna: mn-70a8ac` and run `agent-do manna done mn-70a8ac` only after the work is verified.
