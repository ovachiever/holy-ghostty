# Changelog

All notable Holy Ghostty changes should be recorded in this file.

The format is intentionally simple and release-oriented.

## Unreleased

Post-`0.2.0` mainline work currently includes:

### Added

- tmux-backed local and SSH session launches as the default Holy session substrate
- Holy automation entrypoints via `holy-ghostty://spawn`, AppleScript `spawn`, and `scripts/holy-spawn-session.sh`
- persistent remote host registry with schema migration `6`
- host import from `~/.ssh/config` and Tailscale
- remote tmux discovery and attach inside the `Remote Hosts` sheet
- right-rail **Verification** section backed by OSC 133 command telemetry (last outcome, duration, elapsed since)
- right-rail **Actions** row — Copy handoff, Copy diff, Duplicate, Archive
- right-rail **Risk** summary — git changes bucketed by consequence (project / deps / CI / scripts / config / tests / docs / source), full file list behind a disclosure
- external-peer intelligence in **Coordination** via `agent-do coord peers` subprocess probe
- opinionated ASCII angel-ghost background watermark at 4% opacity, rendered by Ghostty's `background-image` config; extracted from an asset catalog data set into `~/Library/Application Support/Holy Ghostty/` on launch

### Changed

- remote Holy sessions now enrich inspector/git state over SSH instead of staying local-only
- public README and Holy docs now describe the current tmux/remote product shape instead of the older v0.2-only surface
- right rail redesigned against a Prime Rule — only show what the terminal itself cannot. **Output** section removed (terminal is output); **Launch** collapsed into a `Details` disclosure; **Mission** gated behind a linked task; **Budget** gated behind configured budget or observed usage.
- left-rail session rows split runtime and project into a two-line label with middle-truncation, replacing the old `Shell — Custom_Codi…` compound truncation
- session action menu hides the `.borderlessButton` disclosure chevron for a clean ellipsis affordance
- Holy defaults config (`background-image`, fit, position, opacity) loads before user config so `~/.config/ghostty/config` always wins on overrides

## 0.2.0 (2026-04-18)

The Foundation Release. Replaces fragile JSON-only persistence with a durable SQLite database, introduces an append-only event ledger, splits the monolithic workspace store into distinct subsystems, and adds budget intelligence, structured telemetry, display modes, and an external task inbox.

### Added

- SQLite database layer with WAL journal mode, schema versioning, and 5 migrations
- Append-only session event ledger with typed events (imported, restored, recovered, created, archived, relaunched, selected, runtimeUpdated, artifactDetected)
- Event timeline UI in both the live inspector and archived session views
- Session supervisor (`HolySessionSupervisor`) owning lifecycle orchestration, alert coordination, worktree recovery, and orphan cleanup
- Workspace repository facade with dual-write (database + JSON) during transition
- Migration service for one-shot import of legacy JSON state into the database
- Budget intelligence: per-session budget model, budget parser (token/cost extraction from terminal output), budget samples ledger, runtime rollups, exhaustion projection, enforcement policies (warn, requireApproval)
- Budget UI sections in the composer, inspector, and history views
- Structured runtime telemetry parser: activity kind inference (idle, approval, progress, reading, editing, command, stalled, looping, failure, completion), command extraction, file path extraction, next-step hint detection, artifact detection, stall/loop detection
- Runtime telemetry sections in the inspector and history views
- External task inbox with GitHub, Linear, Jira, and manual task support
- Task CRUD, task-to-session launching, linked session tracking, canonical URL opening
- Task inbox sheet with split-view search, list, and detail editor
- Focus display mode (Cmd+Shift+F): full-screen single session with floating status overlay
- Grid display mode (Cmd+Shift+G): 2x2/2x3 tiled session previews with selection and promotion
- Diff display mode (Cmd+Shift+D): side-by-side session comparison with branch, file overlap, and phase analysis
- Worktree recovery evaluation (directory existence, git validity, repository match, branch match)
- Orphaned managed worktree cleanup
- `agent-sessions` compatibility views (4 versioned read-only SQL views)
- Shared persistence coders for JSON and ISO8601 timestamps
- In-memory session store state struct with mutation/event pairing
- Agent-sessions interoperability design document
- Roadmap document (v0.2 through v1.0)

### Changed

- Workspace store delegates lifecycle operations to the session supervisor instead of handling them inline
- All launch paths now carry event provenance (origin, source template ID, relaunched-from session ID)
- Session selection emits selection events to the event ledger
- Session composer includes budget configuration (token limit, cost limit, enforcement policy) and linked task display
- History sheet shows recovery context, runtime telemetry, budget telemetry, and event timeline
- Inspector shows runtime telemetry, budget analytics, event timeline, and task source
- Archived sessions now include budget telemetry, runtime telemetry, recovery reason, and cleanup summary
- Launch specs now include optional task reference and budget
- Session drafts include linked task, budget fields, and budget validation
- Sessions track preview stability (signature, first-observed time, repeat count) for stall/loop detection
- Alert coordinator now fires on stalls, loops, and budget warnings in addition to existing triggers
- Worktree manager includes recovery evaluation, orphan cleanup, and improved error handling on creation

## 0.1 (2026-04-16)

Initial public release of Holy Ghostty as a macOS-native agentic coding session control surface built on Ghostty.

### Added

- Holy Ghostty product README at `README.md`
- dedicated public docs set under `docs/holy-ghostty/`
- user guide and tutorial
- as-is engineering spec
- requested-vision vs current-state comparison

### Changed

- app icon and in-app logo updated to the current Holy Ghostty mark
- public repo surface cleaned by removing internal planning, agent-only guidance, and inherited upstream vouch workflow scaffolding
