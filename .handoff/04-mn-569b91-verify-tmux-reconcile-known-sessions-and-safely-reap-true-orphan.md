---
workflow: 2
manna: mn-569b91
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[VERIFY][TMUX] Reconcile known sessions and safely reap true orphans'
inputs: []
binding: sha256:b3db21a18eefa26512a0e0a75ab021ff620e5dfd797cf1112d772e6db65d3519
---

# Handoff: [VERIFY][TMUX] Reconcile known sessions and safely reap true orphans

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-569b91
```

## Scope

[VERIFY][TMUX] Reconcile known sessions and safely reap true orphans

## Inputs

- None declared.

## Work order

Commit 387aec593 provides live-identity reconciliation, archive readoption, unknown-orphan surfacing, and archive retention. Complete and accept the user outcome.

Done when:
- A known archived live tmux session is adopted with its Holy UUID, note, title, and Today pin; no duplicate tmux session is spawned.
- Unknown live sessions are surfaced with evidence and never destroyed automatically.
- A user-confirmed reap targets discovered truth and polls until the real session is absent.
- Repeated reconcile/reap operations are idempotent.
- Archive retention remains bounded without deleting sync/recovery-owned metadata.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-569b91`.
4. Commit with `Manna: mn-569b91` and run `agent-do manna done mn-569b91` only after the work is verified.

## Report: 2026-09-29, Gate 3 build-only lane

Claimed by `codex-01a0ef08871d7243` in the primary checkout after verifying canonical seal `sha256:f52a0ec1cbc9ac6364ec851bef90184557aa5e5d10df61e5dd4a328c2957bd92`. This is a source and compilation receipt, not executed acceptance. No product change was needed to establish the existing known-session mechanisms described below; no claim of runtime completion is made.

- `HolyConvergePlanner` readopts a unique archived match, leaves unknown sessions surfaced in Hosts, deduplicates discovered match keys, and leaves unreachable hosts untouched. The existing planner tests cover these branches.
- `HolyWorkspaceStore` resolves live identities one-to-one, blocks conflicting unresolved roster identities, builds archived launch specs from the archived record, and substitutes only discovery-backed transport and attach-only tmux coordinates. The source UUID and creation time survive in `HolySessionSupervisor.readoptedRecord`; note and Today pin preservation are covered by `HolyTmuxLifecycleIdentityTests.archivedReadoptionPreservesIdentityAndUserMetadata`.
- Reaping uses `HolyTmuxLifecycleService.killVerified` against an exact discovered identity. The lifecycle command polls for absence and reports a failure instead of removing a row when it cannot prove absence. Existing lifecycle suites contain exact-target, already-absent, and poll-until-absent coverage. No kill was performed in this lane.
- Archive retention receives live-matched and discovery-uncovered archive IDs as protected. `HolyArchiveRetentionCoverageTests` covers offline-host preservation and complete socket coverage. Retention implementation and its persistence suites are owned by the concurrent `mn-ca1805` lane; they were read only here. Its integrated result must be included in final acceptance.

Build worktree: `.dev/worktrees/mn-f92871-codex-01a0ef08`, base `38643dcf483c9338fc15d00469e2cc696dfeed56` plus the exact discovery changes committed as `5fdc8040a16840f6d66443a9a69a9e4ab238c12e`.

From that worktree's `macos/`:

```bash
suites=(HolyConvergePlannerTests HolyConvergeKeyTests HolyTmuxLifecycleIdentityTests HolyTmuxLifecycleServiceTests HolyArchiveRetentionCoverageTests)
only_testing=()
for suite in "${suites[@]}"; do only_testing+=("-only-testing:GhosttyTests/$suite"); done
xcodebuild build-for-testing -scheme Ghostty -destination 'platform=macOS' \
  -parallel-testing-enabled NO -skip-testing:GhosttyUITests "${only_testing[@]}" \
  -derivedDataPath ../.dev/DerivedData-mn-f92871 \
  -resultBundlePath ../.dev/verification/mn-569b91/build-1.xcresult
```

Result: **TEST BUILD SUCCEEDED**, exit 0, build-results status `succeeded`, 0 errors. `xcrun xcresulttool get test-results summary` reports **0 total, 0 passed, 0 failed, 0 skipped**, result `unknown`. These suites compiled and did not execute. Receipt files live in the worktree's `.dev/verification/mn-569b91/`.

Required acceptance remains open: serial execution of the selected suites, known archived readoption preserving UUID/note/title/pin without creating tmux sessions, repeated reconciliation and confirmed reaping, and retention against the integrated metadata rules. Cross-host newer note/pin conflict handling is also part of the gate's later `mn-56f896` child. Follow `mn-f92871-executed-live-acceptance` for the coordinated pass. No app launch, install, screenshot, live session spawning, live app data, or `holy` socket access occurred. Do not mark done from this build-only receipt.
