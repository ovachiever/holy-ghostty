---
workflow: 2
manna: mn-8100d4
track: mn-5db142
source: orchestrator 2026-09-29; 09-24 handoff section 5 gate 7
base_commit: b1e6cbfcbda5cd18b2871a955d1ae8857ec2b625
scope: '[P1][1.0 GATE 7] Release prep: launch-by-path docs, the release procedure, and the 1.0 changelog section'
inputs:
- orchestrator 2026-09-29; 09-24 handoff section 5 gate 7
binding: sha256:7b56bd0a51b95cbd0ed3c42d68a05c92505797af23b78b429f397d7211f7915d
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

## Report

2026-09-29, worker `codex-01a0ef08b72e75d0`.

### Outcome and ownership

Release preparation is complete and ready-to-install when the remaining
release gates and Erik's live acceptance window permit it. This gate does not
certify or publish the release.

- The initial gate claim succeeded without stealing ownership. Before editing,
  the handoff's recalculated content binding, frontmatter, canonical Manna
  record, and requested digest all matched
  `sha256:3bcd71bec1bd5cb606261bb3e365fea99a3fb9f2aaf447b1b2c874597b581da4`.
- Read the child work order, verified its original seal, and claimed it before
  editing. Established coord focus and exact path claims. Other workers own the
  concurrent source and board changes; their changes are preserved.

### Delivered changes and commits

| Item | Implementation commit | Acceptance |
| --- | --- | --- |
| `mn-f4546f` | `3a61d4f5e` | README and engineering spec launch the installed bundle by path; installer already ends without launching. Child report sealed and Manna status done. |
| `mn-8100d4`, tasks 2 and 3 | `51e06330d` | CI core import, verified install, serial certification, documented UI-test skip, tag procedure, and commented 1.0.0 changelog draft. |

Both implementation commits use Conventional Commit messages and their exact
item trailers. README also follows the same CI-only core import procedure, so
its onboarding commands agree with the release runbook. Import, verification,
installation, and launch examples stop when the preceding command fails.

The certified-run example retains each attempt under `.dev/release/`, records
the release commit, uses `-parallel-testing-enabled NO` and
`-skip-testing:GhosttyUITests`, and writes a `.xcresult` bundle. It reads actual
counts through `xcrun xcresulttool get test-results summary`, rejects failed or
empty runs, and checks that the clean release commit did not change. It does
not delete an earlier result bundle. The UI-test bootstrap failure and skip
cite `mn-3a4538`; certification belongs to `mn-3bb820`.

`CHANGELOG.md` has a `1.0.0 (YYYY-MM-DD)` header and one-paragraph summary inside
an HTML comment immediately above `Unreleased`. All pre-existing changelog
bytes are preserved. No version setting, active release heading, or tag changed.

### Verification receipts

| Command or check | Actual result |
| --- | --- |
| `rg -n -- 'open -a' scripts docs/holy-ghostty README.md` | No matches, exit 1 as required for the negative search. |
| `rg -n -F 'open /Applications/Holy\ Ghostty.app' README.md docs/holy-ghostty/engineering-spec.md` | Both documents matched, exit 0. |
| `sh -n scripts/install-holy-ghostty.sh` | Passed, exit 0; script inspected through its final no-launch statement. |
| `sh -n scripts/build-holy-ghostty-core.sh` | Passed, exit 0. |
| `/bin/bash -n` on every Bash fence in the changed documents | All 6 snippets passed: 3 in README and 3 in the engineering spec. Syntax only; snippets were not executed. |
| Python AST parse of the embedded result-summary reader | Passed. No certification run was simulated. |
| `xcrun xcresulttool get test-results summary --help` and `--schema` | Installed tool supports `--path`; required result/count fields and the `Passed` enum verified from the actual `schemas` envelope. |
| Changelog preservation check against the pre-edit committed content | Passed: remove the new comment and all original bytes remain; one summary paragraph, correct placeholder, correct placement. |
| README release-procedure link and target heading | Both exist. |
| `git diff --check` on owned paths and `git diff --cached --check` | Passed, exit 0. |

No Xcode suite is named by the child work order. App-hosted tests compiled: 0;
executed: 0. No Xcode build, shell installer fixture suite, core build/import,
real installer, app launch, screenshot, or live session was run in this lane.
No runtime build or test pass is claimed. Source behavior and installer code
are unchanged, so this lane's required acceptance is document and command
verification. No push, PR, tag, or live application-data mutation occurred.

### Remaining release acceptance

Coord publication `mn-8100d4-release-preparation` records the close boundary:
after the other release gates are accepted, Erik coordinates the installed
path launch, Board/fleet/Archive/Hosts visual acceptance and screenshots, final
release commit, full serial green run under `mn-3bb820`, and explicitly
authorized tag and publication. No live pass is scheduled or claimed here.

Lessons logged: 3 (new) | Decisions logged: 0 (new).
Lessons: `les-95adc5` (path launch and prerequisite failures), `les-3b3b38`
(xcresult schema envelope), `les-4c0007` (live repository path discovery).
