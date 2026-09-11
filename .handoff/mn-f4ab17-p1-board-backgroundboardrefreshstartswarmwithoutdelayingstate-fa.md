---
workflow: 2
manna: mn-f4ab17
track: mn-9a97cc
source: Executed-test run 2026-09-10 21:23; cites mn-6160c9
base_commit: abe1f1e556d28622655191d9a12fc43a383dedd9
scope: '[P1][BOARD] backgroundBoardRefreshStartsWarmWithoutDelayingState fails — mn-6160c9 closed on compiled-only verification'
inputs:
- Executed-test run 2026-09-10 21:23; cites mn-6160c9
binding: sha256:a1d5c787df90f0f7ebf4b04c7a83d23225a291ecfc60157bc99690c0166fe606
---

# Handoff: [P1][BOARD] backgroundBoardRefreshStartsWarmWithoutDelayingState fails — mn-6160c9 closed on compiled-only verification

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-f4ab17
```

## Scope

[P1][BOARD] backgroundBoardRefreshStartsWarmWithoutDelayingState fails — mn-6160c9 closed on compiled-only verification

## Inputs

- Executed-test run 2026-09-10 21:23; cites mn-6160c9

## Work order

The mn-6160c9 dispatch-feedback work (c681f6a46) was closed (82dd218f0) with zero executed tests per its own report; first real run fails its regression backgroundBoardRefreshStartsWarmWithoutDelayingState (consistent, 0.02s). Claim, execute the three Board suites, fix, re-close on executed green. Erik's live chip/row acceptance queues behind this.

## Verification receipt, 2026-09-10

The regression repair is implemented and compiled. **Required executed acceptance remains pending.** This item stays `in_progress` under `codex-01a08e4e961a70a1`; no `manna done` was run.

### Authority and ownership

- The first command was `agent-do manna claim mn-f4ab17`, which succeeded. No claim was stolen.
- The initial complete-content binding matched the requested `sha256:db9c8143be67cae57b7fc99788e0e40f97155e9303e9402b4281738ceaf12174`, handoff frontmatter, and canonical `.manna/issues.jsonl` / `agent-do manna state --json`. The hash follows Manna's `binding_material`: normalize the single frontmatter binding line to `binding: ''` before SHA-256.
- Read the applicable parent `AGENTS.md`, repository README, Xcode project/scheme, and original `mn-6160c9` work order. There is no repository-local `AGENTS.md` or `CLAUDE.md`.
- Set coord focus and path claims before editing. Released the exploratory Store claim when evidence narrowed the repair to the test. Foreign documentation, mouse-lane changes, and Manna rows remain owned by their writers.
- Built in `/Users/erik/Custom-Coding/holy-ghostty-fix-mn-f4ab17-board-warm`, branch `fix/mn-f4ab17-board-warm`, from base `1030066b27a1fba3db5724e8c27b8d4b6990c059`. Existing ignored `macos/GhosttyKit.xcframework` and `zig-out/share` were copied into the isolated checkout. Manna and coord operations remained in the primary checkout.

### Confirmed failure and repair

The existing run is preserved at:

`/Users/erik/Library/Developer/Xcode/DerivedData/Ghostty-evzhqzgwedstedhkeiqpqvomarls/Logs/Test/Test-Ghostty-2026.09.10_21-22-49--0500.xcresult`

Its complete action issue records contain these failures in `backgroundBoardRefreshStartsWarmWithoutDelayingState()`:

- Line 385: `Expectation failed: (store.digestText -> nil) == "Warm summary for Native Board"` (arrow normalized here).
- Line 386: `store.presentationDigest(for: try #require(store.selectedItem)) == "Warm Native Board"` failed.

The original console log records both a 0.021-second failure and a 0.046-second pass in different test hosts. The high-level xcresult summary/test-details surface only the passing invocation for this test; the complete action `testFailureSummaries` retain the failure. The extracted records are in `.dev/mn-f4ab17/original-failure.json`, with the relevant console excerpt beside them.

`HolyMannaDigestRecorder.callCount` records entry to the digest service. It does not mean the prewarmer has returned results through its MainActor sink. The old test waited for entry and immediately asserted displayed text, creating a race with that delivery. Production state refresh already schedules warming without awaiting it; no production source change is needed for this diagnosed test failure.

Changed only `macos/Tests/HolyGhostty/HolyMannaBoardTests.swift`:

1. Suspend the fixture's result using an `AsyncStream` until the test releases it.
2. While generation is suspended, require the original one-call count, canonical state, default item selection, completed state refresh, hidden Board, and no digest-loading indicator. The summary must still be absent.
3. Release generation and await the actual `HolyMannaBoardPrewarmer.waitUntilIdle()`, which finishes after sink delivery, before asserting the original summary and row digest. Assert the one-call count again.
4. Keep the existing bounded wait for service entry. No added timing delay, skipped assertion, replacement prewarmer, or app-host bypass was introduced.

The built and integrated test source is byte-identical, SHA-256:

`0c71503be540af556526dde272f07d1362a17a8c977d1728385157de73365202`

### Focused validation actually performed

From the isolated checkout:

```bash
swiftlint lint --strict --config macos/.swiftlint.yml macos/Tests/HolyGhostty/HolyMannaBoardTests.swift
git diff --check -- macos/Tests/HolyGhostty/HolyMannaBoardTests.swift
xcodebuild build-for-testing -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .dev/mn-f4ab17/DerivedData -only-testing:GhosttyTests/HolyMannaBoardActionsTests -only-testing:GhosttyTests/HolyMannaBoardTests -only-testing:GhosttyTests/HolyMannaBoardPresentationTests CODE_SIGNING_ALLOWED=NO
```

All exited 0. SwiftLint reported 0 violations in the changed file. Xcode reported `** TEST BUILD SUCCEEDED **`. This built the app-hosted test target with the three required Board suites selected. **Executed tests in this lane: 0.** A Debug test build with the existing core payload is not a ReleaseLocal core-provenance or installation receipt.

The primary checkout contains copies of the build/lint logs, original failure extraction, source patch, and SHA-256 receipts in `.dev/mn-f4ab17/`. The original build products and `.xctestrun` remain under the isolated checkout's `.dev/mn-f4ab17/DerivedData/`. The tracked handoff carries the commands and outcomes so ignored logs are supplementary evidence.

### Required acceptance at coordinated close

The lane's explicit no-launch instruction prevents executing the app-hosted tests mid-lane. Keep `mn-f4ab17` open until the coordinated pass executes the three Board suites and records zero failures. Queue execution through coord under `mn-f4ab17-executed-board-suites`; do not infer execution from compilation or from the archived pre-fix passing host.

After coordination authorizes the test host, use the same isolated checkout and products:

```bash
xcodebuild test-without-building -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .dev/mn-f4ab17/DerivedData -resultBundlePath .dev/mn-f4ab17/focused-executed.xcresult -only-testing:GhosttyTests/HolyMannaBoardActionsTests -only-testing:GhosttyTests/HolyMannaBoardTests -only-testing:GhosttyTests/HolyMannaBoardPresentationTests CODE_SIGNING_ALLOWED=NO
```

Record actual passed/failed/skipped counts and reconcile the complete xcresult action issues with the console, then update and reseal this handoff. Erik's live dispatch chip/row acceptance remains queued behind executed green: confirm the booting chip, movement only after the canonical claim, and the bounded expiry/session link. No app launch, install, screenshot, live session spawn, push, or pull request occurred in this lane.

Lessons logged: 4 (new) | Decisions logged: 0 (new). Lessons: `les-87ff4d`, `les-1e1e4a`, `les-74d9c1`, `les-11b777`.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-f4ab17`.
4. Commit with `Manna: mn-f4ab17` and run `agent-do manna done mn-f4ab17` only after the work is verified.
