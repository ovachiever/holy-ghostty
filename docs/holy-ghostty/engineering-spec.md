# Holy Ghostty Engineering Spec

Last updated: 2026-07-21

This document describes the current repository implementation. It is an as-is engineering spec.

Current release: `0.44`.

## 1. Purpose

Holy Ghostty is a macOS-native shell built around Ghostty terminal surfaces for running and supervising coding sessions. The Holy layer adds session orchestration, tmux-backed local and SSH launch policy, worktree management, git-aware coordination, runtime heuristics, structured telemetry, budget intelligence, an external task inbox, an append-only event ledger, archive/history, templates, remote host discovery, and native alerts without replacing Ghostty's terminal core.

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
   - Adds the workspace UI, session model, persistence, tmux-backed launch substrate, git/worktree logic, launch guardrails, heuristics, structured telemetry, budget intelligence, task inbox, remote host discovery, event ledger, archive, templates, and alerts.

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
- no attached app toolbar in the standard workspace
- content ignores the top safe area so terminal panes can use the top edge
- full-screen primary and managed collection behavior
- autosaved frame

### SwiftUI shell

- `macos/Sources/HolyGhostty/Workspace/HolyWorkspaceView.swift`

Responsibilities:

- render the overall Holy shell
- render the left tmux roster, selected terminal surfaces, and optional inspector
- compose Holy-owned pane layouts over durable tmux-backed sessions
- manage sheet presentation for session creation, history, remote hosts, and task inbox

Current exposed workspace layouts:

- Single: grouped left roster and one selected session surface
- Split Right: selected session plus one additional session side by side
- Split Down: selected session plus one additional session stacked vertically
- Quad: up to four live session surfaces

The older Focus, Grid, and Diff implementations remain dormant in this file for a later explicit comparison/review pass. They are not exposed in the primary Level 1 chrome.

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

Current filters remove terminal chrome, tmux status bars, separator lines, and readiness footer/prompt lines before classifying activity. If there is no current structured signal, stale telemetry is cleared instead of displayed.

This heuristic layer feeds phase chrome and stall detection only. The roster's six-state indicators come from the provider-native agent-state bridge (section 6A) and never consume screen text.

## 6A. Agent State Bridge And Authoritative Indicators

The authoritative indicator system lives in:

- `macos/Sources/HolyGhostty/AgentState/HolyAgentStateBridge.swift`
- `macos/Sources/HolyGhostty/AgentState/HolyAgentStateBridgeInstaller.swift`
- `macos/Sources/HolyGhostty/AgentState/HolyAgentStateEnvelope.swift`
- `macos/Sources/HolyGhostty/AgentState/HolyTmuxAgentStateMonitor.swift`
- `macos/Sources/HolyGhostty/AgentState/HolyCodexNotifyConfiguration.swift`
- `HolySessionIndicatorPolicy` and `HolySessionAttentionMetadata` in `macos/Sources/HolyGhostty/Domain/HolyModels.swift`

Canonical contract: `docs/superpowers/specs/2026-07-14-authoritative-agent-indicators.md`.

Producers. Holy generates and exact-merges lifecycle hooks for Claude Code
and Codex, a Codex committed-turn notify adapter, and an OpenCode plugin. All
publish the same bounded metadata-only envelope
(`v1|source|lifecycle|epoch-ms|event-token|session-id|reason-code`) through a
shared helper into the pane-scoped tmux option `@holy_agent_state_v1`, with
finishes copied to the independent `@holy_agent_last_finished_v1` register and
an OSC 777 fast path for immediate delivery. Claude publishes `finished` from
its Stop hook (a blocked stop self-corrects via newest-wins ordering), with
idle_prompt as confirmation. A second five-field register,
`@holy_watcher_v1`, is maintained by an inline ScheduleWakeup-matched hook
program that reads only `delaySeconds` and `stop` from the tool input and
records when an armed `/loop` wakeup will fire.

Transport. `HolyTmuxAgentStateMonitor` is an actor polling each distinct
tmux endpoint with one grouped `list-panes` read per second locally (0.75 s
remote start cadence, bounded command timeouts). Each poll carries both
registers plus process evidence: `pane_dead`, `pane_current_command`, and
`window_activity`. Parsing fails closed per register: malformed, conflicting,
or ambiguously owned values yield nothing rather than a guess.

Policy. `HolySessionIndicatorPolicy` derives exactly six mutually exclusive
states. Working and needs-user claims carry 30-minute leases. Process
evidence may extend or invalidate a working claim, never create one: a live
non-shell producer with pane output fresher than three minutes extends past
the lease, and a provably dead producer invalidates within a poll. The
used-today axis (`lastUsedAt`) advances only on committed `user-prompt`
envelopes; the inactive/sleeping split anchors to the latest activity on any
axis. Seen tracking is versioned; the current version clears pre-existing
recency stamps once so blue is earned from real prompts.

Presentation. `HolyWorkspaceStore` recomputes attention presentations against
a published attention clock that ticks each minute and additionally advances
on envelope arrival and process-evidence transitions, so the roster repaints
within about a second of a real change. The watcher eye renders from the
watcher register as a static glyph beside the age label and never feeds
policy.

Notifications. Actionable events (finished, needs-user, failed) schedule
macOS notifications through a deterministic request identity and a persisted
monotonic watermark, so duplicates, restarts, and older recovery registers
never re-alert. Focused visibility acknowledges an event before a banner can
fire for the session the operator is already watching.

Installation. `HolyAgentStateBridgeInstaller` is consent-gated behind the
`Enable Authoritative Agent Indicators` menu action, snapshot-and-rollback
transactional across every touched file, and ownership-exact: it merges only
handlers it can prove it owns, blocks on foreign files, and accepts one
delegation case — a foreign Codex notifier that chains Holy's adapter by file
name is left untouched in both directions.

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

## 8C. Launch Profiles

- `macos/Sources/HolyGhostty/Profiles/HolyLaunchProfile.swift`
- `macos/Sources/HolyGhostty/Profiles/HolyLaunchProfileRepository.swift`

Launch profiles drive the left-roster `New` action without hardcoding personal machine choices into the repo.

Generated profile types:

- `Local Mac`
- one profile per configured SSH host

The selected default profile is stored in `app_state` under `default_launch_profile_id`. On first profile creation, Holy Ghostty defaults `New` to the only configured SSH host when exactly one exists; otherwise it defaults to `Local Mac`.

## 8D. SSH Resilience And Roster Convergence

- `macos/Sources/HolyGhostty/Tmux/HolyTmuxCommandBuilder.swift`
- `macos/Sources/HolyGhostty/Workspace/HolyConvergePlanner.swift`
- `macos/Sources/HolyGhostty/Workspace/HolyRepairBackoff.swift`
- `macos/Sources/HolyGhostty/App/HolyPowerAssertionManager.swift`
- `macos/Sources/HolyGhostty/Workspace/HolyWorkspaceStore.swift`

Remote SSH/tmux sessions used to die silently across sleep and network drops, and the old `Sync` action detached every session serially with no timeout, so one asleep host stalled it for minutes. Three cooperating layers replace that.

Connection hygiene:

- the long-lived attach `ssh` carries `ServerAliveInterval=15`, `ServerAliveCountMax=4`, `TCPKeepAlive=no`, `ConnectTimeout=8` (no `BatchMode` — the pane is interactive), so a dead peer is detected in ~60s
- the headless detach `ssh` carries `ConnectTimeout=5`, `BatchMode=yes`, so an unreachable host fails fast instead of hanging

Converge-to-truth `Sync`:

- `HolyConvergePlanner` is a pure diff engine: it buckets the roster against a live discovery sweep into adopt-archived / surface-orphan / repair-dead / archive-vanished actions and never touches healthy panes
- a discovery-only session that matches an archived record is re-adopted with the discovered socket and session name; an unknown orphan remains visible in Hosts for explicit Attach or confirmed Kill and is never attached or reaped automatically
- a session is "dead" when its local process exited, or it runs while the remote session reports zero attached clients (a zombie whose TCP died); a nonzero remote client count masks the zombie until the keepalive kills the local process
- session identity keys derive from the session's own tmux socket on both the roster and discovery sides; reachability is judged by the sockets the discovery service actually probes, so a vanished session is archived only on a host whose namespace was covered
- incomplete legacy identity is repaired only from a unique live discovery match; convergence never calls launch-spec realization to invent a missing name or silently select the default socket
- convergence requests the full inventory, including shells normally hidden from the Hosts list; if such a shell still cannot be resolved, the roster fallback removes archive authority rather than guessing that it vanished
- the sweep runs each host concurrently under a per-host wall-clock cap; a timed-out host is treated as unreachable, and a single-flight gate with debounce prevents overlapping runs

Self-healing triggers, all firing the same converge engine:

- the `Sync` button (manual, bypasses debounce)
- `NSWorkspace.didWakeNotification` in `HolyWorkspaceWindowController`, after a 4s settle for Wi-Fi/Tailscale
- per-session pane death (`HolySession` posts on the transition into a terminal phase), retried on the `HolyRepairBackoff` schedule of 4s, 10s, 25s, then silent until the next wake or manual `Sync`

Keep-awake:

- `HolyPowerAssertionManager` holds a single `PreventUserIdleSystemSleep` assertion while remote sessions are in the roster (the display may still sleep)
- controlled by `keepAwakeWhileRemoteAttached`, persisted in `UserDefaults` (device-local policy, default on) with a roster overflow-menu toggle

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

Tmux termination is discovery-driven. Holy resolves a roster record against the live inventory, backfills an incomplete legacy identity only when the match is unique and strongly evidenced, kills that exact socket/session pair, and polls `has-session` for absence before archiving the roster row. An incomplete or ambiguous target fails closed and directs the user to the explicit Hosts controls. Normal session creation already persists `HolyTmuxCommandBuilder.realizedLaunchSpec`, so newly created records retain their generated name and socket.

Workspace restoration applies the same boundary before constructing a Ghostty surface. A missing name on the explicit `holy` socket may be repaired from the synchronous launch probe; records whose socket or remote target is incomplete are preserved as deferred archives until the full converge inventory can prove one exact live identity. Deferred records suppress default-session seeding so startup cannot create a replacement shell beside the still-live session.

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
- launch profiles and default launch target
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

Sequential schema migration runner with 8 migrations:

1. Full initial schema (sessions, events, git_snapshots, templates, alerts, annotations, indexes, and `agent-sessions` compatibility views)
2. `latest_budget_json` column on sessions
3. `latest_runtime_telemetry_json` column on sessions
4. `budget_samples` table
5. `tasks` table
6. `remote_hosts` table
7. `launch_profiles` table
8. bounded-retention tombstones (`sessions.purge_pending_at`) and compatibility-view filtering

Current schema version: 8.

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
- `launch_profiles`

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

Retention is bounded and interruption-safe:

- unchanged git state reuses the session's referenced snapshot row instead of inserting another poll sample
- product reads retain only `sessions.latest_git_snapshot_id`; unreferenced legacy snapshots drain oldest-first in bounded utility-queue batches
- removed sessions are hidden with `purge_pending_at` before their dependent history drains, then physically deleted once the cascade is small
- archived history keeps the newest 64 records unconditionally, then records no older than 90 days up to a normal cap of 256; positively discovered live matches are protected until re-adoption
- `HolyDatabaseMaintenance.createCompactedCopy` provides an explicit, free-space-gated `VACUUM INTO` copy with integrity, schema-version, and row-count checks; it never runs at startup and never swaps or deletes the live database

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

- `recoveryEvaluation(for:)`: validates whether a worktree-backed session can be restored (checks directory existence, git validity, repository match, branch match)
- `cleanupOrphanedManagedWorktrees(referencedPaths:)`: removes orphaned managed worktrees not referenced by any session
- worktree creation with cleanup on failure

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
- budget warning or exceeded
- phase becomes completed

Authoritative agent events (replied, needs you, failed) notify separately
through the agent-state gate described in section 6A, with deterministic
request identities and a persisted watermark so duplicates and restarts never
re-alert.

## 22. Views And User-Facing Surfaces

### Session roster

- `macos/Sources/HolyGhostty/Workspace/HolySessionRosterView.swift`

Displays active sessions grouped by runtime and sorted by project/folder context. Each row shows one compact project/folder label, one activity orb, and quiet risk icons when needed.

The roster `New` button launches the current default launch profile. The `More` menu exposes all profiles for direct launch and default selection.

### Session detail

- `macos/Sources/HolyGhostty/Workspace/HolySessionDetailView.swift`

Displays the currently selected session with the live `Ghostty.SurfaceView`. The session header can be shown by callers, but the standard Level 1 workspace hides it so terminal panes start at the top edge.

### Context inspector

- `macos/Sources/HolyGhostty/Workspace/HolyContextPanelView.swift`

Displays:

- mission when linked to a task
- runtime telemetry only when meaningful
- budget state only when configured or usage exists
- session timeline
- coordination summary and external peers
- git risk and changed-file summary
- verification from command telemetry
- actions
- collapsed launch metadata

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

## 23. Pane Layouts

The standard workspace exposes Holy-owned visual pane layouts from the bottom of the left rail. These layouts arrange whole Holy sessions, not tmux panes.

### Single

The selected session fills the main terminal surface.

### Split Right

The selected session stays on the left and another durable Holy session is shown to the right.

### Split Down

The selected session stays on top and another durable Holy session is shown below.

### Quad

Up to four durable Holy sessions are shown at once.

Pane layout state is persisted with the workspace. When a session is visible in a multi-pane layout, the roster shows a small pane-position label such as `Left`, `Right`, `Top`, `Bottom`, or a quadrant label.

The old Diff implementation is intentionally preserved dormant for a future agent/worktree comparison mode. It is not part of the current Level 1 navigation.

## 24. Integration Into Ghostty Host

Holy Ghostty integrates into the existing Ghostty macOS app.

Relevant file:

- `macos/Sources/App/macOS/AppDelegate+Ghostty.swift`

Important integration behavior:

- surface lookup checks `HolyWorkspaceWindowController.all` first
- legacy terminal controllers still exist as fallback

## 25. Build And Install

Verified Holy core build:

```bash
scripts/build-holy-ghostty-core.sh build
```

The wrapper invokes an isolated framework-only Zig build with `ReleaseFast`,
exact Zig-version enforcement, source and payload fingerprints, generated
resource validation, and no recursive macOS app build. It publishes the
finished payload only after validation. Do not use a bare
`zig build -Demit-xcframework`: Zig defaults to Debug and also enables the
separate app-copy path.

When local Zig cannot link the installed macOS SDK, the **Build Holy macOS core**
workflow produces a 90-day, commit-named archive containing the framework,
generated resources, and the same receipt. A monthly main build prevents normal
artifact expiry. Import its contained zip with
`scripts/build-holy-ghostty-core.sh import <archive>`; the local verifier accepts
it only when its source fingerprint and every packaged payload hash match the
current core inputs. Swift-only commit differences do not invalidate it.

macOS app build after the verified core exists:

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration ReleaseLocal SYMROOT=build
```

Canonical build, verification, and installation entrypoint:

- `scripts/install-holy-ghostty.sh`

Installation is transactional: the candidate is copied, signed, and verified
before it is published; the old bundle remains available for rollback through
LaunchServices registration and final verification. The running app is stopped
only after those gates pass. There is no production skip-build path.

Installed bundle path:

```text
/Applications/Holy Ghostty.app
```

## 26. Module Map

```text
macos/Sources/HolyGhostty/
├── AgentState/             # Lifecycle hook bridge, installer, envelope, tmux monitor, notify config
├── App/                    # Window controller, app shell
├── Adapters/               # Runtime-specific heuristic adapters
├── Automation/             # URL scheme parsing for session spawn
├── Budget/                 # Budget parsing and intelligence repository
├── Claude/                 # Claude model indicator bridge and statusline helper
├── Database/               # SQLite engine, migrator, schema, paths
├── DesignSystem/           # Shared colors, spacing, styling
├── Domain/                 # Core data model, indicator policy, attention metadata
├── Events/                 # Event model and event repository
├── Git/                    # Git snapshot model and client
├── Persistence/            # JSON persistence, DB persistence, coders
├── Profiles/               # Launch profiles and default New target persistence
├── Remote/                 # Remote host registry, import, tmux discovery
├── Session/                # Live session model
├── Store/                  # In-memory state struct
├── Supervisor/             # Lifecycle orchestration, migration, workspace repository
├── Tasks/                  # External task models and repository
├── Telemetry/              # Runtime telemetry parser
├── Templates/              # Built-in and custom template catalog
├── Tmux/                   # tmux models and launch command builder
├── Workspace/              # SwiftUI views: roster, pane layouts, detail, inspector, composer, history, task inbox, timeline, budget
└── Worktree/               # Worktree creation, validation, recovery, cleanup
```
