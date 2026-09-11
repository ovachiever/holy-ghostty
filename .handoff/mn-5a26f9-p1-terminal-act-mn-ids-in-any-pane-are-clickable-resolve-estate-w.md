---
workflow: 2
manna: mn-5a26f9
track: mn-9a97cc
source: 'Erik request 2026-09-10 10:07 (screenshot: dm-ephemeris ids cited in-pane)'
base_commit: 516e6e530f24c0ed9f9449baa5bcc3f68c7a7a88
scope: '[P1][TERMINAL][ACT] mn- ids in any pane are clickable: resolve estate-wide, then Claim & build behind the confirm'
inputs:
- 'Erik request 2026-09-10 10:07 (screenshot: dm-ephemeris ids cited in-pane)'
binding: sha256:bf245a40747ab212cf66014d40ff5fba2bae1c07c70de15b9220cdfe85a90d0b
---

# Handoff: [P1][TERMINAL][ACT] mn- ids in any pane are clickable: resolve estate-wide, then Claim & build behind the confirm

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-5a26f9
```

## Scope

[P1][TERMINAL][ACT] mn- ids in any pane are clickable: resolve estate-wide, then Claim & build behind the confirm

## Inputs

- Erik request 2026-09-10 10:07 (screenshot: dm-ephemeris ids cited in-pane)

## Work order

Erik 2026-09-10: manna ids printed in terminal output (agents cite them constantly) should be clickable into the claim-and-run flow. Design, four existing pieces plus one new matcher: (1) MATCHER — extend the core's link-detection engine with the mn-[a-f0-9]{6,} pattern emitting a holy-ghostty://board?item=<id> link, exactly as URLs become clickable today; CONSTRAINT: this is Zig core territory and engine rebuilds go through CI only (local Zig link broken on macOS 26 — house law from the scroll-regression postmortem); if a core change is too heavy a first step, the macOS fallback is surface-level hit-testing of the character cell under a cmd+click against the same regex, no engine change. (2) ROUTE — the existing URL scheme gains the board?item route. (3) RESOLUTION — an id in prose often belongs to ANOTHER repo's board (Erik's screenshot cites dm-ephemeris ids inside an aldebaran session): resolve estate-wide via manna estate --json + per-board state, prefer the session's own cwd board, then unique match across the estate; ambiguous or unknown ids open the board view's search rather than guessing. (4) ACTION — landing surface is the item in Board mode with the SHIPPED Claim & build affordance (mn-ec34cd machinery): the confirm sheet is mandatory (glance law — a click in scrollback must never dispatch or mutate by itself), dreams refuse, claimed items show the claimant. Style: render detected ids with the link underline-on-hover treatment the terminal already uses for URLs. Tests: pattern boundaries (mn- inside words, uppercase, short hex), cross-board resolution incl. ambiguous, the confirm gate, and a scrollback click on a done item landing on its done row. Acceptance: cmd+click a cited id in any session, land on the item, one confirm dispatches the worker.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-5a26f9`.
4. Commit with `Manna: mn-5a26f9` and run `agent-do manna done mn-5a26f9` only after the work is verified.

## Correction receipts: 2026-09-11

Current status: **EXECUTED RED; correction compiled and committed, awaiting coordinated rerun.** Keep `mn-5a26f9` `in_progress`, claimed by `codex-01a08e805e527011`. Execution returns through Erik and verifier `session-17a022e17710`. Do not mark done or start app-hosted execution from this lane.

### Executed evidence and diagnosis

- The verifier executed the four focused suites at `ca8631e4c`: **20 failed / 158 passed** execution-log occurrences. Every failure was in `HolyMannaBoardLinkTests`; the three pre-existing suites were green. Preserve `.dev/acceptance-c2b133-f4ab17/RECEIPT.md`, `.dev/mn-5a26f9-executed.log`, and `.dev/mn-5a26f9-executed/suites.xcresult` as the current executed evidence. The result bundle groups these into 8 failed / 56 passed test identifiers; parameterized and repeated log occurrences use a different denominator.
- Reverified the input handoff binding `sha256:c48337533f60cd022ee91401c54aa782f170ff001708872611599739f6da988e` against its normalized content and canonical Manna state, and verified the existing claim before editing. Refreshed Coord focus and exact path claims; all edits and compilation used the existing isolated worktree.
- The shared `linkState` fixture omitted required `title_plain`. A fresh read of canonical `agent-do manna state --json` confirmed the field in all 4 `now`, 40 `next`, and 133 `all` items. Added `title_plain: "cited work"` to the shared item, covering ready, claimed, dream, and done fixtures. The production item decoder and landing assertions remain unchanged.
- The existing executed bundle also exposes an independent failure: `missingFocusedBoardStillSearchesTheEstate` throws `commandFailed(code: 1, detail: nil)` before item decoding. A read-only canonical CLI probe from `/private/var/empty` returned the absent-board refusal JSON on **stdout**, empty stderr, and **exit 2**. `checkedRun` discarded stdout on nonzero exits, so the resolver could not recognize an absent board. Preserved the canonical refusal envelope and requested directory at that shared client boundary; unrelated nonzero transport failures still throw. This is a production defect, not a reason to weaken the fixture or parser contract.
- Corrected the absent-board fixture to exit 2, extended its regression to local and SSH origins, and covered refusal envelopes at exits 0 and 2 plus nonzero transport failures with malformed/success stdout. The landing, selection, done-row, and confirmation assertions must be judged again after the coordinated rerun. Any surviving failure remains a real defect to diagnose.

Primary code commit: `acd983cebbadeeeb094f29023ce4104f4d8509fe` (`fix(board): align link fixtures and preserve CLI refusals`), trailer `Manna: mn-5a26f9`. Isolated commit: `ce18ce4df785663b0de3bbe139f3b8b904e84c53`. The complete tracked macOS trees match between primary and the compiled isolated commit. Other workers' documentation and Manna rows were preserved.

### Correction validation

The following commands ran in `/Users/erik/Custom-Coding/holy-ghostty-codex-mn-5a26f9`:

```bash
scripts/build-holy-ghostty-core.sh verify
swiftlint lint --strict --quiet \
  macos/Sources/HolyGhostty/Board/HolyMannaBoardClient.swift \
  macos/Tests/HolyGhostty/HolyMannaBoardTests.swift \
  macos/Tests/HolyGhostty/HolyMannaBoardLinkTests.swift
git diff --check
/usr/bin/xcodebuild -quiet \
  -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .dev/DerivedData-mn-5a26f9 \
  -resultBundlePath .dev/mn-5a26f9/fixture-correction/build-for-testing.xcresult \
  -only-testing:GhosttyTests/HolyMannaBoardLinkTests \
  -only-testing:GhosttyTests/HolyMannaBoardActionsTests \
  -only-testing:GhosttyTests/HolyMannaBoardTests \
  -only-testing:GhosttyTests/HolyWorkspaceTerminalMouseTests \
  build-for-testing CODE_SIGNING_ALLOWED=NO
```

All exited 0. Strict SwiftLint found zero violations. Core verification retained ReleaseFast / Zig 0.15.2 / input fingerprint `9d9f76225c12968b5518f7477263b66f6635faff03ff9b9840852de3a38a02be`. Build-for-testing succeeded with **zero errors**, 503 warnings outside the changed files, and zero changed-file warnings. The four suites **compiled; zero tests executed** in this correction lane. No app launch, install, screenshot, live session spawn, push, or PR was performed.

Correction receipts: `.dev/mn-5a26f9/fixture-correction/verification.json`, `input-verification.json`, `absent-board-contract.json`, `previous-execution.json`, `previous-executed-summary.json`, `core-verify.log`, `swiftlint.log`, `build-for-testing.log`, `build-for-testing.xcresult`, and `build-results.json`. Original RED receipts remain intact. Execution must return through Erik; rerun all four suites on the corrected primary source before judging behavior or advancing acceptance.

Lessons logged: 2 (new), `les-40bae7` and `les-188e84` | Decisions logged: 0 (new). Project ZPC harvest completed.

## Implementation receipts: 2026-09-10

Historical status: implemented and compiled. The later executed RED result and correction receipts above supersede this build-only status. Keep this item `in_progress`, claimed by `codex-01a08e805e527011`. Do not mark done from build receipts.

- The first command, `agent-do manna claim mn-5a26f9`, succeeded. The handoff content binding was recomputed using Manna's canonical binding normalization and matched its frontmatter, canonical state, and the expected `sha256:b657efadad2ff572ff3296211dc83c355c1c9361652185c59930f55fc58ea08a` before editing.
- Read `.private/AGENTS.md` and `.private/macos/AGENTS.md`, the available repository guides. Established primary-checkout Coord focus and exact path claims. The existing claim on `HolyMannaBoardView.swift` was respected; that file was not edited.
- Isolated implementation and compilation in `/Users/erik/Custom-Coding/holy-ghostty-codex-mn-5a26f9`, branch `codex/mn-5a26f9`, based on `a03e5a231`. All canonical Manna operations stayed in the primary checkout.
- Used the explicitly permitted native macOS implementation. Ghostty's read-only Quick Look word API supplies viewport cells and baselines, including scrollback. Row/prefix reads preserve cell offsets after Unicode text. Command-hover draws an underline and URL preview; press/release revalidation opens the read-only Board route. Wrapped ASCII references retain their regex boundaries; ambiguous or partly invisible wrapped cell mappings refuse instead of guessing.
- Added strict `holy-ghostty://board?item=<id>` parsing. The native click supplies the originating pane, so its repository and SSH host determine the lookup context. Opening Board never requests a mutation or dispatch and creates no default session when a workspace is needed.
- Resolution prefers a canonical match on the originating board, then reads `manna estate --json` and all existing boards through `manna state --json`, with at most four concurrent reads. Incomplete item coverage, failed reads, and mismatched roots cannot establish uniqueness. Unknown or ambiguous ids open Board search; ambiguous results name the matching boards for explicit selection through the existing estate chooser.
- Landing resets unrelated filters and selects the full item id. Completed items select the done filter and visible done row. The shipped Claim & build confirmation, dream refusal, claimant display, sealed-handoff recheck, and worker launch path remain authoritative.
- Added focused regressions for identifier boundaries, strict URL parsing, Unicode prose, wrapped punctuation and underline geometry, local precedence, nested cwd roots, cross-board and SSH-host resolution, ambiguity, missing boards, failed or incomplete reads, done-row landing, confirmation, dream/claim refusal, and late-result cancellation.

Local commits on primary `main`, both with `Manna: mn-5a26f9`:

1. `3b27bf3f3999effe56078421674c129d1f85ab11` (`feat(board): open Manna items from terminal links`). Isolated commit: `bb396f29c`.
2. `7baec439e` (`fix(terminal): preserve wrapped Manna link boundaries`). Isolated commit: `3d04d2bab`.

The eight changed source/test files in primary were verified byte-for-byte against the compiled isolated checkout. Unrelated README, changelog, engineering-guide, and interoperability edits were preserved. No push or pull request was made.

## Focused validation

All commands below ran in the isolated checkout. No app launch, installation, screenshot, or live session spawn was performed by this lane. The tests are app-hosted: they were compiled, not executed.

Imported and verified the existing CI core artifact without a local Zig rebuild:

```bash
scripts/build-holy-ghostty-core.sh import /Users/erik/Custom-Coding/holy-ghostty/.dev/core-artifacts/ac7148c18/HolyGhostty-Core-ReleaseFast.zip
scripts/build-holy-ghostty-core.sh verify
```

Both exited 0. Core: ReleaseFast, Zig 0.15.2, input fingerprint `9d9f76225c12968b5518f7477263b66f6635faff03ff9b9840852de3a38a02be`.

```bash
swiftlint lint --strict --quiet \
  macos/Sources/HolyGhostty/Automation/HolyMannaLink.swift \
  macos/Sources/HolyGhostty/Automation/HolyAutomationURLParser.swift \
  macos/Sources/HolyGhostty/Board/HolyMannaBoardLink.swift \
  macos/Sources/HolyGhostty/Board/HolyMannaBoardStore.swift \
  macos/Sources/App/macOS/AppDelegate.swift \
  'macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift' \
  'macos/Sources/Ghostty/Surface View/SurfaceView.swift' \
  macos/Tests/HolyGhostty/HolyMannaBoardLinkTests.swift
git diff --check
```

Both exited 0. Strict SwiftLint: zero violations in all eight touched Swift files.

```bash
/usr/bin/xcodebuild -quiet \
  -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .dev/DerivedData-mn-5a26f9 \
  -resultBundlePath .dev/mn-5a26f9/build-for-testing-wrapped.xcresult \
  -only-testing:GhosttyTests/HolyMannaBoardLinkTests \
  -only-testing:GhosttyTests/HolyMannaBoardActionsTests \
  -only-testing:GhosttyTests/HolyMannaBoardTests \
  -only-testing:GhosttyTests/HolyWorkspaceTerminalMouseTests \
  build-for-testing CODE_SIGNING_ALLOWED=NO
```

Final result: exit 0, `succeeded`, zero build errors, 504 warnings outside the touched files, zero touched-file warnings. The four selected suites compiled; **zero tests executed**. The earlier two build-for-testing passes also succeeded. Initial test-helper lint findings were corrected before the recorded green checks.

Receipts in primary `.dev/mn-5a26f9/`: `verification.json`, `source-hashes.json`, `core-verify.log`, `swiftlint-wrapped.log`, `build-for-testing-wrapped.log`, `build-for-testing-wrapped.xcresult`, and `build-results-wrapped.json`. Build products remain in the isolated checkout's `.dev/DerivedData-mn-5a26f9/`.

Lessons logged: 7 (new) | Decisions logged: 0 (new). ZPC harvest completed with zero format issues.

## Required acceptance at close

Coordinate one live window with Erik and the `mn-235e6d` field-acceptance lane. The build-only boundary remains in force until that window is authorized.

1. Return execution through Erik and verifier `session-17a022e17710`: rerun the four focused app-hosted suites above through the repository's Xcode test path on the corrected source. Preserve the executed result bundle and actual pass/fail counts. The latest execution is RED; the correction build receipts do not satisfy this step.
2. Use the canonical coordinated build/install path for the verified source. Retain the CI core fingerprint; do not attempt a local Zig engine rebuild or an alternate launcher.
3. In the installed app, command-hover and command-click valid ids in local and SSH sessions, focused and unfocused panes, and scrollback. Check underline, pointer, preview, Unicode-before-id alignment, wrapping, modifier release, and ordinary URL behavior. Short, uppercase, and word-embedded strings must not link.
4. Check a cited id belonging to another repository, source-board precedence, and unknown/ambiguous search behavior. Click a completed id in scrollback and verify its selected done row is visible.
5. Opening an id must create no worker and request no mutation. A dream refuses dispatch; a claimed item names its claimant. On a ready item with a valid seal, Claim & build must show the shipped confirmation. Cancel must launch nothing; one accepted confirmation must dispatch exactly one worker with the full item id in its note.
6. Record receipts, fix any failures, reseal this handoff, and only then run `agent-do manna done mn-5a26f9`.

This is required acceptance, not optional polish. The item remains open until it passes.
