# Holy Ghostty

Last updated: 2026-04-18

Holy Ghostty is a macOS-native control surface for agentic coding sessions built on top of real Ghostty terminal surfaces. It replaces the "too many tabs, too little awareness" workflow with a single mission-control window that keeps live terminal sessions, launch policy, worktree ownership, git context, notifications, templates, and session history in one place.

This README is the human-facing guide for the app as it exists today.

## What It Is

Holy Ghostty is not a new terminal emulator core. The terminal rendering, PTY handling, and emulation remain Ghostty. The Holy layer is a macOS shell around those surfaces that adds:

- a live session roster
- a focused active surface
- a context and coordination inspector
- session launch templates
- archive and relaunch history
- worktree-aware launch policies
- git-aware coordination and collision detection
- runtime-specific state heuristics for Shell, Claude, Codex, and OpenCode
- native notifications when a session fails, needs input, collides, drifts, or completes

## Current Product Shape

The app opens into a three-part shell:

- Left rail: the live session roster, sorted by attention and recency
- Center: the selected live Ghostty terminal surface
- Right rail: the inspector for mission, telemetry, git status, coordination, ownership, preview text, and environment

There are also two major auxiliary flows:

- New Session: the composer for creating a new agent or shell session
- History: the archive for reviewing and relaunching past sessions

## What You Can Do Today

- Run real live terminal sessions inside a native macOS app
- Launch Shell, Claude, Codex, and OpenCode sessions
- Save and reuse templates
- Start sessions directly in a directory, attach an existing worktree, or create a managed worktree
- Detect shared-worktree and shared-branch collisions before launch
- Override shared-branch warnings when you really intend to share ownership
- Track live git state for each session
- See overlapping changed files and overlapping work between sessions
- Archive completed or paused sessions
- Search session history and relaunch archived sessions
- Get macOS notifications for attention-worthy state changes

## Install And Launch

Build and install the current app bundle:

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug SYMROOT=build build
scripts/install-holy-ghostty.sh Debug
open -a "Holy Ghostty"
```

Installed app path:

```text
/Applications/Holy Ghostty.app
```

If you only need the Zig core and not the macOS app bundle, the upstream repo build still works:

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

In the composer you can set:

- Runtime: `Shell`, `Claude`, `Codex`, or `OpenCode`
- Title: the human label shown in the roster
- Mission: the task or goal for the session
- Workspace strategy
- Repository root or working directory
- Branch
- Launch command
- Initial input
- Environment variables

### 4. Pick the right workspace strategy

Holy Ghostty supports three launch strategies:

#### Direct directory

Use the directory exactly as provided. This is the lightest-weight option.

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

Let Holy Ghostty create and own a dedicated worktree under Application Support.

Use it when:

- the session is agent-driven
- you want cleaner ownership boundaries
- you want to reduce accidental branch or file overlap
- you expect the session to run for a while

This is the best default for long-running AI coding sessions.

### 5. Watch the guardrails before launch

The composer checks the draft against active sessions before launch.

Two important cases:

- Shared worktree: blocking. Holy Ghostty will stop the launch.
- Shared branch: warning. Holy Ghostty allows an explicit override, but treats it as a higher-risk action.

If the app warns you, read it. The point of the product is to prevent invisible session collisions before they happen.

### 6. Work with the live session

Once launched:

- the session appears in the roster
- the terminal becomes a real live Ghostty surface
- the inspector shows ownership, git state, signals, command telemetry, preview text, and coordination info

The session phase can move through states such as active, working, waiting for input, completed, or failed. The app derives these from Ghostty state plus runtime-specific heuristics.

### 7. Use templates

Holy Ghostty ships with built-ins and also lets you save your own launch setups.

Built-in templates include:

- Shell Workspace
- Claude Code
- Codex
- OpenCode
- Managed Claude Worktree
- Managed Codex Worktree

Use templates when you want repeatable session startup without re-entering command, mission, environment, and workspace choices.

### 8. Archive finished work

When a session is done, archive it.

Archive preserves:

- launch spec
- mission and title
- runtime
- timestamps
- output preview
- git snapshot
- command telemetry
- ownership and coordination context

The History sheet lets you:

- search archived sessions
- inspect archived state
- relaunch directly
- relaunch into the editor flow
- delete old archives

### 9. Pay attention to the inspector

The right rail is where Holy Ghostty becomes useful instead of just decorative.

Read it for:

- current mission
- runtime and session signal
- command counts and last outcome
- git branch and sync status
- changed files
- shared worktree or shared branch warnings
- overlapping changed files
- output preview
- environment

### 10. Let alerts interrupt you selectively

Holy Ghostty can surface macOS notifications when a session:

- fails
- needs input
- completes
- drifts from reserved branch ownership
- collides with another session

Treat these as interrupt channels, not ambient decoration.

## Feature Guide

### Supported runtimes

#### Shell

Manual interactive shell session. Best for:

- fallback manual work
- repair work
- commands you do not want an agent to own

#### Claude

Claude-oriented session defaults and markers.

Best for:

- long-form agent work
- repository exploration
- file-editing tasks

#### Codex

Codex-oriented session defaults and markers.

Best for:

- code changes
- patch-driven iteration
- terminal-native AI coding workflows

#### OpenCode

OpenCode-oriented session defaults and markers.

Best for:

- alternate agent workflows
- experiments in parallel with other runtimes

### Session coordination

Holy Ghostty watches for:

- shared worktrees
- shared branches
- overlapping changed files
- branch ownership drift

This is the current coordination model. It is one of the most important existing features and one of the clearest differences from "just a bunch of terminal tabs."

### Archive and relaunch

Archived sessions are first-class records, not discarded tabs. Use them to:

- reconstruct why a session existed
- revisit a prior branch or worktree context
- relaunch a known-good setup
- preserve operational history

## Best Practices

- Prefer managed worktrees for agent-driven sessions.
- Treat shared-branch overrides as exceptional, not normal.
- Use direct directory sessions for short manual work, not for long-running agent ownership.
- Give every session a real mission so the roster remains legible.
- Archive sessions once they stop being operationally active.
- Save templates for repeated agent setups instead of hand-entering the same launch spec.
- Read the inspector before relaunching an archived session so you understand ownership, branch, and git context.
- Use a Shell session as your manual intervention lane while agents stay isolated in their own worktrees.
- When two sessions overlap on files, resolve it early. Do not let both continue blindly.

## Current Limitations

Holy Ghostty is useful today, but it is not the finished end-state of the original vision.

Current limitations:

- Runtime detection is still heuristic and adapter-driven, not a fully structured embedded telemetry bridge.
- Persistence is JSON snapshot based, not a durable SQLite event ledger.
- There is no cost or token budget engine yet.
- There is no grid mode, focus mode, or diff mode yet.
- There is no deep external task-system integration yet.
- The alert system is live and native, but not yet a persisted alert history.
- The workspace store currently owns a lot of responsibilities that will likely split over time.

## Where To Read More

- Engineering spec: `docs/holy-ghostty/engineering-spec.md`
- Request vs current state: `docs/holy-ghostty/request-vs-current-state.md`
- Roadmap: `docs/holy-ghostty/roadmap.md`
- v0.2 implementation plan: `docs/holy-ghostty/v0.2-implementation-plan.md`
- Interoperability notes: `docs/holy-ghostty/agent-sessions-interoperability.md`
