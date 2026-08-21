---
workflow: 2
manna: mn-54c1ae
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: 'Pre-existing test failure: HolyRemoteAgentStateBridgeServiceTests remoteTransactionPreservesUnrelatedSettingsWithoutReturningThem fails on clean main'
inputs: []
binding: sha256:c775f581a5b99b6d4e90e91f7f86eb4d439e153b2ae58424951aa27acbe8386b
---

# Handoff: Pre-existing test failure: HolyRemoteAgentStateBridgeServiceTests remoteTransactionPreservesUnrelatedSettingsWithoutReturningThem fails on clean main

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-54c1ae
```

## Scope

Pre-existing test failure: HolyRemoteAgentStateBridgeServiceTests remoteTransactionPreservesUnrelatedSettingsWithoutReturningThem fails on clean main

## Inputs

- None declared.

## Work order

Found 2026-08-03 during mn-495322: fails on clean HEAD (verified via stash, exit 65, both test clones). Filesystem-fixture test; zero references to discovery/lifecycle code. Not caused by the lifecycle-service work.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-54c1ae`.
4. Commit with `Manna: mn-54c1ae` and run `agent-do manna done mn-54c1ae` only after the work is verified.
