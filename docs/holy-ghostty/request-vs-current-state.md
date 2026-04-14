# Holy Ghostty: Requested Vision Vs Current State

Last updated: 2026-04-13

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

Holy Ghostty is now a working native macOS app that embeds real Ghostty terminal surfaces inside an agent-focused shell.

Current product identity:

- a live session roster on the left
- a focused active Ghostty surface in the center
- an operational inspector on the right
- a native session composer
- a searchable archive and relaunch flow
- worktree-aware and branch-aware launch policy
- git-aware session coordination
- runtime-specific heuristics for Shell, Claude, Codex, and OpenCode
- native notifications for failures, needs-input, collisions, drift, and completion

It is no longer just a concept or a fork idea. It is a real installable app with a real operator workflow.

## 3. Requested Vs Implemented

| Requested direction | Current state | Status | Notes |
| --- | --- | --- | --- |
| Ghostty as the foundation | Ghostty still provides the terminal core and live surface embedding | Implemented | Holy Ghostty is layered into the existing macOS host |
| Agent-first shell instead of generic terminal tabs | Holy shell exists with roster, live surface, inspector, templates, archive, and coordination | Implemented | This is the defining product shape today |
| Native mission-control feel | Native macOS window and SwiftUI shell exist | Partially implemented | The shell is real and installable, but visual/design polish is still iterative |
| Session as first-class unit of work | Sessions have launch specs, runtime, mission, ownership, archive state, git context, and relaunch flow | Implemented | This is one of the strongest shipped changes |
| Better organization of many concurrent agents | Active roster, archive, templates, guardrails, and coordination model exist | Implemented | Current scale is centered on the single-focused-surface workflow |
| Alerts that matter | Native notifications exist for high-signal transitions | Implemented | Alert history is not yet durable |
| Context side panel | Right-side inspector exists and shows mission, telemetry, git, coordination, output preview, and env | Implemented | The current inspector is operational, not yet a final ideal information architecture |
| Worktree-aware agent operation | Direct, attached-worktree, and managed-worktree strategies exist | Implemented | Managed worktrees are a core recommended workflow |
| Conflict prevention | Launch guardrails block shared worktrees and warn on shared branches | Implemented | This is a real prevention layer, not just passive display |
| Session templates | Built-in templates and saveable templates exist | Implemented | Current built-ins target Shell, Claude, Codex, OpenCode |
| Reviewable archive/history | History sheet and archived session model exist | Implemented | Relaunch and edit-relaunch flows are present |
| Output/state awareness | Runtime adapters and preview-based signal heuristics exist | Partially implemented | Works today, but not via deep structured VT/PTY telemetry |
| Token burn and cost tracking | Not implemented | Missing | No budget engine yet |
| Grid mode / multi-surface wall | Not implemented | Missing | Current UI is single-focus with roster |
| Focus mode | Not implemented | Missing | The center surface is dominant, but there is no dedicated mode |
| Diff mode | Not implemented | Missing | No side-by-side review mode yet |
| External task-system integration | Not implemented | Missing | No manna/issue-system layer yet |
| Dependency chains across agents | Not implemented | Missing | No automatic chaining today |
| Broadcast input across sessions | Not implemented | Missing | No multi-send orchestration yet |
| Durable production data layer | JSON snapshot persistence exists | Partially implemented | No SQLite or event ledger yet |

## 4. What Changed In Practice

The biggest product clarification during implementation was this:

Holy Ghostty is not just "Ghostty with agent decorations." It is a session supervisor and control plane whose live execution surfaces happen to be Ghostty terminals.

That shift shows up in the current app through:

- launch guardrails instead of raw tab creation
- worktree ownership as a first-class concern
- archived sessions instead of disposable tabs
- runtime-aware heuristics instead of terminal-only framing
- inspector-driven context instead of plain terminal multiplexing

## 5. Where The Current App Is Strong

The current app is already meaningfully different from stock terminal workflows in these areas:

- live session orchestration
- worktree-aware launch management
- branch and file overlap detection
- archive and relaunch history
- runtime-specific session state classification
- real macOS packaging and installation

These are not placeholder features. They are the core of the current product.

## 6. Where The Current App Still Falls Short Of The Original Ambition

The original ambition was broader than the current implementation.

Major unfinished roads:

- richer structured runtime telemetry instead of heuristics
- cost and budget intelligence
- multi-surface grid and comparison modes
- review-oriented diff workflows
- external issue/task system integration
- durable event and alert history
- deeper separation between shell/store/supervisor/data layers

## 7. The Most Honest Summary

What was requested:

- a serious Ghostty-based platform for agentic coding operations

What exists now:

- a real macOS-native first-generation agent-control app with strong session ownership and coordination semantics, but without the full data, review, multi-surface, and cost systems originally envisioned

That means the app is already real and useful, but it is still version one of the broader platform idea rather than the final expression of that idea.
