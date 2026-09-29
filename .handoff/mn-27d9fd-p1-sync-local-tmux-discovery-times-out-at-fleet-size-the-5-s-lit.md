---
workflow: 2
manna: mn-27d9fd
track: mn-eb7a80
source: .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 5
base_commit: 74e8e8b0daa88cf1681b19ce560068c684fac4a5
scope: '[P1][SYNC] Local tmux discovery times out at fleet size; the 5 s literal starves Sync'
inputs:
- .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 5
binding: sha256:218c38bffb1914ce38c84d1e1f28d8fbdc69f70cdaabee4e95283ac11a8c3df9
---

# Handoff: [P1][SYNC] Local tmux discovery times out at fleet size; the 5 s literal starves Sync

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-27d9fd
```

## Scope

[P1][SYNC] Local tmux discovery times out at fleet size; the 5 s literal starves Sync

## Inputs

- .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 5

## Work order

Log line at 55 local sessions: Tmux discovery for local tmux timed out after 5.000000 seconds; Sync then starves. The 5 s is a bare bounding literal (CLAUDE.md quantities rule): measure discovery cost per session and derive the bound from the fleet size or the measured per-session cost, or replace the single timeout with incremental discovery. mn-12801a (Sync adopts never-seen sessions from every host) is the consumer. Done when Sync completes at 55 or more local sessions with no timeout line and the bound is named from a measured constraint.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-27d9fd`.
4. Commit with `Manna: mn-27d9fd` and run `agent-do manna done mn-27d9fd` only after the work is verified.

## Report: 2026-09-29, Gate 3 build-only lane

Implementation commit: `5fdc8040a16840f6d66443a9a69a9e4ab238c12e` (`Manna: mn-27d9fd` and `Manna: mn-f92871`). Claimed by `codex-01a0ef08871d7243` in the primary checkout. Initial seal verified against canonical Manna: `sha256:11fed0ccfbcd0c634c14d9735a16bb6b3f64e49a328c4a8ed339e25630abefc2`.

Local Sync now takes one identity census per socket and inspects each inventoried session in its own bounded process. The caller's deadline applies per inspection instead of to all 55 sessions together. This is the work order's incremental-discovery option; no guessed larger fleet timeout was introduced. Each detail must return exactly its inventoried identity. Timeout, cancellation, malformed output, a vanished session, or a mismatched identity fails the sweep before it can authorize roster removal. Rich title, runtime, note, pin, and working-directory inference still uses the existing script. Remote discovery and Hosts retain their existing deadline policy.

The shared process runner now drains stdout and stderr concurrently with execution and joins both EOFs with process exit. Previously it read only after process termination, allowing large output to block the child on pipe capacity. This is a source-derived failure mechanism, not a claim that live fleet timing was measured in this lane.

Added compiled regression coverage to `HolyRemoteTmuxDiscoveryTimeoutTests`: 55 independent inspections, distinct socket identities, missing/malformed/mismatched detail rejection, timeout fail-closed behavior, a 1 MiB fixture on each pipe, and a real 55-session throwaway-socket acceptance test. The latter was not executed. Existing timeout, Hosts, and directory-inference suites were included in the build selection.

### Verification receipts

Build workspace: `.dev/worktrees/mn-f92871-codex-01a0ef08`, based on `38643dcf483c9338fc15d00469e2cc696dfeed56`. Its two source changes exactly match the implementation commit. Manna and Coord operations remained in the primary checkout. The verified shared core payload has input fingerprint `df28bebb6ebfe4a473978513324c78da1f5148e4952f7f59d53e3806f7781141`, ReleaseFast, Zig 0.15.2. `scripts/build-holy-ghostty-core.sh verify` passed in both checkouts.

From the build worktree's `macos/`:

```bash
suites=(HolyRemoteTmuxDiscoveryTimeoutTests HolyHostsDiscoveryTests HolyDiscoveredWorkingDirectoryTests)
only_testing=()
for suite in "${suites[@]}"; do only_testing+=("-only-testing:GhosttyTests/$suite"); done
xcodebuild build-for-testing -scheme Ghostty -destination 'platform=macOS' \
  -parallel-testing-enabled NO -skip-testing:GhosttyUITests "${only_testing[@]}" \
  -derivedDataPath ../.dev/DerivedData-mn-f92871 \
  -resultBundlePath ../.dev/verification/mn-27d9fd/build-5.xcresult
```

Final result: **TEST BUILD SUCCEEDED**, exit 0. `xcrun xcresulttool get build-results` reports status `succeeded`, 0 errors, 498 warnings (build-wide, including cached diagnostics). `xcrun xcresulttool get test-results summary` reports **0 total, 0 passed, 0 failed, 0 skipped**, result `unknown`: this action compiled tests and executed none. Strict SwiftLint on the two changed files passed with 0 violations; `git diff --check` passed. Full logs, result bundles, and JSON summaries are under the build worktree's `.dev/verification/mn-27d9fd/`.

Preserved intermediate receipts: build 1 failed with 5 lint errors because `macos/.dev` was scanned as source, including generated and Sparkle files. Moving DerivedData outside `macos/` exposed cached absolute package paths in build 2 (1 error). That state was archived and a fresh root `.dev` build reached compilation. Build 3 found the test helper's private result type (1 error); the helper now returns a value tuple. Builds 4 and 5 succeeded. No lint phase was disabled.

### Required acceptance still pending

No app launch, install, screenshot, live session spawn, live app-data access, or `holy` socket access occurred. The latest user instruction permits only compilation mid-lane and overrides the older `xcodebuild test` action in the gate handoff. Do not mark this child done until the selected suites execute serially and the 55-session Sync outcome is verified without a timeout. Coordinate through `mn-f92871-executed-live-acceptance`; the real fixture uses a unique scratch socket and removes its socket file. Installed fleet acceptance is separate from that fixture. This child is an implemented, compiled candidate, not accepted or ready-to-install.
