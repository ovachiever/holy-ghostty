# Holy Ghostty Guide

Updated: 2026-05-12

Holy Ghostty is a macOS workspace for live Ghostty terminal sessions. The app treats a session as the primary unit instead of a terminal tab.

Current release: `0.40`.

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

## Runtime Status

Holy Ghostty infers runtime status. It does not receive structured internal state from Claude, Codex, or OpenCode.

Inputs:

- Ghostty surface state.
- Ghostty progress reports.
- OSC 133 shell integration command-finished events.
- Visible terminal output near the bottom of the screen.
- tmux metadata.
- SSH git probes for remote sessions.

Filtering:

- tmux status bars are ignored.
- terminal separators are ignored.
- terminal chrome is ignored.
- prompt/footer lines are treated as readiness evidence.
- stale telemetry is cleared when there is no current structured signal.

Displayed phases:

- `Ready`
- `Working`
- `Needs Input`
- `Complete`
- `Issue`

Roster cues:

- Working: multicolor spinner.
- Waiting on user: waiting orb colored by freshness.
- Complete: subdued gray orb.
- Stalled: orange orb.
- Failed: red orb.
- Shared worktree, shared branch, branch drift, and overlapping files: quiet inline risk icons.

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
zig build -Demit-xcframework
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug SYMROOT=build build
scripts/install-holy-ghostty.sh Debug
open -a "Holy Ghostty"
```

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

- Runtime status is heuristic.
- Remote orchestration is SSH/tmux based.
- Broadcast input is not implemented.
- Dependency-chain automation is not implemented.
- External task writeback is not implemented.
- Settings UI is limited.
