---
workflow: 2
manna: mn-4e9e84
track: null
source: Erik 2026-09-26 'yes to all' — Fable's unauthorized cross-repo edit, filed for a holy-ghostty worker
base_commit: fd11a35eeb0bee1ee0e3389313d9450c3802e3e5
scope: 'Revert and assess Fable''s unauthorized brief edit (54fb6b58d): restore ''Run focused test suites only''; workers run focused suites, the orchestrator runs full suites'
inputs:
- Erik 2026-09-26 'yes to all' — Fable's unauthorized cross-repo edit, filed for a holy-ghostty worker
binding: sha256:adb81d04b9e447f64936ebf30a12b25d469f0eb7c5aac673f035e6d8d20a3c7c
---

# Handoff: Revert and assess Fable's unauthorized brief edit (54fb6b58d): restore 'Run focused test suites only'; workers run focused suites, the orchestrator runs full suites

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-4e9e84
```

## Scope

On 2026-09-24 the aldebaran-group orchestrator (a Fable session) edited this repository without Erik's authorization: commit `54fb6b58d` ("fix(board): the launch brief runs the suites the sealed handoff names …"), touching `macos/Sources/HolyGhostty/Board/HolyMannaBoardWorker.swift` (the board-worker brief: the line "Run focused test suites only, using the repository's canonical validation commands." was replaced by a three-sentence rule deferring to the sealed handoff, and the report line "focused test/build commands" lost the word focused) and `macos/Tests/HolyGhostty/HolyMannaBoardActionsTests.swift` (the pinned clause `"focused test suites only"` was changed to match). Erik's ruling (2026-09-26): the original brief is the intended design — workers run focused suites so many lanes run at once, and the orchestrator runs the full suites afterward. The edit was not warranted. Nothing was pushed; the commit sits on `main` beneath later commits.

## Inputs

- Commit `54fb6b58d` on `main` (the two files it touched); the original brief text quoted in Scope; the Holy test target `HolyMannaBoardActionsTests`.
- Erik's ruling 2026-09-26 (workers run focused suites; the orchestrator runs full suites afterward).

## Work order

1. **Revert** `54fb6b58d` with `git revert` (never a reset; later commits stay). Confirm the brief line reads exactly "Run focused test suites only, using the repository's canonical validation commands." and the report line reads "focused test/build commands" again; confirm the test clause is back to `"focused test suites only"`; run the Holy test target that covers `HolyMannaBoardActionsTests`.
2. **Assess** and record in the return: was the change needed (the orchestrator's own answer: no — the mismatch was in its sealed orders, which demanded full suites from builders); was it done well (source and test moved together; commit message accurate); what, if anything, the brief should say so that a sealed order asking for something beyond focused suites is handled without a worker stalling on "clarification unanswered" (a suggestion for Erik, not a change in this lane).
3. Commit with the trailer `Manna: mn-4e9e84`. No push.

### Boundaries

This repository only; the two files named plus the return. No other edits. Record the claim in the return as prose, never as the literal command.

## Completion

1. Deliverables: the revert commit; a return under the repository's convention with the assessment. Verdict `SUBMITTED` / `PARTIAL` / `BLOCKED`, never `ACCEPTED` — Erik accepts.
2. Coord: touch, claim `mn-4e9e84`, focus with the file paths; release on stop.
3. Seal with `agent-do manna handoff seal mn-4e9e84` only if continuation context changed. `agent-do manna done mn-4e9e84` when the revert is committed and the test target passes.
