---
workflow: 2
manna: mn-5a26f9
track: mn-9a97cc
source: 'Erik request 2026-09-10 10:07 (screenshot: dm-ephemeris ids cited in-pane)'
base_commit: 516e6e530f24c0ed9f9449baa5bcc3f68c7a7a88
scope: '[P1][TERMINAL][ACT] mn- ids in any pane are clickable: resolve estate-wide, then Claim & build behind the confirm'
inputs:
- 'Erik request 2026-09-10 10:07 (screenshot: dm-ephemeris ids cited in-pane)'
binding: sha256:b657efadad2ff572ff3296211dc83c355c1c9361652185c59930f55fc58ea08a
---

# Handoff: [P1][TERMINAL][ACT] mn- ids in any pane are clickable: resolve estate-wide, then Claim & build behind the confirm

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-5a26f9
```

## Scope

[P1][TERMINAL][ACT] mn- ids in any pane are clickable: resolve estate-wide, then Claim & build behind the confirm

## Inputs

- Erik request 2026-09-10 10:07 (screenshot: dm-ephemeris ids cited in-pane)

## Work order

Erik 2026-09-10: manna ids printed in terminal output (agents cite them constantly) should be clickable into the claim-and-run flow. Design, four existing pieces plus one new matcher: (1) MATCHER — extend the core's link-detection engine with the mn-[a-f0-9]{6,} pattern emitting a holy-ghostty://board?item=<id> link, exactly as URLs become clickable today; CONSTRAINT: this is Zig core territory and engine rebuilds go through CI only (local Zig link broken on macOS 26 — house law from the scroll-regression postmortem); if a core change is too heavy a first step, the macOS fallback is surface-level hit-testing of the character cell under a cmd+click against the same regex, no engine change. (2) ROUTE — the existing URL scheme gains the board?item route. (3) RESOLUTION — an id in prose often belongs to ANOTHER repo's board (Erik's screenshot cites dm-ephemeris ids inside an aldebaran session): resolve estate-wide via manna estate --json + per-board state, prefer the session's own cwd board, then unique match across the estate; ambiguous or unknown ids open the board view's search rather than guessing. (4) ACTION — landing surface is the item in Board mode with the SHIPPED Claim & build affordance (mn-ec34cd machinery): the confirm sheet is mandatory (glance law — a click in scrollback must never dispatch or mutate by itself), dreams refuse, claimed items show the claimant. Style: render detected ids with the link underline-on-hover treatment the terminal already uses for URLs. Tests: pattern boundaries (mn- inside words, uppercase, short hex), cross-board resolution incl. ambiguous, the confirm gate, and a scrollback click on a done item landing on its done row. Acceptance: cmd+click a cited id in any session, land on the item, one confirm dispatches the worker.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-5a26f9`.
4. Commit with `Manna: mn-5a26f9` and run `agent-do manna done mn-5a26f9` only after the work is verified.
