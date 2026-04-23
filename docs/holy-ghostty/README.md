# Holy Ghostty

Last updated: 2026-04-23

Holy Ghostty is a macOS-native control surface for agentic coding sessions built on real Ghostty terminal surfaces. The app is terminal-first, but sessions are no longer disposable tabs. They are durable, tmux-backed work units with launch policy, budget state, task linkage, event history, and remote attach paths.

This document is the human-facing guide for the app as it exists in the repository today.

## What It Is

Holy Ghostty keeps Ghostty's terminal core and adds a macOS shell around it with:

- a live session roster
- a focused active surface
- a right-side operator inspector
- tmux-backed local and SSH session launches
- session templates
- archive and relaunch history
- worktree-aware launch policy
- git-aware coordination and collision detection
- runtime-specific heuristics for Shell, Claude, Codex, and OpenCode
- structured runtime telemetry, budget intelligence, and an append-only event ledger
- an external task inbox
- remote host discovery and remote tmux attach

## Current Product Shape

The app opens into a mission-control shell:

- Left rail: active sessions, sorted by urgency and recency. Each row stacks runtime on top with the project directory as a dim subtitle that middle-truncates on overflow.
- Center: the selected live Ghostty surface. The Holy ASCII angel-ghost logo rides behind every surface as a 4% opacity watermark — an opinionated default baked into the app. Override via `~/.config/ghostty/config`.
- Right rail: governed by a Prime Rule — only surface information the terminal itself cannot. The sections, top to bottom: **Mission** (linked task only), **Runtime** (active telemetry only), **Budget** (configured or with usage), **Timeline**, **Coordination** (internal collisions + external peers via `agent-do coord`), **Risk** (git state summarized by consequence — project / deps / CI / scripts / config — with the file list behind a disclosure), **Verification** (last command outcome from OSC 133 shell integration), **Actions** (Copy handoff · Copy diff · Duplicate · Archive), and a collapsed **Details** drawer for launch metadata.

Auxiliary flows:

- New Session: compose a local or remote tmux-backed session
- Task Inbox: create or manage external work items and launch them into sessions
- Remote Hosts: save hosts, import them from SSH config or Tailscale, and discover remote tmux sessions
- History: review, search, and relaunch archived sessions

Display modes:

- Standard
- Focus
- Grid
- Diff

## What You Can Do Today

- Run real live Ghostty terminals inside a native macOS app
- Launch Shell, Claude, Codex, and OpenCode sessions
- Launch local sessions through tmux so they remain attachable after Holy Ghostty closes
- Launch remote SSH sessions through tmux so they remain attachable from other machines
- Save and reuse launch templates
- Start sessions directly in a directory, attach an existing worktree, or create a managed worktree
- Detect shared-worktree and shared-branch collisions before launch
- Track git state for local and remote sessions
- See overlapping changed files and overlap risk between sessions
- Use focus, grid, and diff modes for different operator tasks
- Search session history and relaunch archived sessions with recovery context
- Track runtime telemetry, budget usage, event timelines, and coordination state
- Manage external tasks from GitHub, Linear, Jira, or manual entries
- Import remote hosts from `~/.ssh/config` and Tailscale
- Discover remote tmux sessions and attach them into first-class Holy sessions
- Automate session creation through the `holy-ghostty://spawn` URL scheme, the `scripts/holy-spawn-session.sh` helper, or AppleScript `spawn`

## Install And Launch

Prerequisites:

- macOS 15+
- Xcode 26+ with Metal Toolchain (`xcodebuild -downloadComponent MetalToolchain`)
- Zig **0.15.2** (not 0.16; Zig minor versions are breaking)

Build and install:

```bash
zig build -Demit-xcframework
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug SYMROOT=build build
scripts/install-holy-ghostty.sh Debug
open -a "Holy Ghostty"
```

Installed app path:

```text
/Applications/Holy Ghostty.app
```

If you only need the Zig core and not the macOS app bundle:

```bash
zig build -Demit-macos-app=false
```

## First-Run Tutorial

### 1. Launch the app

Open `Holy Ghostty.app`. If there is no saved workspace and no archive yet, the app seeds a default interactive shell session so the window is immediately usable.

### 2. Understand the shell

- The roster is the list of active sessions
- The center surface is the selected session's live terminal
- The inspector explains what that session is doing, where it is running, and whether it is colliding with any other session

### 3. Create a session

Click `New Session`.

The composer lets you define:

- Runtime: `Shell`, `Claude`, `Codex`, or `OpenCode`
- Title and mission
- Transport: `Local` or `SSH`
- Host destination for SSH sessions
- Workspace strategy
- Repository root or working directory
- Branch
- Launch command or bootstrap command
- Initial input
- Environment variables
- Budget policy
- Tmux socket and tmux session name

By default, Holy launches through tmux. That is intentional. The tmux server owns the durable session; Holy is the operator surface attached to it.

### 4. Pick the right workspace strategy

Holy Ghostty supports three launch strategies:

#### Direct directory

Use the directory exactly as provided.

Use it when:

- you are running a manual shell
- you are debugging something locally
- you intentionally want the session to work in the same checkout as you

#### Attach existing worktree

Use an already-created git worktree.

Use it when:

- you already manage worktrees externally
- the session must attach to a known worktree path
- you are restoring an existing agent's working area

#### Create managed worktree

Let Holy Ghostty create and own a dedicated worktree.

Use it when:

- the session is agent-driven
- you want cleaner ownership boundaries
- you want to reduce accidental branch or file overlap
- you expect the session to run for a while

This is the best default for long-running AI coding sessions.

### 5. Watch the guardrails before launch

The composer checks the draft against active sessions before launch.

Two important cases:

- Shared worktree: blocking
- Shared branch: warning with explicit override

If the app warns you, read it. The whole point is to stop invisible collisions before they form.

### 6. Work with the live session

Once launched:

- the session appears in the roster
- the terminal becomes a real live Ghostty surface
- the inspector shows mission, telemetry, budget, git state, tmux context, and coordination state

The session phase can move through states such as active, working, waiting for input, completed, or failed. The app derives these from Ghostty state, runtime adapters, and telemetry parsing.

### 7. Use display modes

- `Command-N`: new session
- `Command-Shift-T`: task inbox
- `Command-Shift-R`: remote hosts
- `Command-Shift-F`: focus mode
- `Command-Shift-G`: grid mode
- `Command-Shift-D`: diff mode

Use:

- Standard mode for everyday work
- Focus mode when one session matters most
- Grid mode when you need to watch multiple sessions at once
- Diff mode when comparing two related sessions before merging or deciding which path to keep

### 8. Use the task inbox

Task Inbox is where work items become sessions.

You can:

- create manual tasks
- store GitHub, Linear, Jira, or generic URL tasks
- set preferred runtime, mission, and working directory
- launch directly from a task into a session

### 9. Use remote hosts

Open `Remote Hosts` when you want Holy to work like a serious tmux control plane instead of a local-only app.

You can:

- add hosts manually
- import hosts from `~/.ssh/config`
- import hosts from Tailscale
- choose a tmux socket per host
- refresh discovered remote tmux sessions
- attach a discovered session into a first-class Holy session

Holy-managed tmux sessions carry metadata so discovery can reconstruct better labels and context than plain `tmux ls`.

### 10. Archive finished work

When a session is done, archive it.

Archive preserves:

- launch spec
- mission and title
- runtime
- timestamps
- output preview
- git snapshot
- runtime telemetry
- budget telemetry
- event timeline
- recovery context

The History sheet lets you:

- search archived sessions
- inspect archived state
- relaunch directly
- relaunch into the editor flow
- retry recovery-archived sessions
- delete old archives

## Automation

### URL scheme

Holy Ghostty registers:

```text
holy-ghostty://spawn?...query...
```

Example:

```bash
open 'holy-ghostty://spawn?host=studio&transport=ssh&tmuxSession=temp&title=studio%2Ftemp'
```

### Shell helper

The repo includes:

```bash
scripts/holy-spawn-session.sh
```

Examples:

```bash
./scripts/holy-spawn-session.sh --tmux-session temp --title temp
./scripts/holy-spawn-session.sh --host studio --transport ssh --tmux-session temp --title studio/temp
```

### AppleScript

Holy Ghostty also exposes an AppleScript `spawn` command for first-class Holy sessions. Use this when replacing keyboard-macro workflows that previously targeted tabbed Ghostty windows.

## Best Practices

- Prefer managed worktrees for long-running agent sessions.
- Treat shared-branch overrides as exceptional, not normal.
- Use direct directory sessions for short manual work, not for durable agent ownership.
- Give every session a real mission so the roster stays legible.
- Leave tmux enabled unless you intentionally want an ephemeral shell.
- Use a dedicated tmux session name for anything you expect to revisit remotely.
- Use the remote host registry instead of ad hoc SSH macros when you want repeatable attach and discovery.
- Archive sessions once they stop being operationally active.
- Save templates for repeated launch patterns instead of hand-entering the same spec.
- Read the inspector before relaunching an archived session so you understand ownership, branch, budget, and git context.
- When two sessions overlap on files, resolve it early instead of hoping the merge will be obvious later.

## Current Limitations

Holy Ghostty is useful and substantially complete, but it is not finished.

Current limitations:

- Runtime telemetry is still largely inference-based, not a full embedded VT/PTY event bridge.
- Remote host discovery is registry-driven, not zero-config network discovery.
- There is no dependency-chain orchestration between sessions yet.
- There is no broadcast input across multiple sessions yet.
- External task sources do not receive status writeback yet.
- There is no full preferences surface for notifications, budgets, templates, and remote policy.
- Signing, notarization, and release distribution are not finished.
- Production hardening still needs more migration, restore, and degraded-mode testing.

## Where To Read More

- Engineering spec: `docs/holy-ghostty/engineering-spec.md`
- Request vs current state: `docs/holy-ghostty/request-vs-current-state.md`
- Roadmap: `docs/holy-ghostty/roadmap.md`
- v0.2 implementation plan: `docs/holy-ghostty/v0.2-implementation-plan.md`
- Interoperability notes: `docs/holy-ghostty/agent-sessions-interoperability.md`
