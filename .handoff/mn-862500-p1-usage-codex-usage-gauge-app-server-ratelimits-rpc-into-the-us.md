---
workflow: 2
manna: mn-862500
track: mn-eb7a80
source: null
base_commit: 7222aecf5866afd639f8078610cb8ac4926b3972
scope: '[P1][USAGE] Codex usage gauge: app-server rateLimits RPC into the usage pipeline'
inputs: []
binding: sha256:806532789017cfe45f1d19a2b5a2bb34fb35dc8c3f57fc998530acc9243855e6
---

# Handoff: [P1][USAGE] Codex usage gauge: app-server rateLimits RPC into the usage pipeline

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-862500
```

## Scope

[P1][USAGE] Codex usage gauge: app-server rateLimits RPC into the usage pipeline

## Inputs

- None declared.

## Work order

Poll codex app-server account/rateLimits/read (verified live: weekly + per-model 5h/weekly windows, credits, reset credits, planType) from the usage probe; passive fallback from newest rollout jsonl rate_limits snapshot; codex buckets join usage/latest.json, green bar gains a codex chip group (models shown when >0%), guard hook excludes codex buckets so a codex cap never pauses Claude sessions; notifications reword for codex.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-862500`.
4. Commit with `Manna: mn-862500` and run `agent-do manna done mn-862500` only after the work is verified.
