---
workflow: 2
manna: mn-d9e12d
track: mn-9a97cc
source: null
base_commit: c4fce47f3d105ae22b1ae70e5061140f65dd1053
scope: '[P1][BOARD][DISPATCH] Intelligence level picker on Claim & build — low/med/high/xhigh/max, default max for both runtimes'
inputs: []
binding: sha256:01c1544c7386612583bf3e02c6bed08d8e8ae1c231baea873e2c4dd6ebbcb376
---

# Handoff: [P1][BOARD][DISPATCH] Intelligence level picker on Claim & build — low/med/high/xhigh/max, default max for both runtimes

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-d9e12d
```

## Scope

[P1][BOARD][DISPATCH] Intelligence level picker on Claim & build — low/med/high/xhigh/max, default max for both runtimes

## Inputs

- None declared.

## Work order

Erik 2026-09-15: the board's worker dispatch chooses only Codex or Claude (plus a free-text model); add an intelligence LEVEL — low, med, high, xhigh, max — with MAX AS THE DEFAULT for both runtimes (Erik's ruling). This is Holy-only: no agent-do change, no engine change. Work: (1) MODEL — extend HolyMannaWorkerProfile (macos/Sources/HolyGhostty/Board/HolyMannaBoardWorker.swift:3) with a level enum (low, med, high, xhigh, max; default .max). (2) MAPPING — a per-runtime table from level to concrete launch arguments, derived from each runtime's REAL flag surface, not memory: run codex --help / codex config schema and claude --help on the dispatch host (the resolver machinery already finds the binaries; a probe receipt goes in the handoff) and record the exact model + effort flags each level produces. Known in-repo precedent: Holy's own digest path drives claude --print --effort high|low (HolyMannaBoardDigest.swift), and Erik's codex composer runs gpt-6-astra at max effort — but the shipped table cites the live --help output as its authority. Precedence: an explicit model typed in the model field overrides the level's model choice while the level's effort flags still apply where the runtime accepts them; an empty model field takes the level's full mapping. (3) UI — the level picker sits beside the runtime choice in the board item detail (HolyMannaBoardView dispatch controls), default max; the confirmation sheet (HolyMannaWorkerDispatch.confirmation, Worker.swift:158) names the level; the generated brief records it. (4) COMMAND — launchSpec (Worker.swift:189) appends the mapped arguments with the existing quoting; the exec pane-leader behavior, refusal gates, and session-note plumbing are untouched. Tests (executed, not compiled): default level is max for both runtimes; each level maps to its receipted arguments per runtime; explicit-model precedence; quoting of injected model text stays safe (the existing injection regression extends to level arguments); refusals unchanged. Acceptance: Erik opens Claim & build, sees the level picker defaulted to max, dispatches one worker per runtime, and the pane command line carries the mapped flags. Coordinated execution and install return through the coordinator; no push, no PR, no launches from the builder lane beyond the probe commands.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-d9e12d`.
4. Commit with `Manna: mn-d9e12d` and run `agent-do manna done mn-d9e12d` only after the work is verified.
