---
workflow: 2
manna: mn-5fff6f
track: mn-5db142
source: orchestrator 2026-09-29; final gates 09-26
base_commit: b1e6cbfcbda5cd18b2871a955d1ae8857ec2b625
scope: '[P0][1.0 GATE 2] Green run: clear the four suite blockers so the certified serial run can pass'
inputs:
- orchestrator 2026-09-29; final gates 09-26
binding: sha256:9165cb192f337837dd9eeb5f43b0001244b5fbbc6168151cc05552780472c6e5
---

# Handoff: [P0][1.0 GATE 2] Green run: clear the four suite blockers so the certified serial run can pass

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-5fff6f
```

## Scope

[P0][1.0 GATE 2] Green run: clear the four suite blockers so the certified serial run can pass

## Inputs

- orchestrator 2026-09-29; final gates 09-26

## Work order

Goal: after this gate, a serial run on the release commit with the console unlocked has zero failures (09-26 baseline on 2be038009: 1112 total, 1099 passed, 10 failed, 3 skipped; the 10 are nine environmental cases plus mn-cf5f48). Children, in order: (1) mn-cf5f48, the real failing test dispatchNoteSurvivesTmuxDetachDiscoveryAndReadoption (red since 09-15, 'Holy host state mirror failed: CalledProcessError'); two lanes observed it runs with an empty environment and the debug bundle database path org.holyghostty.app.debug, start there. (2) mn-1b111a, the HolyRosterInstantKillTests host deaths; after the exact tmux targets (mn-8905ec) relaunches fell from five to one, the remaining one is staleXAfterCommandReleaseAndDisabledXNeverKill. (3) mn-76e6f0, key-window and clipboard and clear-lifecycle tests must not depend on a frontmost test host (they fail whenever the console is locked). (4) mn-3a4538, GhosttyUITests crashes at bootstrap: repair it or record the skip and its receipt in docs/holy-ghostty/engineering-spec.md section Build and Validation. Not in this gate: the certified run itself (mn-3bb820) needs the console unlocked and is the ceremony. Paths: macos/Tests/HolyGhostty for these suites, the host-state mirror code the failing test exercises, and the roster kill path only as mn-1b111a requires. Protocol. Claim this gate item first (agent-do manna claim <this id>). Then, in the order below, for each child: run agent-do manna show <child> and read its work order in .handoff/; agent-do manna claim <child>; deliver exactly that work order; run only the suites it names, serially, from macos/: xcodebuild test -scheme Ghostty -destination 'platform=macOS' -parallel-testing-enabled NO -skip-testing:GhosttyUITests -only-testing:GhosttyTests/<Suite> -derivedDataPath .dev/DerivedData-<this gate id> -resultBundlePath /tmp/<child>-<n>.xcresult, and read counts with xcrun xcresulttool get test-results summary --path <bundle>; never count failures by grepping the log; build -only-testing flags as a shell array. Commit with a conventional message and the trailer line Manna: <child>, staging by exact path; append a Report section to the child's handoff; agent-do manna handoff seal <child>; agent-do manna done <child>. When every child is done, write the gate summary (child, commit, suite counts) into this item's handoff, seal it, and done this item. Rules. Other gate agents work in this same checkout at the same time: set agent-do coord focus with your children's paths and stay inside them; if a child needs a file another gate owns, stop and report instead of editing. Never touch live app data under ~/Library/Application Support/org.holyghostty.app or the tmux socket named holy; tests use throwaway sockets and remove their socket files. Every quantity comes from an authority or a measurement, never a bare literal. No push and no installer: finish by reporting ready-to-install. Never write markdown containing a manna claim command outside .handoff/ (the shadow-handoff guard refuses claims on it). Environment: the Studio console is usually locked while Erik works from the MacBook, so tests that need a key window or a terminal surface fail for environmental reasons (NSApp.isActive false; embedded_window err=error.OutOfMemory); do not chase those unless they are your child's subject. Read the reports of the 2026-09-26 lanes in .handoff/ (mn-3c4b23 restore freshness, mn-a7baaa discovery paths, mn-8905ec exact tmux targets, mn-2c8f51 persistence writer, mn-3aeeef notification ledger, mn-59bbbf archive resolver) before changing their areas.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-5fff6f`.
4. Commit with `Manna: mn-5fff6f` and run `agent-do manna done mn-5fff6f` only after the work is verified.

## Report: 2026-09-29 build delivery, acceptance pending

The initial canonical claim succeeded as `codex-01a0ef086a247781`. The original file, frontmatter binding, canonical Manna digest, and dispatch expectation all matched `sha256:398c3b343d969f128adec4cb498f6f91b22d12388b7e8fee8336769901b26c3d`. No repository-local AGENTS.md was present; the supplied global instructions, nearest workspace guide, checked-in Xcode project, and engineering specification governed the lane.

### Outcome

| Child | Commit | Delivered change | Verified state |
| --- | --- | --- | --- |
| `mn-cf5f48` | `e075e9bc5` | Persistent synthetic dispatch worker, isolated host journal, command-specific mirror diagnostics | Actions test build and focused strict lint passed; executed tests 0; two consecutive green executions still required |
| `mn-1b111a` | `befeeb421` | Suite-lifetime core owner, deferred surface cleanup coverage, windowless kill-button guard test | Roster test build and focused strict lint passed; executed tests 0; runner-restart acceptance pending |
| `mn-76e6f0` | `2a925b3a5` | Clear window/responder invariants and Board-copy fallback independent of app activation | Clear/Clipboard test build and focused strict lint passed; executed tests 0; unattended outcomes of the three named cases pending |
| `mn-3a4538` | `59c8ef7d6` | Documented UI-target exclusion with exact retained crash receipt, also bound into `mn-3bb820` | Documentation alternative verified; child marked done. UI target remains unrepaired and was not executed |

This is a compiled candidate for coordinated acceptance. The gate remains **in_progress**, as do the first three children. It is not a certified green run. The separate full-run ceremony `mn-3bb820` remains open and unclaimed. The broader clipboard keyboard-integration tests still require an active, unlocked console; they were preserved rather than weakened or silently skipped.

### Validation

Source/build work was isolated in `/Users/erik/Custom-Coding/holy-ghostty-mn-5fff6f`, branch `fix/mn-5fff6f-green-run`, starting at `38643dcf483c9338fc15d00469e2cc696dfeed56`. Canonical Manna and Coord stayed in this primary checkout. Only owned source patches were applied and committed here, by exact path. Other workers' source, handoffs, and ledger rows were preserved.

The canonical `xcodebuild build-for-testing` command ran serially from the isolated worktree's `macos/`, with `-scheme Ghostty -destination 'platform=macOS' -parallel-testing-enabled NO -skip-testing:GhosttyUITests`, a shell array of suite-level `-only-testing:` arguments, `-derivedDataPath ../.dev/DerivedData-mn-5fff6f`, and isolated `SYMROOT` plus distinct result bundles. Exact commands are in each child's Report above. Build-for-testing compiles the scheme's test bundles; it does not execute the selected suites.

Receipts copied to this repository's `.dev/mn-5fff6f/`:

| Final build receipt | Selected suites | Result from xcresulttool get build-results |
| --- | --- | --- |
| `mn-cf5f48-build-2.xcresult` | `HolyMannaBoardActionsTests` | succeeded, 0 errors, 533 warnings |
| `mn-1b111a-build-2.xcresult` | `HolyRosterInstantKillTests` | succeeded, 0 errors, 497 warnings |
| `mn-76e6f0-build-1.xcresult` | `HolyWorkspaceClearLifecycleTests`, `HolyModeClipboardTests` | succeeded, 0 errors, 497 warnings |

The earlier `mn-cf5f48-build-1.xcresult` remains a failed receipt: 5 build errors came from generated/dependency sources because the original `macos/.dev` output location fell inside the lint scan root. The failed cache was archived in the worktree and the build was rerun with outputs at repository-root `.dev`; no lint bypass was used. All owned files passed focused strict SwiftLint and `git diff --check`.

`scripts/build-holy-ghostty-core.sh verify` passed against cloned ReleaseFast/Zig 0.15.2 inputs `df28bebb6ebfe4a473978513324c78da1f5148e4952f7f59d53e3806f7781141`. `source-receipt.json` records SHA-256 hashes proving the five integrated source/test files match the files compiled in the isolated worktree. These receipts do not certify unrelated concurrent changes or replace the final release-commit run.

### Needed next: coordinated acceptance

1. Stop concurrent edits and agree on the console window before any app-hosted execution, installation, screenshot, or live session. The lane performed none of those actions.
2. Execute `HolyMannaBoardActionsTests` twice consecutively. Both result bundles must have nonzero executed cases and zero failures, and the diagnostics regression must run.
3. Execute `HolyRosterInstantKillTests` serially. Check all five historical cases plus the new teardown regression; no test-host restart may be hidden by retries.
4. Execute `HolyWorkspaceClearLifecycleTests` and `HolyModeClipboardTests` serially. Verify both Clear parameter cases and the Board fallback case; the real keyboard integration requires the active console. Read all counts from `xcrun xcresulttool get test-results summary --path <bundle>`.
5. Only after those required results are verified, close the first three children and this gate. The full certified serial run on the final release commit remains `mn-3bb820`, with the explicit `mn-3a4538` exclusion receipt. No push, PR, tag, or installation is authorized by these build receipts.

Reports and receipts are also delivered to `~/Library/Mobile Documents/com~apple~CloudDocs/Transfer/Holy-Ghostty-mn-5fff6f/`; a report copy is saved to the Erkverse vault under `+/2026-09-29 Holy Ghostty Gate 2 build delivery.md`.

Lessons logged: 4 new (`les-528c2e`, `les-d76c03`, `les-8ef18f`, `les-b97426`). Decisions logged: 0 new. `agent-do zpc harvest` reported 0 format issues. Optional backlog: none added.
