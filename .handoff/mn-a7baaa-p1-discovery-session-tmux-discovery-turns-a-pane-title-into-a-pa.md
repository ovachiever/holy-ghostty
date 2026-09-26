---
workflow: 2
manna: mn-a7baaa
track: mn-eb7a80
source: session_events 985BC829 seq 166-167; lane mn-9682f6 report
base_commit: 86874c4c760c01889ef349a037ecded06d9bcd53
scope: '[P1][DISCOVERY][SESSION] tmux discovery turns a pane title into a path component and overwrites the session''s recorded working directory'
inputs:
- session_events 985BC829 seq 166-167; lane mn-9682f6 report
binding: sha256:a1915f9d6fdd7cc5a28e9245bdc7b4b82f6d5529920e70258b1e25c87abe02e7
---

# Handoff: [P1][DISCOVERY][SESSION] tmux discovery turns a pane title into a path component and overwrites the session's recorded working directory

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-a7baaa
```

## Scope

[P1][DISCOVERY][SESSION] tmux discovery turns a pane title into a path component and overwrites the session's recorded working directory

## Inputs

- session_events 985BC829 seq 166-167; lane mn-9682f6 report

## Work order

Receipt, row 985BC829 (versova-supply-intelligence, codex, created 2026-09-23T13:40Z with working directory /Users/erik/Custom-Coding/versova-supply-intelligence, kept through event 165): event 166 at 2026-09-24T20:58:33Z session_runtime_updated carries workingDirectory /Users/erik/Custom-Coding (the pane had moved to the parent), event 167 at 20:58:49Z carries /Users/erik/Custom-Coding/⠸ Research Comprehensive App Security | Custom-Coding, which is the parent plus the Codex window title with its spinner glyph; the row and its resume metadata lastKnownWorkingDirectory still hold that string (without the glyph) and the restore sheet showed the row as unrestorable on 2026-09-26. Source, established by lane mn-9682f6: HolyRemoteTmuxDiscoveryService.swift:717-721 inferred_working_directory appends a candidate taken from pane_title or window_name when pane_current_path ends in a generic folder name (custom-coding, projects, and similar); the candidate filter rejects only a slash; HolySession.swift:653-655 then writes the inferred value into record.launchSpec.workingDirectory. Deliver: (1) inferred_working_directory never emits a path that does not exist on the host: a title-derived candidate is accepted only when base/candidate is an existing directory there (local FileManager, or test -d over the managed control lane for remote hosts, the same probe shape lane mn-9682f6 added to Board), otherwise the pane's real path stands; titles carrying spinner or status glyphs or a pipe are never path material; (2) HolySession never overwrites a launch spec working directory that Holy set at creation with an inferred one; an observed pane directory is recorded as observed state (resume metadata lastKnownWorkingDirectory) only when it exists, and the launch spec keeps the creation value; (3) tests: a discovery fixture whose pane reports cwd /tmp/<base> and title '⠸ Research Comprehensive App Security | Custom-Coding' yields /tmp/<base>; the same fixture with an existing /tmp/<base>/Research directory and title 'Research' yields that directory; a session created with directory X keeps X after discovery reports a non-existent Y, and records Y as observed when Y exists. Own macos/Sources/HolyGhostty/Remote/HolyRemoteTmuxDiscoveryService.swift, macos/Sources/HolyGhostty/Session/HolySession.swift, and their test files only; Restore/, Archive/, Board/, and Workspace/ belong to other lanes.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-a7baaa`.
4. Commit with `Manna: mn-a7baaa` and run `agent-do manna done mn-a7baaa` only after the work is verified.
