---
workflow: 2
manna: mn-7c56c0
track: mn-9a97cc
source: null
base_commit: 8386b2dbd864b8cf23413b4cedd2b7e15bea9508
scope: '[P1][ROSTER] Hold cmd: every session indicator becomes an instant-kill X — no confirmation, plus cmd-delete on the selected row'
inputs: []
binding: sha256:3b5f4ed7d9da6fa03c5a012287e7ef55f7c6223466ee6bab70e9e7e8742f118d
---

# Handoff: [P1][ROSTER] Hold cmd: every session indicator becomes an instant-kill X — no confirmation, plus cmd-delete on the selected row

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-7c56c0
```

## Scope

[P1][ROSTER] Hold cmd: every session indicator becomes an instant-kill X — no confirmation, plus cmd-delete on the selected row

## Inputs

- None declared.

## Work order

Erik 2026-09-11: dispatch is now so fast that culling needs to match — 'click click click through a bunch.' Design (ratified in discussion): (1) While cmd is held and the pointer is over the roster, each session row's status indicator swaps in place to a red X; clicking it kills that session IMMEDIATELY — no confirmation, no dialog — the row leaves the roster and the next X is under the cursor. Releasing cmd restores normal indicators instantly. The cmd hold is the intent gate; kills are recoverable context-wise because transcripts persist in Archive. (2) Keyboard twin: cmd-delete kills the currently selected session with the same no-confirm semantics. Implementation: roster rows render in HolySessionRosterView (indicator/orb area — reuse its hover plumbing); cmd state is already tracked by the workspace modifier machinery (flagsChanged forwarding, HolyWorkspaceWindowController) — do not add a second event tap; kill goes through the EXISTING session-kill path so local tmux, adopted, and SSH-remote sessions all route correctly (post-exec-fix the pane leader is the agent, so kill targeting is truthful) and dead rows reconcile with discovery. Edge rules: an X click must never focus/switch to the session first; killing the selected session moves selection to the next row so cmd-delete chains; a kill that fails (transport down) surfaces inline on the row, not as a dialog. Tests: indicator swaps only while cmd held; click kills without confirmation prompt (assert no sheet); selection advance on cmd-delete chain; remote rows use the transport kill path; release of cmd mid-hover restores indicators. Acceptance: Erik holds cmd and culls a batch of workers X-X-X in a few seconds, then cmd-delete chains through a few more.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-7c56c0`.
4. Commit with `Manna: mn-7c56c0` and run `agent-do manna done mn-7c56c0` only after the work is verified.

## Implementation and verification receipt (2026-09-11)

Implementation and build verification are committed. Erik confirmed acceptance on 2026-09-11 with the exact instruction: "works, close". That acceptance and explicit closure instruction resolve the prior closing hold. App-hosted tests remain compiled only; no executed-test results are claimed.

- Owner: `codex-01a090bf786d7de2`. The first command was `agent-do manna claim mn-7c56c0`, which succeeded without takeover.
- Initial canonical row, handoff frontmatter, and recomputed binding all matched `sha256:4e89d42e2c8c8daa251c8238b220e46852a859cb11b5cf866bd9891c17a88675` before implementation.
- Implementation commit: `c4d8d982cfc23187df1d641c78662d841b9486d1`, `feat(roster): add Command-gated instant session kills`, with the exact trailer `Manna: mn-7c56c0`.
- Exact source, test, handoff, and build-output paths were claimed through Coord before edits. Build artifacts use this lane's `.dev/mn-7c56c0/` output roots. Foreign changes in `CHANGELOG.md`, `README.md`, and the three `docs/holy-ghostty/` documents were preserved and excluded from the commit.

### Changes

1. `macos/Sources/HolyGhostty/Workspace/HolySessionRosterView.swift`: all row indicators become red X buttons in their existing 18-by-18 point slots while Command is held over the roster. Releasing Command or leaving the roster restores the normal glyph. The AppKit button consumes mouse-down without selecting the row, rechecks the click's Command modifier, and disables duplicate pending clicks. Kill errors render on the affected row. Displayed sections are shared with successor selection across Classic, Triage, and Focus layouts.
2. `macos/Sources/HolyGhostty/App/HolyWorkspaceWindowController.swift`: the existing modifier monitor updates roster state, including while Board or Archive is presented. Window resignation clears it. Command-Delete calls the same roster action for the selected session; editing fields, sheets, and palette input retain their own keys. Auto-repeat does not consume additional rows.
3. `macos/Sources/HolyGhostty/Workspace/HolyWorkspaceStore.swift`: tmux kills retain the existing exact identity resolution, adopted-session fallback, managed SSH transport, and `HolyTmuxLifecycleService.killVerified` path. Rows leave only after verified absence. Pending requests are deduplicated; failures remain inline. Killing the selected row selects its displayed successor, or the preceding row at the end. Plain local terminals use the existing close/archive lifetime path. A remote row with missing tmux identity fails inline and remains attached.
4. `macos/Tests/HolyGhostty/HolyRosterInstantKillTests.swift`: nine new test functions, with the selection-chain function parameterized over three layouts. Covers indicator gating and release, direct kill without victim selection or a sheet, stale/disabled X clicks, selection chains, editing/repeat guards, pending/adopted failure and retry, remote command construction, missing remote identity, and modifier clearing. These tests are compiled, not executed.

### Executed build and static checks

All commands were run from `/Users/erik/Custom-Coding/holy-ghostty`.

```bash
scripts/build-holy-ghostty-core.sh verify

xcodebuild -quiet -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -configuration ReleaseLocal -destination 'platform=macOS' \
  -derivedDataPath .dev/mn-7c56c0/ReleaseDerivedData \
  SYMROOT=/Users/erik/Custom-Coding/holy-ghostty/.dev/mn-7c56c0/release-products \
  -resultBundlePath .dev/mn-7c56c0/validation/release-build.xcresult \
  -jobs 4 build

codesign --verify --deep --strict --verbose=2 \
  '.dev/mn-7c56c0/release-products/ReleaseLocal/Holy Ghostty.app'

xcodebuild -quiet -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .dev/mn-7c56c0/TestDerivedData \
  SYMROOT=/Users/erik/Custom-Coding/holy-ghostty/.dev/mn-7c56c0/test-products \
  -resultBundlePath .dev/mn-7c56c0/validation/build-for-testing-final.xcresult \
  -only-testing:GhosttyTests/HolyRosterInstantKillTests \
  -only-testing:GhosttyTests/HolyWorkspaceTerminalMouseTests \
  -only-testing:GhosttyTests/HolyTmuxLifecycleIdentityTests \
  -only-testing:GhosttyTests/HolyTmuxLifecycleServiceTests \
  -jobs 4 build-for-testing CODE_SIGNING_ALLOWED=NO

swiftlint lint --strict --config macos/.swiftlint.yml \
  macos/Sources/HolyGhostty/Workspace/HolySessionRosterView.swift \
  macos/Sources/HolyGhostty/Workspace/HolyWorkspaceStore.swift \
  macos/Sources/HolyGhostty/App/HolyWorkspaceWindowController.swift \
  macos/Tests/HolyGhostty/HolyRosterInstantKillTests.swift

git diff --check
```

| Check | Actual result |
| --- | --- |
| Existing core verification | Exit 0. ReleaseFast, Zig 0.15.2, input fingerprint `9d9f76225c12968b5518f7477263b66f6635faff03ff9b9840852de3a38a02be`. |
| ReleaseLocal app build | Exit 0. Xcode result: succeeded, 0 errors, 55 warnings, 0 analyzer warnings. |
| Signature verification | Exit 0. Bundle valid on disk and satisfies its Designated Requirement. |
| Final focused build-for-testing | Exit 0. Xcode result: succeeded, 0 errors, 497 warnings, 0 analyzer warnings. |
| Focused strict SwiftLint | Exit 0. Zero violations across all four changed Swift files. |
| Diff whitespace validation | Exit 0. |
| App-hosted test execution | NOT RUN: zero tests executed under the no-launch boundary. |
| Erik acceptance | CONFIRMED on 2026-09-11: "works, close". Individual scenario results and the installed commit were not supplied. |

Xcode still emits warnings in the existing shared target. A successful build is not a warning-free build or a passing test run. The first intermediate test build also succeeded; the final receipt above includes the additional missing-identity and text-field guards.

Detailed logs, Xcode result bundles, extracted build summaries, signature output, strict-lint output, and compiled source hashes are under `.dev/mn-7c56c0/validation/`. `source-sha256.json` binds all four source/test files to the reviewed commit. No app launch, installation, screenshot, live session creation, test execution, push, or pull request occurred in this lane.

### Acceptance plan recorded before Erik's confirmation

This command was prepared for the coordinated app-hosted pass and has NOT been run by this lane. It is retained as a reproducible validation command; Erik subsequently accepted the feature and explicitly instructed closure.

```bash
xcodebuild -quiet -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .dev/mn-7c56c0/TestDerivedData \
  SYMROOT=/Users/erik/Custom-Coding/holy-ghostty/.dev/mn-7c56c0/test-products \
  -resultBundlePath .dev/mn-7c56c0/validation/executed-acceptance.xcresult \
  -only-testing:GhosttyTests/HolyRosterInstantKillTests \
  -only-testing:GhosttyTests/HolyWorkspaceTerminalMouseTests \
  -only-testing:GhosttyTests/HolyTmuxLifecycleIdentityTests \
  -only-testing:GhosttyTests/HolyTmuxLifecycleServiceTests \
  -jobs 4 test-without-building CODE_SIGNING_ALLOWED=NO
```

The lifecycle suite uses isolated disposable tmux namespaces. The new store tests use synthetic terminal processes and absent unique tmux sockets. Executing these suites launches the test app, so it belongs in the coordinated pass.

The original field checklist is retained below for context. It does not assert that Erik supplied a separate result for every scenario:

1. Hold Command over the roster and click X-X-X through disposable workers in a few seconds. Check that each X stays in the indicator slot and no victim is focused before its kill.
2. Release Command while stationary over a row; its real indicator must return immediately. Leave/re-enter the roster and change windows to check modifier clearing.
3. Select a middle row and press Command-Delete repeatedly. Check successor selection and chaining in the displayed order, including the final row and a populated split layout.
4. Verify local managed, adopted, and SSH-remote sessions use the existing kill path and remain absent after discovery reconciles.
5. With a controlled unavailable transport, attempt a remote kill. The row must remain with an inline failure, with no dialog; retry after recovery must work.
6. Confirm retained transcripts in Archive and record available acceptance evidence in this canonical handoff.

### Closure authorization (2026-09-11)

Erik's "works, close" is the user acceptance receipt and authorization to close `mn-7c56c0`. `agent-do manna done mn-7c56c0` succeeded on 2026-09-11 at 14:31:31 UTC, and canonical Manna state reports `done`. The Coord acceptance hold is cleared. The implementation commit and all existing build receipts remain unchanged. No additional app launches, installations, screenshots, sessions, or test executions were performed for closure.

Lessons logged: 3 (new) | Decisions logged: 1 (new).
Lesson IDs: `les-729d6d`, `les-33de6f`, `les-e5d072`. Decision ID: `dec-540356`.

**TL;DR (12th grade):** Erik confirmed that the fast kill controls work, and the item is now closed in Manna. Existing build and lint checks passed; app-hosted tests were compiled but not run by this lane.
