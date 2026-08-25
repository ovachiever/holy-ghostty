---
workflow: 2
manna: mn-e47cd0
track: mn-eb7a80
source: null
base_commit: 10efb7907a69959ccfef11bf22c0b2d848c17920
scope: '[P0][USAGE] Usage-cap early warning: sidebar meter + wrap-up hook + account switch prompt'
inputs: []
binding: sha256:e023143fdb48c8e4abc077e800ded4372d9203eb2e36c33bfab7b0ce2a500b14
---

# Handoff: [P0][USAGE] Usage-cap early warning: sidebar meter + wrap-up hook + account switch prompt

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-e47cd0
```

## Scope

[P0][USAGE] Usage-cap early warning: sidebar meter + wrap-up hook + account switch prompt

## Inputs

- None declared.

## Work order

Claude Code Max sessions die mid-work when a 5h/weekly/Fable cap hits (subagents fail outright; only the main session auto-waits). Build: (1) a probe that polls /api/oauth/usage with the keychain OAuth token and writes a machine-wide snapshot; (2) statusline extension capturing per-session rate_limits; (3) a PreToolUse/UserPromptSubmit guard hook that injects a wrap-up-and-pause instruction into every running session when a bucket crosses the warn threshold and denies new subagent spawns at critical; (4) a sidebar usage meter with reset times, burn-rate ETA, threshold alerts, and last-known numbers per account so Erik can /login to the account with headroom before a cap lands.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-e47cd0`.
4. Commit with `Manna: mn-e47cd0` and run `agent-do manna done mn-e47cd0` only after the work is verified.
