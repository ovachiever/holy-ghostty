---
workflow: 2
manna: mn-ede22a
track: mn-eb7a80
source: session_events rows 584641-584642; app log 2026-09-24 17:25:29.833
base_commit: 54fb6b58d3bcd289aef8411084d393826437a172
scope: '[P1][AUTOMATION][ROSTER] Spawn route records a session whose surface never initialized (engine OutOfMemory), preview says shell ready'
inputs:
- session_events rows 584641-584642; app log 2026-09-24 17:25:29.833
binding: sha256:4770ca3aa165308d8c7b04d64692042a827166891616ee9095e6d03a7a544d85
---

# Handoff: [P1][AUTOMATION][ROSTER] Spawn route records a session whose surface never initialized (engine OutOfMemory), preview says shell ready

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-ede22a
```

## Scope

[P1][AUTOMATION][ROSTER] Spawn route records a session whose surface never initialized (engine OutOfMemory), preview says shell ready

## Inputs

- session_events rows 584641-584642; app log 2026-09-24 17:25:29.833

## Work order

2026-09-24 17:25:29 local, receipts: scripts/holy-spawn-session.sh --runtime shell --initial-input ... created session row 42FCA2D4-09AF-4C33-A1D1-75220C10D6EF (origin automation, title worker mn-e9f9a9 spawn URL gate) with preview Interactive shell ready and phase completed; at 17:25:29.833 the engine logged embedded_window: error initializing surface err=error.OutOfMemory (fatal level, process holy-ghostty pid 1611, /usr/bin/log show --predicate process == holy-ghostty AND eventMessage CONTAINS OutOfMemory); no tmux session was created on socket holy; the roster row then carried attention conflict at session_selected and nothing else, so the record described a shell that never existed. Machine had 97 percent memory free and the app was at 1.11 GB RSS, so this is an allocation failure inside surface init, not system pressure; single occurrence in 10 hours of log. The initialInput was never delivered. Fix: (1) when surface init fails, the session row must say so (phase failed, attention needsUser, preview carrying the engine error) and never claim a ready shell; (2) automation spawn returns the failure to the caller (the URL route today returns nothing); (3) find why surface init can return OutOfMemory with free memory (Ghostty embedded_window path). Recovery used 09-24: tmux -L holy new-session -d -s <recorded name> -c <cwd> then send-keys the initial input; the app row became true once the tmux session existed.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-ede22a`.
4. Commit with `Manna: mn-ede22a` and run `agent-do manna done mn-ede22a` only after the work is verified.
