---
workflow: 2
manna: mn-0532e8
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: 'Load-flake: HolyRemoteTmuxDiscoveryTimeoutTests/exitedParentWithInheritedPipeIsStillCapped starves under full-suite load'
inputs: []
binding: sha256:d5be2ce48ed16a0a4d299863d368cf8874634b42c27369be9a4ffe0c2dfcffd4
---

# Handoff: Load-flake: HolyRemoteTmuxDiscoveryTimeoutTests/exitedParentWithInheritedPipeIsStillCapped starves under full-suite load

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-0532e8
```

## Scope

Load-flake: HolyRemoteTmuxDiscoveryTimeoutTests/exitedParentWithInheritedPipeIsStillCapped starves under full-suite load

## Inputs

- None declared.

## Work order

Timing-sensitive timeout test: fails intermittently in full-suite runs (seen 2026-08-06 in two independent gates), passes consistently in isolation (0.2s). Either widen its timing margins or mark it serialized. Not related to restore/inbox work.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-0532e8`.
4. Commit with `Manna: mn-0532e8` and run `agent-do manna done mn-0532e8` only after the work is verified.
