# Holy Ghostty Guide

Updated: 2026-08-22

Holy Ghostty is a macOS workspace for live Ghostty terminal sessions. The app treats a session as the primary unit instead of a terminal tab.

Current release: `0.50`.

## Session Model

A session contains:

- Runtime: Shell, Claude, Codex, or OpenCode.
- Transport: local process or SSH.
- Optional tmux socket and tmux session name.
- Working directory and repository root.
- Optional task reference.
- Optional budget policy.
- Optional session note, edited from the roster row and synced through tmux metadata.
- Git snapshot.
- Runtime telemetry snapshot.
- Append-only event history.
- Archive and relaunch state.

Sessions are persisted in SQLite and restored on launch.

## Main Window

### Left Rail

The standard workspace keeps the left rail scoped to tmux sessions so the terminal can own the main surface. `Tasks` and `Inspect` are hidden from the standard workspace.

Layout controls live at the bottom of the left rail:

- `Single`: show the selected session.
- `Split Right`: show two sessions side by side.
- `Split Down`: show two sessions stacked.
- `Quad`: show up to four sessions.

Layouts are Holy visual layouts over durable tmux sessions, not tmux panes. When a session is visible in a split layout, the roster adds a pane label such as `Left`, `Right`, `Top`, `Bottom`, or a quadrant label.

A dormant Diff implementation is preserved in code for a later explicit agent/worktree comparison mode; it is not exposed in the primary Level 1 chrome.

The window removes the empty native toolbar band in standard mode. The left rail keeps traffic-light clearance, while the terminal surface starts at the top edge. Holy defaults add top terminal padding so the first prompt row clears macOS window controls without adding a separate app bar. The bundled Holy background image stretches to the live terminal surface size.

### Left Roster

The roster lists active sessions. A four-way layout switcher in the roster header chooses how they are arranged, and the choice persists per device:

- `Classic`: grouped by agent runtime with the canonical status vocabulary.
- `Calm`: the same indicators with less surrounding detail.
- `Triage`: lanes by status, so what needs you floats up.
- `Focus`: pinned `Today` sessions on top, the rest dimmed.

TMUX session controls:

- `New`: start a tmux-backed session from the selected default launch profile.
- `Clear`: detach all active sessions from the roster without stopping tmux.
- `Sync`: refresh and reconnect tmux sessions in the roster.
- `Hosts`: open local and remote tmux hosts.
- `More`: launch profiles, templates, hosts, history, duplicate, detach, and kill from roster.

Holy Ghostty creates generated launch profiles for `Local Mac` and configured SSH hosts. The `More` menu can launch from any profile and can set the default profile used by `New`.

The default launch profile is stored in local SQLite state. This keeps personal defaults, such as starting new sessions on a remote workstation from a laptop, out of the public repository.

Each session row's `...` menu keeps `Detach From Roster` beside `Kill from Roster`. Detach leaves tmux alive; kill attempts to stop the backing tmux session and always removes Holy's roster attachment.

Runtime section order in `Classic` and `Calm`:

- Claude
- Codex
- OpenCode
- Shell

Rows are sorted by project/folder context, then parent folder, then launch identity.

Rows show one compact project/folder label, a single activity orb, and quiet risk icons when needed. Selecting a session does not move it.

A row's `...` action menu can add, edit, or clear a session note, and pin or unpin the session for the `Focus` layout's `Today` zone. The note draws with the identity line in the roster and reappears on the session's row in Session Restore.

The roster width defaults to a narrow working size and can be resized by the divider.

### Center Surface

The center region embeds one or more live Ghostty surfaces according to the current Holy pane layout.

### Inspector

The inspector remains available in code, but the standard workspace hides its visible toggle to reserve space for the terminal.

When visible, the inspector shows selected-session state that is not already visible in the terminal.

Sections include:

- Risk: branch, sync, and git state.
- Coordination: worktree, branch, and file overlap risk.
- Verification: last command outcome when shell integration is available.
- Actions: copy handoff, copy diff, duplicate, detach from roster, and kill from roster when available.
- Details: launch metadata.

## Pane Layouts

Pane layout state is persisted with the workspace.

Layouts:

- Single: one selected surface.
- Split Right: selected surface plus another session to the right.
- Split Down: selected surface plus another session below.
- Quad: up to four live surfaces.

Shortcuts:

- `Command-N`: new session from the default launch profile.
- `Command-P`: toggle the Inbox panel.
- `Command-Shift-R`: remote hosts.
- `Command-W`: detach selected session.
- `Option-Q`: kill selected tmux session when available.

## Agent Indicators

The roster's activity orb speaks a six-state vocabulary driven by structured
lifecycle hooks, not by reading terminal text. Each state answers one
question:

| Orb | Meaning |
|---|---|
| Spinner | The agent is working right now. The spinner stops within a second of the agent process dying, and survives long tool-less stretches only while the agent is visibly producing output |
| Question mark | The agent needs you: a committed question, permission request, or failure |
| Glowing green dot | An unread agent reply. It clears only when you genuinely focus the session; selecting a row in a background window does not count |
| Blue dot | You prompted this session within the last 24 hours. Blue is earned by you alone — agent activity, restores, and app launches never fake it |
| Grey dot | No prompt from you in 24 hours, but something happened here (a reply landed, or you read one) within 48 |
| Sleeping Z | Nothing at all for 48 hours or more |

Two quiet companions sit beside the orb:

- The **watcher eye**: a small static eye on any session armed with a
  scheduled `/loop` wakeup. Hover for the next fire time. It disappears when
  the loop stops, the session dies, or a fired wakeup goes ten minutes without
  rescheduling. It never animates: motion in the roster always means compute
  burning, and a promise to wake is not burning.
- Risk icons for shared worktree, shared branch, branch drift, and
  overlapping changed files.

`Mark Unread` in a row's `...` action menu restores the green dot for a reply
you want to revisit.

### Enabling the indicators

Hook installation is explicit: run `Enable Authoritative Agent Indicators`
from the app menu. Holy adds exact-owned lifecycle hooks for Claude Code and
Codex, a Codex committed-turn notifier, and one OpenCode plugin. The hooks
publish only state, source, time, and an opaque event token — never prompts,
responses, or terminal text. Existing hooks and settings stay intact, and
anything Holy does not own fails closed instead of being overwritten. Codex
asks you to approve the handlers once via `/hooks`. Sessions already running
keep their previous hooks until restarted.

Agent notifications (replied, needs you, failed) ride the same event
identities with a persisted watermark, so restarts and duplicate deliveries
never re-alert, and a finish committed while Holy is closed alerts exactly
once on the next launch.

## Claude Usage Guard

A claude.ai Max subscription has three windows that each end work when they
cap: the 5-hour session window, the weekly all-models window, and the weekly
per-model window (Fable). A capped window kills subagents and teammates
outright; only the main session waits for the reset, and everything a worker
had in flight is gone. The usage guard watches all three and tells every
running Claude session to reach a checkpoint, then pause, before that
happens.

### What you see

The green tmux bar carries the numbers, centred between the window list
and the model label: `⌁ claude 5h 30% · wk 41% · Fable 79%`, the same in
every session because the value is machine-global. Calm windows stay plain;
a warn window is a yellow chip, critical or capped a red one; an active
wrap-up prepends `⏸ WRAP UP`, and a probe that cannot reach the endpoint
appends `(stale Nm)`. A pause glyph means a
wrap-up is in force; a clock badge means the last probe failed and the
numbers are carried forward. Click the meter for the popover:

- Account, tier, and how old the snapshot is.
- Each window's percent with threshold ticks, reset time, burn rate, and
  projected time to cap.
- Sessions reporting their own 5-hour and weekly windows through the Claude
  Model Indicator status line.
- Last-known numbers for every account Holy has seen. Only the signed-in
  account is live; the meter follows the keychain.
- `Refresh`, and `Wrap up all sessions` / `Cancel wrap-up`.

With the Claude Model Indicator enabled, the status row printed inside
each Claude pane reads `· 5h N% · wk N%` after the model name — the one
place per-session numbers show. The green bar's model label stays model
and effort only, so usage appears in the bar exactly once, centred.

### Levels

| Level | When | Sessions are told |
|---|---|---|
| Normal | Below every threshold | Nothing |
| Warn | 75% of any window; a projected cap within 40 minutes once the window is past half the warn threshold; or a non-normal severity from Anthropic | Once on entry and again every half lead window: checkpoint now, no new subagents or long tasks |
| Critical | 90%, or a projected cap within 20 minutes | On every tool call: stop at a safe point, commit or write state, reply with a note beginning `PAUSED (usage cap):`, end the turn. `Agent`, `Task`, and `Workflow` are denied |
| Capped | 100% | As critical |

The hook never blocks by exit code, and your own prompts are informed, never
blocked. The thresholds and the poll cadence are preferences (defaults
shown):

```bash
defaults write org.holyghostty.app holy.claudeUsage.warnPercent 75
defaults write org.holyghostty.app holy.claudeUsage.criticalPercent 90
defaults write org.holyghostty.app holy.claudeUsage.leadMinutes 20
defaults write org.holyghostty.app holy.claudeUsage.pollSeconds 60
```

Holy writes them to `usage/policy.json` so the hook applies the same numbers.

### Wrapping up before a switch

`Wrap up all sessions` writes a request that treats every session as
critical on its next tool call, for one lead window or until the keychain
account changes. The request records the signed-in e-mail, so running
`/login` on another account cancels it by itself; `Cancel wrap-up` withdraws
it early.

### Notifications

Each window's first upward level crossing raises a macOS notification,
identified per window and level so a repeat replaces rather than stacks.
Critical and capped also bounce the Dock. The text names the account and
tells you to `/login` on an account with headroom.

### Enabling the guard

Run `Enable Claude Usage Guard…` from the app menu, beside `Enable Claude
Model Indicator…`. Holy installs two generated helpers it owns in
`~/Library/Application Support/Holy Ghostty/` — `claude-usage-probe.py` and
`claude-usage-guard.py` — and adds Holy-owned hook entries on `PreToolUse`
(all tools) and `UserPromptSubmit` in `~/.claude/settings.json`. Other hooks
and settings stay untouched. The same menu item reads `Disable…` once
installed and `Repair…` if the helpers or hooks have drifted; disabling
removes only Holy's own entries and helpers and leaves `usage/` on disk.

The probe reads the signed-in account's OAuth token from the macOS keychain
item `Claude Code-credentials` over a pipe, never on a command line, and
sends it only as a request header to
`https://api.anthropic.com/api/oauth/usage`. Holy runs it once a minute and
never makes network calls itself. If Holy is not running and the snapshot
goes stale, the hook runs the probe in the background, so the guard keeps
working without the app. Enable the Claude Model Indicator too: its
per-session readings keep the guard right for a session still running under
a previous account after `/login` elsewhere.

### Limits

- Only the signed-in account is polled live; other accounts show their
  last-known numbers.
- The per-model (Fable) weekly window exists only in the machine-wide
  snapshot, not in per-session readings.
- The usage endpoint is undocumented; the probe matches the observed
  behavior of Claude Code's own `/usage` screen.
- A session that just ran `/login` may receive one stale warning before its
  own reading refreshes.

## Phase Telemetry

Beneath the authoritative indicators, Holy infers a phase for the bottom
status chrome: `Ready`, `Working`, `Needs Input`, `Complete`, `Issue`.

Inputs:

- Ghostty surface state.
- Ghostty progress reports.
- OSC 133 shell integration command-finished events.
- Visible terminal output near the bottom of the screen.
- tmux metadata.
- SSH git probes for remote sessions.

The parser filters tmux status bars, separators, and terminal chrome, treats
prompt/footer lines as readiness evidence, and clears stale telemetry when
there is no current structured signal. Phase telemetry never decides the
roster's six-state vocabulary.

## Session Restore

When a tmux server dies — a crash, a reboot, or a deliberate kill — the
sessions it carried become restorable. Three doors open the Session Restore
sheet: a workspace banner, `View ▸ Restore Sessions…`, and a callout at the
top of Session History.

Inside the sheet, sessions are grouped per shutdown. Each shutdown group
wears its own recency hue as a wash over its rows, and each group offers a
per-shutdown restore beside per-row actions.

Restore resumes the exact agent conversation:

- Conversations are resolved through one `agent-sessions resolve-batch` call
  covering the whole sheet, with a scoped reindex.
- Assignment is globally unique: no two rows can receive the same
  conversation.
- A resolved row resumes with the exact provider argv — `claude --resume`,
  `codex resume`, or `opencode --session` — and the executable is pinned to
  an absolute path when discovery came from fallback directories, including
  every installed nvm node version.
- An ambiguous match offers a `Pick…` candidate picker instead of guessing.
- A row with no recoverable history is offered only as a labeled shell-only
  recreate, never a fake resume.
- Machine-titled helper shells (`-shell-XXXXXXXX`) are collapsed inside
  their shutdown group.
- Rows carry the session's note.

The identity guarantee is the argv itself: once a row restores, nothing
re-resolves behind it.

## Human Inbox

`Command-P` or `View ▸ Inbox Panel` toggles the Human Inbox: one pane for
everything waiting on a human.

Sections:

- GitHub attention: needs-review items first, then maintainer sweeps, with
  bot authors collapsed into one digest per repository.
- In-app alerts: delivered alerts stay listed until explicitly acknowledged.
- Manna board triage: rows from the repository's agent-do manna board, with
  human decisions listed prominently. Ids are validated against manna's own
  alphabet before any board command runs.

Rows clear themselves when the underlying condition clears. The unread badge
refreshes on a five-minute cadence while the panel is hidden — and
immediately on panel open, app foreground, or manual refresh — so it cannot
lie about what is waiting.

## Creating Sessions

The `New` button creates a tmux-backed session from the selected default launch profile.

Generated profiles:

- `Local Mac`: local Holy-managed tmux session.
- SSH hosts: remote Holy-managed tmux sessions over the configured host destination.

When no profile state exists yet, Holy Ghostty creates these profiles automatically. If exactly one SSH host exists on first profile creation, that host becomes the default `New` target; otherwise `Local Mac` is the default. The default can be changed later from `More`.

Session templates and advanced launch settings are available from the left-rail `More` menu and task/remote flows.

Launch settings support:

- Runtime.
- Title.
- Objective.
- Transport.
- Host destination.
- Working directory.
- Repository root.
- Launch command.
- Initial input.
- Environment variables.
- Workspace strategy.
- Budget policy.
- tmux socket.
- tmux session name.

## Workspace Strategies

### Direct Directory

Use the provided directory as-is.

### Attach Existing Worktree

Attach to an existing git worktree path.

### Create Managed Worktree

Create a dedicated worktree for the session.

## Guardrails

Guardrails are evaluated for non-shell agent sessions.

- Shared worktree: blocking.
- Shared branch: warning.
- Overlapping changed files: conflict risk.
- Branch ownership drift: warning.

Local shell sessions do not receive shared-worktree warnings.

Overlapping changed files are computed only across distinct worktrees. Two sessions attached to the same checkout report their shared uncommitted file count (`N uncommitted files in the shared checkout`) instead of claiming cross-session overlap.

## Remote Hosts

Remote hosts support:

- Manual host records.
- SSH config import.
- Tailscale import.
- tmux socket configuration.
- remote tmux session discovery.
- attach into an existing remote tmux session.

Remote tmux discovery reads Holy metadata when present and falls back to tmux pane path data when needed.

## Persistence

Database:

```text
~/Library/Application Support/org.holyghostty.app.debug/HolyGhostty/holy-ghostty.sqlite3
```

Persistence includes:

- Active sessions.
- Archived sessions.
- Event ledger.
- Latest git snapshot.
- Latest runtime telemetry.
- Latest budget telemetry.
- Task records.
- Launch profiles and the default `New` profile.
- Compatibility views.

The database uses schema migrations and WAL.

## Automation

Entrypoints:

- `holy-ghostty://spawn`
- `scripts/holy-spawn-session.sh`
- AppleScript `spawn`

## Build

Requirements:

- macOS 15 or newer.
- Xcode 26 or newer.
- Zig 0.15.2.

Commands:

```bash
scripts/install-holy-ghostty.sh
open -a "Holy Ghostty"
```

The installer owns both halves of the product: a fingerprinted ReleaseFast
Ghostty core (framework plus generated resources) and the ReleaseLocal Swift
app. It fails before replacing the installed app if that payload is missing,
stale, unverified, or built in another optimization mode, and it keeps the old
bundle available for rollback until the replacement passes final validation.

## Public Status

Source-ready:

- yes

Release-ready:

- source and ad-hoc app zip only

Missing release infrastructure:

- Developer ID signing configuration.
- notarization.
- packaged installer.
- automated release workflow.

Known implementation limits:

- Phase telemetry is heuristic; roster indicators are hook-driven.
- Remote orchestration is SSH/tmux based.
- Broadcast input is not implemented.
- Dependency-chain automation is not implemented.
- External task writeback is not implemented.
- Settings UI is limited.
