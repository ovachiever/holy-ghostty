<p align="center">
  <img src="./docs/holy-ghostty/assets/holy-ghostty-logo.jpeg" alt="Holy Ghostty logo" width="120">
</p>

<h1 align="center">Holy Ghostty</h1>

<p align="center">
  An operating system for AI coding agents, built into a macOS terminal.
</p>

<p align="center">
  <a href="./docs/holy-ghostty/README.md">Guide</a>
  ·
  <a href="./docs/holy-ghostty/engineering-spec.md">Engineering Spec</a>
  ·
  <a href="./docs/holy-ghostty/agent-sessions-interoperability.md">Interoperability</a>
  ·
  <a href="./CHANGELOG.md">Changelog</a>
  ·
  <a href="https://erikfritsch.substack.com/p/the-terminal-became-the-holy-ghost">The Essay</a>
</p>

<p align="center">
  <img src="./docs/holy-ghostty/assets/holy-ghostty-app.jpg" alt="Holy Ghostty workspace" width="920">
</p>

## What this is

Every AI company is selling better coding agents. Nobody sells the place where
a fleet of them works for one person. Holy Ghostty is that place: a native
macOS workspace, grown out of a fork of the [Ghostty](https://github.com/ghostty-org/ghostty)
terminal, that runs AI coding agents the way an operating system runs
processes.

The parts map one to one:

- **The roster is the process table.** Every session, on this machine or on
  any machine you reach over SSH, survives reboots because tmux never hangs
  up, and every row reports its true state: working, needs you, asleep.
- **The board is the scheduler.** Work lives on a git-backed ledger as items
  with sealed work orders. Dispatch is one confirmation: pick the item, pick
  how much intelligence the job deserves, and a worker spawns in the right
  repository already holding its orders.
- **The archive is long-term memory.** Every conversation with every AI coding
  tool on the machine is indexed into one searchable place that answers
  questions with citations into its own history.
- **The usage guard is the resource governor.** Account burn rides in the
  status bar. The fleet gets warned as usage climbs, new hiring stops near the
  cap, and running work is asked to checkpoint before the lights go out.
- **The inbox is attention.** GitHub activity for your repositories sits
  beside the work instead of in another browser tab.

## Why you'd care

If you run one agent in one repository, a chat window is fine. The moment you
run several agents across several projects, the chat window becomes the
bottleneck: tab-hunting, lost context, and no shared truth about who is doing
what. Holy Ghostty exists for the person who wants to build many things at
once, with a day that feels like running a shop rather than refereeing
browser tabs.

## Why there's nothing else like it

- **It runs harnesses, not a vendor.** Claude Code, Codex, OpenCode, Factory's
  Droid: full workers with their own habits, whatever brain each one carries.
  They all read the same board, write to the same ledger, land in the same
  archive. The house rule is written down: vendors sell features, you keep the
  protocol.
- **Agents coordinate through a ledger, never chat.** There is no message
  plane between workers. If something is true, it is written where everyone
  can read it, in work orders sealed by hash that refuse to open if they
  drift. One shop, one truth, and the truth has receipts.
- **Sessions are durable by construction.** tmux owns the processes. Macs
  attach and detach, reboots don't end work, and every attached machine shares
  the same read on session state.

The longer story, and why a terminal turned out to be the right bones for all
of this, is in the launch essay:
[The Terminal Became the Holy Ghost](https://erikfritsch.substack.com/p/the-terminal-became-the-holy-ghost).

## Workspace

| Surface | Capability |
|---|---|
| Terminal | Local and SSH/tmux sessions for Shell, Claude, Codex, and OpenCode, with single, side-by-side, stacked, and quad layouts. |
| Board | Manna estate and project ledgers, human asks, peer activity, confirmed actions, cited board answers, and Claude or Codex worker dispatch. |
| Archive | Five-provider history indexing, transcripts, parent and child sessions, tags, notes, hybrid search, research chat, and remote archive browsing. |
| Inbox | GitHub attention for all repositories or the selected session's repository. |

`New` starts a tmux session from the default launch profile. `Hosts` manages SSH
hosts and discovers existing sessions. `Clear` detaches the roster while tmux
keeps running. `Sync` reconciles known sessions with the discovered inventory.
`Archive` and `Board` fill the terminal area; `‹ terminal` returns to live panes.
`Command-P` opens the GitHub dock.

Manna IDs highlighted in any pane Command-click through to their board item.
Holding Command over the roster turns session indicators into immediate kill
controls.

The roster sorts by runtime, attention, or pinned Today sessions. Session notes,
launch profiles, pane layouts, and workspace state persist locally. Explicit
launch runtimes control grouping. Git state and worktree checks identify shared
checkouts, branch drift, and changed-file overlap across distinct worktrees.

## Shared Session State

Enable **Authoritative Agent Indicators** from the app menu to install lifecycle
hooks for Claude Code, Codex, and OpenCode. The hooks publish metadata without
prompt or response text. Codex requires handler approval through `/hooks`.

The roster distinguishes working, needs-you, unread, used-today, inactive, and
sleeping sessions. Seen acknowledgements and prompt recency belong to the tmux
host, so attached Macs share the same state. A host-side journal restores missing
registers after reboot. Selecting a session in a background window does not mark
it read. Questions and permissions remain until the provider resolves them.

Session Restore groups interrupted sessions by shutdown. Captured conversation
identity selects the provider session. The native archive resolves fallback
candidates, with a picker for ambiguity and an explicit shell-only option when
history is absent. Claude, Codex, and OpenCode resume through provider-specific
commands.

## Board and Archive

Board requires [`agent-do`](https://github.com/ovachiever/agent-do) and a Manna board on the selected host. It reads
`manna state --json` and `manna estate --json`. Changes require confirmation.
Type to filter the board; press Enter to ask a question. Answers link to cited
items. `Claim & build` opens a confirmed worker with the item's sealed handoff.

Archive reads Claude Code, Codex, Droid, Cursor, and OpenCode history into
`holy-archive.sqlite3`. Keyword search works locally without model credentials.
Semantic search requires a configured embedding provider and generated vectors.
Research chat uses an OpenAI API key available to the app process. Board model
requests use the configured Claude CLI or OpenAI route.

Configured SSH hosts contribute their own indexed archives. Remote rows show the
source host and freshness. Tags and notes are edited on the owning host.
Claude, Codex, and OpenCode conversations resume into that host's roster.
Droid and Cursor history is browsable.

See the [guide](docs/holy-ghostty/README.md) for setup, search syntax, model
configuration, and session controls.

## Usage Guard

Enable **Claude Usage Guard…** from the app menu. Account usage appears beside
the clock in the tmux status bar. **Claude Usage…** in the roster menu opens
reset times, projected caps, account readings, refresh, and manual wrap-up.

The defaults notify Claude at 75%, block new worker spawns at 90%, and request a
checkpoint and pause at 95% or within 20 minutes of the projected cap. Existing
work continues at the 90% tier. Per-session readings take precedence for their
account windows. Stale readings carry an age marker.

Codex contributes rate-limit, per-model, and reset-credit readings through
`codex app-server`. These are usage gauges; the installed guard hooks act on
Claude sessions. Provider limits still determine when requests are accepted.

## Requirements

- macOS 15 or newer.
- Xcode 26 or newer with the Metal Toolchain component.
- Zig 0.15.2 for the Ghostty core.
- tmux and the selected runtime executable on each session host.
- SSH access and Python 3 on remote hosts for metadata and archive queries.
- [`agent-do`](https://github.com/ovachiever/agent-do) on hosts used for Board; authenticated GitHub access for the Inbox.

Install the Xcode component if needed:

```bash
xcodebuild -downloadComponent MetalToolchain
```

## Build and Install

Build the engine core through the **Build Holy macOS core** CI workflow. The
current macOS 26 SDK cannot be linked by the pinned local Zig 0.15.2 toolchain.
Download the workflow's core artifact whose inputs match this checkout, then
import its contained zip before running the installer:

```bash
scripts/build-holy-ghostty-core.sh import /path/to/HolyGhostty-Core-ReleaseFast.zip && \
scripts/build-holy-ghostty-core.sh verify && \
scripts/install-holy-ghostty.sh && \
open /Applications/Holy\ Ghostty.app
```

CI builds the core with `ReleaseFast`; the installer reuses the verified import
and builds the Swift app with `ReleaseLocal`. Source and payload fingerprints
bind the framework and generated resources to the executable. A failed import
or verification blocks installation. Installation retains the previous app for
rollback until signing, registration, and final verification pass. The installer
does not launch the app; the final command opens the installed bundle by path.

For a Swift app build without installation, import and verify the core first:

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration ReleaseLocal SYMROOT=build build
```

The importer checks current core inputs and all payload hashes. A bare
`zig build -Demit-xcframework` does not produce the supported release payload.
The installed bundle is `/Applications/Holy Ghostty.app`. The
[release procedure](docs/holy-ghostty/engineering-spec.md#release-procedure)
covers the coordinated acceptance run and tag.

## Data and Automation

Workspace and Archive databases live under
`~/Library/Application Support/org.holyghostty.app/HolyGhostty/`.
Debug builds use the `org.holyghostty.app.debug` container.
Claude bridge helpers and usage history live under
`~/Library/Application Support/Holy Ghostty/`.
Provider history stays in each provider's own directory.

Sessions can also be created through `holy-ghostty://spawn`, AppleScript `spawn`,
and `scripts/holy-spawn-session.sh`.

Optional host administration tools are documented in the
[engineering spec](docs/holy-ghostty/engineering-spec.md#host-administration).

## Repository

- `src/` contains the Ghostty terminal core.
- `macos/Sources/HolyGhostty/` contains the native workspace.
- `docs/holy-ghostty/` contains the product guide and engineering contracts.
- `scripts/` contains build, installation, and session helpers.

Holy Ghostty is a macOS fork of [Ghostty](https://github.com/ghostty-org/ghostty).
Ghostty's terminal documentation is at [ghostty.org/docs](https://ghostty.org/docs).
