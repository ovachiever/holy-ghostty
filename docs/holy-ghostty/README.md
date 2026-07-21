# Holy Ghostty Guide

Updated: 2026-07-21

Holy Ghostty is a macOS workspace for live Ghostty terminal sessions. The app treats a session as the primary unit instead of a terminal tab.

Current release: `0.44`.

## Session Model

A session contains:

- Runtime: Shell, Claude, Codex, or OpenCode.
- Transport: local process or SSH.
- Optional tmux socket and tmux session name.
- Working directory and repository root.
- Optional task reference.
- Optional budget policy.
- Git snapshot.
- Runtime telemetry snapshot.
- Append-only event history.
- Archive and relaunch state.

Sessions are persisted in SQLite and restored on launch.

## Main Window

### Left Rail

The standard workspace keeps the left rail scoped to tmux sessions so the terminal can own the main surface. `Tasks` and `Inspect` are hidden from the standard workspace for now.

Layout controls live at the bottom of the left rail:

- `Single`: show the selected session.
- `Split Right`: show two sessions side by side.
- `Split Down`: show two sessions stacked.
- `Quad`: show up to four sessions.

Layouts are Holy visual layouts over durable tmux sessions, not tmux panes. When a session is visible in a split layout, the roster adds a pane label such as `Left`, `Right`, `Top`, `Bottom`, or a quadrant label.

The old Diff implementation is preserved in code for a later explicit agent/worktree comparison mode, but it is not exposed in the primary Level 1 chrome.

The window removes the empty native toolbar band in standard mode. The left rail keeps traffic-light clearance, while the terminal surface starts at the top edge. Holy defaults add top terminal padding so the first prompt row clears macOS window controls without adding a separate app bar. The bundled Holy background image stretches to the live terminal surface size.

### Left Roster

The roster lists active sessions grouped by runtime.

TMUX session controls:

- `New`: start a tmux-backed session from the selected default launch profile.
- `Clear`: detach all active sessions from the roster without stopping tmux.
- `Sync`: refresh and reconnect tmux sessions in the roster.
- `Hosts`: open local and remote tmux hosts.
- `More`: launch profiles, templates, hosts, history, duplicate, detach, and kill from roster.

Holy Ghostty creates generated launch profiles for `Local Mac` and configured SSH hosts. The `More` menu can launch from any profile and can set the default profile used by `New`.

The default launch profile is stored in local SQLite state. This keeps personal defaults, such as starting new sessions on a remote workstation from a laptop, out of the public repository.

Each session row's `...` menu keeps `Detach From Roster` beside `Kill from Roster`. Detach leaves tmux alive; kill attempts to stop the backing tmux session and always removes Holy's roster attachment.

Section order:

- Claude
- Codex
- OpenCode
- Shell

Rows are sorted by project/folder context, then parent folder, then launch identity.

Rows show one compact project/folder label, a single activity orb, and quiet risk icons when needed. Selecting a session does not move it.

The roster width defaults to a narrow working size and can be resized by the divider.

### Center Surface

The center region embeds one or more live Ghostty surfaces according to the current Holy pane layout.

### Inspector

The inspector remains available in code, but the standard workspace hides its visible toggle for now to reserve space for the terminal.

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

`Mark Unread` in a row's context menu restores the green dot for a reply you
want to revisit.

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
