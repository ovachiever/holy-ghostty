---
workflow: 2
manna: mn-12801a
track: mn-eb7a80
source: 'Erik 2026-09-08 14:18 + planner receipts (HolyWorkspaceStore convergeRoster: only .repair/.adoptArchived exist)'
base_commit: f04446826826ce17e7ed4c0712210323f0af7eb2
scope: '[P1][ROSTER][SYNC] Sync adopts never-seen Holy sessions from every host — and reports what it did'
inputs:
- 'Erik 2026-09-08 14:18 + planner receipts (HolyWorkspaceStore convergeRoster: only .repair/.adoptArchived exist)'
binding: sha256:86a416f7c7411a62295ab788d1a56550bce1c4ff20e6c2b2d830b3162228db03
---

# Handoff: [P1][ROSTER][SYNC] Sync adopts never-seen Holy sessions from every host — and reports what it did

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-12801a
```

## Scope

[P1][ROSTER][SYNC] Sync adopts never-seen Holy sessions from every host — and reports what it did

## Inputs

- Erik 2026-09-08 14:18 + planner receipts (HolyWorkspaceStore convergeRoster: only .repair/.adoptArchived exist)

## Work order

Erik 2026-09-08: Sync 'always sucked so I never used it' — root cause found in the planner: convergeRoster has exactly two actions, .repair (dead roster sessions) and .adoptArchived (sessions THIS machine's DB has known). A tmux session born on another machine (the dominant case: MacBook viewing Studio-born sessions) discovers fine but has no local match key and is silently skipped — Sync looked broken while working as designed. Add the third verb: .adoptDiscovered for sessions that prove Holy ancestry via their own markers (holy-* tmux naming and/or @holy_* session options — with mn-2c82a2's host-authoritative options carrying identity/seen/title, adoption anywhere reconstructs an honest row); non-Holy tmux sessions are never touched, and the existing ambiguity-blocks-adoption law stands. Sweep scope stays as coded: local + every saved remote host + hosts inferable from the roster. And kill the silence that built the distrust: each Sync ends with a visible converge report — attached N, repaired M, adopted K from <host>, skipped J (each with its reason: not Holy-born, ambiguous, host unreachable) — in the toast/footer strip and the flight-recorder log. Acceptance: from a MacBook with an empty roster and zero local history, one Sync populates every Holy session running on the Studio with correct identity, titles, and seen-state (per mn-2c82a2), and the report accounts for every discovered session; the Hosts sheet remains for browsing/select-adoption but is no longer required for the daily 'mirror reality' gesture. Relates: mn-569b91 (reconcile known sessions / reap true orphans) — same discovery substrate, coordinate.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-12801a`.
4. Commit with `Manna: mn-12801a` and run `agent-do manna done mn-12801a` only after the work is verified.
