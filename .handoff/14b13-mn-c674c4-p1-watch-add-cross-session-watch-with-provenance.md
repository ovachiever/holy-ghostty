---
workflow: 2
manna: mn-c674c4
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P1][WATCH] Add cross-session Watch with provenance'
inputs: []
binding: sha256:644d6f01492e9eb9928fcb72172f778566d415acab087ef4c8aa9ec06ecb2d69
---

# Handoff: [P1][WATCH] Add cross-session Watch with provenance

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-c674c4
```

## Scope

[P1][WATCH] Add cross-session Watch with provenance

## Inputs

- None declared.

## Work order

Allow an agent or human in one project session to observe another session read-only before any control path exists.

Done when Watch consumes the versioned observe feed, preserves event/output ordering, audits access, and visibly distinguishes human, target-agent, peer-agent, and system origins. Peer-injected spans must be tagged so a watcher cannot mistake its own messages for target output or create an unmarked feedback loop.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-c674c4`.
4. Commit with `Manna: mn-c674c4` and run `agent-do manna done mn-c674c4` only after the work is verified.
