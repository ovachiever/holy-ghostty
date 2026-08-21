---
workflow: 2
manna: mn-569b91
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[VERIFY][TMUX] Reconcile known sessions and safely reap true orphans'
inputs: []
binding: sha256:f52a0ec1cbc9ac6364ec851bef90184557aa5e5d10df61e5dd4a328c2957bd92
---

# Handoff: [VERIFY][TMUX] Reconcile known sessions and safely reap true orphans

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-569b91
```

## Scope

[VERIFY][TMUX] Reconcile known sessions and safely reap true orphans

## Inputs

- None declared.

## Work order

Commit 387aec593 provides live-identity reconciliation, archive readoption, unknown-orphan surfacing, and archive retention. Complete and accept the user outcome.

Done when:
- A known archived live tmux session is adopted with its Holy UUID, note, title, and Today pin; no duplicate tmux session is spawned.
- Unknown live sessions are surfaced with evidence and never destroyed automatically.
- A user-confirmed reap targets discovered truth and polls until the real session is absent.
- Repeated reconcile/reap operations are idempotent.
- Archive retention remains bounded without deleting sync/recovery-owned metadata.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-569b91`.
4. Commit with `Manna: mn-569b91` and run `agent-do manna done mn-569b91` only after the work is verified.
