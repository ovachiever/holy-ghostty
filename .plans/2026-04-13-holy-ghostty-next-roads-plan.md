# Holy Ghostty Next Roads Plan

Date: 2026-04-13

## Current State

Holy Ghostty is already a native macOS shell over Ghostty surfaces, with:

- a real resizable macOS window and installed app identity
- session creation, duplication, close, archive, and restore flows
- adapter-driven runtime profiles for Claude, Codex, OpenCode, and Shell
- git-aware session context, worktree attachment, and conflict detection
- launch guardrails for shared worktrees and shared branches
- native alerts for attention, failure, completion, and branch drift

The remaining work is no longer about proving the concept. It is about hardening the app into a durable operator-grade control plane for agentic coding work.

## Roads Still To Walk

### 1. Database Backbone

Replace snapshot persistence with a real SQLite-backed storage layer:

- schema migrations
- indexed session/event/history tables
- budget and cost ledgers
- crash-safe replay and restore
- searchable structured logs and artifacts

### 2. Session Supervisor Split

Pull orchestration logic out of the workspace store into dedicated services:

- session launch orchestration
- lifecycle policy and recovery
- dependency chains
- restart and archive behavior
- ownership enforcement
- managed worktree cleanup

### 3. Budget And Cost Intelligence

Add a first-class financial model for long-running agent work:

- per-session and per-template budgets
- cumulative spend tracking
- burn-rate and projected completion cost
- threshold alerts and enforcement actions
- runtime-specific cost extraction

### 4. Review Mode

Turn the right rail into a real review surface:

- file-grouped diff summaries
- build and test outcome review
- merge-readiness signals
- commit safety checks
- artifact cards for outputs, commits, and logs

### 5. Grid / Focus / Diff Modes

Complete the mission-control shell:

- 2x2 and 2x3 live multi-surface views
- focus mode with minimal chrome
- promotion and demotion of sessions
- frozen previews and render throttling
- side-by-side diff mode for comparing session output and code impact

### 6. Deeper Runtime Telemetry

Strengthen runtime intelligence beyond coarse text heuristics:

- better stalled and looping detection
- more reliable waiting-for-input detection
- richer command and phase timelines
- artifact extraction
- runtime-specific summaries and completion state

### 7. Worktree Policy Hardening

Make branch and worktree ownership strict and auditable:

- explicit worktree registry
- provenance records
- reservation release semantics
- orphaned worktree recovery
- safer relaunch and duplicate behavior

### 8. Embedded Bridge Extensions

Add Zig-side bridge work only where host code needs stronger signals:

- richer parsed terminal events exposed to the host
- cleaner progress and command metadata
- reduced reliance on preview scraping
- targeted signal forwarding for runtime adapters

### 9. External Integrations

Connect the app to the broader agent workflow:

- issue and task source integration
- work item to session mapping
- prompt and context injection
- policy packs per repo
- external notification and automation hooks

### 10. Ship-Grade macOS Productization

Finish the app as a real Mac product:

- final icon and visual identity
- settings and preferences
- keyboard shortcut system for operator actions
- onboarding and first-run flow
- accessibility pass
- signing, notarization, and release distribution

## Recommended Build Order

The best next implementation order remains:

1. SQLite persistence plus event ledger
2. Session supervisor split from the workspace store
3. Budget and cost engine
4. Review mode
5. Grid, focus, and diff modes
6. Deeper runtime telemetry
7. Targeted embedded bridge extensions
8. Final macOS productization and release hardening

## Working Principle

There is no throwaway MVP track here. Each road should be built as permanent production code, with each phase becoming part of the final app rather than a disposable prototype.
