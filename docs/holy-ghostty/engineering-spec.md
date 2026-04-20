# Holy Ghostty Engineering Spec

Last updated: 2026-04-19

This document describes Holy Ghostty as it exists today in the repository. It is an as-is engineering spec, not a forward-looking design document.

## 1. Purpose

Holy Ghostty is a macOS-native shell built around Ghostty terminal surfaces for running and supervising agentic coding sessions. The Holy layer adds session orchestration, tmux-backed local and SSH launch policy, worktree management, git-aware coordination, runtime heuristics, structured telemetry, budget intelligence, an external task inbox, an append-only event ledger, archive/history, templates, remote host discovery, and native alerts without replacing Ghostty's terminal core.

## 2. Scope And Current Boundary

Holy Ghostty currently lives inside the existing Ghostty macOS host instead of replacing upstream app architecture wholesale.

Current boundary:

- Keep Ghostty terminal core behavior intact
- Use the macOS host to embed and manage live `Ghostty.SurfaceView` instances
- Add Holy-specific orchestration and presentation in SwiftUI and AppKit
- Use tmux as the durable substrate for Holy-managed local and SSH sessions
- Avoid deep Zig core changes unless the host truly needs more structured signals

## 3. High-Level Architecture

Architecture layers:

1. Ghostty core
   - Terminal emulation, PTY handling, rendering, fonts, and process integration remain in upstream Ghostty.
2. Existing macOS host integration
   - The macOS app embeds Ghostty surfaces and manages app lifecycle.
3. Holy Ghostty shell
   - Adds the mission-control UI, session model, persistence, tmux-backed launch substrate, git/worktree logic, launch guardrails, heuristics, structured telemetry, budget intelligence, task inbox, remote host discovery, event ledger, archive, templates, and alerts.

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
- compose the layout for the active display mode
- manage sheet presentation for session creation, history, and task inbox

Display modes (selectable via toolbar or keyboard shortcuts):

- Standard: left roster, center session surface, right inspector
- Focus: full-screen single session with floating status overlay
- Grid: 2x2 or 2x3 tiled session previews with selection and promotion
- Diff: side-by-side comparison of two sessions with branch, file overlap, and phase analysis

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

- `HolySessionRuntime`: shell, claude, codex, opencode
- `HolySessionPhase`: active, working, waitingInput, completed, failed
- `HolySessionAttention`: none, watch, needsInput, failure, conflict, done
- `HolyWorkspaceStrategy`: directDirectory, attachExistingWorktree, createManagedWorktree
- `HolySessionBudgetStatus`: none, healthy, warning, exceeded
- `HolySessionBudgetEnforcementPolicy`: warn, requireApproval
- `HolySessionActivityKind`: idle, approval, progress, reading, editing, command, stalled, looping, failure, completion

Important structs:

- `HolySessionLaunchSpec` (now includes transport, tmux spec, optional task reference, and budget)
- `HolySessionRecord`
- `HolySessionDraft` (now includes linked task, budget fields, budget validation, transport, and tmux fields)
- `HolySessionTemplate`
- `HolyArchivedSession` (now includes budget telemetry, runtime telemetry, recovery reason, and cleanup summary)
- `HolyWorkspaceSnapshot`
- `HolySessionOwnership`
- `HolySessionCoordination`
- `HolySessionSignal`
- `HolySessionCommandTelemetry`
- `HolyLaunchGuardrail`
- `HolySessionBudget`
- `HolySessionBudgetTelemetry`
- `HolySessionRuntimeTelemetry`
- `HolyExternalTaskReference`
- `HolySessionTransportSpec`
- `HolySessionTmuxSpec`

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
- launch transport and tmux context through the session record
- command telemetry
- budget telemetry (parsed from terminal output)
- runtime telemetry (inferred activity kind, commands, files, artifacts, stall/loop detection)
- git snapshot
- activity timestamp
- preview stability tracking (signature, first-observed time, repeat count)

Derived state is refreshed from:

- surface state changes
- command-finished notifications
- a repeating timer at roughly 1.25 seconds
- budget parser (extracts token/cost figures from preview text)
- runtime telemetry parser (infers activity kind, detects stalls and loops)
- git client using either local process execution or SSH process execution depending on launch transport

Budget enforcement: when a session's enforcement policy is `requireApproval` and the budget is exceeded, a budget signal is inserted into the session's signal list.

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

### Structured runtime telemetry

- `macos/Sources/HolyGhostty/Telemetry/HolySessionRuntimeTelemetryParser.swift`

The telemetry parser infers structured activity from terminal preview text, signals, and phase:

- Activity kind classification (idle, approval, progress, reading, editing, command, stalled, looping, failure, completion)
- Command extraction (xcodebuild, git, npm, cargo, etc.)
- File path extraction
- Next-step hint detection ("press enter", "[y/n]", etc.)
- Artifact detection ("created", "wrote", etc.)
- Stall detection (same evidence signature persisting beyond a threshold)
- Loop detection (same evidence signature repeating)

This is not yet a structured embedded telemetry bridge. It is a useful runtime-classification layer that combines adapter markers with inference from terminal output.

## 7. Budget Intelligence

### Budget parser

- `macos/Sources/HolyGhostty/Budget/HolySessionBudgetParser.swift`

Regex-based parser that extracts token counts and cost figures from terminal preview text. Parses input/output/total tokens and dollar costs.

### Budget repository

- `macos/Sources/HolyGhostty/Budget/HolyBudgetIntelligenceRepository.swift`

Records budget samples to the `budget_samples` table and computes analytics:

- Appends samples only when usage has changed or 300 seconds have elapsed
- Per-runtime rollups (total tokens, total cost across all sessions)
- Per-session intelligence (sample count, rollup, projected exhaustion date)
- Exhaustion projection by linear extrapolation of burn rate against limits

## 8. External Task Inbox

### Task models

- `macos/Sources/HolyGhostty/Tasks/HolyTaskModels.swift`

Defines the external task data model:

- `HolyTaskSourceKind`: manual, githubIssue, linearIssue, jiraIssue, genericURL (auto-inferred from canonical URL)
- `HolyExternalTaskStatus`: inbox, claimed, active, waitingInput, done, failed, archived
- `HolyExternalTaskReference`: lightweight reference attached to a launch spec
- `HolyExternalTaskRecord`: full task record with preferred runtime, working directory, linked session, status

### Task repository

- `macos/Sources/HolyGhostty/Tasks/HolyTaskRepository.swift`

CRUD for the `tasks` table. Loads and saves all tasks as a batch within a transaction.

### Task inbox UI

- `macos/Sources/HolyGhostty/Workspace/HolyTaskInboxSheet.swift`

Split-view task management: search, list, detail editor. Supports creating, editing, saving, launching into sessions, opening canonical URLs, and deleting tasks.

## 8A. Automation And Durable Launch Substrate

### Automation entrypoints

- `macos/Sources/HolyGhostty/Automation/HolyAutomationURLParser.swift`
- `macos/Sources/Features/AppleScript/AppDelegate+AppleScript.swift`
- `macos/Ghostty.sdef`
- `scripts/holy-spawn-session.sh`

Holy Ghostty exposes three first-class automation paths for creating Holy sessions:

- `holy-ghostty://spawn?...`
- AppleScript `spawn`
- the `scripts/holy-spawn-session.sh` helper, which wraps the URL scheme

These paths create Holy sessions directly. They do not depend on tabs or simulated key presses.

### Tmux-backed launch substrate

- `macos/Sources/HolyGhostty/Tmux/HolyTmuxModels.swift`
- `macos/Sources/HolyGhostty/Tmux/HolyTmuxCommandBuilder.swift`

Holy-managed sessions are tmux-backed by default:

- local sessions attach to a local tmux server
- SSH sessions attach to a remote tmux server
- tmux session/socket can be configured per launch
- Holy writes metadata into tmux session options so later discovery can reconstruct operator-facing context

This is the durable-session substrate that lets sessions survive Holy Ghostty shutdown and remain attachable from other clients.

## 8B. Remote Hosts And Discovery

- `macos/Sources/HolyGhostty/Remote/HolyRemoteModels.swift`
- `macos/Sources/HolyGhostty/Remote/HolyRemoteHostRepository.swift`
- `macos/Sources/HolyGhostty/Remote/HolyRemoteHostImportService.swift`
- `macos/Sources/HolyGhostty/Remote/HolyRemoteTmuxDiscoveryService.swift`
- `macos/Sources/HolyGhostty/Workspace/HolyRemoteHostsSheet.swift`

Current remote-host model:

- persistent host registry in SQLite
- manual host creation
- import from `~/.ssh/config`
- import from Tailscale
- per-host tmux socket selection
- remote tmux discovery over SSH
- Holy metadata readback from discovered tmux sessions
- remote git enrichment for Holy-managed SSH sessions

## 9. Session Supervisor

- `macos/Sources/HolyGhostty/Supervisor/HolySessionSupervisor.swift`

The supervisor owns lifecycle orchestration that was previously embedded in `HolyWorkspaceStore`. It handles:

- workspace restore (including worktree recovery evaluation and orphan cleanup)
- session creation (with event provenance tracking)
- session archive
- archive deletion
- template saving
- persistence (writing to both database and JSON during the transition period)
- scheduled persistence (debounced)
- alert coordination

### Alert coordinator

The supervisor contains an internal `HolySessionAlertCoordinator` that delivers macOS notifications based on state transitions:

- collision detected
- phase becomes failed
- phase becomes waiting for input
- branch ownership drift
- session stalled
- session looping
- budget warning or exceeded
- phase becomes completed

### Worktree recovery

The supervisor evaluates whether worktree-backed sessions can be restored by checking directory existence, git validity, repository match, and branch match. Sessions whose worktrees have disappeared are archived with a recovery reason.

### Orphan cleanup

The supervisor scans the managed worktree container and removes orphaned worktrees (those not referenced by any active or archived session) if they are clean.

## 10. Workspace Store And Orchestration

Main orchestration lives in:

- `macos/Sources/HolyGhostty/Workspace/HolyWorkspaceStore.swift`

The store delegates lifecycle operations to the `HolySessionSupervisor` and manages:

- active session list
- session selection (with event emission)
- templates
- archives
- external tasks
- remote hosts and discovered remote tmux sessions
- composer state
- history state
- task inbox state
- draft evaluation
- launch guardrails
- ownership preview
- session creation (delegated to supervisor)
- duplication
- archive and relaunch (delegated to supervisor)
- task management (create, upsert, delete, launch)
- external task reconciliation (updating linked session state)
- coordination recomputation

All launch paths now carry event provenance: origin, source template ID, relaunched-from session ID.

## 11. Database Layer

### Database engine

- `macos/Sources/HolyGhostty/Database/HolyDatabase.swift`

Core SQLite connection wrapper using the system `SQLite3` framework directly. Configures WAL journal mode, foreign keys, and busy timeout. Provides execute, query, transaction, and user-version APIs.

### Schema and migrations

- `macos/Sources/HolyGhostty/Database/HolyDatabaseMigrator.swift`
- `macos/Sources/HolyGhostty/Database/HolyDatabaseModels.swift`

Sequential schema migration runner with 6 migrations:

1. Full initial schema (sessions, events, git_snapshots, templates, alerts, annotations, indexes, and `agent-sessions` compatibility views)
2. `latest_budget_json` column on sessions
3. `latest_runtime_telemetry_json` column on sessions
4. `budget_samples` table
5. `tasks` table
6. `remote_hosts` table

Current schema version: 6.

### Database paths

- `macos/Sources/HolyGhostty/Database/HolyDatabasePaths.swift`

Database location:

```text
~/Library/Application Support/<bundle-id>/HolyGhostty/holy-ghostty.sqlite3
```

Also defines the legacy JSON snapshot path for migration discovery.

### Compatibility views

The schema includes four read-only SQL views for future `agent-sessions` interoperability:

- `agent_sessions_sessions_v1`
- `agent_sessions_resume_targets_v1`
- `agent_sessions_events_v1`
- `agent_sessions_annotations_v1`

See `docs/holy-ghostty/agent-sessions-interoperability.md` for the contract.

Additional persisted tables now include:

- `budget_samples`
- `tasks`
- `remote_hosts`

## 12. Event Ledger

### Event model

- `macos/Sources/HolyGhostty/Events/HolySessionEvent.swift`

Append-only session event log with typed events:

- imported, restored, recovered, created, archived, relaunched, selected, runtimeUpdated, artifactDetected

Each event carries a rich payload (runtime, title, mission, working directory, git info, telemetry fields, recovery reason) and tracks its origin (legacyJSON, workspaceRestore, directLaunch, templateLaunch, archiveRelaunch, duplicate, surfaceClone, defaultSeed).

### Event repository

- `macos/Sources/HolyGhostty/Events/HolySessionEventRepository.swift`

Appends events with monotonically increasing per-session sequence numbers. Queries recent events for timeline display.

### Timeline UI

- `macos/Sources/HolyGhostty/Workspace/HolySessionTimelineSection.swift`

SwiftUI view rendering a session's event timeline with colored badges, timestamps, titles, and details. Used in both the live inspector and archived session views.

## 13. Persistence

### Database persistence

- `macos/Sources/HolyGhostty/Persistence/HolyWorkspaceDatabasePersistence.swift`

The primary persistence layer. Saves and loads the full workspace state from SQLite:

- upsert active sessions with live telemetry projections
- upsert archived sessions with git snapshots
- save templates
- manage `app_state` key-value pairs (selected session, ordering)
- trigger budget sample recording and event appending within each save transaction

### JSON persistence (legacy, dual-write)

- `macos/Sources/HolyGhostty/Persistence/HolyWorkspacePersistence.swift`

JSON snapshot persistence remains for backward compatibility during the transition. The workspace repository writes to both database and JSON on every save.

### Workspace repository

- `macos/Sources/HolyGhostty/Supervisor/HolyWorkspaceRepository.swift`

Facade that loads from database first, triggers migration from JSON if needed, then falls back to JSON. Saves to both destinations during the transition period.

### Migration service

- `macos/Sources/HolyGhostty/Supervisor/HolyMigrationService.swift`

One-shot service that imports the legacy JSON workspace state into the database on first run.

### Shared coders

- `macos/Sources/HolyGhostty/Persistence/HolyPersistenceCoders.swift`

Shared JSON and timestamp encoding/decoding utilities using ISO8601 with fractional seconds.

## 14. Persistence Paths

Database:

```text
~/Library/Application Support/<bundle-id>/HolyGhostty/holy-ghostty.sqlite3
```

Legacy JSON snapshot:

```text
~/Library/Application Support/<bundle-id>/HolyGhostty/workspace-state.json
```

Corrupt state quarantine:

```text
~/Library/Application Support/<bundle-id>/HolyGhostty/workspace-state.corrupt-<timestamp>.json
```

Managed worktrees:

```text
~/Library/Application Support/<bundle-id>/HolyGhostty/ManagedWorktrees/<repo>-<hash>/<branch>
```

## 15. Session Store

- `macos/Sources/HolyGhostty/Store/HolySessionStore.swift`

Defines the in-memory state struct (`HolySessionStoreState`) that the workspace store operates on. Holds sessions, templates, archives, and selected IDs. Provides a snapshot property for persistence and pairs mutations with pending events via `HolySessionStoreMutationResult`.

## 16. Templates

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

## 17. Git Model

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

`HolyGitClient` now supports both:

- local git inspection
- SSH-based remote git inspection for SSH-backed Holy sessions

## 18. Worktree Management

Worktree management code:

- `macos/Sources/HolyGhostty/Worktree/HolyWorktreeManager.swift`

Supported launch ownership patterns:

- direct directory
- attach existing worktree
- create managed worktree

New in v0.2:

- `recoveryEvaluation(for:)`: validates whether a worktree-backed session can be restored (checks directory existence, git validity, repository match, branch match)
- `cleanupOrphanedManagedWorktrees(referencedPaths:)`: removes orphaned managed worktrees not referenced by any session
- Improved worktree creation with cleanup on failure

## 19. Launch Guardrails

Launch guardrails are evaluated before session creation.

Supported launch conflict kinds:

- shared worktree
- shared branch

Severity:

- shared worktree is blocking
- shared branch is warning-level and requires explicit override

Guardrails are derived from the active session set and the current draft.

## 20. Coordination Model

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

## 21. Alerts

Alert logic lives in `HolySessionSupervisor` via an internal coordinator.

Current alert transport:

- macOS `UNUserNotificationCenter`
- Ghostty surface user notifications
- app attention requests for higher-priority states

Current alert triggers:

- collision detected
- phase becomes failed
- phase becomes waiting for input
- branch ownership drift
- session stalled (new in v0.2)
- session looping (new in v0.2)
- budget warning or exceeded (new in v0.2)
- phase becomes completed

## 22. Views And User-Facing Surfaces

### Session roster

- `macos/Sources/HolyGhostty/Workspace/HolySessionRosterView.swift`

Displays live active sessions sorted by attention and recent activity.

### Session detail

- `macos/Sources/HolyGhostty/Workspace/HolySessionDetailView.swift`

Displays the currently selected session with the live `Ghostty.SurfaceView` and session header/status.

### Context inspector

- `macos/Sources/HolyGhostty/Workspace/HolyContextPanelView.swift`

Displays:

- mission (with task source if linked)
- runtime and signal
- runtime telemetry (activity kind, headline, progress, command, file, next step hint, artifact, stagnant/repeat counters)
- command telemetry
- budget status, usage, remaining, burn rate, evidence
- budget intelligence (ledger, projection, runtime spend rollup)
- ownership state
- coordination summary
- git state and changed files
- session event timeline
- output preview
- environment

### New session sheet

- `macos/Sources/HolyGhostty/Workspace/HolyNewSessionSheet.swift`

Collects launch state with:

- template selection
- workspace strategy
- linked task display (when composing from a task)
- budget configuration (token limit, cost limit, enforcement policy, validation)
- live ownership preview and guardrails

### History sheet

- `macos/Sources/HolyGhostty/Workspace/HolySessionHistorySheet.swift`

Archived session search, inspection, relaunch, and deletion. Now includes:

- recovery section (recovery reason, cleanup summary, suggested action)
- runtime telemetry section
- budget telemetry section
- session event timeline

### Remote hosts sheet

- `macos/Sources/HolyGhostty/Workspace/HolyRemoteHostsSheet.swift`

Provides:

- host registry management
- SSH-config and Tailscale import
- per-host discovery status
- discovered remote tmux session list
- direct attach into Holy sessions

### Task inbox sheet

- `macos/Sources/HolyGhostty/Workspace/HolyTaskInboxSheet.swift`

Split-view task management with search, list, and detail editor. Supports creating, editing, launching into sessions, opening canonical URLs, and deleting tasks.

### Budget intelligence section

- `macos/Sources/HolyGhostty/Workspace/HolyBudgetIntelligenceSection.swift`

Shows budget analytics in the context panel: sample count, exhaustion projection, runtime spend rollup.

### Session timeline section

- `macos/Sources/HolyGhostty/Workspace/HolySessionTimelineSection.swift`

Renders a session's event timeline with colored badges, timestamps, titles, and details.

## 23. Display Modes

The workspace view supports four display modes, selectable via toolbar or keyboard shortcuts:

### Standard mode

The default three-zone layout: left roster, center session surface, right inspector.

### Focus mode (Cmd+Shift+F)

Full-screen single session with a floating status overlay showing session title, phase, and action buttons.

### Grid mode (Cmd+Shift+G)

Tiled session previews (2x2 or 2x3) with selection, phase badges, and promote-to-focus action.

### Diff mode (Cmd+Shift+D)

Side-by-side comparison of two sessions showing terminal surfaces, signals, git summaries, and a comparison summary (branch conflict, file overlap, phase mismatch).

## 24. Integration Into Ghostty Host

Holy Ghostty integrates into the existing Ghostty macOS app.

Relevant file:

- `macos/Sources/App/macOS/AppDelegate+Ghostty.swift`

Important integration behavior:

- surface lookup checks `HolyWorkspaceWindowController.all` first
- legacy terminal controllers still exist as fallback

## 25. Build And Install

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
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug SYMROOT=build
```

Install script:

- `scripts/install-holy-ghostty.sh`

Installed bundle path:

```text
/Applications/Holy Ghostty.app
```

## 26. Module Map

```text
macos/Sources/HolyGhostty/
├── App/                    # Window controller, app shell
├── Adapters/               # Runtime-specific heuristic adapters
├── Budget/                 # Budget parsing and intelligence repository
├── Database/               # SQLite engine, migrator, schema, paths
├── DesignSystem/           # Shared colors, spacing, styling
├── Domain/                 # Core data model (enums, structs)
├── Events/                 # Event model and event repository
├── Git/                    # Git snapshot model and client
├── Persistence/            # JSON persistence, DB persistence, coders
├── Session/                # Live session model
├── Store/                  # In-memory state struct
├── Supervisor/             # Lifecycle orchestration, migration, workspace repository
├── Tasks/                  # External task models and repository
├── Templates/              # Built-in and custom template catalog
├── Telemetry/              # Runtime telemetry parser
├── Workspace/              # All SwiftUI views (roster, detail, inspector, composer, history, task inbox, timeline, budget, display modes)
└── Worktree/               # Worktree creation, validation, recovery, cleanup
```
