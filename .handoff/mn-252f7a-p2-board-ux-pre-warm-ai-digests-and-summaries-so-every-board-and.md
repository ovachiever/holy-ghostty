---
workflow: 2
manna: mn-252f7a
track: mn-9a97cc
source: Erik ratified 2026-09-03 (instant-everything discussion)
base_commit: dc2bd6e0d45304bed73f217fb2ccf18bd1ab7e43
scope: '[P2][BOARD][UX] Pre-warm AI digests and summaries so every board and inspector opens fully written'
inputs:
- Erik ratified 2026-09-03 (instant-everything discussion)
binding: sha256:ab463dd5b4b68eef1585fb7ef07db675b9f440ab353e5e603b1b695874993256
---

# Handoff: [P2][BOARD][UX] Pre-warm AI digests and summaries so every board and inspector opens fully written

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-252f7a
```

## Scope

[P2][BOARD][UX] Pre-warm AI digests and summaries so every board and inspector opens fully written

## Inputs

- Erik ratified 2026-09-03 (instant-everything discussion)

## Work order

Today digests (DIGEST column one-liners) and inspector summary paragraphs generate lazily on first view via the fast role, then content-hash cache in Holy's SQLite — so the first encounter with any item shows 'writing…'. Build a pre-warm queue: after each board state refresh, a low-priority background worker generates every missing digest and summary ahead of viewing. Rules: governed by the write-pacer pattern from the archive lane (idle-priority, slows when NSApp is active — the archive freeze taught us why); focused board warms first, then the rest of the estate; content-hash keyed so the estate-wide backfill (~1,200 items across ~33 boards) is a one-time cost and only changed items ever regenerate; batched requests on the fast role; never blocks or delays the state refresh itself; cache stays in Holy's SQLite, NEVER written into .manna (AI presentation text stays out of the git ledger, agents never read it). If mn-1c1f4c-style digest attachment lands on the agent-do side (sibling ticket filed today: manna state --json attaches cached digests), prefer attached digests and generate only what is absent. Acceptance: after one warm pass, a full day of board use shows zero 'writing…' placeholders — every board and every inspector renders complete on first open; the warmer provably yields while the user is active.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-252f7a`.
4. Commit with `Manna: mn-252f7a` and run `agent-do manna done mn-252f7a` only after the work is verified.

## Implementation

- `manna state --json` digest and summary attachments are preferred. The warmer sends only missing fields to the fast role.
- A background actor warms the focused board before changed estate boards in batches of 12.
- Every batch passes through `HolyArchiveWritePacer`, including a foreground-aware delay while Holy Ghostty is active.
- One SQLite slot per host, board, and item stores both presentation fields plus the current source hash. Changed content overwrites that slot, while unchanged estate versions are not reread.
- State refresh lands before warm work and never awaits model generation. Selection reads the warmed overlay instead of starting a second generation path.

## Verification

- `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug -destination 'platform=macOS' -only-testing:GhosttyTests/HolyMannaBoardTests -only-testing:GhosttyTests/HolyMannaBoardPresentationTests test`: 30 unique tests passed, 0 failed.
- The deterministic workday replay warms 25 focused items in `12, 12, 1` batches, then the estate, records a foreground pacer delay after every batch, performs no new work across 144 unchanged estate refreshes, and performs exactly one new pass after a changed estate version.
- `./scripts/test-holy-ghostty-build-contract.sh`: passed.
- Strict SwiftLint on all six touched Swift files: 0 violations.
- Board render smoke: passed. Seven PNGs were visually inspected and copied byte-identically to `.dev/mn-252f7a/render/` and iCloud Transfer.
- Full receipt: `.dev/mn-252f7a/receipt.json`.

## Remaining acceptance

The implementation and deterministic full-day replay are green. Keep this ticket `in_progress` until one ordinary full day of live Board use records zero `writing…` sightings. A sighting is a bug receipt, not an acceptable transient.
