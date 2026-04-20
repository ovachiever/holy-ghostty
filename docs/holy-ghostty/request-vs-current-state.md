# Holy Ghostty: Requested Vision Vs Current State

Last updated: 2026-04-19

This document compares the original product request to the current app as it exists in the repository today.

## 1. What Was Requested

The original ask was not "make Ghostty look different." It was:

- take Ghostty as the foundation
- make it agent-AI first
- replace the "tons of tabs with agents in browsers and terminals" workflow
- build a mission-control style operator surface
- better organize concurrent agent sessions
- surface alerts and status
- treat sessions as first-class work units
- dream toward a serious multi-agent coding and organization platform

The early product thesis also leaned on:

- keeping Ghostty core intact
- building a custom shell around live terminal surfaces
- making worktrees, branches, and agent ownership explicit
- adding archives, coordination, templates, and eventually richer multi-agent views

## 2. What Holy Ghostty Is Now

Holy Ghostty is a working native macOS app that embeds real Ghostty terminal surfaces inside an agent-focused shell, backed by a durable SQLite database with an append-only event ledger, a separated supervisor architecture, tmux-backed local and SSH session launches, remote host discovery, budget intelligence, structured runtime telemetry, multiple display modes, and an external task inbox.

Current product identity:

- a live session roster on the left
- a focused active Ghostty surface in the center
- an operational inspector on the right with runtime telemetry, budget analytics, event timeline, and coordination
- a native session composer with budget configuration and task linking
- a searchable archive and relaunch flow with recovery context
- worktree-aware and branch-aware launch policy
- tmux-backed launch substrate so sessions stay attachable after Holy Ghostty closes
- automation entrypoints through URL scheme, shell helper, and AppleScript
- remote host registry with manual, SSH-config, and Tailscale import
- remote tmux discovery and attach, including Holy metadata readback
- remote git enrichment for SSH-backed Holy sessions
- git-aware session coordination
- runtime-specific heuristics for Shell, Claude, Codex, and OpenCode
- structured telemetry parsing (activity kind, stall/loop detection, command/file/artifact extraction)
- budget intelligence (token/cost tracking, burn rate, exhaustion projection, enforcement policies)
- an external task inbox with support for GitHub, Linear, Jira, and manual tasks
- focus mode, grid mode, and diff mode for multi-session operation
- native notifications for failures, needs-input, collisions, drift, stalls, loops, budget warnings, and completion
- durable SQLite persistence with schema migrations and an event ledger
- `agent-sessions` compatibility views for future cross-tool interoperability

## 3. Requested Vs Implemented

| Requested direction | Current state | Status | Notes |
| --- | --- | --- | --- |
| Ghostty as the foundation | Ghostty still provides the terminal core and live surface embedding | Implemented | Holy Ghostty is layered into the existing macOS host |
| Agent-first shell instead of generic terminal tabs | Holy shell exists with roster, live surface, inspector, templates, archive, and coordination | Implemented | This is the defining product shape today |
| Native mission-control feel | Native macOS window and SwiftUI shell with multiple display modes | Implemented | Standard, focus, grid, and diff modes are all functional |
| Session as first-class unit of work | Sessions have launch specs, runtime, mission, ownership, budget, task linkage, event history, archive state, git context, and relaunch flow | Implemented | The strongest shipped feature, now with durable persistence |
| Better organization of many concurrent agents | Active roster, archive, templates, guardrails, coordination, grid mode, and diff mode exist | Implemented | Grid and diff modes address the multi-session visibility gap |
| Alerts that matter | Native notifications exist for high-signal transitions including stalls, loops, and budget warnings | Implemented | Alert history is stored in the event ledger |
| Context side panel | Right-side inspector shows mission, runtime telemetry, budget analytics, event timeline, git, coordination, output preview, and environment | Implemented | Significantly richer than v0.1 |
| Worktree-aware agent operation | Direct, attached-worktree, and managed-worktree strategies exist with recovery validation | Implemented | Recovery evaluation and orphan cleanup are new |
| Conflict prevention | Launch guardrails block shared worktrees and warn on shared branches | Implemented | Real prevention layer, not passive display |
| Session templates | Built-in templates and saveable templates exist | Implemented | Current built-ins target Shell, Claude, Codex, OpenCode |
| Reviewable archive/history | History sheet with recovery context, runtime telemetry, budget telemetry, and event timeline | Implemented | Substantially richer than v0.1 |
| Output/state awareness | Runtime adapters, telemetry parser (activity kind, stall/loop detection, command/file extraction), and budget parser | Partially implemented | Strong inference layer, but not yet a structured VT/PTY bridge |
| Token burn and cost tracking | Budget model, telemetry parsing, ledger, projections, burn rate, enforcement policies, UI sections | Implemented | Full budget intelligence system |
| Grid mode / multi-surface wall | 2x2/2x3 tiled session previews with selection and promotion | Implemented | Functional scaffold |
| Focus mode | Full-screen single session with floating status overlay | Implemented | Functional scaffold |
| Diff mode | Side-by-side session comparison with branch, file, and phase analysis | Implemented | Functional scaffold |
| External task-system integration | Task inbox with GitHub, Linear, Jira, and manual task support, task-to-session launching | Implemented | Full CRUD and launch flow |
| Durable tmux-backed sessions | Local and SSH launches are tmux-backed by default, with socket/session controls and metadata | Implemented | Sessions remain attachable after the app closes |
| Replacing SSH/tmux macro workflows | URL scheme, shell helper, AppleScript spawn, remote host registry, and remote tmux discovery | Implemented | Holy can now act as a first-class tmux control plane instead of a tab macro target |
| Dependency chains across agents | Not implemented | Missing | No automatic chaining today |
| Broadcast input across sessions | Not implemented | Missing | No multi-send orchestration yet |
| Durable production data layer | SQLite database with WAL, schema migrations, event ledger, budget samples, and compatibility views | Implemented | Replaced the v0.1 JSON-only persistence |

## 4. What Changed From v0.1 To v0.2

v0.2 was planned as the foundation release (database, event ledger, supervisor split). It delivered all of that plus significant work originally planned for later releases:

- Budget intelligence (originally v0.3)
- Structured runtime telemetry parsing (originally v0.3)
- Focus, grid, and diff display modes (originally v0.4)
- External task inbox (originally v0.5)

The supervisor split separated lifecycle orchestration from the workspace store, with the `HolySessionSupervisor` owning restore, create, archive, persist, alert coordination, worktree recovery, and orphan cleanup.

The event ledger now captures session lifecycle transitions with typed events and rich payloads, displayed in an inline timeline in both the live inspector and archived session views.

Post-`v0.2.0`, the app also gained a tmux-backed execution substrate, URL/AppleScript automation entrypoints, a remote host registry, SSH-config and Tailscale import, remote tmux discovery, and remote git enrichment for SSH-backed Holy sessions.

## 5. Where The Current App Is Strong

- live session orchestration with durable persistence
- worktree-aware launch management with recovery validation
- branch and file overlap detection
- archive and relaunch history with recovery context
- runtime-specific session state classification with stall/loop detection
- budget intelligence with enforcement and projection
- multiple display modes for different operational needs
- external task inbox bridging work items to sessions
- tmux-backed durable sessions that survive app shutdown
- remote host discovery and tmux attach without tab macros
- append-only event ledger for session history
- real macOS packaging and installation
- `agent-sessions` compatibility views for future interoperability

## 6. Where The Current App Still Falls Short Of The Original Ambition

Remaining unfinished roads:

- deeper structured runtime telemetry via an embedded VT/PTY bridge (current system is inference-based)
- broader remote orchestration and remote policy beyond host registry plus tmux discovery
- dependency chains and automated session orchestration
- broadcast input across sessions
- status updates pushed back to external task sources
- post-completion triggers and automation hooks
- settings and preferences surface for budgets, notifications, and templates
- signing, notarization, and distribution path
- production hardening (migration testing, corruption recovery, degraded-mode behavior)

## 7. The Most Honest Summary

What was requested:

- a serious Ghostty-based platform for agentic coding operations

What exists now:

- a real macOS-native second-generation agent-control app with durable persistence, budget intelligence, structured telemetry, multiple display modes, an external task inbox, and strong session ownership semantics

The gap between v0.1 and v0.2 was substantial. Most of the originally-missing systems now exist in at least a functional first form. The remaining work is primarily about depth (deeper telemetry, automation hooks, production hardening) rather than breadth.
