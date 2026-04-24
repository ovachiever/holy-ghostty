# Holy Ghostty Guide

Updated: 2026-04-24

Holy Ghostty is a macOS workspace for live Ghostty terminal sessions. The app treats a session as the primary unit instead of a terminal tab.

Current release: `0.25`.

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

### Top Bar

- `+`: create a local shell immediately.
- checklist: task inbox.
- server: remote hosts.
- grid: grid mode.
- split: compare mode.
- diagonal arrows: focus mode.
- menu: templates, task inbox, remote hosts, history, duplicate, archive.

Only the empty space in the top bar drags the window.

### Left Roster

The roster lists active sessions in the user's manual order.

Rows show:

- First line: `Runtime - Project`.
- Second line: `Local`, `Host/session`, or `Host/tmux-socket`.

The handle on the left of a row reorders sessions. The order is persisted. Selecting a session does not move it.

The roster width defaults to a narrow working size and can be resized by the divider.

### Center Surface

The center region embeds the selected live Ghostty surface.

### Right Inspector

The inspector shows selected-session state that is not already visible in the terminal.

Sections include:

- Risk: branch, sync, and git state.
- Coordination: worktree, branch, and file overlap risk.
- Verification: last command outcome when shell integration is available.
- Actions: copy handoff, copy diff, duplicate, archive.
- Details: launch metadata.

## Display Modes

Display mode state is in SwiftUI view state. It is not persisted.

Modes:

- Standard: roster, selected surface, inspector.
- Focus: selected surface only, with a small status overlay.
- Grid: up to four session tiles.
- Compare: selected session next to another session, with repository/worktree/branch comparison.

Shortcuts:

- `Command-N`: new shell.
- `Command-Shift-T`: task inbox.
- `Command-Shift-R`: remote hosts.
- `Command-Shift-G`: grid.
- `Command-Shift-D`: compare.
- `Command-Shift-F`: focus.

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

## Creating Sessions

The `+` button creates a local shell immediately.

Session templates and advanced launch settings are available from the top-right menu and task/remote flows.

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

- no

Missing release infrastructure:

- code signing configuration.
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
