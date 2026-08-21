---
workflow: 2
manna: mn-13a213
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P0][RECOVERY] Real crash 2026-08-14: live-but-younger server re-opens the graveyard door — restore never offered'
inputs: []
binding: sha256:bc451d6d75b66d65af53222b643f94d0b82f2e3d12866e7eaa3d7fa36db77b3a
---

# Handoff: [P0][RECOVERY] Real crash 2026-08-14: live-but-younger server re-opens the graveyard door — restore never offered

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-13a213
```

## Scope

[P0][RECOVERY] Real crash 2026-08-14: live-but-younger server re-opens the graveyard door — restore never offered

## Inputs

- None declared.

## Work order

> Legacy migration source: ".dev/session-prompts/09-INBOX-LATENCY.md"

# 09 — Inbox latency and the unavailable GitHub sweep

Read this whole file before touching anything. Claim the manna item named in
BOARD below before work; commit with its `Manna:` trailer; run the named test
suites before every commit. Repo: `/Users/erik/Custom-Coding/holy-ghostty`,
work on `main` in the primary checkout.

## Symptoms (Erik, live app, 2026-08-10 ~18:05)

1. Switching sessions makes the manna section of the inbox panel disappear,
   and the focused project's board takes up to ~a minute to appear. It must
   be effectively instant — manna reads local files.
2. The GitHub section still shows the degraded row ("GitHub inbox
   unavailable") even after commit a895d4030 gave the subprocess a
   deterministic PATH.

## Verified mechanism (receipts, checked 2026-08-10 18:06)

- `HolyInboxEngine.runRefresh` (macos/Sources/HolyGhostty/Inbox/HolyInboxEngine.swift:121-140)
  runs sources IN ORDER and assigns `sections` ONCE at the end. Source order
  is now [GitHub, Manna, Alerts] (HolyWorkspaceStore.swift:~130, commit
  eaebd0d7d). Consequence: every refresh blocks manna and alerts behind the
  GitHub subprocess.
- The GitHub sweep is slow by nature: `agent-do gh inbox --json --limit 50`
  measured 30.63s wall just now (exit 0, 38 items). GitHub rate limits are
  NOT the cause today: core 5000/5000 remaining, search 30/30.
- NOTHING refreshes on session switch. `selectedSession` feeds
  `focusedRepoSlugProvider` and the manna roots provider (read at refresh
  time only); no code path calls `requestRefresh()` when selection changes.
  Poll cadence is 75s visible / 300s hidden (HolyInboxEngine.swift:25-26).
  So after a switch: stale-or-empty manna until the next poll, plus ~30s of
  GitHub serialization. That is Erik's "nearly a minute".
- Manna scope is focused-only BY DESIGN as of eaebd0d7d
  (`HolyMannaInboxSource.repositoryRoots(focused:)`, ~:501). Ratified by
  Erik; do not widen it back.
- The degraded row truncates its detail (`degradedSnapshot`,
  HolyGitHubInboxSource.swift:353-366): the real stderr is unreadable in the
  UI, which has already cost two diagnosis rounds.

## Mission, in priority order

1. **Focus-change invalidation.** Switching the selected session must update
   the manna section with the focused repo's board in under a second when a
   board exists on disk. Shape latitude: a targeted manna-only refresh on
   selection change, or full per-source decoupling (below) plus a
   selection-change trigger. Do NOT solve it by widening manna scope.
2. **Per-source section updates.** No source may delay another source's rows.
   Let each source's snapshot land in `sections` as it completes, keeping
   PANEL ORDER by source index (GitHub slot first, even if it fills last).
   Mind actor isolation: `sections`/`badgeCount` updates stay on MainActor;
   keep the serialized-refresh guarantee per source (no overlapping refreshes
   of the SAME source).
3. **Root-cause the in-app GitHub failure.** First, capture the FULL failure:
   make the degraded row (or an os_log line in HolyGitHubInboxSource) carry
   the complete stderr + exit code, install, reproduce, and read it. Known
   facts: the same command works from a login shell (30.63s, 38 items);
   commit a895d4030 overlays the login-shell PATH onto the inherited env
   (`sharedSubprocessEnvironment`, HolyGitHubInboxSource.swift:~414); gh auth
   is hosts.yml-based (no keychain). Candidate suspects, unproven: the 120s
   `commandTimeout` interacting with cold caches; something in the app's
   inherited env poisoning gh/agent-do; the subprocess needing a cwd it does
   not get. Fix what the evidence names — do not guess.
4. **Timeout sanity.** If the sweep legitimately runs 30s+, consider whether
   75s polling of a 30s subprocess is the right duty cycle (a slower visible
   cadence or a skip-if-still-running guard). Small, honest change only.

## Done when

- Session switch → focused board's manna rows visible in <1s (manual check
  plus a unit test that a selection-change triggers a manna refresh without
  waiting on the GitHub source).
- GitHub section shows real rows in the installed app on a normal network;
  on failure the row carries the complete reason, untruncated.
- An engine test proves one slow source cannot delay another's sections.
- Suites green before each commit:
  `-only-testing:GhosttyTests/HolyInboxSourceTests`
  `-only-testing:GhosttyTests/HolyInboxSectioningTests`
  `-only-testing:GhosttyTests/HolyInboxRowLifecycleTests`
  `-only-testing:GhosttyTests/HolyMannaInboxBoardTests`
  (plus any test file you add). Known unrelated pre-existing failures:
  mn-54c1ae, mn-0532e8 — do not chase them.
- Install via `scripts/install-holy-ghostty.sh`. KNOWN TRAP: headless
  codesign fails post-reboot (errSecInternalComponent). If it fails, write
  the install command into a `.command` file and `open -a Terminal` it —
  the keychain dialog can only appear in a GUI context. Never ask for or
  pipe the keychain password.

## Guardrails

- Notification/alert delivery path: untouched.
- Manna stays focused-only; GitHub stays global (its data is already global:
  verified 38 items across ovachiever + Versova-Intelligence-Division).
- No agent-do changes without asking Erik first (taxonomy gate).
- The board is the only backlog: claim before working, `Manna:` trailer on
  every commit, ledger honest deviations in the item before closing.

---

# ADDENDUM 2026-08-10 18:20 — first fix round FAILED human contact; start here

Session fc450563 built the structural half (commits a895d4030, c42bfccdf,
installed 18:17:35): per-source engine workers, manna-only refresh on session
switch, concurrent pipe drain in the runner, full-stderr logging in the
GitHub source. Erik's live verdict minutes later:

1. GitHub degraded EVERYWHERE with the same "error connecting to
   api.github.com" row as before.
2. Some sessions show NO GitHub section at all.
3. Manna shows for holy-ghostty only — no other project's board ever
   appears (aldebaran-group HAS a board: its mn-4d778d ids are visible in
   session titles).

## The contradiction to resolve FIRST

`log show --last 12m --predicate 'category == "HolyGitHubInboxSource"'` is
EMPTY while the degraded row is on screen. Both failure branches in
HolyGitHubInboxSource.swift log before returning a degraded snapshot. So
either the app logs under an unexpected subsystem/level, or the row Erik
sees comes from a path that skips those branches. Run `log stream` live
while reproducing before trusting ANY hypothesis. If logging is invisible,
temporarily dump to a file in /tmp from the failure branch — evidence
first, then delete the dump.

## Facts that KILL prior hypotheses (verified tonight)

- Not the sandbox: macos/GhosttyReleaseLocal.entitlements has NO
  com.apple.security.app-sandbox key (read in full; only automation,
  library-validation, media, personal-info keys).
- Not a third-party network filter: no LuLu/Little Snitch/Vallum in
  /Applications, no such processes running.
- Not gh auth: token is file-based (~/.config/gh/hosts.yml), works in
  minimal env (verified: env -i HOME PATH(+homebrew) gh api user succeeds).
- Not rate limits (5000/5000 core at 18:06).
- The same agent-do gh inbox command in a login shell: 30.63s, exit 0,
  38 items, 19,755 bytes.

## Ranked leads

GH-1. Capture the app subprocess's ACTUAL environment: log/dump
  `ProcessInfo.processInfo.environment` and the resolved
  `sharedSubprocessEnvironment` at sweep start, then run
  `env -i <exactly that env> agent-do gh inbox --json --limit 50` in a
  terminal. Whatever differs from the working login-shell run is the cause.
  (agent-gh fans out MANY `gh` subprocesses; think about what each inherits.)
GH-2. The runner's 120s timeout vs the sweep's 30s+: if the sweep runs
  slower inside the app (cold caches, qos throttling of .utility Tasks?),
  a timeout kill mid-sweep may surface gh's partial stderr. The runner's
  timeout failure string names the binary and seconds — check whether the
  row text is ACTUALLY the timeout message vs gh's connect error; read the
  full row text (it now shows the last stderr line).
GH-3. "Some sessions have no GitHub section": with per-source slots, the
  GH slot is nil until its FIRST snapshot lands — a 120s slow-fail leaves
  a 2-minute window with no GH section. Likely an artifact of GH-1/GH-2,
  not an independent bug; confirm after fixing them.

MANNA-1. Log `HolyMannaInboxSource.repositoryRoots(focused:)` output per
  switch. Suspect: `ownership.repositoryRoot` for non-holy sessions
  resolves to a WORKTREE path or nil (ownership derives from gitSnapshot —
  HolySession.swift:328-334 — which may be unpopulated at switch time).
  The switch-time targeted refresh reads it ONCE; nothing re-fires when
  the git snapshot lands later. Fix shape: re-fire the manna refresh when
  the focused session's ownership/gitSnapshot changes, and/or fall back to
  workingDirectory when repositoryRoot is nil (boardRoots' umbrella climb
  already walks up from any path).
MANNA-2. Verify with a real second board: cd into aldebaran-group's
  primary checkout, confirm `.manna` exists, focus a session there, and
  trace the roots the provider returned.

## Unchanged rules

Ratified UX stands: GitHub first and global, manna focused-only and
instant, collision alerts stay dead. The per-source engine and its two new
tests stay unless evidence convicts them. Suites and install trap: see the
main body above.


## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-13a213`.
4. Commit with `Manna: mn-13a213` and run `agent-do manna done mn-13a213` only after the work is verified.
