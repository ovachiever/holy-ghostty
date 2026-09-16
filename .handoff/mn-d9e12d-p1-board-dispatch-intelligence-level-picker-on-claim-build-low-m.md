---
workflow: 2
manna: mn-d9e12d
track: mn-9a97cc
source: null
base_commit: c4fce47f3d105ae22b1ae70e5061140f65dd1053
scope: '[P1][BOARD][DISPATCH] Intelligence level picker on Claim & build — low/med/high/xhigh/max, default max for both runtimes'
inputs: []
binding: sha256:5a1d0bf0da84ee964965d47dada6ec63fed0c8db5bc3cb257993d165433e0b87
---

# Handoff: [P1][BOARD][DISPATCH] Intelligence level picker on Claim & build — low/med/high/xhigh/max, default max for both runtimes

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-d9e12d
```

## Scope

[P1][BOARD][DISPATCH] Intelligence level picker on Claim & build — low/med/high/xhigh/max, default max for both runtimes

## Inputs

- None declared.

## Work order

Erik 2026-09-15: the board's worker dispatch chooses only Codex or Claude (plus a free-text model); add an intelligence LEVEL — low, med, high, xhigh, max — with MAX AS THE DEFAULT for both runtimes (Erik's ruling). This is Holy-only: no agent-do change, no engine change. Work: (1) MODEL — extend HolyMannaWorkerProfile (macos/Sources/HolyGhostty/Board/HolyMannaBoardWorker.swift:3) with a level enum (low, med, high, xhigh, max; default .max). (2) MAPPING — a per-runtime table from level to concrete launch arguments, derived from each runtime's REAL flag surface, not memory: run codex --help / codex config schema and claude --help on the dispatch host (the resolver machinery already finds the binaries; a probe receipt goes in the handoff) and record the exact model + effort flags each level produces. Known in-repo precedent: Holy's own digest path drives claude --print --effort high|low (HolyMannaBoardDigest.swift), and Erik's codex composer runs gpt-6-astra at max effort — but the shipped table cites the live --help output as its authority. Precedence: an explicit model typed in the model field overrides the level's model choice while the level's effort flags still apply where the runtime accepts them; an empty model field takes the level's full mapping. (3) UI — the level picker sits beside the runtime choice in the board item detail (HolyMannaBoardView dispatch controls), default max; the confirmation sheet (HolyMannaWorkerDispatch.confirmation, Worker.swift:158) names the level; the generated brief records it. (4) COMMAND — launchSpec (Worker.swift:189) appends the mapped arguments with the existing quoting; the exec pane-leader behavior, refusal gates, and session-note plumbing are untouched. Tests (executed, not compiled): default level is max for both runtimes; each level maps to its receipted arguments per runtime; explicit-model precedence; quoting of injected model text stays safe (the existing injection regression extends to level arguments); refusals unchanged. Acceptance: Erik opens Claim & build, sees the level picker defaulted to max, dispatches one worker per runtime, and the pane command line carries the mapped flags. Coordinated execution and install return through the coordinator; no push, no PR, no launches from the builder lane beyond the probe commands.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-d9e12d`.
4. Commit with `Manna: mn-d9e12d` and run `agent-do manna done mn-d9e12d` only after the work is verified.

## Builder return, 2026-09-16

**Implementation complete. Coordinator acceptance is pending; do not mark done.**
The picker now sits beside the runtime choice, binds to the five intelligence
levels, and starts at `max` through the existing Board store default. The
confirmation and brief name the selected level. The optional model override is
on the following line to preserve room in the inspector. Strict lint, the
focused Board test build, and the optimized app build passed. Tests remain
compiled-only in this lane; execution, installation, and Erik's live acceptance
belong to the coordinator.

- Claim owner: `codex-01a0a6bac33f70f2`.
- Incoming expected binding, frontmatter binding, computed normalized content
  binding, and canonical `manna state --json` binding all matched
  `sha256:01c1544c7386612583bf3e02c6bed08d8e8ae1c231baea873e2c4dd6ebbcb376`.
- Original handoff was tracked. No repository-local `AGENTS.md` exists; the
  supplied global instructions, parent workspace guide, this work order, and
  `docs/holy-ghostty/engineering-spec.md` supplied the working rules.
- Backend implementation commit: `c244f2af010462aaa507bf16a87651f655b15665`,
  `feat(board): map worker intelligence levels to launch arguments`, with
  `Manna: mn-d9e12d`.
- Build worktree: `/Users/erik/Custom-Coding/holy-ghostty/.dev/worktrees/mn-d9e12d`.
  Its base is `c4d550125c2063ba046578f357d48fa396fb19b5`. The three backend source
  files were already identical to the primary committed versions. The final
  view change was copied back only after verifying the primary view still
  matched `5837603bb2e53ec6500df5264f61b359a5f8c46b` and its copied bytes matched
  the compiled receipt. All four final source hashes are recorded below.
- Canonical Manna and Coord operations belong in the primary checkout,
  `/Users/erik/Custom-Coding/holy-ghostty`.

### Implemented behavior

- `HolyMannaWorkerLevel`: `low`, `med`, `high`, `xhigh`, `max`.
- Both the worker profile and a fresh Board store default to `max`.
- The item detail shows the level picker beside the runtime choice, with an
  optional model override on the following line.
- Each runtime has one explicit default model; level controls its effort.
- A nonempty, trimmed model override changes only the model argument.
- Confirmation and the generated brief name runtime, intelligence level, and
  resolved model. Confirmation freezes the selected profile.
- All new arguments pass through the existing single-quote encoder. The `exec`
  pane leader, refusal gates, executable resolver, and initial Manna session note
  remain unchanged.
- The level is held in the Board store for the current store lifetime. This
  change adds no persisted setting or schema.

### Dispatch-host probe authority

Host: `Eriks-Mac-Studio.local`. Probes were run on 2026-09-15. These commands
display help, catalog data, or schemas; none starts a worker session.

| Runtime | Resolved executable | Version |
| --- | --- | --- |
| Codex | `/Users/erik/.nvm/versions/node/v22.16.0/bin/codex` | `codex-cli 0.154.0` |
| Claude | `/opt/homebrew/bin/claude` | `2.1.272 (Claude Code)` |

Commands executed successfully:

```text
codex --version
codex --help
codex debug --help
codex debug models --help
codex -c 'model_reasoning_effort="max"' debug models --bundled
codex app-server --help
codex app-server generate-json-schema --help
codex app-server generate-json-schema --out .dev/mn-d9e12d/probes/codex-schema
claude --version
claude --help
```

Codex help exposes `--model` and `-c/--config`, with TOML values. This installed
CLI has no `config schema` subcommand. Its supported schema generator emits a
`Config.model_reasoning_effort` reference to `ReasoningEffort`, defined as a
nonempty model-advertised string. The bundled `gpt-6-astra` catalog explicitly
advertises `low`, `medium`, `high`, `xhigh`, `max`, and `ultra`; this UI deliberately
exposes only the five requested levels. Claude help explicitly lists `fable`
as a model alias and all five requested effort spellings.

The fetched [OpenAI configuration reference](https://developers.openai.com/codex/config-reference/)
documents the effort key but lists fewer effort names than the installed
schema/catalog. The installed CLI receipts are the authority for this mapping.

| Level | Codex arguments | Claude arguments |
| --- | --- | --- |
| low | `--model gpt-6-astra -c 'model_reasoning_effort="low"'` | `--model fable --effort low` |
| med | `--model gpt-6-astra -c 'model_reasoning_effort="medium"'` | `--model fable --effort medium` |
| high | `--model gpt-6-astra -c 'model_reasoning_effort="high"'` | `--model fable --effort high` |
| xhigh | `--model gpt-6-astra -c 'model_reasoning_effort="xhigh"'` | `--model fable --effort xhigh` |
| max (default) | `--model gpt-6-astra -c 'model_reasoning_effort="max"'` | `--model fable --effort max` |

Probe receipts are under `.dev/mn-d9e12d/probes/`: `codex-help.txt`,
`claude-help.txt`, both version files, `codex-astra-efforts.json`, and
`codex-config-effort-schema.json`. `SHA256SUMS` binds those six source receipts.
No authenticated runtime/model request was made, so account entitlement and
live execution are not established by these probes.

### Initial backend validation receipts, 2026-09-15

1. `git diff --check`: passed.
2. Focused SwiftLint: passed, zero violations across the three changed Swift files.

   ```bash
   swiftlint lint --strict --config macos/.swiftlint.yml \
     macos/Sources/HolyGhostty/Board/HolyMannaBoardWorker.swift \
     macos/Sources/HolyGhostty/Board/HolyMannaBoardStore.swift \
     macos/Tests/HolyGhostty/HolyMannaBoardActionsTests.swift
   ```

3. Canonical core verification passed: ReleaseFast, Zig 0.15.2, input hash
   `1bee2b6a6d03f263c352ee999916e5ff65dd0e18c69842f83da977401fbc607a`.
   The older `ac7148c18` archive was refused for changed source inputs
   (`core-import.log`). The currently verified primary framework and resources
   were then packaged using the checked-in CI packaging command and imported
   through `scripts/build-holy-ghostty-core.sh import`. Both import verification
   passes succeeded (`core-import-current.log`). No gate was bypassed.
4. From the build worktree, this focused build completed with exit 0 and
   `TEST BUILD SUCCEEDED`:

   ```bash
   xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty \
     -configuration Debug -destination 'platform=macOS,arch=arm64' \
     -derivedDataPath /Users/erik/Custom-Coding/holy-ghostty/.dev/mn-d9e12d/DerivedData \
     SYMROOT=/Users/erik/Custom-Coding/holy-ghostty/.dev/mn-d9e12d/build \
     -only-testing:GhosttyTests/HolyMannaBoardActionsTests \
     -resultBundlePath /Users/erik/Custom-Coding/holy-ghostty/.dev/mn-d9e12d/build-initial.xcresult \
     build-for-testing
   ```

   **Compiled tests only. Executed tests: 0.** The xcresult records build status
   `succeeded` and execution action `notRequested`, with zero errors and 521
   warnings. The warning in an owned source file is the unchanged executable
   resolver initializer's non-Sendable function conversion, now at line 66.
   `build-initial.log`, `build-initial.xcresult`, `build-summary.json`, and
   `compiled-source-sha256.json` are under `.dev/mn-d9e12d/`.

The compiled suite covers both defaults, all ten runtime/level combinations,
empty and explicit model precedence, confirmation/brief metadata, frozen
confirmation selections, existing refusal gates, and the extended shell
injection regression at every runtime/level combination. No test pass is
claimed until the coordinator executes the suite.

### Final picker validation receipts, 2026-09-16

The coordinator released the historical `mn-61fb80` view claim. This worker
verified the path was free, acquired it under the existing Manna owner, and
cleared `mn-d9e12d-board-view-release`. Before editing, canonical ownership and
the previous seal were verified against normalized contents and Manna state:
`sha256:603ef5722a3308bf70823e61205c3677e7e8f58ae122983b43cca55d9c1e6490`.
The prepared `.dev/mn-d9e12d/picker-pending.patch` was then applied unchanged.
It is retained as the original draft receipt, and is no longer pending work.

From the retained build worktree, strict SwiftLint passed with zero violations
across all four Swift files changed for this item:

```bash
swiftlint lint --strict --config macos/.swiftlint.yml \
  macos/Sources/HolyGhostty/Board/HolyMannaBoardView.swift \
  macos/Sources/HolyGhostty/Board/HolyMannaBoardWorker.swift \
  macos/Sources/HolyGhostty/Board/HolyMannaBoardStore.swift \
  macos/Tests/HolyGhostty/HolyMannaBoardActionsTests.swift
```

`git diff --check` and `scripts/build-holy-ghostty-core.sh verify` also passed.
The core input hash remains
`1bee2b6a6d03f263c352ee999916e5ff65dd0e18c69842f83da977401fbc607a`.

The final Debug app and test bundle compiled with the five Board suite selectors:

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /Users/erik/Custom-Coding/holy-ghostty/.dev/mn-d9e12d/DerivedData \
  SYMROOT=/Users/erik/Custom-Coding/holy-ghostty/.dev/mn-d9e12d/build \
  -only-testing:GhosttyTests/HolyMannaBoardActionsTests \
  -only-testing:GhosttyTests/HolyMannaBoardTests \
  -only-testing:GhosttyTests/HolyMannaBoardPresentationTests \
  -only-testing:GhosttyTests/HolyMannaBoardRenderSmokeTests \
  -only-testing:GhosttyTests/HolyMannaBoardLinkTests \
  -resultBundlePath /Users/erik/Custom-Coding/holy-ghostty/.dev/mn-d9e12d/build-picker.xcresult \
  build-for-testing
```

Result: exit 0, `TEST BUILD SUCCEEDED`, zero errors, 32 warnings, and zero
warnings attributed to `HolyMannaBoardView.swift`. The xcresult records build
status `succeeded` and execution action `notRequested`. **Executed tests: 0.**
The result bundle and `build-picker.log`, `build-picker-summary.json`,
`swiftlint-picker.log`, and `core-verify-picker.log` are under `.dev/mn-d9e12d/`.

The optimized app also rebuilt successfully without being run or installed:

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -configuration ReleaseLocal -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /Users/erik/Custom-Coding/holy-ghostty/.dev/mn-d9e12d/DerivedData \
  SYMROOT=/Users/erik/Custom-Coding/holy-ghostty/.dev/mn-d9e12d/build \
  -resultBundlePath /Users/erik/Custom-Coding/holy-ghostty/.dev/mn-d9e12d/build-picker-release.xcresult \
  build
```

Result: exit 0, `BUILD SUCCEEDED`, zero errors, 55 warnings; execution action
`notRequested`. `lipo -archs` reports `x86_64 arm64`. The executable SHA-256 is
`21af6a9534c3dac9bc896b9b40069aa528ae3faf88ccffe21d5ba8cd869ece33`.
The result bundle, `build-picker-release.log`, and
`build-picker-release-summary.json` are under `.dev/mn-d9e12d/`.

Final compiled source SHA-256 (also `compiled-picker-source-sha256.json`):

| File | SHA-256 |
| --- | --- |
| `macos/Sources/HolyGhostty/Board/HolyMannaBoardView.swift` | `bee753f84b6e4d500c3aa73e24dfaf234001c86cd92f606323bace176ae0b786` |
| `macos/Sources/HolyGhostty/Board/HolyMannaBoardWorker.swift` | `afcb7bb47a944e4a2ba8b8199c9bf103c4f0cdf67a58ad2166ad16883cd72f8d` |
| `macos/Sources/HolyGhostty/Board/HolyMannaBoardStore.swift` | `3168b80f6e1a2f90b244f6ee2520112f6d8df7e5cd929490cd021cbacf8d53ff` |
| `macos/Tests/HolyGhostty/HolyMannaBoardActionsTests.swift` | `6c13d63fa787df4c07a28d9e549f77c10b5fd5b6e717436fc7a4ab7506d9ba62` |

### Needed next

1. Coordinator: execute the five Board suites using canonical Xcode `test` or
   `test-without-building`, with a fresh result bundle and the final source/build.
   Repeat all five `-only-testing` selectors above during execution: the
   generated `.dev/mn-d9e12d/build/Ghostty_Ghostty_macosx26.4-arm64.xctestrun`
   includes both test targets and does not store `OnlyTestIdentifiers`.
   `picker-test-plan.json` records that inspection. Tests are app-hosted and the
   Actions suite includes the existing isolated tmux note test; execution
   belongs in the coordinated launch window. The coordinator dependency remains
   `mn-d9e12d-executed-live-acceptance`.
2. Coordinator/Erik: complete the supported install and live acceptance from
   the work order. Open Claim & build, verify the picker defaults to max, dispatch
   one Codex and one Claude worker, and inspect their pane command lines for
   the mapped model/effort flags. Preserve the no-push/no-PR boundary.
3. Append actual executed/live receipts, reseal this handoff, and mark done only
   after the required acceptance is verified.

No app launches, app installations, screenshots, or live worker spawning were
performed in this builder lane. No push or pull request was made.

This continuation: Lessons logged: 1 (new) | Decisions logged: 0 (new).
New lesson: `les-7a8c90`. Initial lane: 6 lessons and 1 decision (`les-370f5d`,
`les-e4b3f8`, `les-7dca28`, `les-2e6afc`, `les-b7c3a4`, `les-d56c19`,
`dec-dd2a2f`). `zpc harvest --since last` completed locally after the new lesson.

**TL;DR (12th grade):** The level picker is implemented beside the runtime
choice, with max as the starting setting. Strict lint, the Board test build,
and the optimized app build passed. Tests have not run, and the app has not been
launched or installed in this lane. The coordinator performs those checks and
returns Erik's acceptance before this item closes.
