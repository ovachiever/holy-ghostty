---
workflow: 2
manna: mn-57866a
track: mn-9a97cc
source: Erik request 2026-09-08 13:35; deferred from mn-330752's original scope
base_commit: 78b6847ac0ff92b707d8f483d96e8996ff22294b
scope: '[P1][BOARD][AI] The grep bar is also the ask bar: question the board, get a cited answer'
inputs:
- Erik request 2026-09-08 13:35; deferred from mn-330752's original scope
binding: sha256:407c3dd5f89980b741b2dda4c8c9eacbcb7cd65b2c1e1fdfe6653d022cf64e45
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
