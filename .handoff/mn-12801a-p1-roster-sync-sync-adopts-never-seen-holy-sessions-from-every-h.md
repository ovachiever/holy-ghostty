---
workflow: 2
manna: mn-12801a
track: mn-eb7a80
source: 'Erik 2026-09-08 14:18 + planner receipts (HolyWorkspaceStore convergeRoster: only .repair/.adoptArchived exist)'
base_commit: f04446826826ce17e7ed4c0712210323f0af7eb2
scope: '[P1][ROSTER][SYNC] Sync adopts never-seen Holy sessions from every host — and reports what it did'
inputs:
- 'Erik 2026-09-08 14:18 + planner receipts (HolyWorkspaceStore convergeRoster: only .repair/.adoptArchived exist)'
binding: sha256:4fb0a5347a421ae0282434ae308268b8686139df726d2c61d19e05c4fc748bd6
---

# Handoff: [P1][ROSTER][SYNC] Sync adopts never-seen Holy sessions from every host — and reports what it did

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-12801a
```

## Scope

[P1][ROSTER][SYNC] Sync adopts never-seen Holy sessions from every host — and reports what it did

## Inputs

- Erik 2026-09-08 14:18 + planner receipts (HolyWorkspaceStore convergeRoster: only .repair/.adoptArchived exist)

## Work order

Erik 2026-09-08: Sync 'always sucked so I never used it' — root cause found in the planner: convergeRoster has exactly two actions, .repair (dead roster sessions) and .adoptArchived (sessions THIS machine's DB has known). A tmux session born on another machine (the dominant case: MacBook viewing Studio-born sessions) discovers fine but has no local match key and is silently skipped — Sync looked broken while working as designed. Add the third verb: .adoptDiscovered for sessions that prove Holy ancestry via their own markers (holy-* tmux naming and/or @holy_* session options — with mn-2c82a2's host-authoritative options carrying identity/seen/title, adoption anywhere reconstructs an honest row); non-Holy tmux sessions are never touched, and the existing ambiguity-blocks-adoption law stands. Sweep scope stays as coded: local + every saved remote host + hosts inferable from the roster. And kill the silence that built the distrust: each Sync ends with a visible converge report — attached N, repaired M, adopted K from <host>, skipped J (each with its reason: not Holy-born, ambiguous, host unreachable) — in the toast/footer strip and the flight-recorder log. Acceptance: from a MacBook with an empty roster and zero local history, one Sync populates every Holy session running on the Studio with correct identity, titles, and seen-state (per mn-2c82a2), and the report accounts for every discovered session; the Hosts sheet remains for browsing/select-adoption but is no longer required for the daily 'mirror reality' gesture. Relates: mn-569b91 (reconcile known sessions / reap true orphans) — same discovery substrate, coordinate.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-12801a`.
4. Commit with `Manna: mn-12801a` and run `agent-do manna done mn-12801a` only after the work is verified.

## Report: 2026-09-29, Gate 3 build-only lane

Implementation commit: `2d98378b7` (`Manna: mn-12801a` and `Manna: mn-f92871`). Initial canonical seal verified: `sha256:86a416f7c7411a62295ab788d1a56550bce1c4ff20e6c2b2d830b3162228db03`. Claimed by `codex-01a0ef08871d7243` in the primary checkout. This is an implemented, compiled candidate with executed and installed acceptance still open.

Changes:

- Discovery records a separate raw Holy-option provenance field before inferring title, runtime, or working directory. The existing `isHolyManaged` presentation heuristic accepts inferred fields and therefore cannot authorize automatic adoption. New `hasHolyProvenance` requires a `holy-` session name or actual nonempty Holy session options.
- `HolyConvergePlanner` has `adoptDiscovered`. Unique archived identities retain precedence. Any current roster or archive identity that could refer to the discovery blocks fresh adoption, and the guard runs again immediately before mutation. Ordinary tmux sessions remain browse-only and receive a skipped reason.
- New adoption uses the existing supervisor creation path with the discovered exact tmux identity and `createIfMissing == false`; it does not start a second tmux session. The bulk path preserves selection instead of invoking the user-facing New/Attach selection behavior. Host-owned seen-state still enters through the existing agent-state monitor; no new seen acknowledgement is sent by this path.
- `HolyConvergeReport` records one outcome per discovered identity, host/session labels, skipped reasons, inaccessible-host errors, and archive count. The existing footer shows its summary, full details are available through help/accessibility, and the same details are written to the app log. Repair reporting awaits the actual attachment repair and rejects a missing surface rather than reporting the scheduled task as success. Missing adoption surfaces also report a skip.
- Focused regression coverage checks proven fresh adoption, archive precedence, idempotence, raw-option versus inferred-metadata provenance, ambiguity refusal, and report accounting. No tests were executed in this lane.

### Verification receipts

Build workspace: `.dev/worktrees/mn-f92871-codex-01a0ef08`, base `38643dcf483c9338fc15d00469e2cc696dfeed56` plus the exact source changes in `5fdc8040a` and `2d98378b7`. The primary checkout retained all Manna and Coord operations; other workers' changes were preserved.

From that worktree's `macos/`:

```bash
suites=(HolyConvergePlannerTests HolyConvergeKeyTests HolyConvergeGateTests HolyHostsDiscoveryTests HolyRemoteTmuxDiscoveryTimeoutTests HolyTmuxLifecycleIdentityTests)
only_testing=()
for suite in "${suites[@]}"; do only_testing+=("-only-testing:GhosttyTests/$suite"); done
xcodebuild build-for-testing -scheme Ghostty -destination 'platform=macOS' \
  -parallel-testing-enabled NO -skip-testing:GhosttyUITests "${only_testing[@]}" \
  -derivedDataPath ../.dev/DerivedData-mn-f92871 \
  -resultBundlePath ../.dev/verification/mn-12801a/build-1.xcresult
```

Result: **TEST BUILD SUCCEEDED**, exit 0. `xcrun xcresulttool get build-results`: `succeeded`, 0 errors, 502 build-wide warnings. `xcrun xcresulttool get test-results summary`: **0 total, 0 passed, 0 failed, 0 skipped**, result `unknown`. Strict SwiftLint passed on all seven changed Swift files with 0 violations; `git diff --check` passed. Full receipts are in the build worktree's `.dev/verification/mn-12801a/`.

### Required acceptance still pending

Execute the selected suites serially, then verify a MacBook with no local history adopts the Studio's Holy fleet in one Sync, preserves correct host identity/titles/seen-state, leaves non-Holy sessions untouched, and reports every discovery and inaccessible host. Verify footer readability and help details in the coordinated visual pass. Newer title/note/pin conflict handling remains the gate's next metadata child; this commit does not claim that broader lifecycle contract is complete. No app launch, install, screenshot, live session spawning, live app-data access, or `holy` socket access occurred. Coordinate via `mn-f92871-executed-live-acceptance`. Do not mark done from compilation alone.
