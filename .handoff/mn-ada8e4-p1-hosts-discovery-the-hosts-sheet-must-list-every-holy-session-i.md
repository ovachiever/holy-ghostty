---
workflow: 2
manna: mn-ada8e4
track: mn-eb7a80
source: Erik screenshot 2026-09-10 19:38 (badge 32, rows fewer, spinner stuck) + Studio ground truth 43 sessions
base_commit: c681f6a468251b3b262b4023e020d546de6cb5ba
scope: '[P1][HOSTS][DISCOVERY] The hosts sheet must list every holy session it counts: no classification-based drops, no partial-as-complete'
inputs:
- Erik screenshot 2026-09-10 19:38 (badge 32, rows fewer, spinner stuck) + Studio ground truth 43 sessions
binding: sha256:3564ea4445f8e005fb19bfe892d932f6613068b6cae2501468ee17f522a4ccec
---

# Handoff: [P1][HOSTS][DISCOVERY] The hosts sheet must list every holy session it counts: no classification-based drops, no partial-as-complete

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-ada8e4
```

## Scope

[P1][HOSTS][DISCOVERY] The hosts sheet must list every holy session it counts: no classification-based drops, no partial-as-complete

## Inputs

- Erik screenshot 2026-09-10 19:38 (badge 32, rows fewer, spinner stuck) + Studio ground truth 43 sessions

## Work order

Erik 2026-09-10, MacBook: the Studio row's badge says 32 live sessions while the actual server runs 43, and entire groups are missing from the list (his six VSI workers among them) — sessions the classifier cannot type (bash-leader wrapper panes, see the sibling exec-dispatch item) are silently dropped from display, and a still-running discovery sweep renders partial results indistinguishable from complete ones. Fix: (1) COMPLETENESS LAW — every session on the host whose name carries Holy's prefixes (holy-shell-*, holy-worker-*, and adopted names) appears in the list; unknown runtime renders honestly in an 'unclassified' group with the session name and cwd rather than vanishing; the count badge equals the number of rows, always, or the discrepancy itself is displayed. (2) PARTIAL HONESTY — while the sweep runs, the list says 'showing N of M discovered so far'; a hung or timed-out sweep says so (the admission lane's typed diagnoses exist for this) instead of freezing a spinner over stale rows. Tests: fixture with unclassifiable sessions asserts they render; count==rows invariant; partial-sweep banner. Acceptance: MacBook hosts sheet shows all 43 Studio sessions with the six VSI workers present (grouped correctly once the exec fix lands, honestly unclassified before it).

## Build return, 2026-09-10

Outcome: implemented and locally compiled. Required app-hosted test execution
and MacBook-to-Studio visual acceptance remain pending. Keep this item
`in_progress` and claimed; do not run `manna done` from these build receipts.

Admission receipt: the first command was `agent-do manna claim mn-ada8e4`, which
succeeded for `codex-01a08dec15c57081`. The canonical Manna prompt pointer,
frontmatter binding, and recomputed normalized handoff SHA256 all matched the
requested starting binding
`sha256:a0aee5f2fcd4838b59b131b7ec8d5356dd8a57658d0d60195429e6b8ca165dba`.
The binding normalizes the frontmatter binding line according to Manna's
`binding_material`; it is not the raw whole-file SHA256.

The repository has no checked-in AGENTS.md or CLAUDE.md. The nearest parent
AGENTS.md delegates work to the child repository; the supplied AGENTS
instructions and this sealed work order govern this lane. The Ghostty Xcode
scheme, README, and engineering spec identify the canonical build boundary.
Path claims were established before edits. Foreign documentation changes and
the sibling dispatch worker change were preserved. The sibling dispatch fix
landed independently as `13299d37d` during this lane and was present for the
final build.

Changes:

- Hosts publishes the unfiltered identity census across its configured tmux
  servers before inspecting runtime/git details. Placeholder names, adopted
  names, and unknown runtimes remain present.
- Unknown runtimes render under Unclassified, using the tmux session name and
  working directory. Badges and groups share the same row set, including while
  discovery is busy.
- Progress reports the rows discovered so far and incomplete server coverage.
  The 30-second discovery deadline includes queued SSH admission. Timeouts,
  malformed replies, and missing detail rows leave the published inventory
  visible with an incomplete/error message.
- Tmux query errors propagate instead of becoming a successful empty result.
  Background metadata probes apply metadata without replacing the broader
  Hosts inventory, and converge cannot overwrite its partial/error state.
- `HolyHostsDiscoveryTests` adds seven test functions (eight parameter-expanded
  cases): the 43-session fixture with six VSI workers, every runtime group,
  same-name sessions on different servers, census-before-enrichment progress,
  timeout/SSH failure retention, malformed/missing details, empty inventory,
  and cancellation of queued SSH admission without a process launch.

Executed validation:

```sh
scripts/build-holy-ghostty-core.sh verify
swiftlint lint --strict --config macos/.swiftlint.yml \
  macos/Sources/HolyGhostty/Remote/HolyRemoteModels.swift \
  macos/Sources/HolyGhostty/Remote/HolyRemoteTmuxDiscoveryService.swift \
  macos/Sources/HolyGhostty/Workspace/HolyRemoteHostsSheet.swift \
  macos/Sources/HolyGhostty/Workspace/HolyWorkspaceStore.swift \
  macos/Tests/HolyGhostty/HolyHostsDiscoveryTests.swift
git diff --check
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .dev/mn-ada8e4/DerivedData \
  SYMROOT=/Users/erik/Custom-Coding/holy-ghostty/.dev/mn-ada8e4/build \
  -only-testing:GhosttyTests/HolyHostsDiscoveryTests \
  -only-testing:GhosttyTests/HolyRemoteTmuxDiscoveryTimeoutTests \
  -only-testing:GhosttyTests/HolyConvergeKeyTests \
  -only-testing:GhosttyTests/HolySSHAdmissionControllerTests \
  build-for-testing
```

Results: core verification passed (ReleaseFast, Zig 0.15.2, input fingerprint
`9d9f76225c12968b5518f7477263b66f6635faff03ff9b9840852de3a38a02be`);
strict SwiftLint passed with zero violations in five files; whitespace check
passed; final Xcode result was `TEST BUILD SUCCEEDED`, exit 0. The first build
also passed, but exposed new weak-capture concurrency warnings; declaring the
progress callback MainActor removed those warnings in the final build.
Existing warnings outside the new code remain.

**Compiled tests are not executed tests. Zero app-hosted tests were executed.**
No app launch, installation, screenshot, live session spawn, push, or PR occurred.
Full command output is under `.dev/mn-ada8e4/`, including
`build-for-testing.log`, `build-for-testing-final.log`, and `swiftlint.log`.
The local implementation commit carries `Manna: mn-ada8e4`; its exact hash is
recorded in `.dev/mn-ada8e4/report.md` after commit creation.

Needed next: coordinate one live acceptance window, execute the four selected
app-hosted suites, then use the approved installed build on the MacBook to
verify the Studio host against a contemporaneous tmux inventory. Confirm all
43 reported sessions and six VSI workers are present (reconcile any real
inventory changes), count equals rendered rows, unknown runtime rows show their
name/cwd, and partial/timeout state is visible without hiding discovered rows.
The selected existing timeout suite includes a scratch tmux-server test, so its
execution also requires the coordinated session-spawning boundary to be lifted.
No live or visual acceptance is claimed by this return.

Lessons logged: 4 (new) | Decisions logged: 1 (new).

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-ada8e4`.
4. Commit with `Manna: mn-ada8e4` and run `agent-do manna done mn-ada8e4` only after the work is verified.
