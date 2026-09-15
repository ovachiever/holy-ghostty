---
workflow: 2
manna: mn-d9e12d
track: mn-9a97cc
source: null
base_commit: c4fce47f3d105ae22b1ae70e5061140f65dd1053
scope: '[P1][BOARD][DISPATCH] Intelligence level picker on Claim & build — low/med/high/xhigh/max, default max for both runtimes'
inputs: []
binding: sha256:603ef5722a3308bf70823e61205c3677e7e8f58ae122983b43cca55d9c1e6490
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

## Builder return, 2026-09-15

**Partial implementation. Do not mark done.** The model, command, confirmation,
brief, and store plumbing are committed and compile. The picker is not applied:
Coord refused the exact view path because `session-17a022e17710` still holds it.
Executed tests and the coordinated live acceptance remain outstanding.

- Claim owner: `codex-01a0a6bac33f70f2`.
- Incoming expected binding, frontmatter binding, computed normalized content
  binding, and canonical `manna state --json` binding all matched
  `sha256:01c1544c7386612583bf3e02c6bed08d8e8ae1c231baea873e2c4dd6ebbcb376`.
- Original handoff was tracked. No repository-local `AGENTS.md` exists; the
  supplied global instructions, parent workspace guide, this work order, and
  `docs/holy-ghostty/engineering-spec.md` supplied the working rules.
- Implementation commit: `c244f2af010462aaa507bf16a87651f655b15665`,
  `feat(board): map worker intelligence levels to launch arguments`, with
  `Manna: mn-d9e12d`.
- Build worktree: `/Users/erik/Custom-Coding/holy-ghostty/.dev/worktrees/mn-d9e12d`.
  Its base is `c4d550125c2063ba046578f357d48fa396fb19b5`. The three compiled source
  files were copied back only after verifying the primary originals still
  matched that base and the copied bytes matched the build receipt.
- Canonical Manna and Coord operations belong in the primary checkout,
  `/Users/erik/Custom-Coding/holy-ghostty`.

### Implemented behavior

- `HolyMannaWorkerLevel`: `low`, `med`, `high`, `xhigh`, `max`.
- Both the worker profile and a fresh Board store default to `max`.
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

### Focused validation receipts

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

Compiled source SHA-256:

| File | SHA-256 |
| --- | --- |
| `macos/Sources/HolyGhostty/Board/HolyMannaBoardWorker.swift` | `afcb7bb47a944e4a2ba8b8199c9bf103c4f0cdf67a58ad2166ad16883cd72f8d` |
| `macos/Sources/HolyGhostty/Board/HolyMannaBoardStore.swift` | `3168b80f6e1a2f90b244f6ee2520112f6d8df7e5cd929490cd021cbacf8d53ff` |
| `macos/Tests/HolyGhostty/HolyMannaBoardActionsTests.swift` | `6c13d63fa787df4c07a28d9e549f77c10b5fd5b6e717436fc7a4ab7506d9ba62` |

### Needed next

1. Resolve `mn-d9e12d-board-view-release` through the coordinator. The failed
   `agent-do coord claim macos/Sources/HolyGhostty/Board/HolyMannaBoardView.swift`
   returned `already claimed by session-17a022e17710`. Its reason is the older
   `mn-61fb80 terminal crumb unconditional` lane. Its owner must release the
   path before this worker claims and edits it. No ownership takeover occurred.
2. Add the picker next to the runtime choice. A reviewable, **unapplied and
   uncompiled** draft is `.dev/mn-d9e12d/picker-pending.patch`; it binds the five
   cases to `store.workerLevel`, shows a level label, and moves the optional
   model field below so it retains space in the narrow inspector. Recheck the
   view's current contents before applying it. Then repeat focused lint and
   `build-for-testing` on the final source.
3. Coordinator: execute `GhosttyTests/HolyMannaBoardActionsTests` using canonical
   Xcode `test` or `test-without-building`, with a fresh result bundle and the
   final source/build. This suite is app-hosted and includes the existing
   isolated tmux note test; execution belongs in the coordinated launch window.
4. Coordinator/Erik: complete the supported install and live acceptance from
   the work order. Open Claim & build, verify the picker defaults to max, dispatch
   one Codex and one Claude worker, and inspect their pane command lines for
   the mapped model/effort flags. Preserve the no-push/no-PR boundary.
5. Append actual executed/live receipts, reseal this handoff, and mark done only
   after the required acceptance is verified.

No app launches, app installations, screenshots, or live worker spawning were
performed in this builder lane. No push or pull request was made.

Lessons logged: 6 (new) | Decisions logged: 1 (new).
Lesson IDs: `les-370f5d`, `les-e4b3f8`, `les-7dca28`, `les-2e6afc`, `les-b7c3a4`,
`les-d56c19`. Decision: `dec-dd2a2f`. `zpc harvest --since last` completed locally.

**TL;DR (12th grade):** The intelligence settings and launch commands are built
and committed, but the visible picker is still blocked by another worker's file
claim. Tests compiled and have not run. Release that file, finish the picker,
and run the coordinated tests and live checks before closing this item.
