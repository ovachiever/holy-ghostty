---
workflow: 2
manna: mn-3aeeef
track: mn-eb7a80
source: log show 2026-09-25 22:30 window
base_commit: 962f13ad23c8f022a2b5d44d29de8085c36339de
scope: '[P2][LOGGING] The app writes about 60 log lines per second to the unified log, four per session per second'
inputs:
- log show 2026-09-25 22:30 window
binding: sha256:0fcf2bd7b56acd9327bbf35468dcd5405cd44e5f8732b4be772ae27382c64593
---

# Handoff: [P2][LOGGING] The app writes about 60 log lines per second to the unified log, four per session per second

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-3aeeef
```

## Scope

[P2][LOGGING] The app writes about 60 log lines per second to the unified log, four per session per second

## Inputs

- log show 2026-09-25 22:30 window

## Work order

Receipt: /usr/bin/log show for process holy-ghostty between 2026-09-25 22:30 and 22:36 counted 3,734 to 3,854 lines per minute, and per-session short ids appear about 21,950 times each over 90 minutes (about 4 per second per session for roughly 16 sessions). This predates the 23:40 leak onset and is not the leak, but it is cost and noise on every fleet poll. Deliver: name the categories and call sites, rate-limit or demote the per-poll lines to debug, keep the HolyKeyDebug and HolyAttentionDebug tapes available behind their switches, and show the before and after line rate.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-3aeeef`.
4. Commit with `Manna: mn-3aeeef` and run `agent-do manna done mn-3aeeef` only after the work is verified.
