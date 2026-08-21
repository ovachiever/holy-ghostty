# Holy Ghostty — Session Handoff (2026-07-04)

Session span: 2026-06-16 → 2026-07-04 (one long conversation, multiple days, model switched Opus 4.8 → Fable 5 on Jul 3).
Repo: `/Users/erik/Custom-Coding/holy-ghostty` (fork of ghostty-org/ghostty; all Holy work in `macos/Sources/HolyGhostty/`).
HEAD at handoff: `0cde1db8b` on `main`, tree clean, **2 commits ahead of `upstream/main` (UNPUSHED: `ef5234dfb`, `0cde1db8b`)**.

## 1. Where This Session Ended (read this first)

The SSH-resilience/converge-Sync feature is **specced, planned, approved — NOT built**.
Last message offered the execution choice; the user asked for this handoff instead of answering.

**First action for next session:** ask (or decide) subagent-driven vs inline execution, then run
`docs/superpowers/plans/2026-07-04-ssh-resilience-sync-converge.md` task-by-task
(8 TDD tasks; the plan header mandates superpowers:subagent-driven-development or superpowers:executing-plans).

| Pending item | State |
|---|---|
| SSH resilience plan execution | Approved, awaiting subagent-vs-inline choice |
| Throbber regression (Jul 3) | **PARKED mid-investigation** — see §7 |
| MacBook disk 100% full | User action pending — see §7 |
| Push `ef5234dfb` + `0cde1db8b` | Docs-only, safe to push with next work |
| `stash@{0}: autostash` (Jun 29, 12 files) | Intent unknown; **conflicts likely with plan Task 1** — see §7 |

## 2. The Approved Plan (what gets built next)

Spec: `docs/superpowers/specs/2026-07-04-ssh-resilience-sync-converge-design.md` (`ef5234dfb`)
Plan: `docs/superpowers/plans/2026-07-04-ssh-resilience-sync-converge.md` (`0cde1db8b`)

Core idea: **one converge engine, three triggers.** Parallel discovery sweep (5s/host cap) → diff vs roster → attach new / repair only dead / auto-archive confirmed-gone / never touch healthy. Fired by: Sync button, system wake (+4s settle, 10s debounce), pane-exit (backoff 4/10/25s). Plus: power assertion (`PreventUserIdleSystemSleep`) while remote sessions attached (default on, toggle in overflow menu), keepalive flags on attach ssh (`ServerAliveInterval=15/CountMax=4/TCPKeepAlive=no/ConnectTimeout=8`, NO BatchMode), fail-fast flags on detach ssh (`ConnectTimeout=5/BatchMode=yes`).

User decisions locked during design (do not re-litigate): all three layers; converge-to-truth Sync; keep-awake default ON; UserDefaults for the pref (device-local, deliberate spec deviation, documented in plan Task 5); "dead" = local process exited OR (local running AND remote `attachedClientCount == 0`) — remote count alone is NOT truth (MacBook may hold its own attachment; keepalive self-corrects in ~60s).

Root-cause receipts behind the design (verified in code this session):
- Sync = `reattachAllSessions()` (`HolyWorkspaceStore.swift:573`): serial `ssh … tmux detach-client` per session with **no timeout** (`HolyTmuxClientDetachCommand`, store:2777-2800, `waitUntilExit()` unbounded) → one asleep host = minutes of hang. Record-driven, never validates. Detaches healthy panes.
- Hosts→Attach All is discovery-driven (`launchRemoteTmuxSessions(_:on:keepHostsOpen:)` store:1067, `launchLocalTmuxSessions` store:1046) — that's why Erik's Clear+AttachAll ritual "always works."
- Attach command is bare `ssh -tt` (no keepalive): `HolyTmuxCommandBuilder.swift:121-124` `remoteLaunchWrapper`.
- Zero sleep/wake/power handling app-wide (grep verified empty).
- `HolyDiscoveredTmuxSession.attachedClientCount` **already exists** (`HolyRemoteModels.swift:77`) — no discovery changes needed.

## 3. Commits This Session (chronological, with attribution)

| Commit | Author | What |
|---|---|---|
| `a9606f5e5` | codex (pre-session context) | opencode runtime classified from screen chrome; fixed stale TEST_HOST + set `PRODUCT_MODULE_NAME=Ghostty` |
| `16902e728` | this session | idle OpenCode false "working" throbber — footer `• OpenCode 1.17.7` matched `(opencode[^\n]*)` command pattern; added `isAgentStatusFooterLine` guard in telemetry parser |
| `3397a830a` | this session | working OpenCode showed NO throbber after above — OpenCode's live signal is `esc interrupt` (no "to"); added to `isLiveAgentStatusLine` |
| `f1c2dbf74`…`40466c243` | other agents (Jun 17-22) | roster perf/reply-orb/Hosts work — audited, not authored here |
| `e8ba212c4` | other agent | lazy roster right-click context menu — **scoped in this session** (design: reuse lazy NSMenu, hitTest right-clicks only; avoid SwiftUI .contextMenu scroll-freeze) |
| `2fe039af6` | other agent | install script: defaults ReleaseLocal, refuses others (exit 64), bundle-id check (exit 65) |
| `649e659d6` | this session | split-view linkage design spec (brainstorm → 4 user decisions → spec) |
| `f7738ffac`, `679d79251`, `fbbf55318`, `dace264f0` | other agent | split-view linkage BUILT + spec archived to `.dev/docs-archive/…` (gitignored). Ship verified this session: symbols, tests, ⌘1-4 wiring, `.triple` all present; upstream/main aligned at `dace264f0` |
| `ef5234dfb` | this session | SSH resilience spec (UNPUSHED) |
| `0cde1db8b` | this session | SSH resilience implementation plan (UNPUSHED) |

## 4. Files Created / Modified by This Session's Own Commits

| File | What |
|---|---|
| `macos/Sources/HolyGhostty/Telemetry/HolySessionRuntimeTelemetryParser.swift` | `isAgentStatusFooterLine` guard in `extractCommand` (~line 305); `#if DEBUG extractCommandForTesting` |
| `macos/Sources/HolyGhostty/Session/HolySession.swift` | `esc interrupt` in `isLiveAgentStatusLine` (~1202); `#if DEBUG isLiveAgentStatusLineForTesting` |
| `macos/Tests/HolyGhostty/HolySessionTelemetryCommandTests.swift` | new — footer-not-a-command + real-command tests |
| `macos/Tests/HolyGhostty/HolySessionLiveStatusTests.swift` | new — `@MainActor`; working/idle footer live-status tests |
| `docs/superpowers/specs/2026-07-04-ssh-resilience-sync-converge-design.md` | new |
| `docs/superpowers/plans/2026-07-04-ssh-resilience-sync-converge.md` | new |
| `.gitignore` | `.handoff/` added (this handoff) |

## 5. Deleted (disk cleanup, Jul 4 — user-instructed)

| Machine | Deleted | Freed |
|---|---|---|
| Studio | `~/Library/Developer/Xcode/DerivedData/Ghostty-{cfwe…,evzh…}`, `macos/build/` (incl. 0.30 ad-hoc zip), `.zig-cache` (4G), stray nested `macos/macos/` build tree | ~8.5 GB |
| MacBook (ssh alias `macbook`) | `~/Library/Developer/Xcode/DerivedData/Ghostty-*` | 785 MB |

**Kept deliberately:** `/Applications/Holy Ghostty.app` (running) and `macos/GhosttyKit.xcframework` (May-29 CI ReleaseFast engine — NOT locally rebuildable, local Zig link broken on macOS 26; rebuilds go through CI `build-holy-macos.yml`). `macos/build/` absence is fine — install script rebuilds.

## 6. Bugs Fixed (root causes, this session's own)

| Symptom | Root cause | Fix |
|---|---|---|
| Debug app installed (slow) | script defaulted Debug; stale ReleaseLocal bundle trap (script only builds if app missing) | ReleaseLocal rebuild discipline; later hardened by `2fe039af6` |
| Idle OpenCode spins forever | footer `97.9K (10%) ctrl+p commands • OpenCode 1.17.7` extracted as a running command → `.command` activity → `isActiveWork` → `.working` | `16902e728` |
| Working OpenCode shows no spinner | OpenCode says `esc interrupt`, matcher only knew `esc to interrupt` (footer false-positive had been masking this) | `3397a830a` |
| Other machine: insta-crash at launch | failed headless re-sign left ad-hoc main binary WITHOUT `disable-library-validation` entitlement → dyld refused Sparkle (Team-ID mismatch is the symptom, dropped entitlement is the mechanism) | diagnosis + fix message delivered; see §8 signing playbook |

## 7. Known Remaining Issues

| # | Issue | Detail |
|---|---|---|
| 1 | **Throbber regression — PARKED mid-investigation (Jul 3)** | "Agent Do" + "Aldebaran Group" sessions actively working showed no spinner. Evidence gathered: split-view commits (`f7738ffac`..`fbbf55318`) touched RosterView (+61), WorkspaceStore (+287), WorkspaceView (+252) = prime blast radius. Installed binary (Jun-30 10:29:05) predates `fbbf55318` commit (10:29:37) by 32s — may or may not contain it. Screenshots were in iCloud `Transfer/` but listing showed only divination folders — never examined; ask user to re-share. Suspects in order: (a) attention pipeline regression from split commits, (b) occluded/non-presented surfaces stop refreshing previews → evidence goes stale (`agentScreenActivityFreshnessInterval=4`s gate in HolySession), (c) App Nap (no power mgmt exists — note: SSH plan's assertion may accidentally help), (d) Claude TUI footer phrasing changed. Protocol that solved the last two throbber bugs: find pane via `tmux -L holy list-panes -a -F '#{session_name}|#{pane_current_command}|#{pane_title}'`, capture twice 1.3s apart, diff for ground truth, replay Swift regexes in python against captured lines. |
| 2 | **MacBook disk still ~100% full** (886/926 Gi) | Ghostty cleanup freed only 785M. Identified but NOT deleted (need user go-ahead): Xcode non-Ghostty 41G, Docker.raw 32G actual, CoreSimulator 19G, caches 9.5G. ~700G unaccounted in TCC-blocked dirs (SSH can't see Documents/Desktop/Downloads/Photos). User has: local scan one-liner + repo-clone cleanup one-liner (`rm -rf ~/Documents/AI/Custom_Coding/holy-ghostty/{.zig-cache,macos/build}`) + option to grant sshd Full Disk Access. |
| 3 | **`stash@{0}: autostash`** (Jun 29) | 12 files, 122 insertions — incl. `HolyTmuxCommandBuilder.swift` **+67 lines**, Ghostty.Config/Input, SurfaceView_AppKit, HolySession, RosterView. Intent never determined. **Plan Task 1 edits HolyTmuxCommandBuilder — popping this stash later will likely conflict.** Inspect with `git stash show -p stash@{0}` before or after plan execution; do not drop blind. |
| 4 | Unpushed docs commits | `ef5234dfb`, `0cde1db8b` — push with next work batch |
| 5 | Install script signs AFTER copying to /Applications | A failed re-sign still leaves a broken bundle live (caused the other machine's brick). Flagged in forensics message; never fixed. Candidate follow-up: sign+verify in staging, then swap. |
| 6 | Installed app vintage | Jun-30 binary; all later commits are docs-only, but the `fbbf55318` 32s ambiguity means triple-split control may be missing from the running app. Plan Task 8's install resolves this regardless. |

## 8. Knowledge Transfer — Playbooks & Gotchas

**Build/install (the only correct way):**
```sh
rm -rf "macos/build/ReleaseLocal/Holy Ghostty.app"   # force fresh build from HEAD (script only builds if missing)
./scripts/install-holy-ghostty.sh ReleaseLocal        # builds, installs, re-signs; refuses non-ReleaseLocal (exit 64)
osascript -e 'tell application "Holy Ghostty" to quit'; pkill -f 'Holy Ghostty.app/Contents/MacOS/holy-ghostty'
open "/Applications/Holy Ghostty.app"                 # old in-memory instance does NOT auto-swap — must quit+relaunch
```
tmux-backed sessions reattach on relaunch; replacement is safe. ReleaseLocal binary is a single static ~63M `holy-ghostty` (a `.debug.dylib` beside it = Debug build = wrong).

**Signing:** identity `Apple Development: Erik Fritsch (296U646CYV)` (Team `TY4QKVXBCL`). A second cert `HBJ4G9C752` exists — don't grab blind. The load-bearing piece is the `com.apple.security.cs.disable-library-validation` entitlement from `macos/GhosttyReleaseLocal.entitlements` — without it dyld rejects Sparkle (ad-hoc/Team-ID mix) and the app dies at launch. `--deep` NOT required. Headless SSH cannot sign (keychain locked). Verify after any install:
```sh
codesign -dv --verbose=4 "/Applications/Holy Ghostty.app" 2>&1 | grep -E "TeamIdentifier|Authority"
codesign -d --entitlements - "/Applications/Holy Ghostty.app" 2>&1 | grep library-validation
codesign --verify --deep --strict "/Applications/Holy Ghostty.app" && echo OK
```

**Tests:** module is `Ghostty` (`@testable import Ghostty`); Swift Testing; `@MainActor` on structs touching HolySession/Store; private prod code exposed via `#if DEBUG …ForTesting` helpers (never widen access — SwiftLint flags it).
```sh
cd macos && env -i HOME="$HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" \
xcodebuild -project Ghostty.xcodeproj -scheme Ghostty -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -only-testing:GhosttyTests/<ClassName> test
```

**Ground-truth debugging for session-state bugs:** the Holy tmux socket is `-L holy`. Capture the exact text the classifier sees; never theorize from the UI. Two captures + `diff` = is it live. Replay the Swift regexes in python against the capture before touching Swift.

**Classifier/attention map (file:line, verified this session):** `classifyPhase` HolySession:780 · `detectSignals` :828 · `agentWorkingEvidence` :1082 (gated on `previewChangedRecently`) · `isLiveAgentStatusLine` :1197 (has `esc to interrupt` + `esc interrupt`) · spinner glyphs `agentSpinnerTitlePrefixes` :1068 · telemetry `extractCommand` + footer guard, TelemetryParser:305 · attention decision `attentionPresentation` WorkspaceStore:1263 (order matters: failed → planningQuestion → approval → swarming → stalled → **working** → waiting) · `isActiveWork` WorkspaceStore:3008 · orbs `HolyAgentStatusOrb` RosterView:1278 (throbber = `.working`).

**Environment:** MacBook = ssh alias `macbook` (Tailscale 100.102.213.43); TCC blocks `~/Documents` over SSH — deploy there via `git push macbook` → build on that machine, never scp into Documents. `ssh` remote ops always with `-o ConnectTimeout=…` — an asleep host hangs raw ssh for 60-75s. iCloud screenshots are TCC-blocked for the Read tool — `cp` to `/tmp` via Bash first. Multiple agents work this repo (codex peers, tmux-40 etc.) — `agent-do coord focus set` before editing; check `git log` before assuming your context is current: **other agents land commits between your turns** (split-view was designed here, built elsewhere).

## 9. Verification Commands (prove this handoff)

```sh
cd /Users/erik/Custom-Coding/holy-ghostty
git log --oneline -3                      # 0cde1db8b, ef5234dfb, dace264f0
git status --porcelain                    # empty
git rev-list --left-right --count upstream/main...HEAD   # 0	2  (2 unpushed)
git stash list                            # stash@{0}: autostash
ls docs/superpowers/specs docs/superpowers/plans          # ssh-resilience spec + plan
ls macos/Tests/HolyGhostty                # 4 test files incl. LiveStatus + TelemetryCommand
stat -f %Sm macos/GhosttyKit.xcframework  # May 29 (engine intact)
pgrep -fl "Holy Ghostty.app/Contents/MacOS/holy-ghostty"  # app running
```
Tests last verified green Jun 16 (throbber suites) / Jun 29 (pane-layout, via ship-audit); re-run per §8 before building on them.

## 10. Next Steps (priority order)

1. **Execute the SSH plan** — `docs/superpowers/plans/2026-07-04-ssh-resilience-sync-converge.md`, subagent-driven (recommended) or inline; 8 tasks, commit per task; Task 8 installs ReleaseLocal + manual sleep checklist (lid-close self-heal, `pmset -g assertions | grep -i holy`).
2. **Push** the two docs commits (plus the feature commits as they land).
3. **Resume throbber regression** (§7.1) with the tmux capture protocol — ask user for fresh screenshots or a currently-affected session name.
4. **MacBook disk** — get user's go/no-go on the ~60G quick wins; get local scan output for the ~700G.
5. **Inspect `stash@{0}`** before it collides with Task 1's builder edits.
