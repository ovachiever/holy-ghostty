---
workflow: 2
manna: mn-0b49e9
track: mn-9a97cc
source: null
base_commit: d1d0c1100b9747bdf7730c6abc74da410353d52a
scope: '[P1][BOARD][ARCHIVE] Clipboard citizenship: copy and paste work everywhere in Board and Archive — the surface stops owning the keyboard under overlays'
inputs: []
binding: sha256:36dac7e35c938893374ebafa9760730ddc0a7f966f786dd4878d6fc9d6fec839
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

## Current status: 2026-09-23

Erik's 09:47 live verdict and HolyKeyDebug tape confirm that the field editor
now owns the keyboard, but editing chords still fail to dispatch. The coordinator
executed the fixture repair; all five direct paste controls succeeded and the
subsequent Command-V checks failed. The new native editing-routing candidate
below has compiled in Debug and ReleaseLocal but has not executed. Keep `mn-0b49e9` `in_progress`
for coordinator re-execution, installation, and Erik's re-check. Earlier dated
receipts are historical, not passing acceptance for the new candidate.

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

## Fixture repair receipt: 2026-09-23

### Executed findings received from the coordinator

The original receipts remain intact in `.dev/mn-0b49e9-receipt.md`,
`.dev/mn-0b49e9-executed/suites.xcresult`, `.dev/mn-0b49e9-executed.log`,
`.dev/release-readiness/serial.xcresult`, and `.dev/rr-serial.log`.

- The focused run reported 30 failures and 192 passes. All 30 clipboard cases
  failed at the fixture's real-surface requirement before behavioral acceptance.
- Read-only diagnostic export of that xcresult identifies the lower failure:
  both clipboard worker logs report 15 instances each of
  `CVDisplayLinkCreateWithCGDisplays error -6661 due to invalid display count (0)`,
  followed by `error initializing surface err=error.OutOfMemory`. Core renderer
  initialization creates that display link only when `window-vsync` is enabled
  (`src/renderer/generic.zig`). This was a display-link prerequisite failure;
  the nil wrapper assertion alone did not identify it.
- The serial run restarted the host four times inside this suite. The old
  teardown called `window.close()` and could invoke the host's last-window quit
  policy. Source inspection also found a separate lifetime hazard: the fixture's
  core app could deinitialize before `Ghostty.Surface.deinit` completed its
  queued main-actor `ghostty_surface_free`.
- The one Board Command-V behavior assertion reached in the serial run failed
  with an empty editor. This remains a red receipt. The repair adds a direct
  `paste:` control so the rerun can separate editor/binding behavior, host focus,
  and key-equivalent routing without converting a failed shortcut into a pass.

### Repair

Only `macos/Tests/HolyGhostty/HolyModeClipboardTests.swift` changes executable
code in this revision. Production behavior is unchanged.

- A process-retained test host owns one reusable real `HolyWorkspaceWindow`
  and one core app. Teardown clears content, responders, and callbacks, then
  orders the window out. It never closes that last window. The core app outlives
  deferred surface destruction. A new regression drains weak surface/userdata
  references and creates the next fixture in the retained window.
- The real surface uses supported `window-vsync = false`, removing the diagnosed
  display-link dependency from these input tests, and `command = direct:/bin/cat`
  with shell integration disabled. Surface initialization still must succeed;
  no mock, skipped case, retry fallback, or production test bypass was introduced.
- Every actual Board/Archive field first receives direct `paste:` and checks
  its native editor and store binding against a known synthetic value. The test
  clears that value before independently checking Command-V. A console receipt
  preserves the direct-control outcome even if keyboard dispatch later fails.
- Keyboard dispatch requests activation during setup and requires the actual
  host to be active with the fixture window key and main. It retains
  `NSApp.sendEvent` and the host's production menu. An unavailable keyboard host
  fails explicitly; no fake menu or direct-paste fallback is installed.
- Command-V failures include responder/menu-target diagnostics, and the surface
  records handled key equivalents as well as keyDown calls. Expected binding
  values are compared to the synthetic marker, avoiding an empty-editor equals
  empty-binding false positive.

### Builder validation (compiled, not executed)

The nine test definitions expand to 16 cases. The canonical Debug
build-for-testing completed with exit 0, `TEST BUILD SUCCEEDED`, zero errors,
and 514 warnings. None reference the changed test file. The xcresult execution
action is `notRequested`. **Executed tests in this repair lane: 0.**

```sh
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .dev/mn-0b49e9/DebugDerivedData \
  SYMROOT=/Users/erik/Custom-Coding/holy-ghostty/.dev/mn-0b49e9/test-build \
  -only-testing:GhosttyTests/HolyModeClipboardTests \
  -only-testing:GhosttyTests/HolyMannaBoardTests \
  -only-testing:GhosttyTests/HolyArchiveModeTests \
  -parallel-testing-enabled NO \
  -resultBundlePath .dev/mn-0b49e9/fixture-repair-build.xcresult \
  build-for-testing

swiftlint lint --strict --quiet --config macos/.swiftlint.yml \
  macos/Tests/HolyGhostty/HolyModeClipboardTests.swift
scripts/build-holy-ghostty-core.sh verify
git diff --check
```

Strict SwiftLint passes with zero violations; the core verifier passes for
ReleaseFast, Zig 0.15.2, input hash
`df28bebb6ebfe4a473978513324c78da1f5148e4952f7f59d53e3806f7781141`.
Whitespace validation passes. No app/test host launches, installs, screenshots,
or live sessions occurred in this lane. No push or pull request was made.

Receipts under `.dev/mn-0b49e9/`:
`fixture-repair-receipt.json`, `fixture-repair-build.log`,
`fixture-repair-build.xcresult`, `fixture-repair-build-summary.json`,
`fixture-repair-build-actions.json`, `fixture-repair-swiftlint.log`,
`fixture-repair-core-verify.log`, and `fixture-repair-learning-receipts.json`.
Read-only exports of the existing failures are retained in
`focused-failure-diagnostics/` and `serial-failure-diagnostics/`.

### Needed next: coordinator re-execution

Run the focused suites in an active GUI test host using the rebuilt test products:

```sh
xcodebuild \
  -xctestrun .dev/mn-0b49e9/test-build/Ghostty_Ghostty_macosx26.4-arm64.xctestrun \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:GhosttyTests/HolyModeClipboardTests \
  -only-testing:GhosttyTests/HolyMannaBoardTests \
  -only-testing:GhosttyTests/HolyArchiveModeTests \
  -parallel-testing-enabled NO \
  -resultBundlePath .dev/mn-0b49e9/fixture-repair-executed.xcresult \
  test-without-building
```

Verify all 16 clipboard cases, including teardown/reopen, finish without host
restarts. For each field compare the direct-control receipt with Command-V and
responder diagnostics. Preserve any host-precondition or behavior failure as
red; compilation does not establish that either the host deaths or the Board
paste failure is resolved. The coordinator's wider release gate and Erik's
live clipboard acceptance remain pending. Keep Manna `in_progress`.

Lessons logged: 3 (new: les-075da1, les-9b8315, les-e9491f) |
Decisions logged: 1 (new: dec-eecaa9).

## Native editing routing repair: 2026-09-23

### Live verdict and exact diagnosis

The coordinator's drop and `.dev/mn-0b49e9-receipt.md` report six Command-V
presses at 09:47 with `fr=SystemTextFieldFieldEditor` (runtime class
`_SystemTextFieldFieldEditor`) and `superHandled=false`. Erik saw highlighted
selection, no copy effect, and a beep on paste. The responder exclusion works;
the missing step is dispatch of the editing chord after the terminal relinquishes
the keyboard. The menu does not provide a usable Paste key equivalent.

Correction to the pass-two receipt's Bin B description: the actual raw logs
`.dev/mn-0b49e9-clip2.log` and `.dev/mn-0b49e9-serial2.log` each record successful
direct paste controls for Board, search, tag, note, and research. Their later
Command-V diagnostics report `directPasteSucceeded=true`, `active=true`,
`firstResponderIsEditor=true`, and `pasteTargetsEditor=true`. The empty editor
assertion is in the subsequent keyboard phase, not in the direct control.
`.dev/mn-0b49e9/editing-routing-diagnosis.json` preserves these synthetic-only
control lines without copying unrelated clipboard contents from failed logs.

The default shortcut is present in the core. Its absence from the menu follows
the checked-in source, not a missing fixture keybind:

1. `src/config/Config.zig` registers a physical Paste key, then Unicode Command-V
   with `performable = true` (and the corresponding Copy bindings).
2. `src/input/Binding.zig` intentionally excludes performable bindings from the
   action-to-trigger reverse map (`track_reverse = !flags.performable`). This
   preserves core control over conditional bindings.
3. `src/config/CApi.zig` implements `ghostty_config_trigger` via that reverse
   map. With the defaults, Paste resolves to the earlier physical Paste trigger,
   not the performable Command-V trigger.
4. `macos/Sources/Ghostty/Ghostty.Input.swift` converts physical keys only when
   present in `keyToEquivalent`; physical Paste/Copy are absent, so conversion
   returns nil.
5. `Ghostty.Config.keyboardShortcut(for:)` forwards that conversion, and
   `Ghostty.MenuShortcutManager.syncMenuShortcut` clears the menu equivalent and
   modifier mask on nil. Native modes therefore cannot depend on this menu path.

### Change

`HolyWorkspaceWindow.performKeyEquivalent` now tries native editing dispatch
while Board or Archive owns the keyboard in the key window. Command-V/C/X/A
send `paste:`, `copy:`, `cut:`, and `selectAll:` via
`NSApp.sendAction(..., to: nil, from: self)`. Command-Z and Shift-Command-Z use
the focused responder's undo manager only when it can undo or redo.

The branch handles only the standard modifier combinations, excludes attached
sheets and stale terminal responders, and returns true only when dispatch is
accepted or an available undo/redo is performed. Empty read-only selections still
reach Board's existing row-copy fallback; an unavailable row copy is not reported
as accepted. Normal terminal routing remains outside this mode branch.
HolyKeyDebug records `modeEditing` and the responder class for accepted chords.

The Bin A menu assertions are removed. Actual-field tests call the production
window's key-equivalent method and require both acceptance and insertion, so a
menu cannot mask missing window routing. Direct paste remains a separate control.
Added native NSTextView coverage checks Select All, Copy, Cut, Undo, Redo, and
Paste in both modes, plus unhandled-action fallthrough. Terminal restoration
asserts that the surface receives its own key equivalents again. Existing
SwiftUI selection-copy tests retain full `NSApp.sendEvent` dispatch.

Each fixture now seeds synthetic clipboard content after retaining the user's
original formats in memory, preventing a failed assertion from printing the
original clipboard. Teardown still restores all retained representations.

### Validation and remaining acceptance

The focused Debug build-for-testing passes with exit 0, zero errors, and 494
warnings, none in either changed file. Xcode records execution as `notRequested`.
The suite now has 11 test definitions and 19 cases. **Executed tests for this
editing-routing candidate: 0.** Strict SwiftLint passes for both changed Swift
files, and `git diff --check` passes.

ReleaseLocal passes with exit 0, zero errors, 55 warnings (none in an owned
file), and both x86_64 and arm64 slices. The resulting production app passes
`codesign --verify --deep --strict`. Core verification passes for ReleaseFast,
Zig 0.15.2, input hash
`df28bebb6ebfe4a473978513324c78da1f5148e4952f7f59d53e3806f7781141`.
No test/app launches, installs, screenshots, live sessions, pushes, or pull
requests occurred in this lane.

```sh
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .dev/mn-0b49e9/DebugDerivedData \
  SYMROOT=/Users/erik/Custom-Coding/holy-ghostty/.dev/mn-0b49e9/test-build \
  -only-testing:GhosttyTests/HolyModeClipboardTests \
  -only-testing:GhosttyTests/HolyMannaBoardTests \
  -only-testing:GhosttyTests/HolyArchiveModeTests \
  -parallel-testing-enabled NO \
  -resultBundlePath .dev/mn-0b49e9/editing-routing-build.xcresult \
  build-for-testing

xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -configuration ReleaseLocal \
  -derivedDataPath .dev/mn-0b49e9/ReleaseDerivedData \
  SYMROOT=/Users/erik/Custom-Coding/holy-ghostty/.dev/mn-0b49e9/production-build \
  -resultBundlePath .dev/mn-0b49e9/editing-routing-release.xcresult build

swiftlint lint --strict --quiet --config macos/.swiftlint.yml \
  macos/Sources/HolyGhostty/App/HolyWorkspaceWindowController.swift \
  macos/Tests/HolyGhostty/HolyModeClipboardTests.swift
scripts/build-holy-ghostty-core.sh verify
codesign --verify --deep --strict \
  '.dev/mn-0b49e9/production-build/ReleaseLocal/Holy Ghostty.app'
git diff --check
```

Receipts under `.dev/mn-0b49e9/`: `editing-routing-receipt.json`,
`editing-routing-diagnosis.json`, `editing-routing-build.log`,
`editing-routing-build.xcresult`, `editing-routing-build-summary.json`,
`editing-routing-build-actions.json`, `editing-routing-release.log`,
`editing-routing-release.xcresult`, `editing-routing-release-summary.json`,
`editing-routing-swiftlint.log`, `editing-routing-core-verify.log`,
`editing-routing-codesign.log`, and the editing-routing learning receipts.
The candidate receipt binds both changed Swift files by SHA-256.

The coordinator must re-execute the rebuilt clipboard, Board, and Archive suites,
then install through the supported path for Erik's re-check. Confirm native
editing in each field, selection-copy round trips, Board row fallback, and
normal terminal input after dismissal. Inspect `modeEditing=true` and the editor
responder in HolyKeyDebug. The prior serial run's later host exits in
`HolyRosterInstantKillTests` remain a separate unresolved release-gate observation;
this revision does not claim to repair that suite. Keep Manna `in_progress`.

Coordinator execution command, not run by this builder:

```sh
xcodebuild \
  -xctestrun .dev/mn-0b49e9/test-build/Ghostty_Ghostty_macosx26.4-arm64.xctestrun \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:GhosttyTests/HolyModeClipboardTests \
  -only-testing:GhosttyTests/HolyMannaBoardTests \
  -only-testing:GhosttyTests/HolyArchiveModeTests \
  -parallel-testing-enabled NO \
  -resultBundlePath .dev/mn-0b49e9/editing-routing-executed.xcresult \
  test-without-building
```

Lessons logged: 3 (new: les-9f5d47, les-54d793, les-926023) |
Decisions logged: 1 (new: dec-652295).
