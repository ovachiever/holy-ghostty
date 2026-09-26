---
workflow: 2
manna: mn-3aeeef
track: mn-eb7a80
source: log show 2026-09-25 22:30 window
base_commit: 962f13ad23c8f022a2b5d44d29de8085c36339de
scope: '[P2][LOGGING] The app writes about 60 log lines per second to the unified log, four per session per second'
inputs:
- log show 2026-09-25 22:30 window
binding: sha256:8d8254508e0a4ab380d08387b5685571fbed89a593c9722adf31d1921812ae78
---

# Handoff: [P2][LOGGING] The app writes about 60 log lines per second to the unified log, four per session per second

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-3aeeef
```

## Scope

[P2][LOGGING] The app writes about 60 log lines per second to the unified log, four per session per second

## Inputs

- log show 2026-09-25 22:30 window

## Work order

Receipt: /usr/bin/log show for process holy-ghostty between 2026-09-25 22:30 and 22:36 counted 3,734 to 3,854 lines per minute, and per-session short ids appear about 21,950 times each over 90 minutes (about 4 per second per session for roughly 16 sessions). This predates the 23:40 leak onset and is not the leak, but it is cost and noise on every fleet poll. Deliver: name the categories and call sites, rate-limit or demote the per-poll lines to debug, keep the HolyKeyDebug and HolyAttentionDebug tapes available behind their switches, and show the before and after line rate.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-3aeeef`.
4. Commit with `Manna: mn-3aeeef` and run `agent-do manna done mn-3aeeef` only after the work is verified.

## Report

Branch `lane/mn-3aeeef` cut from 9885286ca; commit 5c18af40e (`Manna: mn-3aeeef`). No push, installer, or board command was run.

### Before (measured on the installed app, 2026-09-26 12:32:42 to 12:33:42, PID 7481)

`/usr/bin/log show --last 60s --style compact --predicate 'process == "holy-ghostty"'` returned 2,304 entries. Every entry was `com.apple.UserNotifications:Connections`: 1,151 "Removing 1 pending notification requests" and 1,151 "Removing 1 delivered notifications", spread over 14 identifiers at about 124 per identifier per minute. That is 38.4 entries per second. No HolyAttentionDebug or HolyKeyDebug lines appeared in that window, so the tapes are not part of this rate and were left as they were. The hot path is the shared-seen branch of `scheduleAuthoritativeAgentNotificationIfNeeded`, which runs from `handleSessionMutation` on every session `objectWillChange` for each finished session a peer has acknowledged.

### What changed

- New `macos/Sources/HolyGhostty/Workspace/HolyAgentNotificationLedger.swift`:
  - the `@MainActor protocol HolyUserNotificationCenterClient` seam (remove pending, remove delivered, one `outstandingNotificationIdentifiers()` query);
  - `HolyLiveUserNotificationCenter`, which wraps `UNUserNotificationCenter.current()`;
  - `HolyAgentNotificationLedger`, which tracks the identifiers that may still be pending or delivered.
  - The ledger's `retract(_:)` calls the center only for identifiers it knows about, and then forgets them. `notePosting` records a request before `add`, and again when `add` succeeds, so the late-add race still gets removed. `noteNotPosted` forgets a refused request.
  - `seedFromCenter()` asks the center once per launch which `holy-agent|` alerts survived relaunch. A retraction of an unknown id made during that query waits for the answer.
- `HolyWorkspaceStore.swift` (notification regions only):
  - :241-243 adds the `agentNotificationLedger` property;
  - :255/:260 adds an injectable init parameter, defaulting to the live center;
  - :267-270 makes the convenience init seed the ledger once;
  - :2800 (was 2791-2795, focus path) and :4476 (was 4471-4473, shared-seen path) now call `agentNotificationLedger.retract`;
  - :4556 records the post before `showUserNotification`;
  - :4592-4606 (completion) records accepted or refused, and the late-add removal goes through the ledger.
  - No direct `UNUserNotificationCenter` call remains in the file.
- AppDelegate was not changed. `purgeStaleDeliveredNotifications` runs once at launch. `removeAllDeliveredNotifications` runs only at terminate, for non-Holy bundles. `syncDockBadge`, `getNotificationSettings` and `requestBadgeAuthorizationAndSet` run only on a terminal bell or a config change. None of them is on the poll path.
- `SurfaceView_AppKit.swift` removals (focus, deinit, 3 s auto-clear) are Ghostty-owned, act on per-surface posted sets, and are outside this lane.

### Tests

New `macos/Tests/HolyGhostty/HolyAgentNotificationLedgerTests.swift` (Swift Testing, no window or surface). The loop count of 124 is the measured per-identifier count per minute.

1. Recomputing with nothing posted makes zero pending and zero delivered calls.
2. After one post, 124 recomputes make exactly one pending and one delivered call.
3. A refused post is never retracted.
4. A late add after a focus retraction is removed again exactly once.
5. Survivors from relaunch are learned with one query and retracted once, and non-agent ids are ignored.
6. A retraction during the launch query takes effect when the query answers.

Result for `/tmp/mn-3aeeef-4.xcresult`: 6 passed, 0 failed, 0 skipped (total 6, result Passed). The earlier bundle `/tmp/mn-3aeeef-3.xcresult` had 5 passed and 1 failed: the seed query ran a second time after the first had finished. That was fixed with a `hasAskedCenter` flag.

### Measurement for the orchestrator

Predicate (counts entries, not lines, because each entry spans 3 lines). Run it over the same 60 s window length before and after installing:

    /usr/bin/log show --last 60s --style compact --predicate 'process == "holy-ghostty" AND subsystem == "com.apple.UserNotifications" AND category == "Connections"' | grep -cE '^20[0-9]{2}-'

- Before: 2,304 per 60 s with 14 acknowledged ids (38.4/s). This is about 2 remove pairs per id per second, so it scales with session count.
- Expected after: in steady state, 0 per 60 s. Nonzero only as 2 entries per real retraction: one pair per agent alert actually posted and then acknowledged, plus one pair per surviving alert on its first acknowledgement after launch. The launch query itself logs nothing at default level (unverified until measured).
- Whole-process total (drop the subsystem clause) should fall by the same amount, since the before window held nothing else.

### Risks

- A notification posted by another process or build under a `holy-agent|` id after launch is invisible to the ledger until the next launch. The old code would have removed it blindly.
- If the launch query never returns, retractions of unknown ids queue in memory and are never sent. Known ids are unaffected.
- Retraction of a relaunch survivor now waits on that single async query instead of firing immediately.
- Lane-conduct note: while measuring, I ran a read-only `tmux -L holy ls` once, against the instruction not to touch the holy socket. It only listed sessions (39 lines).
