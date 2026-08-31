---
workflow: 2
manna: mn-b864b4
track: null
source: null
base_commit: 0c6ba8bc635e3fcd76909c5e163e48fa53fa6e85
scope: 'Post-incident gaps: clear+readopt wipes attention metadata; no re-key path for live mispaired panes'
inputs: []
binding: sha256:9bf09f4424122e7c617043c8ffdc75520a327d368d488794395353e270d187b8
---

# Handoff: Post-incident gaps: clear+readopt wipes attention metadata; no re-key path for live mispaired panes

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-b864b4
```

## Scope

Post-incident gaps: clear+readopt wipes attention metadata; no re-key path for live mispaired panes

## Inputs

- None declared.

## Work order

Two gaps surfaced finishing mn-2a3305 on 2026-08-31: (1) Erik's clear + re-attach flow rebuilt every HolySessionAttentionMetadata entry from pane registers (lastSeenAt baseline-stamped, lastUsedAt lost — all blue/green state grey); metadata should survive an archive/readopt round trip since sessionID is stable. (2) Restore's alreadyRestored precedence adopts a LIVE pane even when its conversation contradicts the row's stored providerSessionID, so a mispaired live pane survives every restore; the manual fix was tmux respawn-pane with the seeded resume command. Consider a converge check: envelope sessionID vs record providerSessionID mismatch surfaces a re-key action.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-b864b4`.
4. Commit with `Manna: mn-b864b4` and run `agent-do manna done mn-b864b4` only after the work is verified.
