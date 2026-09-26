---
workflow: 2
manna: mn-1b111a
track: mn-eb7a80
source: .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 8; 09-23 handoff §10 item 6
base_commit: 74e8e8b0daa88cf1681b19ce560068c684fac4a5
scope: '[P1][TESTS] HolyRosterInstantKillTests kills the test host: five relaunches per serial run'
inputs:
- .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 8; 09-23 handoff §10 item 6
binding: sha256:d6541994c90b891816977850dd4ab47456919ad0621e97e175997ceccedd27f0
---

# Handoff: [P1][TESTS] HolyRosterInstantKillTests kills the test host: five relaunches per serial run

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-1b111a
```

## Scope

[P1][TESTS] HolyRosterInstantKillTests kills the test host: five relaunches per serial run

## Inputs

- .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 8; 09-23 handoff §10 item 6

## Work order

09-24 serial run (.dev/serial-2026-09-24-main-3b83f7de1.log): the host restarted at staleXAfterCommandReleaseAndDisabledXNeverKill, commandDeleteChainsInDisplayedOrder(.classic), commandDeletePreservesTextEditingAndIgnoresKeyRepeat, remoteKillIdentityRetainsTransportAndExactTarget, and remoteRowWithoutTmuxIdentityFailsInlineWithoutDetaching; the xcresult records each as the test runner exited with code 1. Same five relaunches on 09-23 (.dev/mn-0b49e9-serial2.log, one name differs: windowResignAndModifierReleaseClearCommand), so it is the suite, not one test. Likely the mechanism in les-898c86 (a window close lets applicationShouldTerminateAfterLastWindowClosed quit the host); the clipboard fixture repair e57ec0afa shows the shape of the fix. Done when a serial run has zero Restarting after unexpected exit lines and each of the five reports pass or a real expectation failure.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-1b111a`.
4. Commit with `Manna: mn-1b111a` and run `agent-do manna done mn-1b111a` only after the work is verified.
