---
workflow: 2
manna: mn-27d9fd
track: mn-eb7a80
source: .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 5
base_commit: 74e8e8b0daa88cf1681b19ce560068c684fac4a5
scope: '[P1][SYNC] Local tmux discovery times out at fleet size; the 5 s literal starves Sync'
inputs:
- .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 5
binding: sha256:11fed0ccfbcd0c634c14d9735a16bb6b3f64e49a328c4a8ed339e25630abefc2
---

# Handoff: [P1][SYNC] Local tmux discovery times out at fleet size; the 5 s literal starves Sync

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-27d9fd
```

## Scope

[P1][SYNC] Local tmux discovery times out at fleet size; the 5 s literal starves Sync

## Inputs

- .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 5

## Work order

Log line at 55 local sessions: Tmux discovery for local tmux timed out after 5.000000 seconds; Sync then starves. The 5 s is a bare bounding literal (CLAUDE.md quantities rule): measure discovery cost per session and derive the bound from the fleet size or the measured per-session cost, or replace the single timeout with incremental discovery. mn-12801a (Sync adopts never-seen sessions from every host) is the consumer. Done when Sync completes at 55 or more local sessions with no timeout line and the bound is named from a measured constraint.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-27d9fd`.
4. Commit with `Manna: mn-27d9fd` and run `agent-do manna done mn-27d9fd` only after the work is verified.
