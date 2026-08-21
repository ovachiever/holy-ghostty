---
workflow: 2
manna: mn-7afa94
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P1][UX][KEYS] ⌘P dead: panel toggle keystroke has never worked despite wired interception'
inputs: []
binding: sha256:812f9380e0a83e99b254b9dc6e1a5c49f7f2185821636773ce9e73c64d21cdaf
---

# Handoff: [P1][UX][KEYS] ⌘P dead: panel toggle keystroke has never worked despite wired interception

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-7afa94
```

## Scope

[P1][UX][KEYS] ⌘P dead: panel toggle keystroke has never worked despite wired interception

## Inputs

- None declared.

## Work order

Erik 2026-08-11: "command P has never worked as a shortcut it does nothing" — ever, across builds since e260f8780 (2026-08-05) which bound it. CODE STATE (all verified present and wired): HolyWorkspaceWindow.performKeyEquivalent override → handleWorkspaceKeyEquivalent handles key p + .command → workspaceStore.toggleInboxPanel() (HolyWorkspaceWindowController.swift:13-18, :221-224); window.holyWorkspaceController assigned at init (:69); menu item carries the same equivalent. A synthetic ⌘P via System Events (2026-08-11 11:32) did not visibly toggle the panel; probe metric was weak (AX name query), treat as unconfirmed. DIAGNOSE IN-APP: os_log at the top of HolyWorkspaceWindow.performKeyEquivalent (does ⌘P even arrive? does another responder consume it first — Ghostty surface NSTextInputContext, the SwiftUI lens TextField when focused, or fullscreen state?). Sibling data point: ⌘W/⌥Q/⌘1-9 ride the same handler — do THEY work? If yes, the handler runs and the p-branch specifically misfires (charactersIgnoringModifiers under some layout?); if no, the window override never fires and the whole workspace key family is dead, which is a bigger finding than ⌘P.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-7afa94`.
4. Commit with `Manna: mn-7afa94` and run `agent-do manna done mn-7afa94` only after the work is verified.
