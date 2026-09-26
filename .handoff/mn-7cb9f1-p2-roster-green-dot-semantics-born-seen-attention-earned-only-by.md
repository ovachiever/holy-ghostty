---
workflow: 2
manna: mn-7cb9f1
track: mn-eb7a80
source: .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 3
base_commit: 74e8e8b0daa88cf1681b19ce560068c684fac4a5
scope: '[P2][ROSTER] Green-dot semantics: born seen, attention earned only by a real event'
inputs:
- .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 3
binding: sha256:a6c208ec7cb7cef8c8ca4d71ac90c5e205e3bb0a8e9e018edc23260c36c2c966
---

# Handoff: [P2][ROSTER] Green-dot semantics: born seen, attention earned only by a real event

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-7cb9f1
```

## Scope

[P2][ROSTER] Green-dot semantics: born seen, attention earned only by a real event

## Inputs

- .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 3

## Work order

With instant spawning, green equals idle is noise. A new session dot is born seen and earns attention only on a real event: a question, a failed turn, a done. Overlaps mn-a0406e (launch-time focus churn marks every session seen and used); this is its dependent, not a duplicate. Done when a fresh spawn shows no attention state and the first real event flips it.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-7cb9f1`.
4. Commit with `Manna: mn-7cb9f1` and run `agent-do manna done mn-7cb9f1` only after the work is verified.
