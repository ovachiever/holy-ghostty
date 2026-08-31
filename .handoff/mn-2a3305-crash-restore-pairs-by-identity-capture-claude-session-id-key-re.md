---
workflow: 2
manna: mn-2a3305
track: null
source: null
base_commit: 7b16f9136c628a7928baaaab6148dde09fbe6778
scope: 'Crash restore pairs by identity: capture Claude session id, key restore on it, close audit hole'
inputs: []
binding: sha256:d1ebe7bef749c348911d291f4cc489a4c45f65cb5892657dde6e46ca4cefbf0f
---

# Handoff: Crash restore pairs by identity: capture Claude session id, key restore on it, close audit hole

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-2a3305
```

## Scope

Crash restore pairs by identity: capture Claude session id, key restore on it, close audit hole

## Inputs

- None declared.

## Work order

2026-08-31 crash restore rotated 3 of 4 same-cwd agent-do sessions onto wrong conversations (les-b58ae9). Fix: (1) Claude hooks pass session_id as helper 4th arg into envelope field 6; (2) persist last provider session id per session; (3) restore short-circuits to exact resume on stored id, assignment excludes those ids; (4) assignment near-tie audit counts claimed competitors so same-cwd swarms demote to ambiguous instead of certifying coin flips; (5) seed correct ids for the four live agent-do rows.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-2a3305`.
4. Commit with `Manna: mn-2a3305` and run `agent-do manna done mn-2a3305` only after the work is verified.
