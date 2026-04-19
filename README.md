<p align="center">
  <img src="./holy-ghostty-logo.jpeg" alt="Holy Ghostty logo" width="220">
</p>

<h1 align="center">Holy Ghostty</h1>

<p align="center">
  Mission control for agentic coding sessions, built on Ghostty.
</p>

<p align="center">
  Native macOS shell · Real Ghostty surfaces · Session ownership · Worktree guardrails · Budget intelligence · Task inbox · Focus/Grid/Diff modes · Durable SQLite persistence
</p>

<p align="center">
  <a href="./docs/holy-ghostty/README.md">User Guide</a>
  ·
  <a href="./docs/holy-ghostty/engineering-spec.md">Engineering Spec</a>
  ·
  <a href="./docs/holy-ghostty/request-vs-current-state.md">Vision vs Current State</a>
  ·
  <a href="./docs/holy-ghostty/roadmap.md">Roadmap</a>
  ·
  <a href="./CHANGELOG.md">Changelog</a>
</p>

Holy Ghostty is a macOS-first product fork of Ghostty. The terminal core remains Ghostty; the Holy layer adds a native control surface around live terminal sessions so AI coding work can be launched, supervised, coordinated, archived, and resumed without disappearing into a pile of tabs.

## What This Fork Is

Holy Ghostty is not a new terminal emulator core. It is a Ghostty-based operator shell for:

- live Shell, Claude, Codex, and OpenCode sessions
- session launch templates with budget configuration
- managed or attached git worktrees
- pre-launch ownership guardrails
- git-aware coordination and overlap detection
- structured runtime telemetry (activity kind, stall/loop detection, command/file extraction)
- budget intelligence (token/cost tracking, burn rate, exhaustion projection, enforcement)
- external task inbox (GitHub, Linear, Jira, manual)
- archive, history, and relaunch workflows with recovery context
- native notifications for needs-input, failure, collision, drift, stalls, loops, budget warnings, and completion
- durable SQLite persistence with schema migrations and an append-only event ledger

Current product shape:

- left rail for active sessions
- center live Ghostty surface
- right-side operational inspector with telemetry, budget analytics, event timeline, and coordination
- new-session composer with task linking and budget controls
- searchable session history with recovery context and telemetry
- task inbox for external work items
- focus mode, grid mode, and diff mode for multi-session operation

## Quick Start

Build and install the app:

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug SYMROOT=build build
scripts/install-holy-ghostty.sh Debug
open -a "Holy Ghostty"
```

Installed bundle path:

```text
/Applications/Holy Ghostty.app
```

If you only need the shared Ghostty core and not the macOS app bundle:

```bash
zig build -Demit-macos-app=false
```

## Documentation

Primary Holy Ghostty docs live under [`docs/holy-ghostty`](./docs/holy-ghostty).

- [User guide and tutorial](./docs/holy-ghostty/README.md)
- [Engineering spec](./docs/holy-ghostty/engineering-spec.md)
- [Requested vision vs current state](./docs/holy-ghostty/request-vs-current-state.md)
- [Roadmap](./docs/holy-ghostty/roadmap.md)
- [v0.2 implementation plan](./docs/holy-ghostty/v0.2-implementation-plan.md)
- [Interoperability notes](./docs/holy-ghostty/agent-sessions-interoperability.md)
- [Changelog](./CHANGELOG.md)

## Current Strengths

- Real embedded Ghostty surfaces inside a native macOS shell
- Session-oriented workflow instead of tab-oriented workflow
- Durable SQLite persistence with schema migrations and event ledger
- Separated session supervisor architecture
- Worktree-aware launch strategies with recovery validation and orphan cleanup
- Blocking shared-worktree guardrails
- Warning-level shared-branch guardrails with explicit override
- Structured runtime telemetry (activity kind, stall/loop detection, command/file extraction)
- Budget intelligence with token/cost tracking, burn rate, projection, and enforcement
- External task inbox (GitHub, Linear, Jira, manual) with task-to-session launching
- Focus, grid, and diff display modes
- Archive and relaunch history with recovery context and event timeline
- Native notifications for failures, needs-input, collisions, drift, stalls, loops, budget warnings, and completion
- `agent-sessions` compatibility views for future cross-tool interoperability

## Current Limitations

Holy Ghostty is usable and substantially complete, but some areas remain for future work:

- deeper structured runtime telemetry via an embedded VT/PTY bridge (current system is inference-based)
- dependency chains and automated session orchestration
- broadcast input across sessions
- status updates pushed back to external task sources
- settings and preferences surface for budgets, notifications, and templates
- signing, notarization, and distribution path

## Repo Layout

- `src/`: upstream Ghostty shared Zig core
- `macos/`: macOS host app and Holy Ghostty shell
- `macos/Sources/HolyGhostty/`: Holy-specific app logic
- `docs/holy-ghostty/`: Holy Ghostty documentation

## Relationship To Upstream Ghostty

This project depends on Ghostty's terminal core and macOS host infrastructure. Holy Ghostty is best understood as a product shell layered on top of Ghostty rather than a rewrite of Ghostty itself.

For upstream Ghostty:

- Repository: <https://github.com/ghostty-org/ghostty>
- Documentation: <https://ghostty.org/docs>

## Development Notes

Useful commands:

```bash
zig build
zig build -Demit-macos-app=false
zig build test -Dtest-filter=<filter>
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug SYMROOT=build build
scripts/install-holy-ghostty.sh Debug
```

For engineering context beyond this README, start with:

- [`docs/holy-ghostty/engineering-spec.md`](./docs/holy-ghostty/engineering-spec.md)
