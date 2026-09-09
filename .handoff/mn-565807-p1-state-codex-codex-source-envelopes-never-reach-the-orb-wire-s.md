---
workflow: 2
manna: mn-565807
track: mn-eb7a80
source: Erik screenshot 2026-09-09 12:57 + live pane %31 wire receipts this session
base_commit: 1b9e7ee09b4408e7ebd65abcb0ba4743c6dadf65
scope: '[P1][STATE][CODEX] Codex-source envelopes never reach the orb: wire says working, roster shows idle'
inputs:
- Erik screenshot 2026-09-09 12:57 + live pane %31 wire receipts this session
binding: sha256:90d04a1bdd4fd7f08d9163f4d362acc5cf1dd1e251487189e37a62b3f5b40763
---

# Handoff: [P1][STATE][CODEX] Codex-source envelopes never reach the orb: wire says working, roster shows idle

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-565807
```

## Scope

[P1][STATE][CODEX] Codex-source envelopes never reach the orb: wire says working, roster shows idle

## Inputs

- Erik screenshot 2026-09-09 12:57 + live pane %31 wire receipts this session

## Work order

Erik 2026-09-09 12:57: a codex session visibly working ('• Working (1m 23s • esc to interrupt)' in-pane, braille spinner in the tmux title) shows an idle/seen dot in the roster. Receipt from the live pane (%31, holy-worker-bf685295): @holy_agent_state_v1 = 'v1|codex|working|1788976557066|...|01a086b7-...' — current, working, correct codex identity; the hooks and wire are doing everything right (and the codex identity capture from b5287393c is proven live here). The defect is display-side: the envelope-to-indicator path evidently consumes only claude-source wires (pane-scrape vocabulary for codex's Working line and the braille title exist in HolySession but are outvoted or gated), so codex rows fall back to idle. Fix: the six-state indicator pipeline treats a valid envelope identically regardless of source runtime — codex working lights the throbber, codex finished earns the unread dot, needs-user/failed behave exactly as claude's; keep the d204ae precedence/decay laws source-agnostic. Extend HolySessionLiveStatusTests/monitor tests with this exact captured codex wire triplet (state/last_used/last_finished above) asserting the orb outcome per state. Acceptance: a dispatched codex worker shows the working throbber within one poll of the wire flipping, on the live app. Relates: mn-f0b1cc (codex hooks degraded-state surfacing) stays separate — hooks here are healthy.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-565807`.
4. Commit with `Manna: mn-565807` and run `agent-do manna done mn-565807` only after the work is verified.

## Implementation and verification receipt, 2026-09-09

Outcome: implementation committed locally as `a083696b0` on `main`. Required
live acceptance is still pending, so this item remains `in_progress`, claimed
by `codex-01a08753cbed7b33`. No `manna done` was run.

The initial claim succeeded. Before editing, the computed binding, handoff
frontmatter, canonical `agent-do manna state --json` row, and requested digest
all matched `sha256:0ee9c6a44ba4a2b6f045ec5bc00e291a5e6458ae4ad3913f4a8bf552fc2954e2`.
This continuation is intentionally resealed after adding these receipts.

### Root cause and change

The envelope decoder, register election, session ingestion, and orb policy
already accept all sources. The runtime-specific defect was in
`HolyTmuxAgentStateMonitor.parse`: a shell foreground command produced unknown
process evidence for Claude, but false (producer exited) for Codex and every
other source. False suppresses even a fresh working envelope in the indicator
policy. A read-only inspection of the reported pane confirmed the exact
combination: valid Codex working wire, `pane_dead=0`, and
`pane_current_command=bash`.

The monitor now treats shell foreground evidence as unknown for every source.
Dead panes still prove exit. The existing 30-minute working lease, expired
lease scrape fallback, register precedence, conflict handling, and seen/unread
laws remain in force. A shell alone cannot distinguish a tool child from an
exited harness, so that case relies on lifecycle events and lease expiry.

Changed files:

- `macos/Sources/HolyGhostty/AgentState/HolyTmuxAgentStateMonitor.swift`: remove
  the source-specific shell veto, correct its comments, and remove a redundant
  optional nil initializer required by strict SwiftLint.
- `macos/Tests/HolyGhostty/AgentState/HolyTmuxAgentStateMonitorTests.swift`:
  preserve the complete captured triplet and test shell/dead-pane evidence for
  Claude, Codex, OpenCode, and an unknown future source.
- `macos/Tests/HolyGhostty/HolySessionLiveStatusTests.swift`: use the production
  monitor, attention metadata, and indicator policy to assert lifecycle and
  six-state roster parity, first-poll working over seen/idle evidence, lease
  expiry, dead panes, acknowledgement, and recency aging. Preserve the exact
  captured `• Working (1m 23s • esc to interrupt)` line.

### Exact fixture provenance

The filing probe used `cut -c1-110`; its original working event
`1788976557066-80034` is truncated after the initial `t` of its reason code.
Those missing bytes were not invented. Read-only inspection of the same
`holy-worker-bf685295-f346-4ac5-9344-c259da0c7995`, pane `%31`, recovered the
original prompt and finish events in full and captured this newer working
event. The tests explicitly label alternate sources/lifecycles as mutations
and use a fixed test observation clock.

```text
@holy_agent_state_v1 v1|codex|working|1788976911699|1788976911699-48023|01a086b7-655d-7993-b433-4a9c7e18191f|tool-complete
@holy_agent_last_used_v1 v1|codex|working|1788976540068|1788976540068-69719|01a086b7-655d-7993-b433-4a9c7e18191f|user-prompt
@holy_agent_last_finished_v1 v1|codex|finished|1788975832632|1788975832632-60460|01a086b7-655d-7993-b433-4a9c7e18191f:01a08719-4003-7a82-88c0-0f1a26f655e4|turn-finished
@holy_seen_v1 v1|seen|1788976911699|1788976911888
```

### Focused validation

Built in the isolated checkout
`/Users/erik/Custom-Coding/holy-ghostty-codex-mn-565807`, based on `f995436b4`.
Canonical Manna and Coord operations stayed in the primary checkout. Existing
local GhosttyKit and generated resources were copied into the isolated tree;
Debug app/test compilation used the repository's Xcode scheme and its normal
build phases. No release/install gate was bypassed or claimed as passed.

```sh
git diff --check
swiftlint lint --strict --config macos/.swiftlint.yml \
  macos/Sources/HolyGhostty/AgentState/HolyTmuxAgentStateMonitor.swift \
  macos/Tests/HolyGhostty/AgentState/HolyTmuxAgentStateMonitorTests.swift \
  macos/Tests/HolyGhostty/HolySessionLiveStatusTests.swift
/usr/bin/xcodebuild -quiet -project macos/Ghostty.xcodeproj \
  -scheme Ghostty -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .dev/DerivedData-mn-565807 \
  -only-testing:GhosttyTests/HolyAgentStateEnvelopeTests \
  -only-testing:GhosttyTests/HolyTmuxAgentStateMonitorTests \
  -only-testing:GhosttyTests/HolySessionIndicatorPolicyTests \
  -only-testing:GhosttyTests/HolySessionLiveStatusTests \
  build-for-testing CODE_SIGNING_ALLOWED=NO
```

Actual results: diff check exit 0; strict lint exit 0, zero violations across
the three owned Swift files; final build-for-testing exit 0. Xcode compiles
the scheme's app and test targets, including these four selected suites.
Tests executed: **zero**. Existing warnings in unrelated Swift/concurrency,
core debug symbols, and UI-test deployment targets remain. No app launch,
install, screenshot, GUI automation, or provider-session spawn was performed.

The three integrated files were compared byte-for-byte with the verified
isolated sources before the implementation commit. Other source/build inputs
in the primary checkout had no differences from the isolated base. Foreign
documentation edits were preserved and excluded from staging.

Receipts in the primary checkout:

- `.dev/mn-565807/verification.json`: implementation commit, source hashes,
  build results, and explicit zero execution count.
- `.dev/mn-565807/build-for-testing.log`: final Xcode build output.
- `.dev/mn-565807/swiftlint.log`: final strict lint output.

### Required acceptance and close boundary

Coordinate a shared live-validation window through Coord need
`mn-565807-live-acceptance` before any app-hosted test execution, install, or
live worker dispatch. Publish the local build as ready for acceptance, not as
completed acceptance. The required pass must:

1. Execute the four focused suites through the canonical Xcode test path in
   that authorized window; compilation above is not execution evidence.
2. Use the supported build/install path for the candidate and verify that a
   dispatched Codex worker's working wire produces the working throbber within
   one monitor poll, including while tmux samples a shell tool child.
3. Check finished/unread, question/permission demand, failure acknowledgement,
   and the existing lease/precedence behavior without manufacturing live
   success through manual register edits.
4. Add the actual acceptance receipts, reseal this handoff, and only then run
   `agent-do manna done mn-565807` from the primary checkout.

Lessons logged: 5 (new) | Decisions logged: 0 (new).
Lesson IDs: `les-fcf9ea`, `les-5603ad`, `les-61b2be`, `les-acb3a7`, `les-c04356`.
