# Handoff — Holy Ghostty: Hosts sheet shows polluted session name + session vanishes from roster on restart

**Date:** 2026-06-03
**Repo:** /Users/erik/Custom-Coding/holy-ghostty (fork of Ghostty)
**Status:** two related-but-distinct bugs, unresolved. Build/run with `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration ReleaseLocal build`, then install the built app from DerivedData over `/Applications/Holy Ghostty.app` and launch with `env -u TMUX -u TMUX_PANE -u TMUX_TMPDIR open` (clearing TMUX avoids a discovery-duplicate bug). Engine xcframework is a prebuilt ReleaseFast — no zig needed.

## Hard constraints (carried from prior work)
- **Session name and runtime must come from launch intent + STABLE identity (repo / working dir / launch title), NEVER from scraping the live screen, pane title, or OSC title.** Agents (Claude Code, Codex) rewrite the terminal/pane title to a per-task status line (e.g. `✳ Verify auto-commit for Claude and Codex`) prefixed with a status glyph (`✱ ✻ ⏺ ✳ • · ⠂`). That churn must never become a persistent name.
- Do NOT add refresh throttling. Verify with real evidence (tmux probes, logs) before changing.

## Recent context (already fixed in the working tree, uncommitted)
The roster (left list) title pollution was fixed: `HolySession.rosterTitleOverride` (macos/Sources/HolyGhostty/Session/HolySession.swift) now rejects glyph-prefixed titles via `isLiveAgentStatusTitle(_:)`, `shouldApplyDiscoveredTitle` rejects them, and the discovery script's `fallback_session_title` no longer falls back to `pane_title`/`window_name`. **That fix only covered the roster path — not the Hosts sheet, which is a separate title pipeline (Bug A below).**

---

## BUG A — Hosts/Connections sheet shows the live task title as the session name

Screenshot: the Hosts sheet lists a Claude session named **"✱ Verify Auto Commit For Claude And Codex"** (a Claude task status line), instead of its project name (`Custom-Coding`).

### Evidence (verified live)
For that session on the tmux server (`holy-shell-13-shell-CBA04AF3`):
- `@holy_title` = **`Shell 13`** (clean default — NOT polluted)
- `pane_title` = **`✳ Verify auto-commit for Claude and Codex`** (the live Claude task line)

So `@holy_title` is fine; the glyph name is entering through the **discovered-session title pipeline**, which is separate from the roster's.

### The Hosts title pipeline (where to fix)
- The Hosts sheet renders `HolyDiscoveredTmuxSession.displayTitle` — **macos/Sources/HolyGhostty/Remote/HolyRemoteModels.swift:179**.
- It uses `projectTitleForDefaultSession` (≈line 203 region) and `usableExplicitTitle` (just below). `usableExplicitTitle` rejects generated-default / internal / machine / generic titles — **but does NOT reject glyph-prefixed live agent titles.** So if the discovered `title` field is `✳ Verify auto-commit…`, it passes through as the name.
- The discovered `title` field is `field[3]` of the discovery output = the shell script's computed `$title` (macos/Sources/HolyGhostty/Remote/HolyRemoteTmuxDiscoveryService.swift ~line 545-549): it reads `@holy_title`, and if that is "generated"/default it calls `fallback_session_title`. `fallback_session_title` was just fixed to NOT use `pane_title`. **BUT there is also `task_title` = `@holy_task_title` (field[8]) — confirm it isn't pane-derived and isn't feeding the display name.**

### Why it may still show after the fix
Discovery runs on launch + every 300s. The Hosts data in the screenshot may be **stale pre-fix discovery** (captured `pane_title` into `title` before the script fix). FIRST verify: click **Refresh All** in the Hosts sheet (forces re-discovery with the new script) and see if the name corrects. If it does, the remaining work is just the defensive display-layer fix below; if not, the script is still surfacing the pane title somewhere.

### Fix direction
1. Add the same glyph-rejection used in the roster to the Hosts pipeline: reject glyph-prefixed titles in `HolyDiscoveredTmuxSession.usableExplicitTitle` (and ensure `displayTitle` then falls through to `projectTitleForDefaultSession` → repo/dir → sessionName). There's a reference implementation: `HolySession.isLiveAgentStatusTitle(_:)` checks `"✱✻✽✢⏺●○◐◓◑◒•·⠂⠄⠆⠇⠿".contains(first)`. Mirror it in HolyRemoteModels (or hoist to a shared helper).
2. Audit the discovery script `task_title`/`@holy_task_title` path — make sure no live pane/task title becomes the session `title` field.
3. Confirm via Refresh All + a fresh `tmux -L holy show-options -qv -t <s> @holy_title` that the displayed name tracks `@holy_title`/project, not `pane_title`.

---

## BUG B — Session disappears from the roster on restart; only shows in Hosts (unattached)

On app restart, the "Verify auto-commit" session is **gone from the left roster** but appears in the **Hosts sheet** as a discoverable session that is not connected. Expected (user's design): a tmux session that survived the Holy quit should be **restored into the roster (reattached)** on relaunch — Holy must not lose it to the Hosts-only limbo.

### Likely cause — the cold-boot matching I added (PRIME SUSPECT)
`HolySessionSupervisor.restoreWorkspace` (macos/Sources/HolyGhostty/Supervisor/HolySessionSupervisor.swift:52+) was recently changed to, on launch:
- probe live sessions via `probeLocalHolyTmuxSessions()` (line 172 — runs `tmux -L holy list-sessions -F '#{session_name}'`), then
- for each persisted record, if `isLocalManagedHolySession(record.launchSpec)` AND `record.launchSpec.tmux?.sessionName` is **NOT** in the live set, **archive it** as a cold-boot dormant session (lines 75-101).

The risk: if a persisted record's stored `tmux.sessionName` does **not exactly equal** the live tmux session name (name drift, regenerated name, empty/nil name, or a record persisted before its tmux session name was finalized), the matching fails and the **live session is wrongly archived** → it vanishes from the roster, and only the discovery layer (Hosts) still sees the live tmux session.

### Investigate (with evidence, before changing)
1. Compare the persisted record's `tmux.sessionName` to the live name for this session. The workspace DB / snapshot is the source for `restorableRecords`. Live name is `holy-shell-13-shell-CBA04AF3`. Are they equal? If not, that's the dropout.
2. Persistence timing: persistence is debounced (`schedulePersistence`/`flushScheduledPersistence`, ~350ms / ~10s). A session created shortly before quit may not be in the snapshot at all → not restorable → only discovered. Check whether the session is even in the persisted snapshot.
3. Reattach-on-restore: even for `restorableRecords` that survive the cold-boot filter, confirm they are actually **reattached** to their live tmux session (not just recreated as records). Anchors: `recoverActiveRecords` (line 415), `restorableRecords` (line 416), `reattach` (HolyWorkspaceStore.swift:339), `reattachAllSessions` (365), `applyDiscoveredLocalSessionMetadata` (HolyWorkspaceStore.swift:736).
4. Decide the correct contract: a live `tmux -L holy` session that maps to a persisted record should be **restored + reattached** into the roster; the cold-boot archive path should fire ONLY when the holy server is genuinely absent (true reboot), not when an individual record's name fails to match. Consider matching by a stable key (e.g. the `@holy_*` session UUID/metadata) instead of the raw tmux session name, or reconciling roster sessions against live discovery so a live session is never simultaneously "archived" and "discovered in Hosts."

### Note
Bug B may have been introduced or worsened by the cold-boot change made this session (the archive-when-absent logic). Check `git log`/blame on `restoreWorkspace`. The intent was: true macOS reboot (holy server gone) → archive saved sessions for relaunch. It must not archive sessions that are actually alive.

---

## Working-tree state
Everything from the recent sessions is **uncommitted, not pushed**: roster title-stability fix, runtime "opencode" misclassification fix, the glyph-title roster fix, the "Copy tmux Session ID" roster menu item, the menu cleanup/rename/"New tmux"/font/palette/fullscreen wiring. There is also an earlier diverged remote `main` (carries a bad commit `c7ca77416`) — do not push without the owner's instruction. A prior handoff for the still-broken **menu Split Right/Down** is at `.handoff/2026-06-02-menu-splits-and-tab-titles.md`.

### Recommended first moves
- Bug A: hit Refresh All; if name persists, add glyph-rejection to `HolyDiscoveredTmuxSession.usableExplicitTitle` and re-verify against `@holy_title`.
- Bug B: dump the persisted snapshot's records and compare `tmux.sessionName` to live `tmux -L holy list-sessions`; instrument `restoreWorkspace` to log which records are archived vs restored on launch. That will immediately show whether the cold-boot filter is eating a live session.
