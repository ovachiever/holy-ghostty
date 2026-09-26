---
workflow: 2
manna: mn-3a4538
track: mn-eb7a80
source: .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 7; 09-23 handoff §10 item 5
base_commit: 74e8e8b0daa88cf1681b19ce560068c684fac4a5
scope: '[P2][TESTS] GhosttyUITests target crashes at bootstrap; every serial run must skip it'
inputs:
- .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 7; 09-23 handoff §10 item 5
binding: sha256:000bfd7644252ddc9e8c30cd59733be2b20a1f330e68fc1b578e9a6ac24759fc
---

# Handoff: [P2][TESTS] GhosttyUITests target crashes at bootstrap; every serial run must skip it

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-3a4538
```

## Scope

[P2][TESTS] GhosttyUITests target crashes at bootstrap; every serial run must skip it

## Inputs

- .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 7; 09-23 handoff §10 item 5

## Work order

Serial runs die unless -skip-testing:GhosttyUITests is passed: the target exits before establishing a connection (09-23 handoff §10 item 5: early unexpected exit, crashed with signal kill). Either repair the target so it bootstraps, or record the skip in the release runbook (docs/holy-ghostty/engineering-spec.md §Build and Validation) and in the certified-run item with the crash receipt. Done when a serial run completes without the skip, or the runbook carries the skip and its receipt.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-3a4538`.
4. Commit with `Manna: mn-3a4538` and run `agent-do manna done mn-3a4538` only after the work is verified.
