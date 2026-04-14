<p align="center">
  <img src="./holy-ghostty-logo.jpeg" alt="Holy Ghostty logo" width="220">
</p>

<h1 align="center">Holy Ghostty</h1>

<p align="center">
  Mission control for agentic coding sessions, built on Ghostty.
</p>

<p align="center">
  Native macOS shell · Real Ghostty surfaces · Session ownership · Worktree guardrails · Archive and relaunch
</p>

<p align="center">
  <a href="./docs/holy-ghostty/README.md">User Guide</a>
  ·
  <a href="./docs/holy-ghostty/engineering-spec.md">Engineering Spec</a>
  ·
  <a href="./docs/holy-ghostty/request-vs-current-state.md">Vision vs Current State</a>
  ·
  <a href="./CHANGELOG.md">Changelog</a>
</p>

Holy Ghostty is a macOS-first product fork of Ghostty. The terminal core remains Ghostty; the Holy layer adds a native control surface around live terminal sessions so AI coding work can be launched, supervised, coordinated, archived, and resumed without disappearing into a pile of tabs.

## What This Fork Is

Holy Ghostty is not a new terminal emulator core. It is a Ghostty-based operator shell for:

- live Shell, Claude, Codex, and OpenCode sessions
- session launch templates
- managed or attached git worktrees
- pre-launch ownership guardrails
- git-aware coordination and overlap detection
- archive, history, and relaunch workflows
- native notifications for needs-input, failure, collision, drift, and completion

Current product shape:

- left rail for active sessions
- center live Ghostty surface
- right-side operational inspector
- new-session composer
- searchable session history

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
- [Changelog](./CHANGELOG.md)

## Current Strengths

- Real embedded Ghostty surfaces inside a native macOS shell
- Session-oriented workflow instead of tab-oriented workflow
- Worktree-aware launch strategies
- Blocking shared-worktree guardrails
- Warning-level shared-branch guardrails with explicit override
- Runtime-aware heuristics for multiple agent tools
- Archive and relaunch history
- Native notification path for important session transitions

## Current Limitations

Holy Ghostty is already usable, but it is not the full end-state of the original platform vision.

Still missing:

- durable database and event ledger
- cost and budget intelligence
- grid mode, diff mode, and focus mode
- deeper structured runtime telemetry
- external task-system integration
- a fully split session supervisor architecture

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
