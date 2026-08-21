---
workflow: 2
manna: mn-15ba3d
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P1][SYNC] Define stable bidirectional cross-host metadata semantics'
inputs: []
binding: sha256:096425c0f27841ba80ad7cb97adc1c485f359d6a6edf964cfadb65c9d6aa5b34
---

# Handoff: [P1][SYNC] Define stable bidirectional cross-host metadata semantics

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-15ba3d
```

## Scope

[P1][SYNC] Define stable bidirectional cross-host metadata semantics

## Inputs

- None declared.

## Work order

Define the durable contract behind Studio <-> MacBook session-config sync.

NOTE 2026-07-20: the proven v1 slice is mn-2b3a11 (always-on note/pin sync via tmux user options — same channel as @holy_title; one-time import validated the join key and merge rule). This issue remains the GRAND contract: versioned schema distinguishing logical session identity from execution-host identity, ownership/merge rules for roster order and host-bound provider resume descriptors, revisions, tombstones, offline retry, conflict presentation, authentication/encryption, migration, mixed-version behavior. Exclude secrets, environment values, prompts, responses, transcripts by default. User-authored fields merge bidirectionally; harness-authored resume IDs remain owned by the transcript host.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-15ba3d`.
4. Commit with `Manna: mn-15ba3d` and run `agent-do manna done mn-15ba3d` only after the work is verified.
