---
workflow: 2
manna: mn-3a4538
track: mn-eb7a80
source: .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 7; 09-23 handoff §10 item 5
base_commit: 74e8e8b0daa88cf1681b19ce560068c684fac4a5
scope: '[P2][TESTS] GhosttyUITests target crashes at bootstrap; every serial run must skip it'
inputs:
- .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 7; 09-23 handoff §10 item 5
binding: sha256:073202e9785507de07d2c196e2c77c749d10ce8fbbac29d9174330a58e7abb4b
---

# Handoff: [P2][TESTS] GhosttyUITests target crashes at bootstrap; every serial run must skip it

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-3a4538
```

## Scope

[P2][TESTS] GhosttyUITests target crashes at bootstrap; every serial run must skip it

## Inputs

- .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 7; 09-23 handoff §10 item 5

## Work order

Serial runs die unless -skip-testing:GhosttyUITests is passed: the target exits before establishing a connection (09-23 handoff §10 item 5: early unexpected exit, crashed with signal kill). Either repair the target so it bootstraps, or record the skip in the release runbook (docs/holy-ghostty/engineering-spec.md §Build and Validation) and in the certified-run item with the crash receipt. Done when a serial run completes without the skip, or the runbook carries the skip and its receipt.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-3a4538`.
4. Commit with `Manna: mn-3a4538` and run `agent-do manna done mn-3a4538` only after the work is verified.

## Report: 2026-09-29 documented exclusion

Documentation commit: `59c8ef7d6` (`Manna: mn-3a4538`). The work order's documentation alternative is satisfied: the release runbook retains `-skip-testing:GhosttyUITests` and links this exact crash receipt; the canonical certified-run item `mn-3bb820` and its handoff carry the same receipt. The UI target itself is not repaired and no UI tests were executed in this lane.

The original handoff binding `sha256:000bfd7644252ddc9e8c30cd59733be2b20a1f330e68fc1b578e9a6ac24759fc` matched canonical Manna. Gate 7's documentation owner stopped at `2026-09-29T21:36:11Z`; a fresh Coord guard check reported no live conflict before this lane claimed the runbook path. Its committed release procedure was preserved, with only the failure-receipt link and coverage qualification added.

### Preserved crash receipt

- Original run: 2026-09-23; result bundle `/Users/erik/Custom-Coding/holy-ghostty/.dev/release-readiness/full.xcresult`.
- Original log: `.dev/release-readiness-full.log`, line 1356. SHA-256: `e24828b6745f3003116644402a49135e696943d4dcbd917f5d8c831ae6be297e`.
- Exact diagnostic: `GhosttyUITests-Runner (79405) encountered an error (Early unexpected exit, operation never finished bootstrapping - no restart will be attempted. (Underlying Error: Test crashed with signal kill before establishing connection.))`.
- The log's invocation ran `xcodebuild ... test CODE_SIGNING_ALLOWED=NO` without the UI-target exclusion. It records `TEST FAILED`. This historical invocation is failure evidence, not the current certification command.
- `xcrun xcresulttool get test-results summary --path .dev/release-readiness/full.xcresult --compact` was read again without executing tests; its result is `Failed`. The retained output is `.dev/mn-5fff6f/mn-3a4538-historical-test-summary.json`. It is a historical whole-run summary, not a new suite run and not evidence that every failure came from UI bootstrap.

### Verification and remaining coverage

`git diff --check` passed. The runbook's relative receipt link resolves to this tracked handoff and its report heading. The original log hash, error line, result-bundle existence, and the receipt in canonical `mn-3bb820` were verified. No bootstrap repair or new execution is claimed. The exclusion remains explicit in the release ceremony, where every other skip needs its own reason and the final nonempty GhosttyTests serial run must have zero failures on the exact release commit.

Lessons logged: 0 new. Decisions logged: 0 new. No application launch, installation, screenshot, live session, push, or PR occurred.
