# Holy Ghostty Production Plan

Date: 2026-04-08
Repo: `/Users/erik/Documents/AI/Custom_Coding/holy-ghostty`

## Intent

Holy Ghostty is not a prettier tabbed terminal. It is an agent-first coding and organization platform that uses Ghostty as the terminal engine and embedded surface runtime.

The plan below is production-oriented from the start. Phases are sequencing for the final system, not throwaway MVP work.

## Product Thesis

The core job of the app is to make long-running, multi-agent coding sessions visible, steerable, and safe.

A session must become a first-class object with:

- identity
- owning worktree and branch
- assigned objective
- assigned adapter/runtime
- budget and cost state
- live terminal surface
- event stream
- alerts
- artifacts
- archive and replay

The terminal remains essential, but it is no longer the product boundary. The product boundary is orchestration.

## Non-Negotiable Product Goals

- macOS-first and excellent on macOS
- Ghostty rendering quality and responsiveness preserved
- multi-agent session management as the primary workflow
- persistent sessions across app relaunches
- worktree-aware and branch-aware from day one
- budget and attention management built into the core model
- real review surface for diffs, logs, conflicts, and completion state
- no dependence on tmux
- no dependence on browser tabs as the main control plane

## Core Architectural Decisions

### 1. Treat `libghostty` as the terminal engine, not the app shell

We will keep the terminal emulation, rendering, PTY behavior, font handling, and most embedded runtime behavior intact wherever possible.

We will build the agent platform in the macOS host layer and only extend the embedded bridge when the host needs structured signals that do not exist yet.

### 2. macOS shell first, not a new Zig apprt

On macOS, Ghostty already runs as a native host app over the embedded library. The production path is to evolve or replace the current macOS shell with a new mission-control-style shell rather than invent a new top-level Zig runtime.

### 3. Session metadata lives in the host domain, not in terminal ABI

Budgets, labels, issue links, adapters, dependencies, archive metadata, conflict state, and workflow state will live in the host app store and persistence layer.

The terminal surface owns terminal state.

The host owns session state.

### 4. Structured event flow beats terminal scraping

We will use Ghostty's existing embedded/runtime signals first:

- command start and stop
- progress reports
- pwd changes
- child exit
- bell and renderer health

We will add a narrow embedded event bridge only where production requirements demand it.

Terminal text snapshots will be used for previews, search, and contextual summaries, not as the primary source of truth for durable state.

### 5. Agent intelligence uses adapters, not only heuristics

Claude, Codex, OpenCode, Gemini, and future tools do not expose identical output semantics.

The platform will support runtime adapters that can:

- classify session state
- infer waiting-for-input state
- infer completion
- derive cost metrics
- emit attention events
- attach extra artifacts or summaries

Adapters will consume structured terminal signals first, then bounded heuristics where required.

### 6. Production phases are vertical slices of the final system

Each phase builds permanent code that remains in the finished app.

We are not building a "temporary MVP app" and then rewriting it.

## Product Experience

### Primary Shell

The default shell is a three-zone workspace:

- left rail: session roster sorted by urgency
- center: active Ghostty surface
- right rail: context panel for the selected session

### Core Modes

- Mission Control mode: roster + active surface + context
- Grid mode: 2x2 and 2x3 live surfaces, with promotion to focus
- Focus mode: one surface, minimal chrome, aggregate status badge
- Diff mode: two sessions side by side with diffs and merge context
- Review mode: completion summaries, changed files, commit readiness, risk flags
- Archive mode: replayable sessions, searchable logs, artifacts, cost history

### Core Alerts

- waiting for user input
- task completed
- build or test failure
- budget threshold
- conflict on same file or worktree collision
- stalled or looping session

## Target System Architecture

### Layer A: Terminal Engine

Owned by existing Ghostty core:

- VT parsing
- renderer
- PTY management
- font and shaping
- scrollback and selection

Files are largely left intact:

- `src/terminal/**`
- `src/renderer/**`
- `src/font/**`
- most of `src/termio/**`

### Layer B: Embedded Bridge

Purpose:

- expose host-safe surface creation and control
- expose surface identity and host callbacks
- forward structured surface/runtime events to the host

Likely touch points:

- `include/ghostty.h`
- `src/apprt/embedded.zig`
- `src/apprt/surface.zig`
- targeted event forwarding in `src/termio/stream_handler.zig`
- possibly targeted forwarding for currently dropped parsed signals

Rule:

- surgical changes only
- no renderer rewrite
- no terminal parser rewrite

### Layer C: Holy Ghostty Host Application

This becomes the actual product shell.

Primary subsystems:

- WorkspaceShell
- SessionStore
- SessionSupervisor
- SurfaceHost
- RosterEngine
- ContextEngine
- WorktreeManager
- GitMonitor
- AlertCenter
- BudgetEngine
- AdapterRegistry
- ArchiveStore

### Layer D: Persistence and Domain State

Persistent entities:

- Workspace
- Session
- SurfaceBinding
- SessionDependency
- WorktreeRecord
- BudgetRecord
- CostLedger
- SessionEvent
- Alert
- Artifact
- ArchiveEntry

Storage requirements:

- durable local database
- crash-safe writes
- indexed event retrieval
- fast roster queries
- archive and replay support

Preferred approach:

- SQLite-backed store
- explicit schema and migrations
- repository layer in Swift

### Layer E: Integrations

- git and worktree integration
- issue/task source integration
- local filesystem and diff integration
- agent runtime adapters
- optional external notification hooks later

## Proposed Code Layout

New macOS product code should live in a clear parallel structure rather than inside one oversized view/controller cluster.

Proposed layout:

- `macos/Sources/HolyGhostty/App/`
- `macos/Sources/HolyGhostty/Domain/`
- `macos/Sources/HolyGhostty/Persistence/`
- `macos/Sources/HolyGhostty/Workspace/`
- `macos/Sources/HolyGhostty/Session/`
- `macos/Sources/HolyGhostty/SurfaceHost/`
- `macos/Sources/HolyGhostty/Context/`
- `macos/Sources/HolyGhostty/Git/`
- `macos/Sources/HolyGhostty/Adapters/`
- `macos/Sources/HolyGhostty/Alerts/`
- `macos/Sources/HolyGhostty/Archive/`
- `macos/Sources/HolyGhostty/DesignSystem/`

Existing Ghostty macOS bridge code remains available and will be reused where correct:

- surface creation
- embedded callbacks
- Metal-backed terminal surface hosting
- input and clipboard integration

## Session Model

Each session will own:

- `session_id`
- title
- objective
- runtime adapter
- launch spec
- workspace path
- git worktree path
- branch
- env set
- budget policy
- status
- attention state
- selected surface id
- artifact list
- dependency list
- timestamps

Status model:

- queued
- launching
- active
- waiting_input
- blocked
- reviewing
- completed
- failed
- archived

Attention model:

- none
- watch
- needs_input
- failure
- budget
- conflict
- done

## Event Model

We need a real event ledger, not just UI state.

Event classes:

- terminal lifecycle
- command lifecycle
- adapter-derived session state
- git/worktree state changes
- budget and cost changes
- alerts
- artifacts
- user interventions

Event sources:

- embedded Ghostty bridge
- host app actions
- git monitors
- adapter classifiers
- explicit user actions

## Git and Worktree Strategy

Sessions are worktree-native.

Production rules:

- every coding session may own a dedicated worktree
- worktree creation, naming, cleanup, and recovery are first-class features
- branch ownership is visible in the roster
- file overlap across active sessions is tracked continuously
- diffs are summarized in the context rail
- merge readiness is modeled, not guessed

Core capabilities:

- create or attach worktree
- branch status
- changed files summary
- conflict detection
- ahead/behind
- merge conflict surface
- session-to-branch provenance

## Cost and Budget Strategy

Budgets are core session configuration, not an afterthought.

We will track:

- session budget
- cumulative spend
- projected spend
- adapter-reported token velocity
- warning thresholds
- hard stops and soft stops

If a runtime exposes no usable cost data, the adapter still owns a best-effort estimate path and an "unknown" state rather than fake precision.

## Adapter Architecture

Each agent/runtime integration ships as an adapter with:

- runtime id
- launch plan
- status classifier
- completion classifier
- waiting-input classifier
- cost extractor
- artifact extractor
- session summary generator

Initial adapters:

- Claude Code
- Codex
- OpenCode

Future adapters:

- Gemini CLI
- custom shells
- browser-backed agents if you decide to support them as pseudo-sessions

## Performance Strategy

We will preserve the "fast terminal" property.

Production rules:

- do not continuously scrape full screen contents at high frequency
- cache and throttle expensive text reads
- prefer event-driven updates
- grid mode only keeps truly necessary surfaces hot
- larger walls use visibility and promotion rules instead of brute-force always-live rendering

Practical default:

- 2x2 live grid as the standard dense operational mode
- 2x3 available with aggressive update discipline
- larger "wall" modes use frozen previews or activity-triggered refresh if needed

## Security and Safety

- no destructive git automation without explicit user action or explicit session policy
- clear display of commands, branch ownership, and file ownership
- track when a session is waiting for approval
- maintain archive of agent actions and artifacts for review
- never hide budget exhaustion or conflict state

## Production Phases

## Phase 1: Product Skeleton and Domain Backbone

Goal:

Build the permanent host architecture that every later feature hangs from.

Deliverables:

- `HolyGhostty` app shell structure
- domain models
- persistent session database and migrations
- app state container
- session roster model
- surface/session binding model
- placeholder mission-control shell wired to real Ghostty surfaces

Exit criteria:

- app launches into the new shell
- session objects are durable across relaunches
- one live Ghostty surface can be attached to a session record
- no throwaway scaffolding

## Phase 2: Mission Control Workspace

Goal:

Replace the stock terminal shell with the actual Holy Ghostty workspace.

Deliverables:

- left rail roster
- center active surface host
- right rail context shell
- focus mode
- grid mode
- diff mode shell
- keyboard navigation and selection model

Exit criteria:

- multiple live sessions can be opened and switched in the new shell
- roster ordering and selection are correct
- the workspace is stable under multiple surfaces

## Phase 3: Embedded Event Bridge

Goal:

Expose the structured runtime signals the host needs for a real agent platform.

Deliverables:

- host-consumable event callbacks from embedded runtime
- surface lifecycle event forwarding
- command start and stop forwarding
- pwd forwarding
- progress forwarding
- child exit forwarding
- additional forwarding for currently missing parsed signals if required

Exit criteria:

- session state can update from event flow rather than text scraping
- host can build timelines and alerts from runtime events

## Phase 4: Session Supervisor and Worktree Engine

Goal:

Turn terminal surfaces into managed coding sessions.

Deliverables:

- session launch specs
- worktree creation and attachment
- branch policy
- environment management
- restart and recovery behavior
- dependency chains
- session templates

Exit criteria:

- a session can be created from a launch spec and restored after restart
- worktree ownership is visible and durable
- session lifecycle is coherent end to end

## Phase 5: Context Engine and Review Surface

Goal:

Give each session a serious right rail and review workflow.

Deliverables:

- changed files summary
- diff summary
- git status
- conflict detection
- searchable output summaries
- session artifacts
- review mode

Exit criteria:

- the user can inspect active work without manually polling terminals
- completion review is materially better than stock Ghostty tabs

## Phase 6: Adapter Layer and Attention Model

Goal:

Make the system agent-aware instead of terminal-aware.

Deliverables:

- adapter registry
- Claude Code adapter
- Codex adapter
- OpenCode adapter
- waiting-input classification
- completion classification
- budget and cost reporting
- alert routing

Exit criteria:

- major target runtimes produce useful attention signals
- budget and waiting-input flows are visible in roster and notifications

## Phase 7: Archive, Replay, and Operational Polish

Goal:

Finish the platform into an operational daily driver.

Deliverables:

- archive and session replay
- searchable history
- notifications and summaries
- crash recovery
- settings surface
- visual polish
- onboarding and templates

Exit criteria:

- the app supports full-day and multi-day agent workflows without degrading into tab sprawl
- sessions can be resumed, reviewed, and audited

## Swarm Execution Strategy

Decision:

After approval, implementation should use an agent swarm with strict file ownership and me as orchestrator.

Reason:

- the work naturally decomposes into host UI, persistence, adapters, git integration, and embedded bridge
- those slices can progress in parallel with low conflict if ownership is explicit
- the orchestrator needs to preserve architecture and integration correctness

### Worker Ownership Model

Worker A: Host App and Navigation

- `macos/Sources/HolyGhostty/App/**`
- `macos/Sources/HolyGhostty/Workspace/**`
- `macos/Sources/HolyGhostty/DesignSystem/**`

Worker B: Domain and Persistence

- `macos/Sources/HolyGhostty/Domain/**`
- `macos/Sources/HolyGhostty/Persistence/**`
- `macos/Sources/HolyGhostty/Archive/**`

Worker C: Surface Host and Bridge Integration

- `macos/Sources/HolyGhostty/SurfaceHost/**`
- integration glue to existing Ghostty macOS surface hosting

Worker D: Embedded Bridge and Zig Hooking

- `include/ghostty.h`
- `src/apprt/embedded.zig`
- `src/apprt/surface.zig`
- narrowly scoped supporting Zig files only when needed

Worker E: Git and Context

- `macos/Sources/HolyGhostty/Git/**`
- `macos/Sources/HolyGhostty/Context/**`

Worker F: Session Supervisor and Adapters

- `macos/Sources/HolyGhostty/Session/**`
- `macos/Sources/HolyGhostty/Adapters/**`
- `macos/Sources/HolyGhostty/Alerts/**`

### Orchestrator Ownership

I keep ownership of:

- architecture decisions
- cross-module contracts
- merge direction
- event model
- phase sequencing
- integration verification
- final pass on naming, behavior, and tests

## Immediate Build Order After Approval

1. establish the new macOS module structure and product shell
2. wire persistent session domain and storage
3. embed real Ghostty surfaces inside the new shell
4. add the embedded event bridge
5. add session supervisor and worktree manager
6. add the context rail and review surfaces
7. add adapters and attention logic
8. harden archive, recovery, and polish

## Release Gates

The app is not "production-ready" until all of the following are true:

- session persistence is durable
- multi-surface shell is stable
- worktree ownership is correct
- diff and git context are trustworthy
- alerts are not noisy or misleading
- budget handling is coherent
- crash recovery works
- adapter behavior is explicit about unknowns
- performance remains terminal-grade

## Notes For Implementation

- prefer reuse of the existing embedded surface host over a fresh renderer path
- avoid changing terminal core unless there is no host-layer alternative
- if a needed signal is already parsed but dropped, surface it through the bridge instead of inventing a second parser
- favor explicit contracts between host and bridge over hidden heuristics
- keep the repo mergeable with upstream Ghostty by minimizing Zig-side divergence

## Approval Outcome

If this plan is approved, I will start implementation with a swarm model, not solo mode.

Solo mode would only make sense if you want a slower but more serialized rollout.
