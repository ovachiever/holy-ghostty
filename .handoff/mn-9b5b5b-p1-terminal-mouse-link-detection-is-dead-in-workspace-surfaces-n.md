---
workflow: 2
manna: mn-9b5b5b
track: mn-eb7a80
source: Erik live test 2026-09-10 10:12 (both halves fail); config + surface receipts this session
base_commit: a10c7772c0da73425a533f877b3d973923691f1a
scope: '[P1][TERMINAL][MOUSE] Link detection is dead in workspace surfaces: no cmd-hover underline, no cmd-click open'
inputs:
- Erik live test 2026-09-10 10:12 (both halves fail); config + surface receipts this session
binding: sha256:48be672ebd64d9f7fae03dd8f50283e3fda501e76ffd88def51aef50e8322038
---

# Handoff: [P1][TERMINAL][MOUSE] Link detection is dead in workspace surfaces: no cmd-hover underline, no cmd-click open

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-9b5b5b
```

## Scope

[P1][TERMINAL][MOUSE] Link detection is dead in workspace surfaces: no cmd-hover underline, no cmd-click open

## Inputs

- Erik live test 2026-09-10 10:12 (both halves fail); config + surface receipts this session

## Work order

Erik 2026-09-10, live test in a workspace pane: a plain https URL gets NO underline on cmd-hover and NO open on cmd-click — detection never fires at all. Receipts: ghostty config has zero link/mouse overrides (defaults on); upstream SurfaceView mouse handling is present (mouseMoved hits in Surface View/SurfaceView_AppKit.swift); recent surface-view commits are upstream merges, not Holy's. Prime suspects, in bisect order: (1) Holy's workspace hosting hierarchy (SwiftUI containers wrapping the surface, custom HolyWorkspaceWindow, the split tree) breaking NSTrackingArea/mouseMoved delivery or flagsChanged (cmd) tracking to the surface view; (2) first-responder/key-window quirks from the workspace event routing (the cmd-key family had exactly this disease before b5825fac0); (3) mouse-reporting interplay under tmux ONLY IF a bare non-tmux surface works — so BISECT FIRST: open a QuickTerminal (bare Ghostty surface, no Holy workspace wrapper), print a URL, cmd-hover — if links work there, the defect is Holy's hosting layer; if dead there too, it is core/config territory. Fix restores stock Ghostty behavior in workspace panes: cmd-hover underlines with pointer cursor, cmd-click opens, plain click still selects. Regression test at whatever layer the bisect lands. BLOCKS mn-5a26f9 (clickable mn- ids ride this same machinery).

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-9b5b5b`.
4. Commit with `Manna: mn-9b5b5b` and run `agent-do manna done mn-9b5b5b` only after the work is verified.
