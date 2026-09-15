---
workflow: 2
manna: mn-0a4d6c
track: mn-9a97cc
source: null
base_commit: b59c57b942591bc754483e57ec06124feca98439
scope: '[P1][BOARD][AI] A digest deadline miss is never content: retry with backoff, honest pending state, and a real deadline'
inputs: []
binding: sha256:143d34bd84e3a655c2f0903dd488471b6e4aaabbdad9d5ce428debf4219ae9f1
---

# Handoff: [P1][BOARD][AI] A digest deadline miss is never content: retry with backoff, honest pending state, and a real deadline

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-0a4d6c
```

## Scope

[P1][BOARD][AI] A digest deadline miss is never content: retry with backoff, honest pending state, and a real deadline

## Inputs

- None declared.

## Work order

Erik 2026-09-14 (screenshot, mn-56f896 inspector): AI SUMMARY renders 'Holy fast model did not finish before the safety deadline.' — a timeout error occupying the summary surface as terminal state. Traced end to end: HolyMannaBoardDigest.complete() runs one claude --print per batch of up to 12 items (batchSize, HolyMannaBoardDigest.swift:63) under a 60-second deadline (bare literal at :586 for the OpenAI route and :625 for the CLI route — both violate the numbers-from-authority rule); a single slow run throws HolyMannaBoardClientError.timedOut whose errorDescription ('did not finish before the safety deadline', HolyMannaBoardClient.swift:41) flows through the job catch (HolyMannaBoardDigest.swift:534) into sink .failed, and HolyMannaBoardStore.applyWarmEvent (:1004) writes that message into digestFailures for ALL 12 items in the batch — the inspector then shows the error where the summary belongs until some later generation succeeds. Cold-start claude CLI plus a large post-gap board makes 60s routinely insufficient, and one miss poisons twelve rows. Fix (design, not a bigger number): (1) a deadline miss is RETRYABLE, never terminal — requeue the batch with escalating budget (e.g. once at 2x, then park until the next warm cycle), counting attempts per content hash so a genuinely wedged run stops retrying; (2) the UI never renders transport/timeout errors as summary text — timeout-class failures show a quiet 'summarizing…' pending state (the existing digest-loading affordance), while real refusals (usage guard, missing binary) keep their honest message; (3) replace both 60-second literals with a named constant derived from role and batch size, documented with its provenance, shared by the CLI and OpenAI routes; (4) split-batch salvage: on a second miss, halve the batch (6, then 3) so one slow item cannot hold hostage eleven others — mirrors the embeddings halving precedent in the archive lane. Tests: a timed-out batch requeues and its items show pending not error; a usage-guard refusal still shows its message; halving isolates a slow item; the constant is referenced from both routes. Acceptance: Erik opens the board after a burst of new items and never sees a deadline message in AI SUMMARY — summaries either appear or show pending until they do.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-0a4d6c`.
4. Commit with `Manna: mn-0a4d6c` and run `agent-do manna done mn-0a4d6c` only after the work is verified.

## Implementation receipt, 2026-09-14

Implementation and build-only validation are complete. Required executed and
live acceptance remain **PENDING**. Keep the item `in_progress`; do not infer
acceptance from compilation.

- Claim owner: `codex-01a0a306bd467040`.
- Work started at `7f672ca526f953fb9c2320612f187012fa978e92`.
- The incoming handoff and canonical Manna state both validated against
  `sha256:ce97132176592d7d59c5741453f810aa125f7921504c280c237189d2b64fe276`.
  Manna hashes normalized contents with the binding field blanked, not the raw
  file bytes.
- No repository-local `AGENTS.md` exists. The supplied global instructions,
  `.handoff/README.md`, and `docs/holy-ghostty/engineering-spec.md` governed this
  lane. Coord focus and exact path claims preceded source edits.

### Changes

1. `HolyMannaBoardPrewarmer` handles each presentation batch independently.
   Deadline and transient network errors emit a typed pending event, retry once
   at twice the initial budget, then split `12 -> 6 -> 3 -> 2/1 -> 1`.
   Successful siblings are delivered and cached; an unresolved singleton parks.
2. Retry counts bind host, board, and content hash across the entire active warm
   cycle, including refreshes queued during generation. A duplicate refresh
   cannot restart parked work. Changed content or the next warm cycle can retry.
   Successful results release their retry history. An incomplete estate remains
   eligible on its next refresh.
3. Pending events clear error presentation and reuse the existing `writing…`
   loading affordance. Usage-guard and missing-runtime refusals retain their
   message. A guard refresh queued during backoff stops further generation;
   cache-only refreshes can still explain parked items.
4. `HolyIntelligenceDeadline` supplies both the CLI and OpenAI routes. The old
   60-second invocation budget becomes an explicit startup allowance; each
   missing fast-role item adds `60 / 12 = 5` seconds. Thus a full missing batch
   receives 120 seconds, then 240 seconds on retry. Smaller salvage batches use
   their actual missing-item count with the same capped 2x multiplier. Deep-role
   requests use the existing Archive research 180-second envelope. These are
   documented scheduling choices, not measured provider throughput. Backoff
   starts at one fast-item allowance (5 seconds), doubles per miss, and caps at
   the startup allowance (60 seconds). CLI discovery consumes the same budget;
   an expired budget cannot start the model with a fresh grace interval.
5. Seven new regression functions cover ten parameterized cases: CLI/API pending
   UI state, successful retry, explicit refusals, usage protection, split salvage
   and SQLite caching, retry accounting for repeated/changed content, guard
   engagement during backoff, and unchanged-estate retry eligibility. The existing
   cache test also checks missing-item deadline forwarding and the 2x retry.
   The render-smoke fixture only gained the protocol's retry-attempt parameter.

### Focused validation

All commands ran from `/Users/erik/Custom-Coding/holy-ghostty`.

```sh
git diff --check
swiftlint lint --strict --config macos/.swiftlint.yml macos/Sources/HolyGhostty/Board/HolyMannaBoardDigest.swift macos/Sources/HolyGhostty/Board/HolyMannaBoardStore.swift macos/Tests/HolyGhostty/HolyMannaBoardTests.swift macos/Tests/HolyGhostty/HolyMannaBoardRenderSmokeTests.swift
scripts/build-holy-ghostty-core.sh verify
xcodebuild build-for-testing -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .dev/mn-0a4d6c/DerivedData -resultBundlePath .dev/mn-0a4d6c/build.xcresult -only-testing:GhosttyTests/HolyMannaBoardTests -only-testing:GhosttyTests/HolyMannaBoardActionsTests -only-testing:GhosttyTests/HolyMannaBoardPresentationTests CODE_SIGNING_ALLOWED=NO
```

- Diff whitespace check: exit 0.
- Focused SwiftLint: exit 0, zero violations across the four owned Swift files.
- Core verification: exit 0, ReleaseFast, Zig 0.15.2, input fingerprint
  `1bee2b6a6d03f263c352ee999916e5ff65dd0e18c69842f83da977401fbc607a`.
- Build for testing: exit 0, `TEST BUILD SUCCEEDED`. The xcresult records zero
  errors and 521 warnings, none in the four owned Swift files. Build action ran
  from `2026-09-15T03:26:27.564Z` to `2026-09-15T03:26:57.350Z`.
- The original Xcode process stalled during Sparkle manifest loading before the
  build action began. Process samples showed `_dyld_start`; signature verification
  passed. The stall cleared without intervention. No restart, alternate build
  path, security override, or dependency change was used.
- **Tests compiled, zero tests executed.** Xcode compiles the scheme's test
  bundles during build-for-testing. Later execution must retain the explicit
  three-suite selectors. No app launches, installs, screenshots, live session
  spawning, pushes, or pull requests occurred in this lane.
- Receipts: `.dev/mn-0a4d6c/build.log`, `build.xcresult`, `build-results.json`,
  `build-summary.json`, `swiftlint.log`, `source-sha256.json`, and the two process
  samples. Compiled object timestamps postdate the final source edits.

### Source hashes verified against the compiled inputs

| File | SHA-256 |
| --- | --- |
| `macos/Sources/HolyGhostty/Board/HolyMannaBoardDigest.swift` | `edac1552d8851baba5bf8b60cbb29e175363a93a3dc2c0fb0975e827663c6bec` |
| `macos/Sources/HolyGhostty/Board/HolyMannaBoardStore.swift` | `fa1b91458b57f954eb1b90c17620ae6a9a1f079fdac23d6cced2f1830bb981aa` |
| `macos/Tests/HolyGhostty/HolyMannaBoardTests.swift` | `97a3e47c4df5fd354ceb26695123ac5e5434267a968da4d3ad7ef2fd430f6655` |
| `macos/Tests/HolyGhostty/HolyMannaBoardRenderSmokeTests.swift` | `f6aebbf9cf5334dcdc078416a8b409cbffd7f8eed22935b485dc454b74d5342f` |

### Needed next: coordinated acceptance

Coord dependency: `mn-0a4d6c-live-acceptance`. This builder has not received an
executed test or live acceptance receipt.

1. The coordinator runs `HolyMannaBoardTests`, `HolyMannaBoardActionsTests`, and
   `HolyMannaBoardPresentationTests` through the canonical Xcode test path in the
   agreed launch window. Capture invocation counts, failures, source/commit pin,
   and the xcresult. Do not execute render-smoke tests as part of this request.
2. Through the supported candidate, open Board after a burst of real new items.
   Verify summaries appear or retain the quiet pending affordance, and no
   deadline message occupies AI SUMMARY. Confirm normal selection and usage
   refusal behavior. Do not mutate the database/cache or spawn artificial live
   workers to manufacture a pass.
3. Record the actual receipts here, reseal, and only then mark Manna done.

Lessons logged: 5 (new) | Decisions logged: 0 (new).

**TL;DR (12th grade):** The retry fix is implemented and builds successfully.
Slow items stay pending while other summaries can finish. Tests were compiled
but not run; executed and live acceptance must pass before this issue closes.
