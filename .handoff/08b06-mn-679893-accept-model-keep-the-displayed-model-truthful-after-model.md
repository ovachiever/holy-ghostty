---
workflow: 2
manna: mn-679893
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[ACCEPT][MODEL] Keep the displayed model truthful after /model'
inputs: []
binding: sha256:f0ff8f9fb4a70d34bc6df8ad1c642f3d54a8ed78cb5bb94623768cff244fd1bc
---

# Handoff: [ACCEPT][MODEL] Keep the displayed model truthful after /model

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-679893
```

## Scope

[ACCEPT][MODEL] Keep the displayed model truthful after /model

## Inputs

- None declared.

## Work order

The green/tmux status must show the currently confirmed model because users can change it at runtime. Commit df3473bfa is an implementation candidate but acceptance must cover more than a Claude-only happy path.

Done when:
- Claude, Codex, OpenCode, reattached sessions, and restored sessions update promptly after startup and any /model-style runtime change.
- Hooks/provider facts are preferred over terminal text.
- Stale/unavailable data is explicitly Unknown or last-confirmed-with-age, never an unqualified stale model.
- Shells show no fabricated model.
- Installed local and SSH smoke tests prove the displayed value matches the harness's actual selection.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-679893`.
4. Commit with `Manna: mn-679893` and run `agent-do manna done mn-679893` only after the work is verified.
