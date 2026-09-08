---
workflow: 2
manna: mn-57866a
track: mn-9a97cc
source: Erik request 2026-09-08 13:35; deferred from mn-330752's original scope
base_commit: 78b6847ac0ff92b707d8f483d96e8996ff22294b
scope: '[P1][BOARD][AI] The grep bar is also the ask bar: question the board, get a cited answer'
inputs:
- Erik request 2026-09-08 13:35; deferred from mn-330752's original scope
binding: sha256:7ff727a598c7002aecbcbefc3b0b7be1ef2ac9ccc19d97ced31346b953c67102
---

# Handoff: [P1][BOARD][AI] The grep bar is also the ask bar: question the board, get a cited answer

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-57866a
```

## Scope

[P1][BOARD][AI] The grep bar is also the ask bar: question the board, get a cited answer

## Inputs

- Erik request 2026-09-08 13:35; deferred from mn-330752's original scope

## Work order

Erik 2026-09-08: the native board's top bar should match the web cockpit's full behavior — 'ask AI · grep · ⌘K'. Typing stays the instant client-side grep over id/title/digest/track/claimant/description exactly as today; pressing ENTER sends the query plus the current board state to the deep intelligence role and renders the answer in the inspector column with cited mn- ids. Port the web's honesty law verbatim (serve digest.py ask pattern): only ids present in the rows given to the model may come back as citations; cited ids become a '$ manna cited' filter section the user can click through, mirroring app.js. Answer text is display-only — asking never mutates (glance law). Use Holy's existing role routing (deep chain, plan-first default with API models selectable), a visible thinking state in the inspector, a 60s bound with a typed timeout message, and the answer cached per (question, board content-hash) so re-asking is instant. Cmd-K focuses the bar from anywhere in board mode. Tests: citation allowlist enforcement (a hallucinated id is dropped), grep-vs-ask routing on Enter, timeout rendering.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-57866a`.
4. Commit with `Manna: mn-57866a` and run `agent-do manna done mn-57866a` only after the work is verified.

## Implementation receipt (2026-09-08)

Implemented the native ask bar with the verbatim web ASK_SYSTEM, a full row snapshot including done items, allowlisted citations, clickable `manna cited` rows, typed 60-second timeout, cancellation/generation guards, and a bounded in-memory cache keyed by normalized question, row content hash, board identity, and selected model. Typing remains grep; only Enter asks. Cmd-K is handled both by the board and workspace key paths. Answers are plain display text; unknown IDs are omitted and no mutation capability reaches the asker.

The existing role router now defaults board deep work to plan-backed Claude opus. Explicit `gpt-` or `openai/` models use the existing native API client with tools disabled. The archive's separate default is preserved. No model request was executed in this lane.

Validation: focused `xcodebuild build-for-testing` succeeded for HolyMannaBoardActionsTests, HolyMannaBoardTests, and HolyMannaBoardPresentationTests. The new actions suite contains 9 regression cases shared with mn-ec34cd. These are compilation receipts, not executed tests. ReleaseLocal and core verification receipts are in `.dev/mn-board-actions/report.md`.

Needed next: coordinated installed-app acceptance of Cmd-K, instant grep, Enter/thinking/answer, citation navigation, cache reuse/invalidation, and explicit API-model routing. Execute the focused app-hosted tests only in that coordinated lane. Keep this item in_progress until that acceptance is recorded.

## Executed regression repair (2026-09-08)

The user authorized app-hosted test execution after the first implementation failed its default-parallel safety suite. This receipt supersedes the earlier compile-only test status.

Root cause: HolyMannaBinaryResolver set didResolve before awaiting the shell lookup. Concurrent callers observed cached nil and failed with `The agent-do CLI was not found in the runtime environment Holy uses.` The test polling helper concealed that first failure behind an eventual timeout. The Claude resolver had the same pending-versus-missing error.

Fix: both runtimes now use HolyBoardExecutableResolver, which retains one lookup Task and makes every caller await its completed result. No suite serialization or timeout increase was used. Tests now abort setup on a board-read error and preserve the error in the result bundle. Two new tests check concurrent successful and genuinely missing lookups with 16 callers each.

Executed using default parallel testing: HolyMannaBoardActionsTests PASSED 11, FAILED 0, SKIPPED 0 (all original 9 plus 2 new). A final combined run of HolyMannaBoardActionsTests, HolyMannaBoardTests, and HolyMannaBoardPresentationTests PASSED 41, FAILED 0, SKIPPED 0. Both build-for-testing and test-without-building succeeded. Result bundles: `.dev/mn-board-actions/fixed-actions.xcresult` and `.dev/mn-board-actions/fixed-related.xcresult`. Detailed reproduction, commands, and counts: `.dev/mn-board-actions/regression-report.md`.

Both items remain in_progress as requested. The safety-suite repair is complete; the remaining coordinated feature acceptance described above is still pending. No install, worker dispatch, model request, or push was performed in this repair lane. Lessons logged: 1 (new), les-8741f0. Decisions logged: 0 (new).
