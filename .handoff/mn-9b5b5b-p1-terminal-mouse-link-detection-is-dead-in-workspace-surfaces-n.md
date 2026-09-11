---
workflow: 2
manna: mn-9b5b5b
track: mn-eb7a80
source: Erik live test 2026-09-10 10:12 (both halves fail); config + surface receipts this session
base_commit: a10c7772c0da73425a533f877b3d973923691f1a
scope: '[P1][TERMINAL][MOUSE] Link detection is dead in workspace surfaces: no cmd-hover underline, no cmd-click open'
inputs:
- Erik live test 2026-09-10 10:12 (both halves fail); config + surface receipts this session
binding: sha256:97baf2b715a4f38970069af85d656a819ae082e6630e552de3d5de510a1f154a
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

## Continuation receipt: 2026-09-10

Status: **complete on the committed implementation and successful build checks**.
Erik explicitly directed closure after this receipt: "close it, we do not human verify things, we close when the work is done and open a new ticket if needed". This supersedes the previous human/live acceptance gate. Any subsequently observed defect belongs in a new ticket; do not create a speculative follow-up just to retain the removed gate.

- The initial claim succeeded for `codex-01a08d0c22b977c0`. Canonical Manna state, frontmatter, and the recomputed complete-document binding all matched the requested original `sha256:48be672ebd64d9f7fae03dd8f50283e3fda501e76ffd88def51aef50e8322038` before edits.
- No project-local AGENTS.md exists. The parent workspace guide and the user's supplied instructions were followed. Coord focus and exact source/test/handoff claims were established before edits.
- Source/build worktree: `/Users/erik/Custom-Coding/holy-ghostty-codex-mn-9b5b5b`, branch `codex/mn-9b5b5b`, base `f1931e5ba`. All Manna commands ran in the primary checkout. Foreign documentation, Board, and workspace-view changes were preserved.
- Implementation commit in the primary checkout: `4b8b079e085bd5482f02863db397878d32f2967b` (`fix(terminal): preserve workspace mouse event delivery`, trailer `Manna: mn-9b5b5b`). Original isolated commit: `5a2010222b4f8a40190ac5023d5aa2ef9a54a3e6`.

### Changes and limits of the evidence

1. `macos/Sources/HolyGhostty/DesignSystem/HolyGhosttyDesignSystem.swift`: the terminal frame's decorative stroke now ignores hit testing so it cannot intercept terminal mouse input.
2. `macos/Sources/HolyGhostty/App/HolyWorkspaceWindowController.swift`: a lifecycle-owned modifier monitor supplies the responsibility that stock `BaseTerminalController` already provides. Visible mounted unfocused panes receive modifier press/release events; the actual first responder retains normal AppKit delivery without duplication. Hidden, clipped, detached, and foreign-window views are excluded. Board and Archive presentation suppress forwarding.
3. `macos/Tests/HolyGhostty/HolyWorkspaceTerminalMouseTests.swift`: four test functions (five expanded cases) cover halo/non-halo hit-test pass-through, ordinary and Command clicks reaching the embedded view, unfocused modifier delivery, text-field focus, and modifier release from another window with hidden/detached exclusions. These use responder probes and create no terminal or tmux sessions.

These are source-observed hosting differences, not a reproduced diagnosis of Erik's live failure. The requested QuickTerminal/bare-workspace comparison was deferred because the current lane explicitly forbids app launches. The tests have only compiled. Actual underline rendering, pointer cursor, URL opening, selection behavior, and any mouse-reporting interaction remain unverified. No tmux configuration or terminal-core behavior was changed.

### Verification receipts

Commands ran in the isolated worktree unless specified otherwise:

```bash
scripts/build-holy-ghostty-core.sh verify
swiftlint lint --strict --config macos/.swiftlint.yml \
  macos/Sources/HolyGhostty/App/HolyWorkspaceWindowController.swift \
  macos/Sources/HolyGhostty/DesignSystem/HolyGhosttyDesignSystem.swift \
  macos/Tests/HolyGhostty/HolyWorkspaceTerminalMouseTests.swift
git diff --check
/usr/bin/xcodebuild -quiet -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .dev/DerivedData-mn-9b5b5b \
  -resultBundlePath .dev/mn-9b5b5b/build-for-testing.xcresult \
  -only-testing:GhosttyTests/HolyWorkspaceTerminalMouseTests \
  -only-testing:GhosttyTests/HolyPaneLayoutTests \
  build-for-testing CODE_SIGNING_ALLOWED=NO
```

- Core verification: exit 0, ReleaseFast / Zig 0.15.2, source inputs `9d9f76225c12968b5518f7477263b66f6635faff03ff9b9840852de3a38a02be`. Verified first in the primary checkout, then cloned the ignored framework/resources into the isolated worktree and verified again.
- Strict SwiftLint: exit 0, three changed Swift files, zero violations.
- `git diff --check`: exit 0.
- Xcode `build-for-testing`: exit 0. XCResult reports `succeeded`, zero errors, 526 warnings across the build and zero warnings attributed to the three changed files. The Xcode build compiles the shared test target; the two named suites are the focused execution selection.
- **Executed tests: 0.** No `test` or `test-without-building` command ran. No app launches, installs, screenshots, or live session spawning occurred. No push or PR occurred.
- Receipts: `.dev/mn-9b5b5b/{core-verify.log,swiftlint.log,build-for-testing.log,build-for-testing.xcresult,build-summary.json}`. The JSON records hashes of the three compiled source files for comparison with the primary checkout.

### User-directed closeout

The former Coord need `mn-9b5b5b-live-acceptance` is withdrawn. Human verification is not required for closure. The evidence remains unchanged: focused tests compiled, zero tests executed, and the live comparison was not performed. Closing this item does not relabel those checks as executed.

The scoped implementation is complete in `4b8b079e0`; the successful checks and source hashes above are the completion evidence. No new code or app operations are needed for this closeout. Use canonical `agent-do manna done mn-9b5b5b` to close and let Manna recompute dependents, including `mn-5a26f9`.

Lessons logged: 3 (new) | Decisions logged: 1 (new, user-directed completion rule).
