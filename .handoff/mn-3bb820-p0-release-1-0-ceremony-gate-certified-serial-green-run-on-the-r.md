---
workflow: 2
manna: mn-3bb820
track: mn-eb7a80
source: .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 9, §5 gate 2
base_commit: 74e8e8b0daa88cf1681b19ce560068c684fac4a5
scope: '[P0][RELEASE] 1.0 ceremony gate: certified serial green run on the release commit'
inputs:
- .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 9, §5 gate 2
binding: sha256:c1a1ca2dd74d8f29d253c9663a0b20b4ade8e44135cb9999d7780522ff810711
---

# Handoff: [P0][RELEASE] 1.0 ceremony gate: certified serial green run on the release commit

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-3bb820
```

## Scope

[P0][RELEASE] 1.0 ceremony gate: certified serial green run on the release commit

## Inputs

- .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 9, §5 gate 2

## Work order

One xcodebuild test run with -parallel-testing-enabled NO -skip-testing:GhosttyUITests -resultBundlePath on the release commit, with the failure count read from xcrun xcresulttool get test-results summary and attached to the tag item. Never a log grep: the suites are Swift Testing and grep -c "' failed" printed 0 against 8 failed cases on 09-24. Baseline 09-24 on main 3b83f7de1 (.dev/serial-2026-09-24-main-3b83f7de1.log): total 1004, passed 993, failed 8, skipped 3. The eight: dispatchNoteSurvivesTmuxDetachDiscoveryAndReadoption (mn-cf5f48); clearPopulatedStorePreservesKeyWorkspaceAndEmptyPane, both cases, and unhandledBoardCopyUsesSelectedIDAndTitleOnlyInBoard (key-window hygiene item); five HolyRosterInstantKillTests host deaths (host-death item). Done when failedTests is 0 in the summary JSON for the release commit and the GhosttyUITests skip cites its own item.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-3bb820`.
4. Commit with `Manna: mn-3bb820` and run `agent-do manna done mn-3bb820` only after the work is verified.
