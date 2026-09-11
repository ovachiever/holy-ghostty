---
workflow: 2
manna: mn-c2b133
track: mn-eb7a80
source: Executed-test run 2026-09-10 21:23 (FAILED 3/PASSED 111 batch; isolated repro confirmed); cites mn-9b5b5b
base_commit: abe1f1e556d28622655191d9a12fc43a383dedd9
scope: '[P1][MOUSE] releaseFromAnotherWindowClearsHoverButSkipsUnmountedPanes fails consistently — mn-9b5b5b closed on compiled-only verification'
inputs:
- Executed-test run 2026-09-10 21:23 (FAILED 3/PASSED 111 batch; isolated repro confirmed); cites mn-9b5b5b
binding: sha256:935432302f7987c373fe9f89c2bffcf9af49145f5b96318d040fbe2d1f42e73a
---

# Handoff: [P1][MOUSE] releaseFromAnotherWindowClearsHoverButSkipsUnmountedPanes fails consistently — mn-9b5b5b closed on compiled-only verification

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-c2b133
```

## Scope

[P1][MOUSE] releaseFromAnotherWindowClearsHoverButSkipsUnmountedPanes fails consistently — mn-9b5b5b closed on compiled-only verification

## Inputs

- Executed-test run 2026-09-10 21:23 (FAILED 3/PASSED 111 batch; isolated repro confirmed); cites mn-9b5b5b

## Work order

The mn-9b5b5b terminal-mouse patch (4b8b079e0) was closed (abe1f1e55) while its own report said 'zero tests executed; remains in_progress' — first executed run (this session, twice, both parallel hosts, 0.02s) fails its new regression releaseFromAnotherWindowClearsHoverButSkipsUnmountedPanes. Claim, run the suite FOR REAL, fix code or test to match true behavior, and only then re-close. The install of the link-detection patch is HELD until this is green — Erik's cmd-click acceptance (and the blocked mn-5a26f9 clickable-ids feature) queue behind it. Assertion detail did not surface via xcodebuild console; run in Xcode or capture the result bundle.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-c2b133`.
4. Commit with `Manna: mn-c2b133` and run `agent-do manna done mn-c2b133` only after the work is verified.

## Continuation receipt: 2026-09-10

Status: implementation committed and build-verified; **in_progress, executed acceptance pending**.
The current lane explicitly prohibits launching the app, including its test host.
No `test`, `test-without-building`, install, screenshot, or live-session command ran.

### Ownership and provenance

- Initial claim succeeded for `codex-01a08e4e7fc37c33`; no competing claim was displaced.
- Before edits, canonical `agent-do manna state --json`, the frontmatter binding,
  and a recomputation using Manna's complete-document normalization all matched
  `sha256:77afa3915eff3c344392907eecda2247fbbd2646aa67007a1040ab2bcb27481e`.
- The supplied instructions, parent workspace guide, and `.handoff/README.md`
  were read. No project-local `AGENTS.md` was present. Coord focus and exact
  source, test, handoff, and receipt-directory claims preceded edits.
- Source/build worktree: `/Users/erik/Custom-Coding/holy-ghostty-codex-mn-c2b133`,
  branch `codex/mn-c2b133`, base `1030066b27a1fba3db5724e8c27b8d4b6990c059`.
  All Manna mutations ran in the primary checkout.
- Primary implementation commit: `973fc535561d2693927847c335fd47b120e49c03`
  (`fix(terminal): exclude off-window panes from modifier releases`, exact
  trailer `Manna: mn-c2b133`). Isolated commit:
  `4fdf4442a41279200a550a3649425f0e53bd3989`.
- Foreign documentation, Board test changes, and the peer's Manna claim were
  preserved. Only this item's ledger row belongs in this handoff commit.

### Diagnosis and repair

The existing executed result bundle at
`/Users/erik/Library/Developer/Xcode/DerivedData/Ghostty-evzhqzgwedstedhkeiqpqvomarls/Logs/Test/Test-Ghostty-2026.09.10_21-23-50--0500.xcresult`
contains one failed test, zero passed, zero skipped. Its exact failure is
`HolyWorkspaceTerminalMouseTests.swift:102`: `clipped.modifiers.isEmpty` was
false because the off-window probe received the release. The recorded test
duration is 0.019290924 seconds. These are prior-run results, not tests executed
by this lane.

The installed SDK's `NSView.h` documents that `visibleRect` represents ancestor
clipping and that ordinary views default to `clipsToBounds = false` on macOS 14
and later. A nonempty `visibleRect` therefore did not prove window visibility.

1. `macos/Sources/HolyGhostty/App/HolyWorkspaceWindowController.swift` now
   converts each pane's visible rectangle into content-view coordinates and
   requires a nonempty intersection with the window's content bounds.
   Same-window first-responder delivery and existing hidden/detached/foreign
   exclusions remain in the same forwarding path.
2. `macos/Tests/HolyGhostty/HolyWorkspaceTerminalMouseTests.swift` makes the
   non-clipping fixture explicit and retains the original failing assertion.
   A new regression uses an offset nested container with a nonzero bounds
   origin: the partly visible pane receives the release, while a pane touching
   only the window edge receives none. Fixtures create no terminal/tmux sessions.

### Focused validation

Run from the isolated worktree:

```bash
scripts/build-holy-ghostty-core.sh verify
swiftlint lint --strict --config macos/.swiftlint.yml \
  macos/Sources/HolyGhostty/App/HolyWorkspaceWindowController.swift \
  macos/Tests/HolyGhostty/HolyWorkspaceTerminalMouseTests.swift
git diff --check
/usr/bin/xcodebuild -quiet -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .dev/DerivedData-mn-c2b133 \
  -resultBundlePath .dev/mn-c2b133/build-for-testing-final.xcresult \
  -only-testing:GhosttyTests/HolyWorkspaceTerminalMouseTests \
  -only-testing:GhosttyTests/HolyPaneLayoutTests \
  build-for-testing CODE_SIGNING_ALLOWED=NO
```

- Core verify: exit 0 in primary and isolated checkouts, ReleaseFast / Zig
  0.15.2, inputs `9d9f76225c12968b5518f7477263b66f6635faff03ff9b9840852de3a38a02be`.
- Final strict SwiftLint: exit 0, two changed files, zero violations.
  Initial geometry-expression lint failures were corrected without suppressions.
- `git diff --check` and staged diff checks: exit 0.
- Final Xcode build-for-testing: exit 0, `succeeded`, zero errors, 504 warnings
  across the shared build and zero warnings attributed to either changed file.
  The shared test target compiled; the named suites are the focused execution
  selection. The generated xctestrun does not retain OnlyTestIdentifiers, so
  repeat both filters when executing.
- **Tests executed by this lane: 0.** No executed-green result is claimed.
- Committed primary source hashes exactly match the compiled files:
  controller `854b022b55e7bf63c9c29fcd32bb0496c8e1bfb2cd770758c14c981bf063b025`;
  tests `e583d0eda82d874c012820406d2f7e340b8cf2fc1e02eaf6ca06afb56848581b`.
- Receipts in primary `.dev/mn-c2b133/`: `verification.json`,
  `prior-failure-tests.json`, `prior-failure-summary.json`, `core-verify.log`,
  `swiftlint.log`, `build-for-testing-final.log`,
  `build-for-testing-final.xcresult`, and `build-results.json`.
- Canonical Manna lint reports filename/index drift already present on the
  board. For this item the only finding is a numbered filename rename held by
  its live claim; no handoff-content or binding error was reported. Broad board
  synchronization is outside this lane.

### Required acceptance and closeout

Coord need: `mn-c2b133-executed-acceptance`. Coordinate one acceptance window
before launching the app-hosted tests. Run from the preserved isolated worktree
after checking the recorded source hashes:

```bash
/usr/bin/xcodebuild -quiet -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .dev/DerivedData-mn-c2b133 \
  -resultBundlePath .dev/mn-c2b133/executed-acceptance.xcresult \
  -only-testing:GhosttyTests/HolyWorkspaceTerminalMouseTests \
  -only-testing:GhosttyTests/HolyPaneLayoutTests \
  test-without-building CODE_SIGNING_ALLOWED=NO
```

This command has **not** run. Capture actual passed/failed/skipped counts and
inspect any failure through xcresulttool, querying one bundle sequentially.
Keep the link-detection installation hold until the focused suites execute
green. Coordinate the existing URL Command-hover underline/pointer,
Command-click open, and plain-click selection pass at wave close.
Append the acceptance receipts, reseal this handoff, and mark done only after
the required acceptance is verified. No push or pull request is authorized.

Lessons logged: 6 (new) | Decisions logged: 0 (new).
