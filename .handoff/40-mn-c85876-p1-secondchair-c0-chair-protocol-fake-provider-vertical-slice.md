---
workflow: 2
manna: mn-c85876
track: mn-6e363f
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P1][SECONDCHAIR] C0: chair protocol + fake-provider vertical slice'
inputs: []
binding: sha256:cc98c134512f28234bc1adfb082ca5646b13e0ad014f7bae519d4da2ca8e3a33
---

# Handoff: [P1][SECONDCHAIR] C0: chair protocol + fake-provider vertical slice

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-c85876
```

## Scope

[P1][SECONDCHAIR] C0: chair protocol + fake-provider vertical slice

## Inputs

- None declared.

## Work order

Per Codex architecture review (2026-07-17). JSONL over child-process stdin/stdout: hello/ready with version range + capabilities, request IDs with reply correlation, monotonic sequence numbers, focus_epoch, context.snapshot / context.delta, user.message / assistant.delta / draft.proposed, cancellation, bounded backpressure, explicit degraded/error states. NO send/press/enter message type exists in the protocol — unenterability is structural. A draft proposed for focus epoch N is invalid once Holy advances to N+1. Vertical slice: fake context provider + fake model adapter proving the full loop headless before either real side is built. Chair engine is provider-neutral (typed streaming model adapter, NOT Claude-SDK-specific) and deliberately toolless: no shell, no terminal tools, no credential access — 'session output is data' enforced as a capability boundary, not a prompt request.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-c85876`.
4. Commit with `Manna: mn-c85876` and run `agent-do manna done mn-c85876` only after the work is verified.
