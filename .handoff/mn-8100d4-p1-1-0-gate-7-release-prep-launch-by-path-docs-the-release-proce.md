---
workflow: 2
manna: mn-8100d4
track: mn-5db142
source: orchestrator 2026-09-29; 09-24 handoff section 5 gate 7
base_commit: b1e6cbfcbda5cd18b2871a955d1ae8857ec2b625
scope: '[P1][1.0 GATE 7] Release prep: launch-by-path docs, the release procedure, and the 1.0 changelog section'
inputs:
- orchestrator 2026-09-29; 09-24 handoff section 5 gate 7
binding: sha256:3bcd71bec1bd5cb606261bb3e365fea99a3fb9f2aaf447b1b2c874597b581da4
---

# Handoff: [P1][1.0 GATE 7] Release prep: launch-by-path docs, the release procedure, and the 1.0 changelog section

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-8100d4
```

## Scope

[P1][1.0 GATE 7] Release prep: launch-by-path docs, the release procedure, and the 1.0 changelog section

## Inputs

- orchestrator 2026-09-29; 09-24 handoff section 5 gate 7

## Work order

Goal: everything for the tag except the certified run, the screenshots, and the tag itself, which are Erik's. Children and tasks, in order: (1) mn-f4546f, launch the installed app by path, never by name: README.md line 129 still says open -a Holy Ghostty; fix README, the engineering spec, and the installer's final launch. (2) Extend docs/holy-ghostty/engineering-spec.md section Build and Validation with the release procedure as it is now: engine core only via CI ReleaseFast and scripts/build-holy-ghostty-core.sh import, scripts/install-holy-ghostty.sh, launch by path, the certified serial run command with -resultBundlePath and the xcresulttool count, the GhosttyUITests skip, and the tag step. (3) Prepare the 1.0.0 section of CHANGELOG.md as an HTML comment directly above Unreleased (version, date placeholder, one-paragraph summary drawn from the existing entries); do not rename Unreleased, that happens at the tag. Paths: README.md, CHANGELOG.md, docs/holy-ghostty/, scripts/install-holy-ghostty.sh only. For tasks 2 and 3 commit with the trailer Manna: <this gate id>. Protocol. Claim this gate item first (agent-do manna claim <this id>). Then, in the order below, for each child: run agent-do manna show <child> and read its work order in .handoff/; agent-do manna claim <child>; deliver exactly that work order; run only the suites it names, serially, from macos/: xcodebuild test -scheme Ghostty -destination 'platform=macOS' -parallel-testing-enabled NO -skip-testing:GhosttyUITests -only-testing:GhosttyTests/<Suite> -derivedDataPath .dev/DerivedData-<this gate id> -resultBundlePath /tmp/<child>-<n>.xcresult, and read counts with xcrun xcresulttool get test-results summary --path <bundle>; never count failures by grepping the log; build -only-testing flags as a shell array. Commit with a conventional message and the trailer line Manna: <child>, staging by exact path; append a Report section to the child's handoff; agent-do manna handoff seal <child>; agent-do manna done <child>. When every child is done, write the gate summary (child, commit, suite counts) into this item's handoff, seal it, and done this item. Rules. Other gate agents work in this same checkout at the same time: set agent-do coord focus with your children's paths and stay inside them; if a child needs a file another gate owns, stop and report instead of editing. Never touch live app data under ~/Library/Application Support/org.holyghostty.app or the tmux socket named holy; tests use throwaway sockets and remove their socket files. Every quantity comes from an authority or a measurement, never a bare literal. No push and no installer: finish by reporting ready-to-install. Never write markdown containing a manna claim command outside .handoff/ (the shadow-handoff guard refuses claims on it). Environment: the Studio console is usually locked while Erik works from the MacBook, so tests that need a key window or a terminal surface fail for environmental reasons (NSApp.isActive false; embedded_window err=error.OutOfMemory); do not chase those unless they are your child's subject. Read the reports of the 2026-09-26 lanes in .handoff/ (mn-3c4b23 restore freshness, mn-a7baaa discovery paths, mn-8905ec exact tmux targets, mn-2c8f51 persistence writer, mn-3aeeef notification ledger, mn-59bbbf archive resolver) before changing their areas.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-8100d4`.
4. Commit with `Manna: mn-8100d4` and run `agent-do manna done mn-8100d4` only after the work is verified.
