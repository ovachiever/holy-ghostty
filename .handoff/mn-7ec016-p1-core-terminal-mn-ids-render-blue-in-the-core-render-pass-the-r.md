---
workflow: 2
manna: mn-7ec016
track: mn-9a97cc
source: null
base_commit: b5c7f1763fe1e7d71eabb501c219f4e97681b8f1
scope: '[P1][CORE][TERMINAL] mn- ids render blue in the core render pass — the renderer is the only painter'
inputs: []
binding: sha256:25bd308d1640c3472576fd6b3825672bd97284250068870d8b56fc22ef3f85ac
---

# Handoff: [P1][CORE][TERMINAL] mn- ids render blue in the core render pass — the renderer is the only painter

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-7ec016
```

## Scope

[P1][CORE][TERMINAL] mn- ids render blue in the core render pass — the renderer is the only painter

## Inputs

- None declared.

## Work order

Erik ruling 2026-09-11 (supersedes the overlay approach of mn-4be59b, reverted b5c7f1763/6d6c2d2b1/9699989dd): ONE GRID, ONE PAINTER — text-anchored styling lives in the terminal renderer, never in an AppKit overlay shadowing it over a polling API; the overlay was structurally one frame behind (flicker on stream, stuck-white on animated viewports, blink on scroll — one disease, three views). Implementation, in-core: src/renderer/link.zig already regex-matches the viewport per frame into a cell map with per-rule highlight modes (URL hover-underline rides it, and URLs never flicker — that is the proof of home). Add a built-in Holy rule: pattern mn-[a-f0-9]{6,} with word boundaries (reject ids embedded in longer tokens), highlight always (not hover-gated), style = foreground palette color 4 (ANSI blue, follows the user theme), no underline. Gate behind config key holy-manna-highlight default true. The macOS cmd-click/hover hit-testing (mn-5a26f9) is event-side and stays untouched. CONSTRAINT (house law, scroll-regression postmortem): the engine builds via CI ReleaseFast artifact ONLY — local Zig linking is broken on macOS 26; Zig source edits + core-side unit tests land in the repo, the artifact rides CI, and the install that carries it follows the CI cycle. Tests: core-side matcher boundaries (short hex, uppercase, embedded), cell-map runs for wrapped ids, config gate off = no styling. Acceptance: Erik sees blue mn- ids at rest that are rock-steady during streaming, spinners, and scrolling — by construction, since the same pass draws text and color.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-7ec016`.
4. Commit with `Manna: mn-7ec016` and run `agent-do manna done mn-7ec016` only after the work is verified.
