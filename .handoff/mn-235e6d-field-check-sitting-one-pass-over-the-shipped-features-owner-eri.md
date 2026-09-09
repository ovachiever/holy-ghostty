---
workflow: 2
manna: mn-235e6d
track: mn-eb7a80
source: Closing doctrine ruling 2026-09-09; supersedes the acceptance gates formerly embedded in the closed items
base_commit: 2786bfa1695fd80320aea2999e2bc59ea864ffdf
scope: 'Field-check sitting: one pass over the shipped features, owner Erik'
inputs:
- Closing doctrine ruling 2026-09-09; supersedes the acceptance gates formerly embedded in the closed items
binding: sha256:21b498f8ca492e8bf0ebcd58ff6834aafc69bd7182a50ebbb12ea8930c078dc7
---

# Handoff: Field-check sitting: one pass over the shipped features, owner Erik

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-235e6d
```

## Scope

Field-check sitting: one pass over the shipped features, owner Erik

## Inputs

- Closing doctrine ruling 2026-09-09; supersedes the acceptance gates formerly embedded in the closed items

## Work order

The acceptance work formerly held hostage inside eleven build items, now one twenty-minute sitting (per the 2026-09-09 closing doctrine, dec-4db3fe — a failed check never reopens the old item; file a new one citing it). The pass: (1) ledger feel — drag board+archive column grips and both inspector dividers, resize the window narrow and back (mn-f044d0/mn-ac0b36); (2) Clear then Sync — window stays open, roster reconverges (mn-3a03e3); (3) glance the once-stuck codex rows — no eternal spinner, honest states (mn-d204ae); (4) ask the board a question with Enter, click a citation (mn-57866a); (5) one-click Claim & build on any READY item — worker boots to a real prompt, session note carries the mn id (mn-ec34cd + dispatch repair 2786bfa16); (6) rule on the pre-warm day — any 'writing…' sightings since Sep 4? none = verdict clean (mn-252f7a's field half); (7) next natural reboot — codex sessions restore, dots survive (mn-9a9728/mn-18be22 field half); (8) when on the MacBook — archive shows Studio sessions, one cross-host search, one remote restore (mn-b61389 field half); (9) cross-machine dots — seen on Studio shows seen on MacBook (mn-2c82a2 field half). Each finding that fails becomes a NEW item citing the old id.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-235e6d`.
4. Commit with `Manna: mn-235e6d` and run `agent-do manna done mn-235e6d` only after the work is verified.
