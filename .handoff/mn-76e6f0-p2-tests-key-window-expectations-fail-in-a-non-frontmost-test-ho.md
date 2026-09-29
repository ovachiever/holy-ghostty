---
workflow: 2
manna: mn-76e6f0
track: mn-eb7a80
source: .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 8; 09-23 handoff §10 item 7
base_commit: 74e8e8b0daa88cf1681b19ce560068c684fac4a5
scope: '[P2][TESTS] Key-window expectations fail in a non-frontmost test host (Clear lifecycle, clipboard)'
inputs:
- .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 8; 09-23 handoff §10 item 7
binding: sha256:7494bd308e84945a56c8b6fb60b5cfe9d556e13de81b32ca9e743680b19b1a1d
---

# Handoff: [P2][TESTS] Key-window expectations fail in a non-frontmost test host (Clear lifecycle, clipboard)

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-76e6f0
```

## Scope

[P2][TESTS] Key-window expectations fail in a non-frontmost test host (Clear lifecycle, clipboard)

## Inputs

- .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 8; 09-23 handoff §10 item 7

## Work order

clearPopulatedStorePreservesKeyWorkspaceAndEmptyPane(quitAfterLastWindow:) fails both cases at HolyWorkspaceClearLifecycleTests.swift:99 and :109 (isKeyWindow is false); unhandledBoardCopyUsesSelectedIDAndTitleOnlyInBoard fails at HolyModeClipboardTests.swift:285 (general pasteboard nil) for the same reason. Red on 09-23 (.dev/rr-clear-alone.log, .dev/mn-0b49e9-serial2.log) and 09-24 (.dev/serial-2026-09-24-main-3b83f7de1.log). Test hygiene: assert on the responder chain or activate the host explicitly, not on isKeyWindow of a background process. Done when all three cases pass in an unattended serial run.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-76e6f0`.
4. Commit with `Manna: mn-76e6f0` and run `agent-do manna done mn-76e6f0` only after the work is verified.

## Report: 2026-09-29 build lane

Implementation commit: `2a925b3a5` (`Manna: mn-76e6f0`). Status: compiled candidate, executed acceptance pending. The original work order was read and its canonical claim succeeded with binding `sha256:73d0a04df8d6d2311c19d2b3242fdd1bb1b500edf2f19746cff0cac6492fd3df`.

### Changes and boundary

- Both `clearPopulatedStorePreservesKeyWorkspaceAndEmptyPane` cases now assert the surviving window, exact content-controller identity, and the window's ability to accept its empty first responder before/after reuse. They retain visibility, registry membership, empty roster/pane, persistence, archive membership, and auto-quit-policy assertions. They no longer demand foreground key-window ownership. Surface fixtures use the supported `window-vsync = false` setting, consistent with the existing clipboard host.
- `unhandledBoardCopyUsesSelectedIDAndTitleOnlyInBoard` creates its fixture without requesting activation. It invokes the actual window responder chain for unhandled Copy, the production window's key-equivalent fallback for unselected read-only text, and the native text responder for editable empty-selection Copy. The pasteboard value assertions and Archive refusal checks remain.
- Existing tests of Command-V, native editing chords, terminal restoration, and real application event dispatch remain intact. Those separate integration tests still require an active GUI host. This change does not claim that the entire clipboard suite is now runnable with the console locked; it removes the unnecessary foreground prerequisite from the three cases named in this child. No test was skipped or replaced with a passing stub.

### Verification receipts

Worktree: `/Users/erik/Custom-Coding/holy-ghostty-mn-5fff6f`. Artifacts: `.dev/mn-5fff6f/` inside that worktree.

- Focused strict SwiftLint: passed, exit 0 (`mn-76e6f0-lint.log`). `git diff --check`: passed.
- `mn-76e6f0-build-1.xcresult`: passed, exit 0, `TEST BUILD SUCCEEDED`. `xcresulttool get build-results` reports 0 errors and 497 warnings. Log and summary JSON retained beside the bundle.
- Both requested suites compiled in GhosttyTests. Executed tests: 0. The no-launch instruction prohibited an app-hosted run in this lane.

Command from the worktree's `macos/` directory:

```bash
only_testing=(-only-testing:GhosttyTests/HolyWorkspaceClearLifecycleTests
              -only-testing:GhosttyTests/HolyModeClipboardTests)
xcodebuild build-for-testing -scheme Ghostty -destination 'platform=macOS' \
  -parallel-testing-enabled NO -skip-testing:GhosttyUITests "${only_testing[@]}" \
  -derivedDataPath ../.dev/DerivedData-mn-5fff6f \
  SYMROOT=/Users/erik/Custom-Coding/holy-ghostty-mn-5fff6f/.dev/mn-5fff6f/test-build \
  -resultBundlePath ../.dev/mn-5fff6f/mn-76e6f0-build-1.xcresult
```

Needed acceptance: coordinator runs these suites serially and checks actual outcomes for both Clear cases and the Board fallback case, with the failure counts read from `xcrun xcresulttool get test-results summary`. The separate keyboard-integration coverage requires an unlocked, active console. A locked-console pass of all clipboard integration tests remains outside what this test-only change proves. This child remains in progress.

Lessons logged: 1 new (`les-b97426`). Decisions logged: 0 new. No app launch, installation, screenshot, live session, push, or PR occurred.
