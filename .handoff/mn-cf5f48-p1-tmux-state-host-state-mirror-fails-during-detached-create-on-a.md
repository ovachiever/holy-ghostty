---
workflow: 2
manna: mn-cf5f48
track: mn-eb7a80
source: null
base_commit: 8fbf2b4011048ceb5d8e075d5760080cce24e791
scope: '[P1][TMUX][STATE] Host state mirror fails during detached create on an isolated socket — dispatchNote test red since Sep 15'
inputs: []
binding: sha256:31841756bec2b5cca42944252e25a5291ec979bb66ac2698ebf4bcd9ab80d4d9
---

# Handoff: [P1][TMUX][STATE] Host state mirror fails during detached create on an isolated socket — dispatchNote test red since Sep 15

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-cf5f48
```

## Scope

[P1][TMUX][STATE] Host state mirror fails during detached create on an isolated socket — dispatchNote test red since Sep 15

## Inputs

- None declared.

## Work order

Found 2026-09-15 during the mn-0a4d6c coordinated pass: HolyMannaBoardActionsTests/dispatchNoteSurvivesTmuxDetachDiscoveryAndReadoption fails on both parallel hosts (assertions at HolyMannaBoardActionsTests.swift:161 created.exitCode 1, :167 session missing from discovery) with stderr 'Holy host state mirror failed: CalledProcessError' — the embedded mirror python (HolyHostStateMirror.swift:114 catch) had a tmux subprocess exit nonzero during HolyTmuxCommandBuilder.detachedCreateCommand on a fresh isolated socket. DISCRIMINATORS ALREADY RUN: (1) fails identically at parent commit 7f672ca52 with the digest commit's four files reverted — NOT caused by mn-0a4d6c; (2) same test passed repeatedly on 2026-09-11 (1.3-1.6s, receipts in .dev/acceptance-c2b133-f4ab17 logs); (3) tmux is 3.7c installed Aug 22, unchanged — not tmux drift. Remaining suspects for the lane: python3 interpreter drift (macOS/CLT update between Sep 11 and 15 — check softwareupdate history and python3 --version against the mirror's subprocess usage), a mirror tmux call that races or errors on a just-created isolated server, and the test's empty environment interacting with either. Repro: run the failing test alone via -only-testing:GhosttyTests/HolyMannaBoardActionsTests (the method-level filter silently matches nothing — count cases, never trust TEST SUCCEEDED with zero run). Fix wherever the evidence lands: mirror resilience (a failed subprocess names the command and continues where safe) or test environment. Acceptance: the actions suite executes green twice consecutively; the mirror failure path prints WHICH tmux command failed, not just the exception class. Receipts: .dev/mn-0a4d6c-executed.log, .dev/mn-0a4d6c-iso2.log, .dev/mn-0a4d6c-parent.log, bundle .dev/mn-0a4d6c-executed/suites.xcresult.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-cf5f48`.
4. Commit with `Manna: mn-cf5f48` and run `agent-do manna done mn-cf5f48` only after the work is verified.
