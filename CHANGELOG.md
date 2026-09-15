# Changelog

All notable Holy Ghostty changes are recorded in this file.

## Unreleased

The workspace brings live terminals, project boards, and conversation archives onto one native surface, with shared session identity and host-owned attention state.

<!-- Headline option: One ledger, two faces: the terminal became the whole surface. -->

### Added

- Native Board mode fills the terminal area with an estate strip, work ledger,
  asks, peer activity, claims, needs, and board health. It reads Manna's `state`
  and `estate` contracts through `agent-do` on the selected local or SSH host.
- Board actions run the corresponding CLI verbs after confirmation. The search
  bar filters while typing and answers board questions on Enter, with clickable
  item citations and the selected model shown beside the answer.
- `Claim & build` starts a confirmed Claude or Codex worker in the board's
  repository. The worker receives the sealed handoff and instructions to claim
  before editing. Unready, claimed, or unsealed items cannot dispatch.
- Native Archive mode indexes Claude Code, Codex, Droid, Cursor, and OpenCode
  history into its own SQLite database. It includes parent and child sessions,
  transcripts, tags, notes, generated titles, keyword and semantic search, and
  saved research chats with archive tools.
- Federated Archive browsing combines local history with indexed history from
  configured SSH hosts. Rows retain host identity, cache age, and read failures.
  Supported conversations resume through the owning host's managed roster.
- Harness conversation identity persists independently of lifecycle state and
  joins restore records to the provider conversation. Claude and Codex hooks
  capture identity at the source; explicit launch runtimes govern roster groups.
- Seen acknowledgements, finished events, and user-prompt recency are shared on
  the session's tmux host. A host-side SQLite journal restores missing registers
  after reboot without replacing live values. Mark Unread propagates to other
  viewers; questions and permissions remain until resolved.
- The SSH transport manager shares two interactive masters and one control
  master per destination. Admission queues bound surface and control work,
  reserve lifecycle capacity, and limit concurrent discovery.
- Claude Usage Guard reads account and per-session windows, reset times, burn
  rates, and projected caps. Its default tiers notify at 75%, deny new worker
  spawns at 90%, and request checkpoint-and-pause at 95% or an imminent cap.
  Manual wrap-up, account changes, stale readings, and HTTP 429 backoff have
  explicit handling. Hooks continue refreshing while the app is closed.
- Codex usage readings share the tmux status bar through `codex app-server`
  rate-limit and usage calls. They include reported per-model limits and banked
  reset credits, with rollout snapshots as last-known fallback. Codex readings
  do not activate Claude's hook guard.
- Optional host administration scripts install an SSH session-capacity setting
  and collect kernel-zone samples with boot identity and process counts.
- Manna IDs render in a configurable highlight color in the terminal render
  pass (`holy-manna-highlight`, `holy-manna-highlight-color`, default manna
  gold `#FFB86C`). Command-click opens the item in Board mode, resolved
  estate-wide with the session's own board preferred; dispatch keeps its
  confirmation sheet.
- Holding Command over the roster turns each session indicator into an
  immediate kill control; Command-Delete kills the selected session. Kills
  route through the transport-aware path and report failures inline.

### Changed

- Board and Archive replace the terminal area while preserving the session
  roster. Both use full-width ledgers, resizable columns, and compact detail
  navigation when the window narrows.
- Board snapshots appear from cache while refreshing. Content-keyed digests and
  summaries prewarm in the background and retain their source fields.
- Crash restore resolves through the native Archive in process. Captured
  conversation IDs take precedence; fallback candidates receive unique
  assignments across the restore group, with a picker for ambiguous matches.
- The right dock contains GitHub attention only. All repositories is the default
  tab; the project tab follows the selected session's owned repository.
  Notifications retain their separate SQLite delivery history.
- The roster offers Classic, Triage, and Focus sorting. Archive, Board, and Inbox
  sit below session actions; pane controls remain in the footer.
- The database removes the external index compatibility views. Archive ingest
  and embedding writes use a separate database and bounded writer transactions.
- The Board topbar keeps the terminal crumb, host tag, and status labels
  visible at every window width.

### Fixed

- Clear detaches sessions without dereferencing freed terminal surfaces or
  closing the workspace through stale callbacks.
- Codex identity survives later lifecycle events and remains available to
  reboot recovery. Read and prompt ages reconstruct from the owning host.
- Agent-state conflicts recover when valid events arrive. Lost finish signals
  recover from the independent finish register, and process evidence stops stale
  working indicators.
- Ledger divider drags resize the adjacent columns and preserve the dropped
  position. Narrow windows retain reachable controls and detail views.
- Archive project labels use provider working-directory metadata with explicit
  fallbacks. Ingest staging keeps partial writes out of visible sessions and
  yields between batches so indexing does not monopolize the workspace writer.
- Restored window frames stay on the visible display and resist unintended
  collapse to the minimum size.
- SSH control paths fit the Unix socket limit and retain a full host hash.
  Bounded discovery returns after inherited pipes outlive their parent process.
  Failures distinguish channel saturation, authentication, connection, and
  process-launch errors.
- Shared executable discovery waits for concurrent callers during Board startup.
- Usage labels are sanitized before tmux format expansion. Percent signs survive
  status formatting, account changes discard foreign snapshots, and installed
  Holy-owned helpers refresh when their generated content changes.
- Read-only database connections survive WAL checkpoints, restoring board
  digests and every other reader after the companion files are removed.
- Modifier key releases skip panes outside the window's content area.
- Dispatched workers exec the runtime as the pane process, so discovery,
  grouping, and kill targeting see the agent rather than a wrapper shell.

## 0.50 (2026-08-22)

A shutdown is no longer a loss, and attention has a home: whenever the tmux
server goes away — a reboot, a deliberate kill, a crash — Session Restore
rebuilds every session with its exact conversation, and a new right-hand
Inbox panel shows what waits on the human — nothing else.

### Added

- Session Restore: cold boot shows a banner counting interrupted sessions;
  Restore All/Selected recreates each one in its own directory running the
  exact original conversation (`claude --resume`, `codex resume`,
  `opencode --session`), resolved by joining the session archive index by
  directory and time. Ambiguous matches open a candidate picker with
  first-prompt previews; missing history honestly demotes to a labeled
  shell-only recreate. Never `--continue`, never a guess.
- Verified tmux lifecycle primitive: liveness probe, kill, and
  poll-until-absent against the exact persisted socket and session name,
  inventory-proven and idempotent. Kill failures now surface stage, socket,
  target, and stderr instead of an opaque Cocoa error.
- The human inbox (⌘P, View ▸ Inbox Panel): GitHub PRs needing review or
  maintainer attention (bot PRs collapsed to per-repo digests), in-app
  alerts with acknowledge, and the focused project's incomplete Manna board.
  Human decisions stay prominent; in-progress, ready, blocked, and track
  inventory stays compact and out of the unread badge. Rows clear themselves
  when reality changes.
- Every shutdown wears its own color: Session Restore groups interrupted
  sessions by boot batch with recency-ranked washes (blue mist newest, then
  rose, then mauve, fading to grey), each group carrying a relative
  timestamp, an honest count, and a one-click "Restore this shutdown"
  action. Sessions interrupted by more than one shutdown show a lineage
  tick in the other batch's hue.
- Restore rows carry their session notes, sub-agent helper shells
  (machine-titled `…-shell-XXXXXXXX`) group under a collapsed disclosure
  that never preselects and never inflates the banner count, and a
  confirmation-gated "Clear older interruptions…" empties the archive of
  superseded shutdowns. Close buttons are an X, as close buttons are.

### Fixed

- Restored sessions can no longer receive another session's conversation:
  all rows resolve through one batched index call and a globally unique
  assignment — each conversation can be claimed by exactly one row, near
  ties open the candidate picker instead of guessing, and the post-restore
  "identity confirmed" ceremony is gone because launching
  `claude --resume <exact id>` as an argument array is the identity
  guarantee. The resolver stampede that produced 90-second timeouts is
  gone with it: reindexing is scoped to the directories a restore actually
  asks about.
- Codex sessions restore again when codex lives in a version manager:
  executable discovery asks the tmux server's own PATH first, then searches
  every nvm version (plus volta, bun, pyenv, and the usual directories),
  and pins the absolute path into the launch command whenever the runtime's
  PATH could not have resolved the bare name — so a passed preflight can
  never precede a "command not found."
- Two sessions sharing one checkout no longer read as file contention: the
  panel counts "N uncommitted files in the shared checkout" without
  attributing them to anyone, while sessions in genuinely separate
  worktrees keep real overlap detection unchanged.

- Manna no longer hides ordinary project work or waits on a repository-wide
  reconcile audit before showing it. The pane reads the focused board's fast
  list contract, exposes every incomplete state in bounded sections, and
  drains large command output while the child is running.
- The human inbox accepts GitHub maintainer-sweep rows whose comment count is
  unknown, promotes changes requested on your PRs to direct attention, and
  resolves the focused Manna board from cwd immediately while git ownership is
  still loading instead of letting the local section vanish and return later.
- Session Restore now survives first human contact: the sheet scopes to the
  most recent boot batch (a durable per-sweep batch id; legacy rows cluster
  by archive time) with older interruptions collapsed, unselected, and
  never counted in the banner. Small fresh batches open fully selected,
  large ones open with nothing selected, and Select All / Select None act
  on the visible rows. A durable View ▸ Restore Sessions… menu item and a
  prominent Session History callout join the banner as entry points, the
  banner gained warning prominence with an honest per-reboot count and
  relative timestamp, and history rows now label interrupted and
  needs-repair states.
- Manna issue ids are validated against manna's own alphabet before they can
  reach a spawned shell, closing a command-injection path from hostile
  `.manna` boards in cloned repositories.

## 0.44 (2026-07-21)

The roster now tells the truth at a glance: every indicator is driven by
structured lifecycle facts from the agent harnesses, blue means you actually
used the session, and spinners cannot outlive the work they describe.

### Added

- Authoritative six-state roster vocabulary (spinner, question mark, unread
  green, used-today blue, inactive grey, sleeping Z) driven by exact-owned
  lifecycle hooks for Claude Code, Codex, and OpenCode over a metadata-only
  wire contract.
- A watcher eye: a static mark on any session armed with a scheduled `/loop`
  wakeup, showing the next fire time on hover and clearing itself when the
  loop stops or its session dies.
- Process evidence for working claims: a live agent visibly producing output
  keeps its spinner through long tool-less stretches, and a killed agent
  stops spinning within a second.
- Deterministic agent notifications (replied, needs you, failed) with
  restart-safe deduplication and focused-visibility acknowledgement.
- A `Mark Unread` roster action that restores the green dot for a reply worth
  revisiting.

### Changed

- The used-today blue dot is earned only by submitting a prompt; agent
  activity, restores, and app launches can no longer fake recency. Existing
  recency stamps are cleared once on upgrade, so blue grows back from real
  use within a day.
- Sleeping Z now requires every axis quiet for 48 hours; reading a fresh
  reply in an old session lands on plain grey instead of jumping to sleeping.
- Claude turn-endings publish `finished` immediately from the Stop hook, so a
  watched session's spinner clears the moment its turn ends.
- Roster indicators repaint within about a second of a lifecycle event
  instead of waiting for the next minute tick.
- The working spinner animates on every roster row, not only the selected
  one, at a fixed low frame rate.
- A Codex notifier owned by another tool that chains Holy's adapter (the
  Codex Computer Use pattern) is recognized as a delegation and no longer
  blocks enabling the indicators.

### Removed

- Screen-derived stalled/looping notifications; stall handling is moving to
  working-lease evidence.

## 0.40 (2026-05-14)

0.40 turns Holy Ghostty into a cleaner tmux workspace for local and SSH agent sessions, with more terminal space, clearer controls, smarter session status, and more stable local installs.

### Added

- Launch profiles now drive `New`, with generated `Local Mac` and SSH-host profiles plus a saved default target.
- Holy-owned pane layouts now persist across launches: single, split right, split down, and quad.
- Session rows now show pane labels when a session is visible in a split layout.
- Agent status now has separate states for active work, new replies, planning questions, approval prompts, stale replies, and agent swarms.
- Agent swarms now get their own animated roster indicator and bottom status state.
- New-reply indicators now behave like unread mail: opening a session and keeping it visible for about three seconds marks the current reply as seen.
- The local installer now re-signs `/Applications/Holy Ghostty.app` with a stable available signing identity when possible, so macOS privacy permissions are less likely to duplicate after rebuilds.

### Changed

- Session creation, clear-roster, and SSH controls now live in the left tmux roster.
- First-time profile setup defaults `New` to the only configured SSH host when exactly one exists; otherwise it defaults to `Local Mac`.
- SSH tmux sessions can now be reattached from the roster, either per session or all at once, without killing the remote tmux session.
- The old `Grid` / `Diff` / `Focus` controls are removed from the live workspace chrome; Diff code is preserved dormant for a later explicit comparison mode.
- Standard workspace layout controls now live at the bottom of the left rail: single, split right, split down, and quad.
- The selected session header is removed from the terminal pane so the live terminal gets the top edge.
- The standard workspace now removes the empty native toolbar band; the left rail reserves traffic-light clearance while the terminal surface starts at the top edge.
- Holy defaults now add top terminal padding so the first prompt row clears macOS window controls without adding a separate app bar.
- The bundled Holy background image now stretches to the live terminal surface size.
- Roster rows now keep risk and worktree details out of the left list unless they need attention in the selected-session status area.
- Per-session menus now separate `Detach From Roster` from `Kill from Roster`; killing a tmux-backed session attempts to stop tmux and always removes the roster attachment.
- Public docs now describe the Level 1 pane layout model instead of the old toolbar display-mode model.
- Holy Ghostty app marketing version is `0.40`.

### Fixed

- Local tmux startup discovery no longer probes git metadata or checks inferred project directories on disk, preventing automatic restore from triggering repeated macOS Documents permission prompts.
- Local terminal launches now strip inherited direnv active-session state so shells opened above the launch repo do not print a stale `direnv: unloading` message.
- Active tmux session discovery now prefers live pane paths and pane commands over stale launch metadata, so sessions move from `Custom_Coding`/`Shell` to the actual project and agent group after Claude/Codex starts.
- The roster working spinner now requires fresh working evidence instead of stale visible words like `running` or `thinking`.
- Live agent-working signals now take precedence over stale error text in the roster activity indicator.
- Planning-question status clears once the agent moves back into real work instead of staying stuck on the question icon.
- The roster no longer briefly shows a work spinner just because the user clicked into a session.
- Reattaching SSH tmux sessions now detaches existing tmux clients first, preventing stale tiny clients from shrinking the visible session viewport.
- Restored Holy sessions now seed their hidden terminal surfaces with a wide fallback size so offscreen tmux clients do not start at the default 49-column viewport.

### Removed

- The stale public roadmap document was moved out of the release docs surface; Diff remains preserved as dormant code for a future explicit comparison mode.

## 0.30 (2026-05-12)

### Added

- `Command-W` detaches the selected Holy session without closing the Holy Ghostty window.
- `Option-Q` kills the selected tmux session when the selected session has a tmux target.
- `Clear` toolbar action detaches all active sessions from the workspace.
- Optional inspector toggle so the terminal gets the full default workspace width.

### Changed

- Left roster now groups sessions by runtime and sorts each group by project/folder context.
- Roster rows now use one compact project/folder label, one activity orb, and quiet risk icons.
- Working sessions use a multicolor spinner; waiting sessions age through freshness colors.
- Public docs now describe the current two-region default workspace and session cleanup shortcuts.
- Holy Ghostty app marketing version is `0.30`.

### Fixed

- Local tmux discovery now infers project folders from pane, window, and session metadata when tmux reports a shared parent directory, so attached sessions keep project/folder roster titles after restore.
- Holy-embedded terminal scroll views clamp horizontal scroll origin during vertical scrollback.

### Removed

- Internal terminal-scroll handoff note and stale planning docs from the public docs surface.

## 0.25 (2026-04-24)

### Added

- tmux-backed local and SSH session launches as the default Holy session substrate
- Holy automation entrypoints via `holy-ghostty://spawn`, AppleScript `spawn`, and `scripts/holy-spawn-session.sh`
- persistent remote host registry with schema migration `6`
- host import from `~/.ssh/config` and Tailscale
- remote tmux discovery and attach inside the `Remote Hosts` sheet
- right-rail **Verification** section backed by OSC 133 command telemetry (last outcome, duration, elapsed since)
- right-rail **Actions** row: Copy handoff, Copy diff, Duplicate, Archive
- right-rail **Risk** summary: git changes bucketed by consequence (project / deps / CI / scripts / config / tests / docs / source), full file list behind a disclosure
- external-peer intelligence in **Coordination** via `agent-do coord peers` subprocess probe
- opinionated ASCII angel-ghost background watermark at 4% opacity, rendered by Ghostty's `background-image` config; extracted from an asset catalog data set into `~/Library/Application Support/Holy Ghostty/` on launch
- README app screenshot and release version callout

### Changed

- remote Holy sessions now enrich inspector/git state over SSH instead of staying local-only
- public README and Holy docs now describe the current tmux/remote product shape instead of the older v0.2-only surface
- right rail redesigned against a Prime Rule: only show what the terminal itself cannot. **Output** section removed (terminal is output); **Launch** collapsed into a `Details` disclosure; **Mission** gated behind a linked task; **Budget** gated behind configured budget or observed usage.
- left-rail session rows use a compact two-line label with manual persisted ordering
- left-rail width defaults wider while remaining resizable below the default
- session action menu hides the `.borderlessButton` disclosure chevron for a clean ellipsis affordance
- `+` creates a new local shell immediately instead of opening the full launch menu
- app content no longer acts as a window-drag region; only empty top-bar space drags the window
- focus, grid, and compare display modes clamp to available window geometry
- duplicate and archive actions target the selected session consistently
- Holy defaults config (`background-image`, fit, position, opacity) loads before user config so `~/.config/ghostty/config` always wins on overrides
- Holy Ghostty app marketing version is `0.25`

### Fixed

- remote tmux sessions no longer collapse into a single ambiguous Studio surface when selecting local, remote, or attach sessions
- session labels preserve remote project directory when it can be discovered from tmux panes or runtime metadata
- runtime status clears stale `Running command` state when no current structured activity signal exists
- telemetry parser filters tmux chrome, status bars, separators, and prompt/footer output before inferring activity
- fresh installs no longer import stale local database state into new workspaces

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
