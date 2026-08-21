---
workflow: 2
manna: mn-61655a
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P1][RESTORE] Ambiguous picker: allow restoring BOTH matching conversations, not a forced single choice'
inputs: []
binding: sha256:241993ffc4cb1b93e51ab48c4b7e722aa1f68f888ca98549caa959ab46d26e71
---

# Handoff: [P1][RESTORE] Ambiguous picker: allow restoring BOTH matching conversations, not a forced single choice

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-61655a
```

## Scope

[P1][RESTORE] Ambiguous picker: allow restoring BOTH matching conversations, not a forced single choice

## Inputs

- None declared.

## Work order

Erik, 2026-08-12 after the drill restore: 'when there are two matching sessions we shouldn't be forced to choose one or the other, should be able to choose both'. Ratified shape: the picked candidate resumes into the row's identity (title, notes, pins); each additional picked candidate spawns as a SIBLING session in the same working directory via the normal launch path (claude --resume <id> etc.), no archive adoption — identity belongs to the primary. Global unique assignment still holds (a conversation claimed anywhere is not offered twice). Caveat to carry into the UI: two candidates near the same cwd/time are sometimes parent and fork of the SAME thread, so restoring both can duplicate a conversation — previews and timestamps make that the human's informed call (honesty covenant: the sheet loads the choice, the human fires it).

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-61655a`.
4. Commit with `Manna: mn-61655a` and run `agent-do manna done mn-61655a` only after the work is verified.
