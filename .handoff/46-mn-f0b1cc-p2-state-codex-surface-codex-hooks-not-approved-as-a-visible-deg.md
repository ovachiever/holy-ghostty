---
workflow: 2
manna: mn-f0b1cc
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P2][STATE][CODEX] Surface ''codex hooks not approved'' as a visible degraded state'
inputs: []
binding: sha256:b8abf3e7152c990cb89a5d7433eb1f827caa6490c0c4169961660dc8ac79184e
---

# Handoff: [P2][STATE][CODEX] Surface 'codex hooks not approved' as a visible degraded state

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-f0b1cc
```

## Scope

[P2][STATE][CODEX] Surface 'codex hooks not approved' as a visible degraded state

## Inputs

- None declared.

## Work order

Split from mn-8cec74 (its lease-extension and dead-producer invalidation shipped 2026-07-21 via pane_dead/pane_current_command evidence in HolyTmuxAgentStateMonitor + HolySessionIndicatorPolicy). Remaining: generationVersion bumps regenerate .codex/hooks.json which requires manual /hooks re-approval per Codex; unapproved sessions silently emit no hook events (notify-based finished still flows). Surface that as a visible degraded indicator or doctor check instead of silence.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-f0b1cc`.
4. Commit with `Manna: mn-f0b1cc` and run `agent-do manna done mn-f0b1cc` only after the work is verified.
