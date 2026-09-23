---
workflow: 2
manna: mn-0b49e9
track: mn-9a97cc
source: null
base_commit: d1d0c1100b9747bdf7730c6abc74da410353d52a
scope: '[P1][BOARD][ARCHIVE] Clipboard citizenship: copy and paste work everywhere in Board and Archive — the surface stops owning the keyboard under overlays'
inputs: []
binding: sha256:e03b8341a5a41d9776f00c9893e1099f48c797880e3bcebf7a6d722f479e1c93
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

## Builder receipt: 2026-09-22

Status: implementation ready for coordinated acceptance. Keep Manna `in_progress`.
Required executed regression tests and Erik's live acceptance have not run.
No app launches, installs, screenshots, live session spawning, pushes, or pull
requests were performed in this lane.

Ownership was acquired by `codex-01a0cb81bb267ab1`. The initial handoff was
verified against canonical `agent-do manna state --json` and the expected
`sha256:9e624e72ea4bae8bfbe327221e0bbad8d026600196f5d208e9d423984255cc92`.
Verification used Manna's `binding_material` normalization, which blanks only
the frontmatter binding value. The initial raw file SHA-256 was
`165e12281d8dc34b2d5a041a245953459258c179656712b0b2f0a81c1c1b57c3`.
The work followed the supplied AGENTS instructions and the nearest on-disk
`/Users/erik/Custom-Coding/AGENTS.md`; no closer AGENTS file was present.

### Changes

- `HolyWorkspaceWindowController.swift`: a window-local Board/Archive mode set
  owns keyboard exclusion. Presentation synchronously resigns SurfaceView.
  `makeFirstResponder` refuses delayed terminal focus before AppKit can resign
  the active editor. Dismissal restores the currently selected terminal after
  the view update, with a fresh mode check. Mode switches do not restore the
  terminal between overlays.
- Both mode stores notify that window directly from their presentation
  lifecycle. This applies to toolbar, keyboard, link, and programmatic routes.
- `SurfaceView_AppKit.swift`: detached panes retain a weak reference to their
  owning window. Focus, key equivalents, keyboard events, native clipboard
  actions, and text insertion reject input while a mode covers the pane.
- Both mode roots enable native text selection, including digests, summaries,
  descriptions, metadata, annotations, transcript text, and research output.
- Board row copy is a native `copy:` responder fallback containing the selected
  item's ID and plain title. Editable fields and nonempty text selections retain
  priority. A read-only text view with an empty selection gets the row fallback.
- Board's key monitor is restricted to its own window and does not take `/`
  from other editors. Archive distinguishes editable text from read-only
  selections, preserves Enter and y/a/c copy verbs, and leaves `z` as text in
  research input instead of toggling fullscreen.

### Validation

The seven owned Swift files pass strict SwiftLint with zero violations.
`git diff --check` passes. The existing ReleaseFast core passes
`scripts/build-holy-ghostty-core.sh verify`, using Zig 0.15.2 and core input hash
`df28bebb6ebfe4a473978513324c78da1f5148e4952f7f59d53e3806f7781141`.

The canonical Debug build-for-testing completed with exit 0 and
`TEST BUILD SUCCEEDED`: arm64, zero errors, 521 warnings, none referencing an
owned Swift file. Xcode records the execution action as `notRequested`.
**Executed tests: 0.** Xcode compiles the test bundle even with suite selectors;
no test case, render smoke test, or UI test was executed.

```sh
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .dev/mn-0b49e9/DebugDerivedData \
  SYMROOT=/Users/erik/Custom-Coding/holy-ghostty/.dev/mn-0b49e9/test-build \
  -only-testing:GhosttyTests/HolyModeClipboardTests \
  -only-testing:GhosttyTests/HolyMannaBoardTests \
  -only-testing:GhosttyTests/HolyArchiveModeTests \
  -parallel-testing-enabled NO \
  -resultBundlePath .dev/mn-0b49e9/clipboard-debug-build.xcresult \
  build-for-testing
```

The new `HolyModeClipboardTests` defines 15 cases across eight tests. They use
real Ghostty surfaces running `/bin/cat`, native AppKit event dispatch, the
actual SwiftUI fields/text, and NSPasteboard. They cover five input destinations,
detached and delayed focus, dismissal, mode switching, selection copy, Board
row fallback, and Archive's existing copy verbs. They preserve clipboard formats
in memory and restore them. They have compiled, not executed.

The isolated production ReleaseLocal build completed with exit 0 and
`BUILD SUCCEEDED`: x86_64 and arm64, zero errors, 55 warnings, none referencing
an owned Swift file. The resulting app passes `codesign --verify --deep --strict`
and contains no GhosttyTests plug-in. It was not installed or launched.

```sh
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -configuration ReleaseLocal \
  -derivedDataPath .dev/mn-0b49e9/ReleaseDerivedData \
  SYMROOT=/Users/erik/Custom-Coding/holy-ghostty/.dev/mn-0b49e9/production-build \
  -resultBundlePath .dev/mn-0b49e9/release-build-clean.xcresult build
```

Receipts live under `.dev/mn-0b49e9/`: `core-verify.log`,
`swiftlint-final.log`, `build-for-testing-debug.log`,
`clipboard-debug-build.xcresult`, `debug-build-summary.json`,
`compiled-source-sha256.json`, `release-build-clean.log`,
`release-build-clean.xcresult`, and `release-build-summary.json`.
The source hash manifest binds all seven Swift
inputs to the final compilation. The commit carrying this handoff is the
candidate for acceptance.

Failed attempts are retained for diagnosis. The first compile exposed an
inherited NSWindow menu-validation conformance, which was corrected. ReleaseLocal
test attempts then exposed the test target's need for both testability and
DEBUG-only helpers; Debug is the correct project test configuration. A subsequent
release signing attempt found the failed test plug-in in reused build products.
Production and tests now use entirely separate DerivedData and product roots;
normal signing and core verification remain enabled.

### Historical paste safety review

`historical-paste-routing.json` summarizes a read-only unified-log query for
HolyKeyDebug Command-V events over the preceding day. It found 11 events between
2026-09-22 18:03:32 and 18:43:03 CDT. All recorded `fr=SurfaceView` and
`superHandled=true`. The log contains neither clipboard payloads nor shell
execution results, and does not record overlay visibility for every event.
Clipboard contents and shell histories were not collected or exposed.

The former SurfaceView paste path requests the clipboard and writes its encoded
contents into the PTY (`src/Surface.zig`, `startClipboardRequest` and
`completeClipboardPaste`). That path could have executed shell text when command
terminators were delivered and paste protections permitted it. Text left on a
shell command line could also execute on a later Enter. **There is no evidence
here that certifies either zero historical leakage or zero execution.**

### Needed next: coordinated acceptance

The following launches the app-hosted tests. It is a coordinator action, not a
builder-lane receipt, and has not been run. Keep the explicit suite selectors so
the render smoke suites and broader UI suite are not executed inadvertently.

```sh
xcodebuild \
  -xctestrun .dev/mn-0b49e9/test-build/Ghostty_Ghostty_macosx26.4-arm64.xctestrun \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:GhosttyTests/HolyModeClipboardTests \
  -only-testing:GhosttyTests/HolyMannaBoardTests \
  -only-testing:GhosttyTests/HolyArchiveModeTests \
  -parallel-testing-enabled NO \
  -resultBundlePath .dev/mn-0b49e9/clipboard-executed.xcresult \
  test-without-building
```

Then coordinate one supported install/live pass. Verify Command-V in Archive
search, tags, notes, transcript find, research chat, and Board grep/ask. Check
that the first responder is a text editor and no background pane receives the
paste. Select an Archive transcript excerpt and a Board description with the
mouse, copy with Command-C, and round-trip each into a dedicated inert acceptance
pane. Check Board row copy with no text selected, Archive Enter/y/a/c copy verbs,
and normal terminal typing/pasting after closing either mode. Check a direct
Board-to-Archive switch and a different workspace window for focus isolation.

Record the executed test result and live observations here, reseal, and only then
mark `mn-0b49e9` done. Build success alone does not satisfy this work order.

Lessons logged: 6 (new, including one subsequently corrected/retracted) |
Decisions logged: 1 (new).
