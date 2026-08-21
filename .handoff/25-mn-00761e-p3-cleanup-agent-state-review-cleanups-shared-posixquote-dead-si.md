---
workflow: 2
manna: mn-00761e
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P3][CLEANUP] Agent-state review cleanups: shared posixQuote, dead singleton, dead param, duplicated commandPlan'
inputs: []
binding: sha256:f9dab7de6666c68d91944e3dbdc42c736c68562aecefae2c835788ae2f56f727
---

# Handoff: [P3][CLEANUP] Agent-state review cleanups: shared posixQuote, dead singleton, dead param, duplicated commandPlan

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-00761e
```

## Scope

[P3][CLEANUP] Agent-state review cleanups: shared posixQuote, dead singleton, dead param, duplicated commandPlan

## Inputs

- None declared.

## Work order

Four CONFIRMED cleanup findings from the xhigh review of 537c0a567: (1) POSIX single-quote escaping re-implemented 5x (HolyTmuxAgentStateMonitor:554, HolyRemoteAgentStateBridgeService:236, HolyAgentStateBridge.shellQuote:696, HolyTmuxCommandBuilder:311+502) — session identity flows through all of them into tmux/ssh strings, so a hardening fix to one misses four; (2) HolyTmuxAgentStateMonitor.shared is dead (store constructs its own; a second consumer on .shared would double-poll); (3) attentionPresentation threads a coordination arg the private overload ignores; (4) commandPlan .local/.remote branches are byte-identical and will silently diverge.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-00761e`.
4. Commit with `Manna: mn-00761e` and run `agent-do manna done mn-00761e` only after the work is verified.
