---
workflow: 2
manna: mn-e13961
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P0][HOOKS] Complete the open harness identity, lifecycle, and model protocol'
inputs: []
binding: sha256:2482c08cfb5f4077433b450f68408ca10b4228e95c53503930fb23f88bbc3556
---

# Handoff: [P0][HOOKS] Complete the open harness identity, lifecycle, and model protocol

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-e13961
```

## Scope

[P0][HOOKS] Complete the open harness identity, lifecycle, and model protocol

## Inputs

- None declared.

## Work order

Build on authoritative-agent work in 537c0a567, but complete the metadata contract needed by recovery, indicators, model truth, and future harnesses.

Done when:
- A strict versioned metadata-only envelope carries open-string source/adapter ID, exact provider session ID, lifecycle state, current model, cwd, stable event token, and observed time.
- Claude, Codex, and OpenCode adapters parse documented hook/plugin fields; future harnesses register without core enum growth.
- Malformed, stale, or missing data becomes Unknown/fail-closed.
- Local and explicitly selected SSH installation is transactional and preserves unrelated config.
- Prompt, response, transcript, environment, and secret content are never captured.
- Exact provider identity is durably persisted, not left only in memory or tmux.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-e13961`.
4. Commit with `Manna: mn-e13961` and run `agent-do manna done mn-e13961` only after the work is verified.
