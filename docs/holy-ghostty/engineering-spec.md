# Holy Ghostty Engineering Spec

Last updated: 2026-04-13

This document describes Holy Ghostty as it exists today in the repository. It is an as-is engineering spec, not a forward-looking design document.

## 1. Purpose

Holy Ghostty is a macOS-native shell built around Ghostty terminal surfaces for running and supervising agentic coding sessions. The Holy layer adds session orchestration, launch policy, worktree management, git-aware coordination, runtime heuristics, archive/history, templates, and native alerts without replacing Ghostty's terminal core.

## 2. Scope And Current Boundary

Holy Ghostty currently lives inside the existing Ghostty macOS host instead of replacing upstream app architecture wholesale.

Current boundary:

- Keep Ghostty terminal core behavior intact
- Use the macOS host to embed and manage live `Ghostty.SurfaceView` instances
- Add Holy-specific orchestration and presentation in SwiftUI and AppKit
- Avoid deep Zig core changes unless the host truly needs more structured signals

Not currently implemented:

- dedicated database layer
- durable event ledger
- cost tracking system
- grid mode or diff mode
- deep issue-system integrations

## 3. High-Level Architecture

Architecture layers:

1. Ghostty core
   - Terminal emulation, PTY handling, rendering, fonts, and process integration remain in upstream Ghostty.
2. Existing macOS host integration
   - The macOS app embeds Ghostty surfaces and manages app lifecycle.
3. Holy Ghostty shell
   - Adds the mission-control UI, session model, persistence, git/worktree logic, launch guardrails, heuristics, archive, templates, and alerts.

Primary Holy code root:

```text
macos/Sources/HolyGhostty/
```

## 4. Primary Modules

### App shell

- `macos/Sources/HolyGhostty/App/HolyWorkspaceWindowController.swift`

Responsibilities:

- create the main `NSWindow`
- attach the SwiftUI root
- own the `HolyWorkspaceStore`
- create and find session surfaces
- restore the initial session when provided

Current window characteristics:

- titled, closable, miniaturizable, resizable, full-size content view
- transparent titlebar
- hidden title
- movable by background
- unified toolbar style with an attached empty toolbar
- full-screen primary and managed collection behavior
- autosaved frame

### SwiftUI shell

- `macos/Sources/HolyGhostty/Workspace/HolyWorkspaceView.swift`

Responsibilities:

- render the overall Holy shell
- present the header
- compose the three-zone layout
- manage sheet presentation for session creation and history

Primary layout pattern:

- left roster rail
- center selected session detail and live surface
- right context inspector

### Design system

- `macos/Sources/HolyGhostty/DesignSystem/HolyGhosttyDesignSystem.swift`

Responsibilities:

- shared colors
- shell spacing
- surface styling
- status chip and panel treatment

Current state:

- dark palette
- halo-gold accent usage
- app-specific shell styling

### Domain model

- `macos/Sources/HolyGhostty/Domain/HolyModels.swift`

This file defines most Holy-specific data structures and enums.

Important enums:

- `HolySessionRuntime`
  - `shell`
  - `claude`
  - `codex`
  - `opencode`
- `HolySessionPhase`
  - `active`
  - `working`
  - `waitingInput`
  - `completed`
  - `failed`
- `HolySessionAttention`
  - `none`
  - `watch`
  - `needsInput`
  - `failure`
  - `conflict`
  - `done`
- `HolyWorkspaceStrategy`
  - `directDirectory`
  - `attachExistingWorktree`
  - `createManagedWorktree`

Important structs:

- `HolySessionLaunchSpec`
- `HolySessionRecord`
- `HolySessionDraft`
- `HolySessionTemplate`
- `HolyArchivedSession`
- `HolyWorkspaceSnapshot`
- `HolySessionOwnership`
- `HolySessionCoordination`
- `HolySessionSignal`
- `HolySessionCommandTelemetry`
- `HolyLaunchGuardrail`

## 5. Session Model

Live sessions are represented by:

- `macos/Sources/HolyGhostty/Session/HolySession.swift`

Each `HolySession` owns:

- stable session ID
- `Ghostty.SurfaceView`
- current session record
- current phase
- preview text
- signals
- command telemetry
- git snapshot
- activity timestamp

Derived state is refreshed from:

- surface state changes
- command-finished notifications
- a repeating timer at roughly 1.25 seconds

## 6. Runtime Detection And Heuristics

Runtime-specific adapters live in:

- `macos/Sources/HolyGhostty/Adapters/HolySessionAdapters.swift`

Current adapters:

- Shell
- Claude
- Codex
- OpenCode

Each adapter provides:

- runtime description
- recommended launch command
- default idle headline and detail
- approval markers
- reading markers
- editing markers
- command markers
- failure headline mapping
- completion markers

The current heuristic model is based on:

- visible terminal preview text
- Ghostty surface and process state
- adapter marker matching
- generic fallback heuristics

Important current limitation:

This is not yet a structured embedded telemetry bridge. It is a useful runtime-classification layer, but it is still heuristic.

## 7. Workspace Store And Orchestration

Main orchestration lives in:

- `macos/Sources/HolyGhostty/Workspace/HolyWorkspaceStore.swift`

The store is currently the central application brain. It combines several concerns that may eventually split into separate subsystems.

Current responsibilities:

- active session list
- session selection
- templates
- archives
- composer state
- history state
- draft evaluation
- launch guardrails
- ownership preview
- session creation
- duplication
- archive and relaunch
- persistence restore and save
- coordination recomputation
- alert delivery

Important as-is note:

There is no separate supervisor process or database-backed session orchestration layer yet. `HolyWorkspaceStore` is intentionally doing a lot of work today.

## 8. Persistence

Persistence code:

- `macos/Sources/HolyGhostty/Persistence/HolyWorkspacePersistence.swift`

Current persistence model:

- JSON snapshot based
- app-support scoped
- restores workspace state on launch
- quarantines corrupt snapshots

Current state path pattern:

```text
~/Library/Application Support/<bundle-id>/HolyGhostty/workspace-state.json
```

Corrupt state pattern:

```text
~/Library/Application Support/<bundle-id>/HolyGhostty/workspace-state.corrupt-<timestamp>.json
```

Persisted snapshot currently includes:

- session records
- selected session ID
- templates
- archived sessions

Not currently present:

- SQLite schema
- event sourcing
- durable alert history
- cost ledgers
- searchable event timeline

## 9. Templates

Template catalog:

- `macos/Sources/HolyGhostty/Templates/HolySessionTemplateCatalog.swift`

Built-in templates:

- Shell Workspace
- Claude Code
- Codex
- OpenCode
- Managed Claude Worktree
- Managed Codex Worktree

Templates capture reusable launch state for repeatable session setup.

## 10. Git Model

Git snapshot model:

- `macos/Sources/HolyGhostty/Git/HolyGitSnapshot.swift`

Git client:

- `macos/Sources/HolyGhostty/Git/HolyGitClient.swift`

Tracked git context includes:

- repository root
- worktree path
- common git directory
- branch
- upstream branch
- detached head state
- ahead/behind counts
- staged/unstaged/untracked/conflicted counts
- changed files

Derived display helpers include:

- repository name
- worktree name
- branch display name
- sync status text
- change summary text

## 11. Worktree Management

Worktree management code:

- `macos/Sources/HolyGhostty/Worktree/HolyWorktreeManager.swift`

Supported launch ownership patterns:

- direct directory
- attach existing worktree
- create managed worktree

Managed worktree location pattern:

```text
~/Library/Application Support/<bundle-id>/HolyGhostty/ManagedWorktrees/<repo>-<hash>/<branch>
```

Current manager responsibilities:

- validate direct launches
- validate and attach existing worktrees
- create managed worktrees
- produce ownership metadata used by sessions and guardrails

## 12. Launch Guardrails

Launch guardrails are evaluated before session creation.

Supported launch conflict kinds:

- shared worktree
- shared branch

Severity:

- shared worktree is blocking
- shared branch is warning-level and requires explicit override

Guardrails are derived from the active session set and the current draft.

## 13. Coordination Model

Coordination is recomputed across active sessions.

Current coordination tracks:

- shared worktree peers
- shared branch peers
- overlapping changed files
- overlapping sessions

Attention is derived from phase and coordination. Current rough ordering:

- failure
- blocking conflict
- waiting for input
- watch-worthy ownership drift or branch overlap
- completed
- calm/none

This coordination model is one of the product's key implemented features.

## 14. Alerts

Alert logic currently lives inside `HolyWorkspaceStore` via an internal coordinator.

Current alert transport:

- macOS `UNUserNotificationCenter`
- Ghostty surface user notifications
- app attention requests for higher-priority states

Current alert triggers:

- collision detected
- phase becomes failed
- phase becomes waiting for input
- branch ownership drift
- phase becomes completed

Important limitation:

The current alert system is runtime and transition based. There is not yet a durable alert ledger.

## 15. Views And User-Facing Surfaces

### Session roster

- `macos/Sources/HolyGhostty/Workspace/HolySessionRosterView.swift`

Responsibilities:

- display live active sessions
- sort by attention and recent activity
- expose a compact operational summary

### Session detail

- `macos/Sources/HolyGhostty/Workspace/HolySessionDetailView.swift`

Responsibilities:

- display the currently selected session
- render the live `Ghostty.SurfaceView`
- show high-level session header and status

### Context inspector

- `macos/Sources/HolyGhostty/Workspace/HolyContextPanelView.swift`

Responsibilities:

- mission
- runtime and signal
- command telemetry
- ownership state
- coordination summary
- git state
- changed files
- output preview
- environment

### New session sheet

- `macos/Sources/HolyGhostty/Workspace/HolyNewSessionSheet.swift`

Responsibilities:

- collect launch state
- expose built-in and saved templates
- expose workspace strategy selection
- show live ownership preview and guardrails

### History sheet

- `macos/Sources/HolyGhostty/Workspace/HolySessionHistorySheet.swift`

Responsibilities:

- archived session search
- archive inspection
- relaunch
- edit-and-relaunch
- archive deletion

## 16. Integration Into Ghostty Host

Holy Ghostty integrates into the existing Ghostty macOS app.

Relevant file:

- `macos/Sources/App/macOS/AppDelegate+Ghostty.swift`

Important integration behavior:

- surface lookup checks `HolyWorkspaceWindowController.all` first
- legacy terminal controllers still exist as fallback

This means Holy Ghostty is currently an alternative shell layered into the macOS host, not a ground-up separate app architecture.

## 17. Build And Install

Upstream build:

```bash
zig build
```

Faster macOS-core-only build when app bundle emission is unnecessary:

```bash
zig build -Demit-macos-app=false
```

macOS app build:

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug SYMROOT=build build
```

Install script:

- `scripts/install-holy-ghostty.sh`

Installed bundle path:

```text
/Applications/Holy Ghostty.app
```

## 18. Known Current Limitations

This spec describes a working app, but not the full intended end-state.

Known current limitations:

- JSON snapshot persistence instead of a durable DB/event system
- heuristic runtime detection instead of deep embedded structured telemetry
- no budget or token cost subsystem
- no grid mode, focus mode, or diff mode
- no external issue/task integration
- store orchestration remains centralized in one large workspace store
- alert history is not persisted

## 19. Roadmap Context

The current implementation came out of a larger incubation and planning phase, but this document is intentionally the public as-is spec. Treat the checked-in app behavior and the docs in `docs/holy-ghostty/` as the source of truth for the public repo.
