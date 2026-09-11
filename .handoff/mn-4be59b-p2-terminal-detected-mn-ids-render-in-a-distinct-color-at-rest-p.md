---
workflow: 2
manna: mn-4be59b
track: mn-9a97cc
source: null
base_commit: 065ff58584b5ce1b3b1515a589998982f0185148
scope: '[P1][TERMINAL] mn- ids render blue at rest in every pane — no hover underline'
inputs: []
binding: sha256:0e5fa10a56a2c9d7a7543458b82c96672c25e4fe9f35030c351fe95a1ec6b874
---

# Handoff: [P2][TERMINAL] Detected mn- ids render in a distinct color at rest — purple, not the program's own text color

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-4be59b
```

## Scope

[P2][TERMINAL] Detected mn- ids render in a distinct color at rest — purple, not the program's own text color

## Inputs

- None declared.

## Work order

Erik 2026-09-11 after accepting mn-5a26f9: ids are clickable but invisible as links — they render in whatever color the printing program chose (plain white in most agent output). Ruling: detected mn-[a-f0-9]{6,} runs get a distinct at-rest color so clickability is discoverable; Erik suggested purple or yellow — default purple, one Palette token, no per-user config yet. Architecture: the mn-5a26f9 machinery (HolyMannaLink + SurfaceView_AppKit hit test) detects only under the pointer; at-rest painting needs a viewport pass — on output/scroll settle (debounce ~100ms), read visible rows via ghostty_surface_read_text, regex for ids (reuse HolyMannaLink.match and the wrapped-boundary handling from 7baec439e), and draw an overlay per run: opaque cell-background rect in the surface background color, then the id glyphs in purple with the terminal's monospace font at cell metrics, so the original glyphs beneath never fringe through. Keep the existing cmd-hover underline on top. Overlay invalidates on any grid change; zero overlays when no ids visible; no core/Zig change (engine rides CI only). Tests: overlay run geometry for plain and soft-wrapped ids, invalidation on scroll, absence for lookalike words (mn- inside longer tokens). Acceptance: Erik sees purple mn- ids in live agent panes, hover still underlines, click still lands on the board item.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-4be59b`.
4. Commit with `Manna: mn-4be59b` and run `agent-do manna done mn-4be59b` only after the work is verified.
