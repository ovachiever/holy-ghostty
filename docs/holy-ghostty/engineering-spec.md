# Holy Ghostty Engineering Spec

Last updated: 2026-08-22

This document describes the current repository implementation. It is an as-is engineering spec.

Current release: `0.50`.

## 1. Purpose

Holy Ghostty is a macOS-native shell built around Ghostty terminal surfaces for running and supervising coding sessions. The Holy layer adds session orchestration, tmux-backed local and SSH launch policy, worktree management, git-aware coordination, runtime heuristics, structured telemetry, budget intelligence, an external task inbox, a human inbox, crash restore, an append-only event ledger, archive/history, templates, remote host discovery, and native alerts without replacing Ghostty's terminal core.

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
- manage sheet presentation for session creation, history, remote hosts, task inbox, and Session Restore, plus the restore banner and the Inbox panel

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

- `HolySessionLaunchSpec` (transport, tmux spec, optional task reference, budget, session note with edit timestamp, and the Today pin)
- `HolySessionRecord`
- `HolySessionDraft` (linked task, budget fields, budget validation, transport, and tmux fields)
- `HolySessionTemplate`
- `HolyArchivedSession` (budget telemetry, runtime telemetry, recovery reason, and cleanup summary)
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

## 6B. Claude Usage Guard

The usage guard lives in:

- `macos/Sources/HolyGhostty/Claude/HolyClaudeUsage.swift`
- `macos/Sources/HolyGhostty/Claude/HolyClaudeUsageBridge.swift`
- `macos/Sources/HolyGhostty/Claude/HolyClaudeUsageMonitor.swift`
- `macos/Sources/HolyGhostty/Workspace/HolyWorkspaceStore+ClaudeUsage.swift`
- `macos/Sources/HolyGhostty/Workspace/HolyClaudeUsageMeterView.swift`
- the status-line helper in `macos/Sources/HolyGhostty/Claude/HolyClaudeModelBridge.swift`
- `toggleClaudeUsageGuard` in `macos/Sources/App/macOS/AppDelegate.swift`

Tests: `macos/Tests/HolyGhostty/HolyClaudeUsageGuardTests.swift`.

Problem. A claude.ai Max subscription enforces three windows — 5-hour
session, weekly all-models, weekly per-model (Fable) — and a capped window
kills subagents and teammates outright while only the main session
auto-waits. The guard turns those windows into levels and levels into hook
instructions, so every running session checkpoints before the cap.

Files on disk. Everything lives under
`~/Library/Application Support/Holy Ghostty/`: the generated helpers
`claude-usage-probe.py` and `claude-usage-guard.py` (Python string constants
in `HolyClaudeUsageBridge`, stamped `Owner: com.holyghostty.claude-usage.v1`,
mode 0700) and a `usage/` directory (0700) holding `policy.json`,
`latest.json`, `history.jsonl`, `accounts/<email>.json`,
`sessions/<session_id>.json`, `guard-state/<session_id>.json`,
`wrap-up-requested.json`, and a `refresh-requested` stamp.
`HolyClaudeUsageBridgePaths` is the single definition of these paths;
`HOLY_USAGE_DIR` redirects the directory for the helpers and the tests.

Probe. `claude-usage-probe.py` reads `~/.claude.json` `oauthAccount` for
the e-mail, account UUID, and organization, then the keychain item
`Claude Code-credentials` through `/usr/bin/security find-generic-password
-w` with captured stdout — the token is never on a command line — taking
subscription type, rate-limit tier, and token expiry from the same blob. It
sends the token only as a Bearer header (with
`anthropic-beta: oauth-2025-04-20`) to
`https://api.anthropic.com/api/oauth/usage` and normalizes `limits[]` into
buckets keyed `session`, `weekly_all`, and `weekly_scoped:<model display
name>`, each with `percent`, `severity`, `resets_at`, `window_seconds`, and
`is_active`; the older flat `five_hour`/`seven_day` shape is accepted as a
fallback. Burn rate is the slope over the trailing tenth of a bucket's
window, using only history samples from the same account, with points
before an in-span reset discarded; `eta_full_at` is set only when the rate
is positive and the projected cap precedes the reset. Outputs: `latest.json`
(schema 1), `history.jsonl` (one compact `{t, a, b}` line per successful
probe, pruned to one weekly window), and `accounts/<email>.json` (the full
snapshot under the sanitized e-mail). A failed probe writes its error into
`latest.json` but carries the previous buckets forward marked `stale_since`,
so a transient failure neither blanks the meter nor silences the guard. The
probe also removes `sessions/` files untouched for one session window,
budgets the whole run to `poll_seconds` (a quarter for the keychain, the
rest for the request), and exits 1 with the error in the snapshot.

Status line. The Claude Model Indicator helper extracts
`rate_limits.five_hour` and `rate_limits.seven_day` (`used_percentage`,
`resets_at`) from the status-line JSON and, when `usage/sessions/` exists,
writes `{t, session_id, pane, cwd, five_hour, seven_day}` to
`sessions/<session_id>.json` by atomic rename and appends `· 5h N% · wk N%`
to the model label. `SessionEnd` removes the file. These numbers come from
the session's own API responses, so they stay right for a session running
under an account the keychain has since left.

Policy. `HolyClaudeUsagePolicy` (`warnPercent` 75, `criticalPercent` 90,
`leadMinutes` 20, `pollSeconds` 60) is read from the `UserDefaults` keys
`holy.claudeUsage.warnPercent|criticalPercent|leadMinutes|pollSeconds`;
absent, zero, or out-of-range values fall back, and critical is clamped to
at least warn. The store writes it to `usage/policy.json` (`warn_percent`,
`critical_percent`, `lead_minutes`, `poll_seconds`) at install and at every
monitor start; the hook loads the same file with the same fallbacks.

Evaluation. `HolyClaudeUsageEvaluator.level(for:policy:now:)` is the single
Swift rule set: `capped` at ≥ 100%; `critical` at ≥ criticalPercent or when
`eta_full_at − now ≤ lead`; `warn` when the ETA is within 2 × lead and
percent ≥ warnPercent / 2, at ≥ warnPercent, or when the provider severity
is anything but `normal`; else `normal`. `assess` takes the worst bucket,
ties broken by higher percent. The guard script's `level_for` and `assess`
mirror it line for line, and `guardMirrorsSwiftEvaluatorAcrossFixtures` runs
both against the same fixtures.

Guard hook. `claude-usage-guard.py` is registered with an empty matcher on
`PreToolUse` and `UserPromptSubmit`. It reads only `hook_event_name`,
`session_id`, and `tool_name` from stdin, never prompts or tool inputs. Per
call it loads the policy, `latest.json`, and the session's own file
(windows whose `resets_at` has passed are dropped); the session's own
`session` and `weekly_all` buckets replace the machine-wide ones, and the
remaining machine buckets (including `weekly_scoped:*`) are merged in. When
`latest.json` is older than two poll periods it spawns the probe detached,
gated by the `refresh-requested` stamp to one launch per poll period, so the
guard runs without the app. Output is always JSON on stdout with exit 0; a
crash exits 0. At `normal` it clears `guard-state/<session_id>.json` and
emits nothing. At `warn` it emits `additionalContext` (checkpoint now, no
new subagents or long tasks) once on entry and again every half lead
window, tracked in `guard-state`. At `critical` and `capped` every call
carries the stop instruction — finish or abort at a safe point, commit or
write state, reply with a note beginning `PAUSED (usage cap):`, end the
turn — and a `PreToolUse` for `Agent`, `Task`, or `Workflow` adds
`permissionDecision: deny` with the reason. `UserPromptSubmit` only ever
receives `additionalContext`.

Wrap-up. `HolyClaudeUsageBridge.requestWrapUp` writes
`wrap-up-requested.json` (`requested_at`, `expires_at` = now + lead,
`account_email`, `reason`). The hook raises any level below critical to
critical while the request is unexpired and its e-mail matches the
snapshot's signed-in account; a different account cancels it implicitly,
`cancelWrapUp` deletes it explicitly.

Monitor and store. `HolyClaudeUsageMonitor` is an actor that runs the probe
on `pollSeconds` with `HOLY_USAGE_DIR` set, terminates it at the deadline,
then reads back `latest.json`, the live `sessions/*.json` (at least one
window not yet reset), `accounts/*.json` newest first, and the active
wrap-up request into a `HolyClaudeUsageReport`. Holy never talks to the
network. `HolyWorkspaceStore` starts or stops the monitor at launch and on
`holyClaudeUsageBridgeDidChange`, publishes each report, and assesses the
machine-wide buckets for the meter's level. `refreshNow` reruns the probe
immediately; wrap-up request and cancel re-read the disk state without a
probe.

Presentation. `HolyClaudeUsageMeterView` renders as a centered band in the
sidebar footer, directly above `leftRailViewControls` — a level dot, one
bar per bucket colored by that bucket's level, a pause glyph while a
wrap-up stands, a clock badge when the snapshot is stale — and as a
compact percent capsule of the deciding bucket in the collapsed rail. The
footer band draws its own top hairline and background inside the
guard-installed conditional, so nothing reserves space while the guard is
off; its popover opens upward (`arrowEdge: .top`). The
popover (`HolyClaudeUsageDetailView`) shows the level title, account and
tier, snapshot age, each bucket with warn and critical ticks and its reset,
rate, and ETA, sessions reporting their own windows, known accounts (when
more than one, or when the newest differs from the signed-in one), and the
Refresh and wrap-up controls.

Notifications. `notifyClaudeUsageTransitions` keeps the last announced
level per bucket key and delivers one `UNNotificationRequest` per upward
crossing with identifier `holy.claude-usage.<key>.<level>`, so a repeat
replaces rather than stacks; a downward crossing or a vanished bucket resets
the record. Critical and capped call `requestUserAttention(.criticalRequest)`.
Authorization is requested on first need; a denial is silent.

Installation. `toggleClaudeUsageGuard` is consent-gated behind
`Enable Claude Usage Guard…` (inserted after `Enable Claude Model
Indicator…`, hidden outside the Holy bundle; the title becomes `Disable…`
or `Repair…` by installation state). `HolyClaudeUsageBridge.install`
creates the directories, writes both helpers and `policy.json`, and within
each event's groups replaces only handlers whose command is Holy's guard
path, preserving every foreign group and the settings file's permissions and
symlink target. `remove` strips only those handlers and deletes only helpers
carrying the owner marker; `usage/` stays. `installationState` reports
`needsRepair` when a helper or hook is present but not current. Enabling
while the Model Indicator is absent shows a one-time hint to enable it.

Known limits. Only the signed-in account is polled live. The per-model
(Fable) weekly bucket exists only in the probe's machine-wide snapshot, not
in per-session readings. The endpoint is undocumented; the probe matches
the observed behavior of Claude Code's own `/usage` screen. A session that
just ran `/login` may receive one stale warning before its own reading
refreshes.

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

Remote SSH/tmux sessions must survive sleep and network drops without dying silently, and `Sync` must not stall on one asleep host. Three cooperating layers provide that.

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

The supervisor owns lifecycle orchestration on behalf of `HolyWorkspaceStore`. It handles:

- workspace restore (including worktree recovery evaluation and orphan cleanup)
- session creation (with event provenance tracking)
- session archive
- archive deletion
- template saving
- persistence (dual-write to SQLite and the legacy JSON snapshot)
- scheduled persistence (debounced)
- alert coordination

Tmux termination is discovery-driven. Holy resolves a roster record against the live inventory, backfills an incomplete legacy identity only when the match is unique and strongly evidenced, kills that exact socket/session pair, and polls `has-session` for absence before archiving the roster row. An incomplete or ambiguous target fails closed and directs the user to the explicit Hosts controls. Normal session creation already persists `HolyTmuxCommandBuilder.realizedLaunchSpec`, so newly created records retain their generated name and socket.

The kill itself is `HolyTmuxLifecycleService` (`Tmux/HolyTmuxLifecycleService.swift`), a reusable three-verb primitive shared by the roster kill flow, the Hosts panel, and the crash-restore engine: `verifyLiveIdentity` (present/absent/undetermined, fail-closed), `killVerified` (returns `.killed` or `.alreadyAbsent`, both inventory-proven absence), and `pollUntilAbsent`. A dead server or a live server that does not know the exact name counts as proven absence, so kills are idempotent; every other failure carries `HolyTmuxLifecycleFailure` with the command stage (launch/connect/kill/verify/probe/timeout), the exact socket and `=`-prefixed target, tmux's stderr, and the full identity of any process-launch error. Helper spawns preserve the NSError domain/code/errno instead of collapsing into localizedDescription (the "Cocoa error 3584" field failure), and both the service and discovery retry a failed spawn once, since posix_spawn EAGAIN under swarm process pressure is transient and nothing has executed yet.

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

## 9A. Session Restore (Crash Restore)

- `macos/Sources/HolyGhostty/Restore/HolyRestoreEngine.swift`
- `macos/Sources/HolyGhostty/Restore/HolyRestoreModels.swift`
- `macos/Sources/HolyGhostty/Restore/HolyRestoreCrashGroups.swift`
- `macos/Sources/HolyGhostty/Restore/HolyRestoreAssignment.swift`
- `macos/Sources/HolyGhostty/Restore/HolyRestoreResolveClient.swift`
- `macos/Sources/HolyGhostty/Restore/HolyRestoreCommandBuilder.swift`
- `macos/Sources/HolyGhostty/Restore/HolyRestoreExecutableSearch.swift`
- `macos/Sources/HolyGhostty/Restore/HolyRestorePreflight.swift`
- `macos/Sources/HolyGhostty/Restore/HolyRestoreSheet.swift`
- `macos/Sources/HolyGhostty/Restore/HolyWorkspaceRestoreAdapter.swift`

Session Restore turns any tmux-server death — crash, reboot, or deliberate
kill — into a restorable batch. Entry points: a workspace banner, the
`View ▸ Restore Sessions…` menu item, and a callout at the top of Session
History.

Grouping. `HolyRestoreCrashGroups` splits restorable rows into per-shutdown
groups; each group carries a recency rank that the sheet renders as a color
wash, and each offers a per-shutdown restore. Machine-titled helper shells
(title matching `-shell-[0-9A-F]{8}$`) are collapsed inside their group.
Rows display the session's note using the roster's note treatment.

Preflight. `HolyRestorePreflight` is a total, pure function mapping
preflight facts to exactly one row state, with deliberate precedence:
unsupported host, identity conflict, live identity (adoption), undetermined
liveness (fail-closed: unknown is never absence), local preconditions (cwd,
provider executable), then the resolver's confidence verdict.

Conversation resolution. `HolyRestoreResolveClient` ships the whole sheet's
questions in one `agent-sessions resolve-batch --json` call, which performs
its own scoped reindex. `HolyRestoreAssignment` assigns candidates to rows
globally and uniquely: no two rows can receive the same conversation id.

Resume identity. `HolyRestoreCommandBuilder` renders the exact provider
argv — `claude --resume <id>`, `codex resume <id>`, `opencode --session
<id>` — after validating the provider session id. `HolyRestoreExecutableSearch`
pins argv[0] to an absolute executable path when resolution comes from
fallback directories (including every installed nvm node version, newest
first), because the pane's login-shell PATH misses `.zshrc`-initialized
managers. The restored identity is the argv itself; nothing re-resolves
after restore.

Row outcomes. An exact match restores directly; an ambiguous match offers a
candidate picker; a row with no recoverable history offers only a labeled
shell-only recreate (cwd and explicit command). A resolver failure is
retryable and never silently demoted to shell-only. Bulk restore acts only
on rows with exact identity; it never quietly recreates ambiguous rows.

Tmux liveness during restore uses the same `HolyTmuxLifecycleService`
described in section 9, so adoption, conflict, and absence verdicts are
inventory-proven.

## 9B. Human Inbox

- `macos/Sources/HolyGhostty/Inbox/HolyInboxEngine.swift`
- `macos/Sources/HolyGhostty/Inbox/HolyInboxModels.swift`
- `macos/Sources/HolyGhostty/Inbox/HolyInboxPanelView.swift`
- `macos/Sources/HolyGhostty/Inbox/HolyGitHubInboxSource.swift`
- `macos/Sources/HolyGhostty/Inbox/HolyAlertInboxSource.swift`
- `macos/Sources/HolyGhostty/Inbox/HolyInboxAlertStore.swift`
- `macos/Sources/HolyGhostty/Inbox/HolyMannaInboxSource.swift`
- `macos/Sources/HolyGhostty/Inbox/HolyBriefContract.swift`
- `macos/Sources/HolyGhostty/Inbox/HolyBriefFeed.swift`
- `macos/Sources/HolyGhostty/Inbox/HolyBriefTriage.swift`
- `macos/Sources/HolyGhostty/Inbox/HolyBriefViews.swift`

The Inbox panel (`⌘P`, `View ▸ Inbox Panel`) is one pane for everything
waiting on a human.

Engine. `HolyInboxEngine` polls every registered source on a cadence — 75
seconds while the panel is visible, 5 minutes hidden so the unread badge
cannot lie — plus immediately on panel open, app foreground, and manual
refresh. Sources refresh independently (a slow GitHub sweep never holds
local rows hostage), sections render in registration order regardless of
completion order, and per-source refreshes are serialized with coalescing.

Sources:

- GitHub attention (`HolyGitHubInboxSource`): needs-review rows first, then
  maintainer sweeps (`maintainer_unreviewed`, `maintainer_review_stale`);
  bot authors collapse to one digest per repository.
- In-app alerts (`HolyAlertInboxSource` over `HolyInboxAlertStore`): alert
  deliveries are recorded to the `alerts` table; acknowledge writes
  `acknowledged_at` and the row leaves the pane on the next refresh.
- Manna board triage (`HolyMannaInboxSource`): rows from the repository's
  agent-do manna board with human decisions prominent. Manna ids are
  validated against manna's own id alphabet (`mn-` plus lowercase
  `[a-z0-9]`) before any id reaches an executed command's stdin, and a
  glance never mutates the board.

Brief. `HolyBriefFeed` runs `agent-do brief holy --json` as one composite
call and publishes the parsed payload (answer paragraph, threads,
suggestions); `HolyBriefContract` parses it fail-closed against contract
version 1, and `HolyBriefTriage` is a pure mapping deciding which threads
earn the Needs-me drawer versus Library inventory. The brief is not an
engine source; the engine keeps carrying the Library sources.

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

All launch paths carry event provenance: origin, source template ID, relaunched-from session ID.

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

The schema includes four read-only SQL views forming the `agent-sessions` read-model contract:

- `agent_sessions_sessions_v1`
- `agent_sessions_resume_targets_v1`
- `agent_sessions_events_v1`
- `agent_sessions_annotations_v1`

All four filter out purge-pending sessions. See `docs/holy-ghostty/agent-sessions-interoperability.md` for the contract and for the reverse direction, where Holy's crash restore consumes the `agent-sessions` `resolve-batch` CLI as its conversation oracle.

Additional persisted tables:

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

JSON snapshot persistence is retained for backward compatibility. The workspace repository writes to both database and JSON on every save and reads database-first.

### Workspace repository

- `macos/Sources/HolyGhostty/Supervisor/HolyWorkspaceRepository.swift`

Facade that loads from database first, triggers migration from JSON if needed, then falls back to JSON. Saves to both destinations.

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
- Claude Session
- Codex Session
- OpenCode Session
- Claude Managed Session
- Codex Managed Session

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

`HolyGitClient` supports both:

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

Overlapping changed files are computed only across distinct worktrees. Session pairs attached to the same checkout are presented as a shared uncommitted file count (`N uncommitted files in the shared checkout`), never as cross-session overlap. Blocking-conflict detection (`hasBlockingConflict`) derives from conflict severity, independent of that presentation.

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

Alert deliveries are also recorded to the `alerts` table and surface in the
Human Inbox (section 9B), where each row stays until explicitly acknowledged.

## 22. Views And User-Facing Surfaces

### Session roster

- `macos/Sources/HolyGhostty/Workspace/HolySessionRosterView.swift`

Displays active sessions sorted by project/folder context. A four-way layout switcher (persisted via `AppStorage`) selects Classic or Calm (grouped by runtime), Triage (status lanes), or Focus (pinned Today sessions on top, the rest dimmed). Each row shows one compact project/folder label, one activity orb, quiet risk icons when needed, and the session note when set. The row's `...` action menu covers rename, session note editing, Today pinning, Mark Unread, duplicate, detach, and kill.

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

Archived session search, inspection, relaunch, and deletion. Includes:

- a Session Restore callout at the top whenever interrupted sessions exist (`Open Session Restore (N interrupted · M older)`)
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

### Session Restore sheet

- `macos/Sources/HolyGhostty/Restore/HolyRestoreSheet.swift`

Per-shutdown restore groups with recency washes, per-row states, the candidate picker, and per-shutdown restore actions. See section 9A.

### Inbox panel

- `macos/Sources/HolyGhostty/Inbox/HolyInboxPanelView.swift`

The Human Inbox pane: brief answer line, Needs-me drawer, and the Library sections (GitHub attention, alerts, manna triage). See section 9B.

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

A dormant Diff implementation is intentionally preserved for a future agent/worktree comparison mode. It is not part of the current Level 1 navigation.

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
├── Inbox/                  # Human Inbox engine, sources, brief feed, panel view
├── Persistence/            # JSON persistence, DB persistence, retention policy, coders
├── Profiles/               # Launch profiles and default New target persistence
├── Remote/                 # Remote host registry, import, tmux discovery
├── Restore/                # Crash restore: engine, groups, assignment, resolve client, sheet
├── Session/                # Live session model
├── Store/                  # In-memory state struct
├── Supervisor/             # Lifecycle orchestration, migration, workspace repository
├── Tasks/                  # External task models and repository
├── Telemetry/              # Runtime telemetry parser
├── Templates/              # Built-in and custom template catalog
├── Tmux/                   # tmux models, launch command builder, lifecycle service
├── Workspace/              # SwiftUI views: roster, pane layouts, detail, inspector, composer, history, task inbox, timeline, budget
└── Worktree/               # Worktree creation, validation, recovery, cleanup
```
