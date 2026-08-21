---
workflow: 2
manna: mn-e49b22
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P0][CONTROL] Prove a pane is safe for autonomous input'
inputs: []
binding: sha256:ffa445533fe5a6cbb898b9b00613866a899fd94928e1f904b5ca857cc45606a7
---

# Handoff: [P0][CONTROL] Prove a pane is safe for autonomous input

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-e49b22
```

## Scope

[P0][CONTROL] Prove a pane is safe for autonomous input

## Inputs

- None declared.

## Work order

The roster indicator heuristic is not a safety oracle. Build a narrower fail-closed gate before any peer agent may type.

Done when readiness requires runtime-specific exact prompt fingerprinting, stability across multiple samples, authoritative hook state, no live working lease/spinner, and process-level invalidation. Terminal prose and the user's draft can never establish readiness. Unknown means unsafe. Run shadow-mode telemetry across real Claude, Codex, and OpenCode sessions; the defined 24-hour gate must show near-zero/zero false-safe classifications before control is enabled.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-e49b22`.
4. Commit with `Manna: mn-e49b22` and run `agent-do manna done mn-e49b22` only after the work is verified.
