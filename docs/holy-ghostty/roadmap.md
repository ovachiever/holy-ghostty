# Holy Ghostty Roadmap

Last updated: 2026-04-18

This roadmap starts from the released `v0.1` state and carries Holy Ghostty to the point where the remaining missing systems are complete and the product can be honestly described as production-ready.

This is a product roadmap, not just a feature backlog. It is sequenced by dependency, operator value, and architectural leverage.

## Finish Line

Holy Ghostty is production-ready when all of these are true:

- durable database and event ledger exist and survive crashes, upgrades, and restarts
- cost and budget intelligence are first-class product systems
- grid mode, diff mode, and focus mode are live and stable
- runtime telemetry is structured enough that session state is not mostly heuristic
- external task-system integration exists and is operationally useful
- the current monolithic workspace store has been split into cleaner runtime subsystems
- the app remains fast, native, and understandable while doing all of the above

## Why This Order

The missing systems are not independent.

The correct order is:

1. data backbone
2. session supervision
3. structured telemetry
4. operator surfaces that consume those systems
5. external integrations that depend on those systems
6. production hardening of the whole stack

If the order is reversed, the app turns into a pile of features with weak persistence and weak internal truth.

## Current State: v0.2

`v0.2` delivered the foundation release plus significant work originally planned for later milestones.

What v0.2 shipped:

- durable SQLite database with WAL, schema migrations, and event ledger (planned for v0.2)
- session supervisor split from monolithic workspace store (planned for v0.2)
- structured session event model with typed events and rich payloads (planned for v0.2)
- budget intelligence with token/cost parsing, ledger, projections, and enforcement (planned for v0.3)
- structured runtime telemetry parsing with stall/loop detection (planned for v0.3)
- focus, grid, and diff display modes (planned for v0.4)
- external task inbox with GitHub, Linear, Jira, and manual support (planned for v0.5)
- worktree recovery evaluation and orphan cleanup
- `agent-sessions` compatibility views

## v0.2: Foundation Release (shipped)

All v0.2 deliverables were shipped, along with significant work from v0.3, v0.4, and v0.5.

See [CHANGELOG.md](../../CHANGELOG.md) for the full list.

## v0.3: Intelligence Release (largely shipped in v0.2)

Most v0.3 deliverables were shipped as part of v0.2: budget intelligence, structured runtime telemetry parsing, event timeline, and richer inspector sections.

Remaining v0.3 work:

- deeper structured runtime telemetry via an embedded VT/PTY bridge (current system is inference-based from terminal preview text)
- richer adapter/event model per runtime with stronger command lifecycle tracking
- completion and failure classification from structured signals where possible

## v0.4: Mission Control Release (largely shipped in v0.2)

Focus, grid, and diff display modes were shipped as functional scaffolds in v0.2.

Remaining v0.4 work:

- polish and performance optimization for multi-surface rendering
- session cycling and keyboard-first switching in focus mode
- performance-aware rendering policy for grid mode
- review-oriented completion workflow (“safe to merge” vs “done but risky” product states)

## v0.5: Integration Release (partially shipped in v0.2)

The external task inbox (GitHub, Linear, Jira, manual) was shipped in v0.2 with full CRUD and task-to-session launching.

Remaining v0.5 work:

- status updates pushed back to external task sources
- dependency chains between sessions
- post-completion triggers
- broadcast input across sessions
- relaunch from archived context into a new work item flow

## v1.0: Production-Ready Release

Theme:

Finish the platform, harden the edges, and make the promise honest.

Primary goal:

Turn the now-complete system into something that is operationally durable, supportable, and credible as a production tool.

### Deliverables

#### 1. Stability and recovery hardening

Scope:

- migration testing
- database corruption handling and recovery paths
- restart and restore reliability
- degraded-mode behavior when integrations or telemetry sources fail

#### 2. Product hardening

Scope:

- settings and preferences surface for the new systems
- clearer onboarding for worktrees, budgets, and templates
- notification controls
- keyboard shortcuts and operator ergonomics
- stronger archive/review flows

#### 3. Release hardening

Scope:

- consistent versioning and release notes discipline
- signing/notarization/distribution path
- better support and troubleshooting docs
- explicit public product claims that match reality

### v1.0 exit criteria

- all six previously-missing systems are implemented and operational
- the app is no longer architecturally dependent on a monolithic workspace store
- the product can survive restart, failure, and upgrade with durable operator memory
- the UI supports both single-session focus and multi-session control
- external task integration is real, not conceptual
- Holy Ghostty can be honestly described as production-ready

## Cross-Release Workstreams

Some workstreams cut across every release:

### Design discipline

- keep the terminal as the hero
- prevent dashboard sprawl
- make advanced modes feel intentional, not bolted on

### Performance

- preserve Ghostty-native feel
- measure multi-surface cost as modes are added
- do not let richer telemetry make the shell sluggish

### Migration safety

- every architectural rewrite needs a path from `v0.1` state forward
- do not strand existing sessions, archives, or templates

## Roadmap Summary

The original release train was:

1. `v0.2` foundation: database, event ledger, supervisor split (shipped)
2. `v0.3` intelligence: structured telemetry and budgets (largely shipped in v0.2)
3. `v0.4` mission control: focus, grid, diff (scaffolded in v0.2)
4. `v0.5` integrations: task-system integration and orchestration hooks (task inbox shipped in v0.2)
5. `v1.0` production-ready: hardening, reliability, and honest completeness

v0.2 delivered substantially ahead of the original plan. The remaining work concentrates on depth (deeper telemetry bridge, automation hooks, production hardening) rather than breadth.
