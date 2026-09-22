---
workflow: 2
manna: mn-0b49e9
track: mn-9a97cc
source: null
base_commit: d1d0c1100b9747bdf7730c6abc74da410353d52a
scope: '[P1][BOARD][ARCHIVE] Clipboard citizenship: copy and paste work everywhere in Board and Archive — the surface stops owning the keyboard under overlays'
inputs: []
binding: sha256:9e624e72ea4bae8bfbe327221e0bbad8d026600196f5d208e9d423984255cc92
---

# Handoff: [P1][BOARD][ARCHIVE] Clipboard citizenship: copy and paste work everywhere in Board and Archive — the surface stops owning the keyboard under overlays

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-0b49e9
```

## Scope

[P1][BOARD][ARCHIVE] Clipboard citizenship: copy and paste work everywhere in Board and Archive — the surface stops owning the keyboard under overlays

## Inputs

- None declared.

## Work order

Erik 2026-09-22: 'I NEED to be able to copy and paste in board/archive, anywhere.' ROOT CAUSE FOR PASTE, PROVEN ON TAPE: the HolyKeyDebug instrument (5b3f90e8a) recorded every cmd-V since Sep 11 — all show handledByWorkspace=false superHandled=true fr=SurfaceView (receipts: /usr/bin/log show --predicate 'category == "HolyKeyDebug"', entries incl. 2026-09-22 18:39-18:43, Erik's live attempts). Meaning: with Board/Archive presented, AppKit first responder is STILL the terminal SurfaceView; its performKeyEquivalent treats cmd-V as the terminal paste binding and consumes it — the clipboard pastes into a hidden pane behind the overlay. SwiftUI @FocusState on the search fields never moved AppKit responder. Fix, two deliverables in one lane: (1) PASTE/RESPONDER — when Board or Archive presents, the terminal surface resigns first responder and must not reclaim it while the overlay stands (mode stores own presentation lifecycle; restore responder on dismiss); belt-and-suspenders: SurfaceView.performKeyEquivalent returns false when a Holy mode overlay covers it, so even a stale responder cannot eat cmd-V/cmd-C/cmd-A. After the fix, cmd-V into the board grep/ask field, archive search, tag/note editors, and research chat must insert text (the standard paste: selector reaching the field editor). (2) COPY/SELECTION — text in Board and Archive becomes selectable and copyable ANYWHERE: SwiftUI textSelection(.enabled) (or equivalent NSTextView backing) on archive transcripts, message bodies, detail panes, board item descriptions, digests, AI summaries, and inspector text; cmd-C copies the selection; with no selection, cmd-C on a selected ledger row copies its id + title (board) / its resume command already has Enter — keep existing archive copy verbs (y/a transcript, c message) untouched. Regression tests, executed: a focused-field cmd-V inserts rather than reaching the surface (assert the responder identity and that no surface receives the paste binding while presented — the HolyKeyDebug line's fr must be a text view during field focus); overlay-dismiss restores terminal keyboard ownership (typing reaches the pane again); selection-copy round-trips a transcript excerpt through NSPasteboard. Acceptance (Erik): open Archive, click the search field, cmd-V pastes; select transcript text with the mouse, cmd-C, paste it into a terminal pane; same in Board on a description and the ask field; then close the overlay and confirm the terminal types and pastes normally again. Note: verify none of Erik's clipboard content leaked into background panes as stray input historically — if the paste-into-hidden-pane path could have EXECUTED text in a shell, say so in the report (safety review, not blame).

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-0b49e9`.
4. Commit with `Manna: mn-0b49e9` and run `agent-do manna done mn-0b49e9` only after the work is verified.
