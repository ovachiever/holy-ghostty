---
workflow: 2
manna: mn-5fff6f
track: mn-5db142
source: orchestrator 2026-09-29; final gates 09-26
base_commit: b1e6cbfcbda5cd18b2871a955d1ae8857ec2b625
scope: '[P0][1.0 GATE 2] Green run: clear the four suite blockers so the certified serial run can pass'
inputs:
- orchestrator 2026-09-29; final gates 09-26
binding: sha256:398c3b343d969f128adec4cb498f6f91b22d12388b7e8fee8336769901b26c3d
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
