---
workflow: 2
manna: mn-f4ab17
track: mn-9a97cc
source: Executed-test run 2026-09-10 21:23; cites mn-6160c9
base_commit: abe1f1e556d28622655191d9a12fc43a383dedd9
scope: '[P1][BOARD] backgroundBoardRefreshStartsWarmWithoutDelayingState fails — mn-6160c9 closed on compiled-only verification'
inputs:
- Executed-test run 2026-09-10 21:23; cites mn-6160c9
binding: sha256:db9c8143be67cae57b7fc99788e0e40f97155e9303e9402b4281738ceaf12174
---

# Handoff: [P1][BOARD] backgroundBoardRefreshStartsWarmWithoutDelayingState fails — mn-6160c9 closed on compiled-only verification

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-f4ab17
```

## Scope

[P1][BOARD] backgroundBoardRefreshStartsWarmWithoutDelayingState fails — mn-6160c9 closed on compiled-only verification

## Inputs

- Executed-test run 2026-09-10 21:23; cites mn-6160c9

## Work order

The mn-6160c9 dispatch-feedback work (c681f6a46) was closed (82dd218f0) with zero executed tests per its own report; first real run fails its regression backgroundBoardRefreshStartsWarmWithoutDelayingState (consistent, 0.02s). Claim, execute the three Board suites, fix, re-close on executed green. Erik's live chip/row acceptance queues behind this.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-f4ab17`.
4. Commit with `Manna: mn-f4ab17` and run `agent-do manna done mn-f4ab17` only after the work is verified.
