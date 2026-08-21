---
workflow: 2
manna: mn-610814
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P2][CONTROL] Add byte-verified messages and runtime-safe control adapters'
inputs: []
binding: sha256:0be5adf873b0c86b688e8e26e362fc0bf3c80cd02988a5fc8c96d8f6a132fd67
---

# Handoff: [P2][CONTROL] Add byte-verified messages and runtime-safe control adapters

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-610814
```

## Scope

[P2][CONTROL] Add byte-verified messages and runtime-safe control adapters

## Inputs

- None declared.

## Work order

Add controlled interaction only after the broker and transport gates pass.

Done when every injected message carries mandatory disclosure such as [from claude @ session-X], provenance is visible in the target and Watch feed, delivery is paced/checksummed and acknowledged byte-for-byte, and success means an authoritative target transition rather than "the screen changed." Interrupt/cancel keys use a per-runtime allowlist because Escape and Ctrl-C differ across Claude, Codex, OpenCode, and future harnesses. Unsafe controls are unavailable.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-610814`.
4. Commit with `Manna: mn-610814` and run `agent-do manna done mn-610814` only after the work is verified.
