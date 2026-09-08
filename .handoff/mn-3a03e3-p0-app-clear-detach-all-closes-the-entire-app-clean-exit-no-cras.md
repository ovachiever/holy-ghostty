---
workflow: 2
manna: mn-3a03e3
track: mn-eb7a80
source: Erik live report 2026-09-08 11:05; forensics this session (no crash logs both machines; retention verified intact)
base_commit: 5c8c9ddaea6a319e6bbca29785519d3e877dc26d
scope: '[P0][APP] Clear crashes on a late callback to a released surface view'
inputs:
- Erik live report 2026-09-08 11:05; forensics this session (no crash logs both machines; retention verified intact)
binding: sha256:fe5c5437e68d5f3dbf47a394310ae79d7950b8381ac830e09250383ea179b981
---


# Handoff: mn-3a03e3 Clear surface callback lifetime fix

Board state is canonical in `.manna/`. Keep this item **in_progress** until the coordinated synthetic runtime acceptance passes. This lane permits builds only: no install, app launch, test-host launch, or Clear on a live roster.

## Claim

```bash
agent-do manna claim mn-3a03e3
```

## Scope

Fix Clear's surface callback use-after-free; preserve the workspace window and empty state independently of quit config; prepare regression coverage. No push.

## Inputs

Original user report and handoff, current source, unified logs, and the two existing native minidumps identified below. The original clean-exit premise is superseded by these receipts.

## Work order

The implementation and evidence follow. Runtime acceptance remains assigned to the coordinated install lane.

## Corrected forensics

The earlier clean-exit conclusion was incorrect. Empty macOS DiagnosticReports did not account for Ghostty's own Sentry/Breakpad crash handler. Two existing native crash reports prove EXC_BAD_ACCESS, without another reproduction:

| Clear log (CDT, 2026-09-08) | Native crash timestamp (UTC) | Crash envelope |
| --- | --- | --- |
| 11:04:48.728, PID 72115, 29 sessions | 16:04:49.019020Z | `39a7ec49-0070-4288-4208-93d7c5d490a6.ghosttycrash` |
| 11:04:56.631, PID 54608, 29 sessions | 16:04:56.818900Z | `efc63966-8ce8-4e3b-0b2f-f0db77899b13.ghosttycrash` |

Both envelopes are in `/Users/erik/.local/state/ghostty/crash/`. Their embedded minidumps, inspected offline with LLDB, have the same crashing stack:

```text
objc_retain
Ghostty.App.surfaceView (Ghostty.App.swift:472 in the installed binary)
Ghostty.App.setMouseShape
Ghostty.App.action
Surface.handleMessage
ghostty_app_tick
Ghostty.App.appTick / wakeup
```

The installed arm64 Mach-O UUID is `00953A42-4CC2-3AFC-A226-674135FE9116`, matching the dump image. The first callback sets TEXT, the second DEFAULT. Neither captured interval contains a workspace-close or ordinary terminate flight-recorder entry before the crash.

`HolyWorkspaceWindow.keyDebugLogger` uses `Bundle.main.bundleIdentifier` (fallback `com.mitchellh.ghostty`), category `HolyKeyDebug`. The installed identifier is **org.holyghostty.app**, Debug is **org.holyghostty.app.debug**. The Clear logger uses the same dynamic subsystem and category `HolyAttentionDebug`. Sentry/core records use **com.mitchellh.ghostty**. Query all three when following this failure.

The remaining suspects were checked against source:

- Workspace is an `NSWindowController`, not a `TerminalController`. The latter's empty split-tree auto-close is not the workspace lifecycle.
- Controller retention (`Self.retain`, strong registry, `isReleasedWhenClosed = false`) remains intact.
- `40eac9bc5` changes hosting sizing; `a70fa953e` constrains frames; `5c8c9ddae` changes archive providers/resume wiring. None accounts for these callback crash stacks.
- The local standard Ghostty config has no quit-after-last-window or recursive-config override; the macOS source default is false. The live in-memory derived value was not probed. It is not needed to explain the observed crash.

## Root invariant and implementation

A C callback context must remain valid until its C surface has finished destruction. Previously it was an unretained NSView pointer. Clear dropped the views immediately, while `Ghostty.Surface.deinit` deferred `ghostty_surface_free` in a main-actor task. A queued app tick could therefore dereference a freed view.

The macOS surface configuration now supplies a `SurfaceUserdata` box containing a weak view. Both view and surface wrapper own the box; the deferred destructor captures it through `ghostty_surface_free`. Every userdata/action lookup returns nil after the view dies. Close and clipboard callbacks also reject missing views. The platform NSView pointer remains the actual NSView required by the renderer.

The automatic last-window quit delegate now refuses automatic quitting while a workspace window exists, regardless of the configured flag. Explicit user window-close/quit paths are preserved. Clear adds an applied-empty-roster flight-recorder line; rejected stale callbacks are logged.

The regression test constructs an actual surface, releases its view while retaining only the C-surface owner, and sends the exact mouse-shape action from the crash. It checks nullable userdata, late close callbacks, and final userdata destruction. A second parameterized test populates an isolated workspace with three synthetic sleep sessions, calls the real `detachAllSessions`, and checks archived IDs, empty selection/panes/persistence, visible/key window, both quit-flag values, repeated Clear, and subsequent session creation. The injected supervisor captures persistence in memory; it never restores the user's roster. Archive storage uses a temporary database. These are app-hosted tests and have NOT been executed in this lane.

## Validation receipts

- `scripts/build-holy-ghostty-core.sh verify`: PASS. ReleaseFast, Zig 0.15.2, source fingerprint `9d9f76225c12968b5518f7477263b66f6635faff03ff9b9840852de3a38a02be`.
- Focused `xcodebuild build-for-testing`: PASS, including `HolyWorkspaceClearLifecycleTests`, `HolyWorkspacePersistenceRetentionTests`, and `HolyConvergePlannerTests`. This compiles tests; it does not execute them.
- ReleaseLocal instrumented build: PASS, universal arm64/x86_64, unsigned build-only output. Executable SHA-256 `86ffaa0601a244834ee6122f7747ee0d494ca3d82f4c54bb4e5260f33cbecfd2`; arm64 UUID `ACC99815-3043-30D7-B4C7-80D86F5FBCD0`.
- Xcode's SwiftLint phase passed with pre-existing warnings outside this change; `git diff --check` passed.
- Runtime tests, red/green reproduction, key-window/empty-state visual acceptance, and actual Sync reattachment: **NOT RUN**, per the explicit no-launch boundary.
- No installs, app launches, new live sessions, live Clear, push, or PR.

Commands (from repository root):

```sh
xcodebuild build-for-testing -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug -destination 'platform=macOS' -derivedDataPath .dev/mn-3a03e3/DerivedData -only-testing:GhosttyTests/HolyWorkspaceClearLifecycleTests -only-testing:GhosttyTests/HolyWorkspacePersistenceRetentionTests -only-testing:GhosttyTests/HolyConvergePlannerTests CODE_SIGNING_ALLOWED=NO
xcodebuild build -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration ReleaseLocal -destination 'platform=macOS' -derivedDataPath .dev/mn-3a03e3/DerivedData CODE_SIGNING_ALLOWED=NO
```

Local evidence (gitignored):

- `.dev/mn-3a03e3-existing-lifecycle.log`
- `.dev/mn-3a03e3-first-backtrace.txt`
- `.dev/mn-3a03e3-second-backtrace.txt`
- `.dev/mn-3a03e3-build.log`
- `.dev/mn-3a03e3-release-build.log`
- Extracted minidumps `.dev/mn-3a03e3-first-crash.dmp` and `.dev/mn-3a03e3-crash.dmp`.

## Needed next: coordinated runtime acceptance

After this report, the coordinator owns signing/install/launch. Use an instrumented build with isolated app state and only disposable synthetic tmux sessions. Do not launch the test host against an existing saved roster. Execute the focused regression suite, then verify one synthetic Clear leaves the same workspace open/key and renders the empty state, backing tmux sessions survive, and **Sync reattaches those exact session identities**. The new test's subsequent creation check is not a substitute for actual Sync acceptance. Capture log ordering, including Clear, ignored late callbacks if any, and absence of unintended window-close/quit. Repeat with quit-after-last-window-closed true and false. Only then run `agent-do manna done mn-3a03e3`.

## Completion

Seal this handoff with `agent-do manna handoff seal mn-3a03e3`. Commit the owned code/test/handoff/issue row with `Manna: mn-3a03e3`. Do not stage other agents' board/index/drift edits. No push.

Lessons logged: 8 (new) | Decisions logged: 0 (new)
