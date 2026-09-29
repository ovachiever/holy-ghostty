# Holy Ghostty Engineering Spec

Holy Ghostty embeds Ghostty terminal surfaces in a native macOS workspace.
The Swift layer owns session lifecycle, Board, Archive, remote transport,
persistence, and attention state. Ghostty owns terminal emulation and rendering.

## Workspace Composition

`App/HolyWorkspaceWindowController.swift` owns the window and workspace store.
`Workspace/HolyWorkspaceView.swift` composes the roster, terminal area, and
GitHub dock. Paths in this spec are relative to `macos/Sources/HolyGhostty/`
unless stated otherwise.

The terminal area displays live panes, Board, or Archive. Switching to Board or
Archive preserves the roster and session attachments. Single, Split Right,
Split Down, and Quad arrange complete Holy sessions. Pane layout and roster
width persist. Restored frames are constrained to visible screens.

`Workspace/HolySessionRosterView.swift` exposes Classic, Triage, and Focus sorts.
Classic groups by runtime; Triage groups by attention; Focus leads with Today
pins. The actions row contains New, Clear, Sync, and Hosts. Archive, Board, and
Inbox occupy the next row. Pane controls remain in the footer.

`Board/HolyLedgerColumns.swift` provides shared ledger geometry. Column drags
modify the adjacent pair and preserve the drop result. Width constraints fold
optional columns and use compact detail navigation when space is limited.

## Sessions and Launch

`Domain/HolyModels.swift` defines runtime, transport, tmux identity, ownership,
launch specifications, templates, archives, and telemetry. `Session/HolySession.swift`
owns the live surface and record. A persisted non-shell runtime controls roster
grouping; inference supplements shell sessions that enter a provider runtime.

`Supervisor/HolySessionSupervisor.swift` owns creation, restoration, archival,
and persistence. `Workspace/HolyWorkspaceStore.swift` coordinates selection,
profiles, hosts, templates, tasks, and derived presentation.

`Tmux/HolyTmuxCommandBuilder.swift` realizes the launch specification before
persistence. Local sessions attach to a local tmux server. SSH sessions attach
to the selected host and socket. Session options retain Holy launch metadata
for later discovery. Closing a viewer attachment leaves tmux running.

`Profiles/HolyLaunchProfileRepository.swift` stores generated local and SSH
profiles and the default New target. `Templates/HolySessionTemplateCatalog.swift`
provides reusable runtime and worktree launch settings.

`Worktree/HolyWorktreeManager.swift` supports direct directories, existing
worktrees, and managed worktrees. Git snapshots include repository root, common
git directory, branch, upstream counts, status counts, and changed paths.
Coordination distinguishes a shared checkout from changed-file overlap across
separate worktrees. The same-checkout display reports shared uncommitted files.

Session creation also accepts the `holy-ghostty://spawn` URL scheme, AppleScript
`spawn`, and `scripts/holy-spawn-session.sh`. External task records attach local
launch context and canonical URLs to sessions.

Clear detaches roster sessions through the supervisor. Surface callbacks resolve
live ownership before touching the terminal surface. Freed surfaces and stale
callbacks cannot drive workspace-close behavior.

## Harness Identity and Attention

`AgentState/HolyAgentStateBridge.swift` generates provider hooks and metadata
helpers. `HolyAgentStateBridgeInstaller.swift` merges exact-owned handlers.
Claude Code and Codex publish lifecycle hooks; Codex also uses a committed-turn
notifier; OpenCode uses a plugin. Installation requires the app menu action.
Codex handler trust is approved through `/hooks`.

The wire format is bounded metadata:

```text
v1|source|lifecycle|epoch-ms|event-token|session-id|reason-code
```

`HolyAgentStateEnvelope.swift` validates identity, source, lifecycle, and ordering.
A malformed or conflicting register does not become an inferred event.
New valid events can recover a previous conflict.

| Host register | Stored fact |
|---|---|
| @holy_agent_state_v1 | Latest lifecycle event. |
| @holy_agent_last_finished_v1 | Latest independent finish event. |
| @holy_agent_last_used_v1 | Latest committed user prompt. |
| @holy_harness_identity_v1 | Provider conversation identity independent of lifecycle writes. |
| @holy_seen_v1 | Shared acknowledgement or Mark Unread tombstone. |
| @holy_watcher_v1 | Scheduled wakeup metadata. |

Harness identity also persists on the session record and launch specification.
Templates and duplicate launches do not inherit a conversation resume identity.
Later lifecycle events without an ID do not erase the captured identity.

`HolyTmuxAgentStateMonitor` reads grouped pane metadata and process evidence for
each tmux endpoint. The policy uses committed working events, leases, process
liveness, and output activity. Process evidence can invalidate or extend a
working claim; it cannot create a working event. The independent finish register
recovers a finish overwritten by another lifecycle event.

`HolySessionIndicatorPolicy` derives working, needs-user, unread, used-today,
inactive, and sleeping states. User-prompt recency is 24 hours. The inactive
boundary uses the latest activity axis within 48 hours. Questions and permissions
remain until resolved. Terminal-text heuristics do not determine these states.

A focused visible surface acknowledges the newest producer timestamp it has
seen. Background selection does not acknowledge. Mark Unread writes an explicit
shared tombstone. The local SQLite attention row is a cache of host truth.
Notifications use persisted event watermarks and deterministic request identities.

### Host Journal

`AgentState/HolyHostStateMirror.swift` runs the same Python program for hooks,
acknowledgements, launch, and discovery, including over SSH. It stores lifecycle,
finish, prompt, harness identity, and seen registers in `host_indicator_state`
on the producer host. Watcher scheduling is not included in this journal.

The key contains socket path, session name, pane position, and option name.
Seen state uses a session-wide key. Journal updates compare producer timestamps
under a SQLite writer transaction. Restore fills missing tmux registers through
an atomic test-and-set command queue. Existing live values retain authority.

The journal survives roster Clear and tmux server death. Remote state is
journaled on the remote host; a viewer database does not become its authority.
Python 3 with SQLite support is required on the producer host.

## Board

`Board/HolyMannaBoardClient.swift` invokes the canonical host-local commands:

```text
agent-do manna state --json
agent-do manna estate --json
```

Local commands execute in the board root. Remote commands use the managed SSH
control transport. State reads have a 90-second timeout; estate reads have a
60-second timeout. Executable discovery is shared across concurrent callers.
Refusals and invalid JSON remain visible failures.

`HolyMannaBoardStore.swift` owns context, cached snapshots, refreshes, selection,
questions, and pending mutations. `HolyMannaBoardPresentation` derives ledger
rows, asks, peer sections, and estate summaries from the payload.
`HolyMannaBoardView` renders the estate strip, project ledger, asks, coordination,
health, and detail controls.

### Actions

`HolyMannaBoardMutation` maps confirmed UI actions to CLI argument arrays:

| Action | CLI operation |
|---|---|
| Claim | manna claim |
| Done | manna done |
| Release | manna abandon |
| Close landed item | manna claim, then manna done |
| Promote dream | manna update --type item |
| Delete dream | manna delete |
| Remove blocker | manna unblock |
| Sync handoffs | manna sync |
| Safe repair | manna reconcile --fix --json |

Arguments include the selected item or blocker identity. Confirmation precedes
execution. Actor identity is supplied through `HolyMannaActorIdentity`.
Holy does not mutate board files directly.

### Questions and Presentation Cache

`HolyMannaBoardAsk.swift` serializes visible item records, including completed
items, into the question context. Track records are excluded. JSON preserves
row boundaries. Answers expose the model and clickable known item IDs; unknown
cited IDs are replaced with an omission marker.

Question caches bind host, board root, model, normalized question, and content
hash. Input above 200,000 UTF-8 bytes is refused without omitting rows. The store
bounds answer time and discards answers whose board context changes.

`HolyMannaBoardDigest.swift` prewarms digests and summaries by content hash.
Cached text appears while refresh runs. Source titles and descriptions remain
available. The fast route uses a headless Claude CLI; configured GPT/OpenAI
models use the OpenAI Responses client. Deep model selection persists in
`holy.intelligence.deep.model`. The Board default is `opus`.
Claude routes require CLI authentication; OpenAI routes require `OPENAI_API_KEY`
in the app environment. Presentation warm-up observes the Claude usage guard.

### Worker Dispatch

`HolyMannaBoardWorker.swift` accepts ready, open items with an available sealed
handoff. It rejects dreams, existing claims, absent roots, and missing handoff
bindings. Confirmation names the runtime, model, repository, and item.

The launch specification creates a Claude or Codex tmux worker on the board's
host. The startup brief is one quoted argument. It instructs the worker to claim
first, verify the handoff binding, establish coordination, and obey repository
instructions. Dispatch does not claim on the worker's behalf. CLI claim refusal
must stop the worker.

## Archive

`Archive/HolyArchiveProviders.swift` implements Claude Code, Codex, Droid,
Cursor, and OpenCode readers. `HolyArchiveProviderRegistry` discovers available
sources. Parsers retain provider identity, directory metadata, role, message
order, timestamps, and parent-child relationships. Provider history is read as
source data.

`HolyArchiveModeStore` loads indexed results immediately. Incremental indexing
starts by default when Archive prepares. `holy.archive.autoIndex` controls this
default; interrupted stored progress can resume. The UI also exposes incremental
update, full reindex, and embedding generation.

### Database and Writer

`HolyArchiveDatabase.swift` owns `holy-archive.sqlite3`, schema version 2.
The archive stores sessions, messages, chunks, full-text search, embeddings,
annotations, research chats, and ingest progress. The workspace database remains
`holy-ghostty.sqlite3`, schema version 13.

Archive migration copies prior archive tables into the separate database in
bounded batches. It records progress and verifies foreign-key consistency before
reporting completion. The archive rejects newer unsupported schema versions.

`HolyArchiveIndexing.swift` stages messages and chunks before publishing a session
replacement. Production writer batches contain up to 250 rows. Pacing targets
600 rows per second in the foreground and 6,000 in the background. Archive
connections use a two-second busy timeout, a 4,096-page automatic WAL checkpoint,
and a 64 MiB journal-size limit. These are writer settings, not a cap on the
overall archive size.

Archive writes use the archive database. Workspace saves do not queue behind
archive ingestion on the workspace writer. Cancellation and partial ingest leave
published session data readable.

### Search and Research

`HolyArchiveSearch.swift` combines full-text and semantic matches. Filters accept
harness, project, after, before, and tags. Child matches propagate to parent rows.
Semantic unavailability leaves keyword results with a visible explanation.

`HolyArchiveEmbeddings.swift` supports OpenAI, Voyage, and Cohere. The selected
provider requires its API key in the app environment. Vectors are stored with
model identity. OpenAI inputs are bounded before request batching.

`HolyArchiveResearch.swift` runs saved research conversations through the OpenAI
Responses API. Archive tools search and retrieve supporting history. Model,
reasoning effort, chat messages, and tool calls persist. Research requires
`OPENAI_API_KEY`. Retrieved history is sent to the selected research model.

`HolyArchiveModeView.swift` presents parent and child ledgers, transcript find,
annotations, generated titles, resume actions, and research chat. Droid and
Cursor support browsing but have no Holy launch runtime.

### Federation

`HolyArchiveRemoteQuery.swift` sends bounded JSON requests through the managed
SSH control lane to Python 3. The host opens its existing archive with SQLite
`mode=ro` and `query_only`. It rejects unsupported newer schemas. Remote reads
do not crawl provider histories, migrate storage, or create an archive database.

`HolyArchiveFederation.swift` merges host-qualified results. Cache entries include
fetch time, source host, stale state, and error details. The freshness interval
is five minutes. Remote keyword and compatible-vector results participate in
search. Remote transcript and annotation reads retain source identity.

Remote tags, notes, and titles are read-only from the viewer.
`HolyArchiveResumeLaunchSpec` constructs provider-specific commands from the
runtime and provider ID, retaining the source SSH destination and tmux socket.
It does not execute a remote row's supplied resume-command string.

## Crash Restore

`Workspace/HolyWorkspaceStore.swift` injects `HolyArchiveRestoreResolver` into
`Restore/HolyRestoreEngine.swift`. Production restore resolves in process through
the same native archive used for browsing.

Captured identity takes precedence. Fallback batch queries group provider and
project scopes and refresh stale source files. Single resolution is lookup-only.
Reindex claims limit repeated refreshes. `HolyRestoreAssignment` allocates
candidates uniquely across rows and detects close competing matches.

`HolyRestorePreflight` checks host support, identity conflicts, tmux liveness,
directory and executable prerequisites, and resolver outcomes. Unknown liveness
is not absence. A live identity can be adopted. Ambiguous matches require a
picker. Missing history offers labeled shell recreation. Resolver failures
remain retryable.

`HolyRestoreCommandBuilder` creates provider-specific resume arguments.
`HolyRestoreExecutableSearch` checks the runtime environment and supported
fallback locations. The restore sheet groups sessions by shutdown, shows notes,
and supports exact row and group restores.

## SSH Transport and Convergence

`Remote/HolySSHTransportManager.swift` owns two interactive masters and one
control master per destination. Interactive sessions distribute by session hash.
Control commands share the reserved lane. Connections use `ControlPersist=600`.
A private short control directory and bounded socket paths avoid Unix path-size
failures. Host keys retain the full SHA-256 digest.

`HolySSHAdmissionController.swift` queues channel work. Defaults are 100 surface
channels per host, eight control operations per host, two reserved lifecycle
slots, four concurrent discoveries globally, and one discovery per host.
`holy.ssh.surfaceChannelsPerHost` configures the surface budget. Server SSH
limits still apply independently of the client budget.

`HolySSHFailureDiagnosis.swift` distinguishes authentication, connection,
channel-capacity, and process-launch failures. Discovery and lifecycle execution
have bounded deadlines, including output pipes inherited by child processes.
Failure details preserve the stage and underlying error.

`Workspace/HolyConvergePlanner.swift` compares the roster with complete discovery.
It adopts matching archived sessions, repairs dead attachments, and archives
vanished sessions only where discovery proves namespace coverage. Unknown
sessions remain available in Hosts for explicit attachment. Incomplete inventory
removes archive authority for that scope.

Manual Sync, wake, and pane-death recovery use the same convergence path.
Automatic repair uses bounded backoff. A device-local keep-awake preference holds
an idle-system-sleep assertion while remote sessions are attached.

`Tmux/HolyTmuxLifecycleService.swift` verifies exact socket and session identity,
kills the proven target, and polls for absence. Ambiguous identity and unknown
liveness stop the action. Failures report the stage, target, and stderr.

## GitHub Dock and Notifications

`Inbox/HolyInboxEngine.swift` registers the GitHub source. The dock has All and
project tabs, with All selected by default. Project identity and local action
directory derive from the selected session's ownership repository root.

`HolyGitHubInboxSource.swift` reads `agent-do gh inbox --json`. The engine polls
every 75 seconds while visible and five minutes while hidden, plus open,
foreground, and manual refresh. Refreshes serialize and coalesce. Source
conditions determine row removal. Bot rows group into repository digests.
Loaded commands open as visible, unsubmitted shell input.

Native notifications are delivered by the alert coordinator and authoritative
agent-state gate. `HolyInboxAlertStore` retains delivery history in SQLite.
The GitHub dock displays GitHub attention only.

## Persistence and Telemetry

`Database/HolyDatabase.swift` wraps system SQLite with WAL, foreign keys,
transactions, and a busy timeout. `HolyDatabaseMigrator.swift` advances workspace
schema versions. `HolyDatabasePaths.swift` defines the bundle-specific container:

```text
~/Library/Application Support/<bundle-id>/HolyGhostty/
```

Production uses `org.holyghostty.app`; Debug uses `org.holyghostty.app.debug`.
The directory contains workspace and archive databases and the JSON workspace
snapshot. Workspace repositories read SQLite first and retain JSON migration
and dual-write support.

`Persistence/HolyWorkspaceDatabasePersistence.swift` writes session state,
profiles, templates, events, and latest telemetry. Retention hides removed rows
before bounded cleanup. Unchanged git snapshots reuse their existing row.
`Events/HolySessionEventRepository.swift` assigns monotonic per-session event
sequences. Notification watermarks persist separately from presentation state.

`Telemetry/HolySessionRuntimeTelemetryParser.swift` derives phase, activity,
commands, files, and stall signals from terminal previews and structured surface
signals. `Budget/HolySessionBudgetParser.swift` extracts displayed usage figures.
These are heuristic observations; provider usage snapshots and lifecycle hooks
have separate authority.

## Usage Guard

`Claude/HolyClaudeUsage.swift` defines the evaluator. `HolyClaudeUsageBridge.swift`
generates the probe and hooks. `HolyClaudeUsageMonitor.swift` supervises polling.
`Workspace/HolyWorkspaceStore+ClaudeUsage.swift` publishes reports and notifications.

The probe reads Claude credentials through a captured keychain pipe and sends
them as a request header to the usage endpoint. It stores account-scoped
snapshots and history under `~/Library/Application Support/Holy Ghostty/usage/`.
Per-session five-hour and weekly readings override their machine-wide equivalents.
Account changes invalidate foreign snapshots. HTTP 429 causes backoff; forced
Refresh bypasses it. Failed probes retain stale-marked readings.

Default thresholds are notice at 75%, restraint at 90%, wrap-up at 95%, and
capped at 100%. Projected cap within 20 minutes triggers wrap-up. A qualifying
40-minute projection or provider severity triggers notice. At restraint,
PreToolUse denies Agent, Task, and Workflow while existing work continues.
Wrap-up adds checkpoint-and-pause instructions. UserPromptSubmit receives context
only. Python and Swift evaluators share fixture tests.

Codex data comes from `codex app-server` account rate-limit and usage methods.
Rollout files supply last-known fallback data. Codex buckets never enter Claude's
hook enforcement. Holy installs no Codex usage-guard hook.

The probe publishes the machine-wide tmux segment as `@holy_usage_v1` beside
the clock. API-derived labels are sanitized before format expansion, and literal
percent signs are escaped. The roster menu opens the usage details sheet.
Manual wrap-up expires after one lead window or an account change.

## Build and Validation

The core build requires Zig 0.15.2. The macOS app requires Xcode 26 or newer and
the Metal Toolchain component. The supported commands are:

```bash
scripts/build-holy-ghostty-core.sh build
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration ReleaseLocal SYMROOT=build build
scripts/test-holy-ghostty-build-contract.sh
```

The core wrapper verifies source and payload fingerprints for a ReleaseFast
framework and generated resources. The installer uses ReleaseLocal for the
Swift app and validates optimization settings, executable provenance, signing,
and registration before completing replacement. The prior app remains available
for rollback through final verification.

The installer does not launch the app. Open the installed bundle by its full
path so LaunchServices cannot select another registered copy:

```bash
open /Applications/Holy\ Ghostty.app
```

The **Build Holy macOS core** workflow produces an importable verified archive.
`scripts/build-holy-ghostty-core.sh import <archive>` checks the current core
inputs and all packaged payload hashes.

`macos/Ghostty.xcodeproj` contains the Ghostty scheme, GhosttyTests, and
GhosttyUITests. Tests are app-hosted. Xcode test execution launches a test app;
build-for-testing only compiles it. Test builds require a separate output root
from the installer's `macos/build`. SwiftLint rules are in `macos/.swiftlint.yml`.

## Host Administration

`scripts/install-holy-studio-guards.sh` is an explicit host administration tool.
It installs `MaxSessions 110` through an SSH configuration include and verifies
the effective value. It preserves hashes of the primary configuration and sealed
SSH launch definition. It does not restart active SSH connections.

`scripts/holy-kernel-zone-watch.sh` samples kernel allocation zones, boot identity,
process counts, and SSH launch counters. Its report isolates the latest boot
and withholds an hourly growth rate until samples span 30 minutes.
`scripts/test-holy-studio-guards.sh` validates the scripts with fixtures.
These tools are separate from application installation.
