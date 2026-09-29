---
workflow: 2
manna: mn-1b111a
track: mn-eb7a80
source: .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 8; 09-23 handoff §10 item 6
base_commit: 74e8e8b0daa88cf1681b19ce560068c684fac4a5
scope: '[P1][TESTS] HolyRosterInstantKillTests kills the test host: five relaunches per serial run'
inputs:
- .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 8; 09-23 handoff §10 item 6
binding: sha256:be8ad1db9eb6d1b78387dca6b1a31b679a836a4a72fa28c26ddf9848d1bcf9ae
---

# Handoff: [P1][TESTS] HolyRosterInstantKillTests kills the test host: five relaunches per serial run

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-1b111a
```

## Scope

[P1][TESTS] HolyRosterInstantKillTests kills the test host: five relaunches per serial run

## Inputs

- .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 8; 09-23 handoff §10 item 6

## Work order

09-24 serial run (.dev/serial-2026-09-24-main-3b83f7de1.log): the host restarted at staleXAfterCommandReleaseAndDisabledXNeverKill, commandDeleteChainsInDisplayedOrder(.classic), commandDeletePreservesTextEditingAndIgnoresKeyRepeat, remoteKillIdentityRetainsTransportAndExactTarget, and remoteRowWithoutTmuxIdentityFailsInlineWithoutDetaching; the xcresult records each as the test runner exited with code 1. Same five relaunches on 09-23 (.dev/mn-0b49e9-serial2.log, one name differs: windowResignAndModifierReleaseClearCommand), so it is the suite, not one test. Likely the mechanism in les-898c86 (a window close lets applicationShouldTerminateAfterLastWindowClosed quit the host); the clipboard fixture repair e57ec0afa shows the shape of the fix. Done when a serial run has zero Restarting after unexpected exit lines and each of the five reports pass or a real expectation failure.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-1b111a`.
4. Commit with `Manna: mn-1b111a` and run `agent-do manna done mn-1b111a` only after the work is verified.

## Report: 2026-09-29 build lane

Implementation commit: `befeeb421` (`Manna: mn-1b111a`). Status: compiled candidate, executed acceptance pending. The original sealed work order was read and its canonical claim succeeded with binding `sha256:d6541994c90b891816977850dd4ab47456919ad0621e97e175997ceccedd27f0`. Source and build work used `/Users/erik/Custom-Coding/holy-ghostty-mn-5fff6f`; canonical Manna and path claims stayed in the primary checkout.

### Finding and change

- The September 24 serial log records `commandClickKillsWithoutSelectingVictimOrPresentingSheet` closing its workspace, then `staleXAfterCommandReleaseAndDisabledXNeverKill` starting, a deferred surface close, and a test-host restart. `Ghostty.Surface.deinit` queues `ghostty_surface_free` on the main actor, while `Ghostty.App.deinit` immediately frees the owner. The old per-fixture core lifetime did not cover that queued destruction.
- `RosterTestHost` now keeps the core and config alive across this serialized suite. Fixtures still have separate stores/controllers and now use distinct archive database paths. The existing supported `window-vsync = false` setting removes a display-link prerequisite from these input/lifecycle fixtures.
- The stale/disabled button test supplies windowless mouse events to the unchanged production handler, which reads only event type, modifiers, and enabled state. It no longer creates/closes an unrelated window. An enabled Command-click is the positive control.
- A new lifecycle regression waits for retired surface userdata to disappear and then creates another fixture using the same core. No production kill or window behavior changed.

### Verification receipts

Artifacts: `/Users/erik/Custom-Coding/holy-ghostty-mn-5fff6f/.dev/mn-5fff6f/`.

- Focused strict SwiftLint and `git diff --check`: passed (`mn-1b111a-lint.log`).
- `mn-1b111a-build-1.xcresult`: intermediate button-only test build passed.
- `mn-1b111a-build-2.xcresult`: final candidate test build passed, exit 0; `xcresulttool get build-results` reports 0 errors and 497 warnings. Log and summary JSON retained beside the bundle.
- GhosttyTests compiled with `HolyRosterInstantKillTests` selected. Executed tests: 0. No evidence of zero runner restarts is claimed from a compile-only build.

Command, from the isolated worktree's `macos/` directory:

```bash
only_testing=(-only-testing:GhosttyTests/HolyRosterInstantKillTests)
xcodebuild build-for-testing -scheme Ghostty -destination 'platform=macOS' \
  -parallel-testing-enabled NO -skip-testing:GhosttyUITests "${only_testing[@]}" \
  -derivedDataPath ../.dev/DerivedData-mn-5fff6f \
  SYMROOT=/Users/erik/Custom-Coding/holy-ghostty-mn-5fff6f/.dev/mn-5fff6f/test-build \
  -resultBundlePath ../.dev/mn-5fff6f/mn-1b111a-build-2.xcresult
```

Needed acceptance: coordinator executes this suite serially and verifies zero runner restarts, nonzero executed counts, and actual outcomes for all five cases named in the work order plus the new lifecycle regression. Read counts from `xcrun xcresulttool get test-results summary`; use the log only to inspect restart diagnostics. This item remains in progress. No app launch, installation, screenshot, live session, push, or PR occurred.

Lessons logged: 1 new (`les-8ef18f`). Decisions logged: 0 new.
