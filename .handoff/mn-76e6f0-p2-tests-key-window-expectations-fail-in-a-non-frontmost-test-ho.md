---
workflow: 2
manna: mn-76e6f0
track: mn-eb7a80
source: .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 8; 09-23 handoff §10 item 7
base_commit: 74e8e8b0daa88cf1681b19ce560068c684fac4a5
scope: '[P2][TESTS] Key-window expectations fail in a non-frontmost test host (Clear lifecycle, clipboard)'
inputs:
- .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 8; 09-23 handoff §10 item 7
binding: sha256:73d0a04df8d6d2311c19d2b3242fdd1bb1b500edf2f19746cff0cac6492fd3df
---

# Handoff: [P2][TESTS] Key-window expectations fail in a non-frontmost test host (Clear lifecycle, clipboard)

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-76e6f0
```

## Scope

[P2][TESTS] Key-window expectations fail in a non-frontmost test host (Clear lifecycle, clipboard)

## Inputs

- .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 8; 09-23 handoff §10 item 7

## Work order

clearPopulatedStorePreservesKeyWorkspaceAndEmptyPane(quitAfterLastWindow:) fails both cases at HolyWorkspaceClearLifecycleTests.swift:99 and :109 (isKeyWindow is false); unhandledBoardCopyUsesSelectedIDAndTitleOnlyInBoard fails at HolyModeClipboardTests.swift:285 (general pasteboard nil) for the same reason. Red on 09-23 (.dev/rr-clear-alone.log, .dev/mn-0b49e9-serial2.log) and 09-24 (.dev/serial-2026-09-24-main-3b83f7de1.log). Test hygiene: assert on the responder chain or activate the host explicitly, not on isKeyWindow of a background process. Done when all three cases pass in an unattended serial run.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-76e6f0`.
4. Commit with `Manna: mn-76e6f0` and run `agent-do manna done mn-76e6f0` only after the work is verified.
