---
workflow: 2
manna: mn-5a0ca3
track: mn-eb7a80
source: null
base_commit: d9f5b0d9bae60dbb42f390715887f4ab4cd31f56
scope: '[P1][TERMINAL][LINKS] URL clicks do not work in workspace panes — command-click or plain — the mn-9b5b5b field check failed'
inputs: []
binding: sha256:796e03dd2803bddf419372ac34448080817c4c46897b2f971a3b1b43cfb55b71
---

# Handoff: [P1][TERMINAL][LINKS] URL clicks do not work in workspace panes — command-click or plain — the mn-9b5b5b field check failed

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-5a0ca3
```

## Scope

[P1][TERMINAL][LINKS] URL clicks do not work in workspace panes — command-click or plain — the mn-9b5b5b field check failed

## Inputs

- None declared.

## Work order

Erik live 2026-09-20: clicking URLs in Holy panes does nothing, with or without command. Context and receipts: mn-9b5b5b (link detection dead in workspace surfaces) was patched at 4b8b079e0 and closed 2026-09-11, but Erik's cmd-hover/cmd-click URL field check from that item's acceptance was never reported passing — this is that check failing, filed fresh per the no-reopen doctrine. Contrast that matters for the bisect: mn- id cmd-click (the HolyMannaLink machinery, mn-5a26f9) is a SEPARATE macOS-side path — establish immediately whether mn- id clicks still work today; if yes, the break is isolated to the core URL link path. Diagnostic ladder from the mn-9b5b5b handoff, still valid: (1) bare surface first — open a QuickTerminal (no Holy workspace wrapper), print a URL, cmd-hover: underline+pointer there but not in workspace panes → the defect is Holy's hosting/event routing; dead there too → core/config territory. (2) Split the symptom: does cmd-hover show the underline and the hover-URL caption (hoverUrl / displayedHoverURL in SurfaceView) but click not open — open-action path — or is there no hover response at all — detection/tracking delivery. (3) Suspect set from the intervening commits, to bisect not assume: the modifier-forwarding changes (973fc5355 then 61da5f002 frame-overlap check) touched flagsChanged delivery; the mn-5a26f9/mn-4be59b work added and then reverted (b5c7f1763, 6d6c2d2b1, 9699989dd) mouse-path code in SurfaceView_AppKit — verify the revert left the URL hover/click plumbing whole; and the mn-4be59b hover-underline removal commit (daee37c57) edited the same overlay region that displays hoverUrl. Fix restores stock behavior: cmd-hover underlines with pointer and caption, cmd-click opens in the browser on the viewing Mac, plain click still selects. Regression test at whatever layer the bisect lands, executed not compiled. Acceptance: Erik cmd-clicks a printed URL in a workspace pane and the browser opens; the QuickTerminal control case also passes.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-5a0ca3`.
4. Commit with `Manna: mn-5a0ca3` and run `agent-do manna done mn-5a0ca3` only after the work is verified.
