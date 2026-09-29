---
workflow: 2
manna: mn-f92871
track: mn-5db142
source: orchestrator 2026-09-29; 09-24 handoff section 3
base_commit: b1e6cbfcbda5cd18b2871a955d1ae8857ec2b625
scope: '[P0][1.0 GATE 3] Restore and roster truth at fleet size'
inputs:
- orchestrator 2026-09-29; 09-24 handoff section 3
binding: sha256:daf14001d6e637b5bbd1d2a99a039a6df66382936fb62cf3bbcc3ddb72ef4094
---

# Handoff: [P0][1.0 GATE 3] Restore and roster truth at fleet size

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-f92871
```

## Scope

[P0][1.0 GATE 3] Restore and roster truth at fleet size

## Inputs

- orchestrator 2026-09-29; 09-24 handoff section 3

## Work order

Goal: the roster and restore tell the truth with 40 to 60 sessions across hosts. Children, in order, first the discovery cluster then the state cluster: (1) mn-27d9fd, local tmux discovery times out at a 5 s literal at fleet size (logged 12 times an hour on 09-26 with 36 to 49 sessions); derive the bound from a measurement or make discovery incremental. (2) mn-569b91, reconcile known sessions and reap true orphans safely. (3) mn-12801a, Sync adopts never-seen Holy sessions from every host. (4) mn-56f896, preserve notes, Today pins, titles, and identity across lifecycle. (5) mn-a0406e, launch-time focus churn marks every session seen and used. (6) mn-cf5fb6, restore stalled and looping agent alerts via working-lease expiry. (7) mn-ede22a, a failed surface init (engine err=error.OutOfMemory, reproducible under a locked console) must never leave a row claiming a ready shell; create the tmux session detached first so the launch survives. Paths: macos/Sources/HolyGhostty/Remote, Session, Workspace (roster, attention, spawn regions), AgentState, Supervisor, and their tests; do not edit Restore/, Archive/, Board/, Tmux/HolyTmuxCommandBuilder.swift, Persistence/, or Database/ without stopping to report. Protocol. Claim this gate item first (agent-do manna claim <this id>). Then, in the order below, for each child: run agent-do manna show <child> and read its work order in .handoff/; agent-do manna claim <child>; deliver exactly that work order; run only the suites it names, serially, from macos/: xcodebuild test -scheme Ghostty -destination 'platform=macOS' -parallel-testing-enabled NO -skip-testing:GhosttyUITests -only-testing:GhosttyTests/<Suite> -derivedDataPath .dev/DerivedData-<this gate id> -resultBundlePath /tmp/<child>-<n>.xcresult, and read counts with xcrun xcresulttool get test-results summary --path <bundle>; never count failures by grepping the log; build -only-testing flags as a shell array. Commit with a conventional message and the trailer line Manna: <child>, staging by exact path; append a Report section to the child's handoff; agent-do manna handoff seal <child>; agent-do manna done <child>. When every child is done, write the gate summary (child, commit, suite counts) into this item's handoff, seal it, and done this item. Rules. Other gate agents work in this same checkout at the same time: set agent-do coord focus with your children's paths and stay inside them; if a child needs a file another gate owns, stop and report instead of editing. Never touch live app data under ~/Library/Application Support/org.holyghostty.app or the tmux socket named holy; tests use throwaway sockets and remove their socket files. Every quantity comes from an authority or a measurement, never a bare literal. No push and no installer: finish by reporting ready-to-install. Never write markdown containing a manna claim command outside .handoff/ (the shadow-handoff guard refuses claims on it). Environment: the Studio console is usually locked while Erik works from the MacBook, so tests that need a key window or a terminal surface fail for environmental reasons (NSApp.isActive false; embedded_window err=error.OutOfMemory); do not chase those unless they are your child's subject. Read the reports of the 2026-09-26 lanes in .handoff/ (mn-3c4b23 restore freshness, mn-a7baaa discovery paths, mn-8905ec exact tmux targets, mn-2c8f51 persistence writer, mn-3aeeef notification ledger, mn-59bbbf archive resolver) before changing their areas.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-f92871`.
4. Commit with `Manna: mn-f92871` and run `agent-do manna done mn-f92871` only after the work is verified.
