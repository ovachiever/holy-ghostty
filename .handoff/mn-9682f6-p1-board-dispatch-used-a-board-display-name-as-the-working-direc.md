---
workflow: 2
manna: mn-9682f6
track: mn-eb7a80
source: sessions row 985BC829; restore sheet 2026-09-26
base_commit: 962f13ad23c8f022a2b5d44d29de8085c36339de
scope: '[P1][BOARD] Dispatch used a board display name as the working directory; a worker was created into a path that does not exist'
inputs:
- sessions row 985BC829; restore sheet 2026-09-26
binding: sha256:86cce5b5cc1c053a1a61195bbb941ccc166547b59866295351b773a6df74b8c1
---

# Handoff: [P1][BOARD] Dispatch used a board display name as the working directory; a worker was created into a path that does not exist

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-9682f6
```

## Scope

[P1][BOARD] Dispatch used a board display name as the working directory; a worker was created into a path that does not exist

## Inputs

- sessions row 985BC829; restore sheet 2026-09-26

## Work order

Receipt: session 985BC829 (title versova-supply-intelligence, codex, created 2026-09-23T13:40:28Z, note mn-cb43d9, objective Claim and build mn-cb43d9) has working_directory and resume lastKnownWorkingDirectory equal to /Users/erik/Custom-Coding/Research Comprehensive App Security | Custom-Coding; the sibling dispatch 336655AA five minutes later got /Users/erik/Custom-Coding/versova-supply-intelligence. HolyMannaBoardWorker.swift:244 sets spec.workingDirectory = context.boardRoot and :180 only checks the / prefix, so a root composed from a board display name passes. Deliver: find where boardRoot is composed for that board (federation or estate entry whose name carries a pipe) and make it the board's real repository path; dispatch refuses with a named reason when the directory does not exist on the target host; the row title and objective keep the item id. Test: a board whose display name differs from its path dispatches into the path; a missing directory refuses. Own macos/Sources/HolyGhostty/Board/ and the HolyMannaBoard test files only.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-9682f6`.
4. Commit with `Manna: mn-9682f6` and run `agent-do manna done mn-9682f6` only after the work is verified.
