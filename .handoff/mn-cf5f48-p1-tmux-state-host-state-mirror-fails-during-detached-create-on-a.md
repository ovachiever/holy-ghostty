---
workflow: 2
manna: mn-cf5f48
track: mn-eb7a80
source: null
base_commit: 8fbf2b4011048ceb5d8e075d5760080cce24e791
scope: '[P1][TMUX][STATE] Host state mirror fails during detached create on an isolated socket — dispatchNote test red since Sep 15'
inputs: []
binding: sha256:001c63d8a3de7d7e4a4343cfaebd8977bf0e3d27972ec81fb3a8412790839d12
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

## Report: 2026-09-29 build lane

Implementation commit: `e075e9bc5` (`Manna: mn-cf5f48`). Status: compiled candidate, executed acceptance pending. The dispatch work order prohibits app launches and live session spawning during this lane; no app-hosted tests were executed and this child is not done.

The original seal `sha256:31841756bec2b5cca42944252e25a5291ec979bb66ac2698ebf4bcd9ab80d4d9` matched the file and canonical Manna row before edits. Worktree `/Users/erik/Custom-Coding/holy-ghostty-mn-5fff6f` isolates source/build state at base `38643dcf4`. Manna and Coord operations remain in the primary checkout.

### Finding and change

- `HolyMannaWorkerDispatch.launchSpec` intentionally uses `exec` (introduced in `13299d37d9`). The regression fixture supplied `/usr/bin/true`, which exits immediately and removes its only pane, allowing the server to disappear before the host mirror or discovery observes it. The fixture now dispatches a disposable executable that runs `/bin/cat` on its PTY until cleanup. The production launch path remains intact.
- `HolyMannaProcessRunner` merges invocation environment overrides into the process environment. The old `environment: [:]` was not an empty process environment. Both create attempts now override `HOLY_HOST_STATE_DATABASE` with the fixture's database, avoiding the app journal.
- Cleanup is registered before creation, kills only the unique fixture socket, and removes that socket file. Creation failure stops the test at the named cause.
- Mirror subprocess errors now retain stderr and report argv plus exit status. A new Actions-suite regression compiles a failing-command check without a real tmux session.

### Verification receipts

Artifacts: `/Users/erik/Custom-Coding/holy-ghostty-mn-5fff6f/.dev/mn-5fff6f/`.

- Core payload verification passed: ReleaseFast, Zig 0.15.2, source inputs `df28bebb6ebfe4a473978513324c78da1f5148e4952f7f59d53e3806f7781141` (`core-verify.log`). Framework/resources were cloned from the primary checkout into the isolated worktree.
- Focused strict SwiftLint passed, exit 0 (`mn-cf5f48-lint.log`); `git diff --check` passed.
- First build failed, exit 65: placing DerivedData under `macos/.dev` made the canonical lint phase inspect generated Swift and Sparkle sources. `xcresulttool get build-results` reports 5 errors. Receipt: `mn-cf5f48-build-1.xcresult`, log and summary JSON. Failed outputs were archived as `failed-macos-derived-data`.
- Second build passed, exit 0, `TEST BUILD SUCCEEDED`: `mn-cf5f48-build-2.xcresult`, log and summary JSON. `xcresulttool get build-results` reports 0 errors and 533 warnings across the build. The normal lint phase remained enabled. GhosttyTests and its selected Actions suite compiled; executed test count is 0. Build-for-testing also compiled the scheme's UI test bundle but did not launch it.

Successful command, from the worktree's `macos/` directory:

```bash
only_testing=(-only-testing:GhosttyTests/HolyMannaBoardActionsTests)
xcodebuild build-for-testing -scheme Ghostty -destination 'platform=macOS' \
  -parallel-testing-enabled NO -skip-testing:GhosttyUITests "${only_testing[@]}" \
  -derivedDataPath ../.dev/DerivedData-mn-5fff6f \
  SYMROOT=/Users/erik/Custom-Coding/holy-ghostty-mn-5fff6f/.dev/mn-5fff6f/test-build \
  -resultBundlePath ../.dev/mn-5fff6f/mn-cf5f48-build-2.xcresult
```

Needed acceptance: coordinator executes the Actions suite twice consecutively using the same focused selection, serial execution, and distinct result bundles, then obtains nonzero case counts and zero failures from `xcrun xcresulttool get test-results summary --path <bundle>`. A successful build is not those two required passes. No push, installation, app launch, screenshot, or live session was performed in this lane.

Lessons logged for this child/build: 2 new (`les-528c2e`, `les-d76c03`). Decisions logged: 0 new.
