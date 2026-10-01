# Holy Ghostty Guide

Holy Ghostty manages live terminals, project boards, and conversation archives
in a native macOS workspace. Sessions run locally or through SSH and tmux.

## Start a Session

Install tmux and the runtime you want to use on the session host. Holy supports
Shell, Claude, Codex, and OpenCode launches.

1. Open `Hosts` to add an SSH host or import SSH config or Tailscale hosts.
2. Select a launch profile from the roster's `…` menu and set the default.
3. Click `New` to start a tmux session from that profile.
4. Use `Hosts` to discover and attach an existing tmux session.

Holy generates a Local Mac profile and profiles for configured SSH hosts.
On first profile creation, a single configured SSH host becomes the default.
With zero or multiple SSH hosts, Local Mac is the default.

Launch settings include runtime, command, directory, repository, environment,
initial input, transport, and tmux socket and session name. Templates preserve
reusable launch settings. Worktree strategies use a direct directory, attach
an existing worktree, or create a managed worktree.

## Navigate the Workspace

The roster stays visible beside Terminal, Board, and Archive. `Archive` and
`Board` occupy the terminal area. Their `‹ terminal` link returns to live panes.

| Control | Action |
|---|---|
| New | Starts a session from the default launch profile. |
| Clear | Detaches all roster sessions and leaves tmux running. |
| Sync | Reconciles known roster and archived sessions with tmux discovery. |
| Hosts | Manages host records and discovers sessions for attachment. |
| Archive | Opens indexed conversation history. |
| Board | Opens the focused Manna board or estate. |
| Inbox | Opens GitHub attention. |

Unknown discovered sessions remain in Hosts for explicit attachment. Sync does
not treat an unreachable host as proof that its sessions are gone.

The footer selects Single, Split Right, Split Down, or Quad. These layouts
arrange whole Holy sessions. Each visible session receives a pane-position
label in the roster. Drag the roster divider to change its width.

The Sort selector offers three arrangements:

- Classic groups sessions by Claude, Codex, OpenCode, and Shell.
- Triage groups sessions by attention state.
- Focus puts sessions pinned to Today first.

Session menus include notes, Today pinning, Mark Unread, duplicate, detach,
and kill. Detach preserves tmux. Kill verifies the target and waits for absence;
an uncertain identity or failed kill remains an error.

| Shortcut | Action |
|---|---|
| Command-N | New session. |
| Command-P | GitHub dock. |
| Command-Shift-R | Remote hosts. |
| Command-W | Detach the selected session. |
| Option-Q | Kill the selected tmux session. |
| Command-Delete | Kill the selected session immediately, no confirmation. |

Holding Command with the pointer over the roster turns each session indicator
into an immediate kill control. Kills report failures inline on the row.

## Board

Board requires [`agent-do`](https://github.com/ovachiever/agent-do) on the selected host and a Manna board in the project.
Its estate view lists available boards. Select a board to inspect its work,
asks, peers, claims, needs, drops, and health. The board context follows the
selected session's repository or working directory unless you choose a board
from the estate.

The ledger shows item state, claimant, track, priority, and age. Select an item
for its description, blockers, handoff, and available actions. Column grips
resize adjacent columns. Narrow windows switch between list and detail.

Claim, done, release, close, promote, delete, unblock, handoff sync, and safe
repair actions show confirmation before invoking the corresponding Manna CLI
command. The board displays command failures and refreshes after completion.

Type in `ask AI · grep · ⌘K` to filter rows. Press Enter to ask about the board.
The answer includes clickable item citations and the model used. The question
uses board data including completed items. A changed board invalidates its
cached answer. Requests that exceed the input bound stop with an explanation.

Choose Claude or Codex and a worker model in the item detail, then click
`[claim & build]`. Confirm the repository, runtime, and handoff. Holy opens a
worker session with instructions to claim first and verify the sealed handoff.
Only ready, open items with an available sealed handoff can dispatch.
The worker's claim result determines ownership.

Manna IDs printed in any terminal pane render in the configured highlight
color (`holy-manna-highlight-color`, default `#FFB86C`; disable with
`holy-manna-highlight = false`). Command-click an ID to open its item in Board
mode. Resolution prefers the session's own board, then a unique estate-wide
match; ambiguous or unknown IDs open board search. Dispatch keeps its
confirmation sheet.

Board digests use the configured fast model and cache by content. Board answers
use the deep model shown in the answer controls. Claude routes require an
available, authenticated Claude CLI. OpenAI routes require `OPENAI_API_KEY`
in the app process environment. Model requests send the supplied board text
to the selected provider.

## Archive

Archive indexes these provider histories:

| Provider | Browse and search | Resume in roster |
|---|---|---|
| Claude Code | Yes | Yes |
| Codex | Yes | Yes |
| Droid | Yes | No |
| Cursor | Yes | No |
| OpenCode | Yes | Yes |

Opening Archive loads indexed sessions and starts an incremental update by
default. The update menu offers `incremental update`, `full reindex`, and
`generate missing embeddings`. Progress and errors appear in the archive.

Select a parent session to inspect its children and conversation details.
Open a transcript to read, find text, and copy the conversation. Local rows
support tags, notes, and generated titles. Project labels use provider directory
metadata. The archive lists the displayed count and total count separately.

### Search

Type words or a natural-language description in the search field. Filters use
this syntax:

```text
harness:claude-code project:my-project after:7d cache invalidation
harness:codex before:2026-01-01 #tag:release
```

Provider filter names are `claude-code`, `codex`, `droid`, `cursor`, and
`opencode`. Date filters accept calendar dates and relative hours, days, weeks,
or months. Search combines full-text matches and available semantic vectors.
Matching child sessions lead back to their parent conversation.

Keyword search needs no model credentials. Semantic search needs an embedding
provider key in the app process environment and indexed embeddings. The provider
setting is `holy.archive.embedding.provider`:

| Setting | Required environment variable |
|---|---|
| openai (default) | OPENAI_API_KEY |
| voyage | VOYAGE_API_KEY |
| cohere | COHERE_API_KEY |
| off | None; keyword search only. |

For example, select a provider with:

```bash
defaults write org.holyghostty.app holy.archive.embedding.provider openai
```

Generate missing embeddings from the update menu after configuring credentials.
Embedding requests send indexed text to that provider. If semantic search is
unavailable, Archive keeps keyword results and states the reason.

### Research Chat

The researcher searches the archive and reads supporting sessions through
archive tools. It requires `OPENAI_API_KEY` in the app process environment.
Choose the model and reasoning effort, enter a question, and submit it.
Research requests send retrieved conversation content to OpenAI.

Chats persist in the Archive database. The chat controls open recent chats,
start a new chat, copy the transcript, and expand the research view. Research
chat failure appears in the conversation.

### Remote Archives

Configured SSH hosts contribute existing `holy-archive.sqlite3` indexes.
Each remote host needs Python 3 with SQLite support and a populated Holy archive.
The viewer reads the remote index over managed SSH; it does not crawl provider
history or create an index on that host.

Rows preserve host identity. Cached results display freshness and connection
errors. Search combines local and remote matches; remote semantic matches use
compatible stored vectors. Host-qualified identities keep conversations with
the same provider ID distinct across machines.

Remote transcripts and annotations are read-only. Edit tags, notes, and titles
on the owning host. `resume in roster` builds a provider-specific command and
uses the source host's SSH destination and tmux socket. The provider executable
and project directory must be available there.

## Session Restore

After a tmux server disappears, the workspace banner, `View ▸ Restore Sessions…`,
and Session History open the restore sheet. Sessions are grouped by shutdown.
Choose a row or a shutdown group to restore.

Captured provider identity selects the conversation directly. Otherwise the
native archive resolves candidates by provider, project, and activity time.
Assignments are unique across the restore group. Ambiguous rows offer a picker.
Missing history offers an explicit shell-only recreate. Resolution failures
remain retryable.

Resume commands are `claude --resume`, `codex resume`, and
`opencode --session` with the selected conversation ID. Executable discovery
checks the target environment and supported fallback directories. Session notes
remain visible in restore rows.

## Agent Indicators

Run `Enable Authoritative Agent Indicators` from the app menu. Holy installs
owned lifecycle hooks for Claude Code and Codex, a Codex turn notifier, and an
OpenCode plugin. Other handlers remain intact. Codex requires `/hooks` approval.
Running sessions need to load the installed hooks before they can publish state.

| Indicator | Meaning |
|---|---|
| Spinner | A committed working event remains valid and process evidence supports it. |
| Question mark | A question, permission request, or failure needs attention. |
| Green dot | A reply is unread. |
| Blue dot | A real user prompt occurred within 24 hours. |
| Grey dot | No prompt occurred within 24 hours, but another activity axis is within 48 hours. |
| Sleeping Z | No activity axis is within 48 hours. |

A static watcher eye identifies a scheduled wakeup. Its tooltip shows the fire
time. Git risk icons identify shared worktrees, branches, and changed-file
conflicts across separate worktrees.

Seen state belongs to the tmux host. Focusing a visible session acknowledges the
producer event across attached Macs. A background selection does not. Mark
Unread writes a shared tombstone. Questions and permissions remain until a
resolving provider event arrives.

The host journal preserves identity, lifecycle, finished, prompt, and seen
registers across reboot. Clear and reattachment reconstruct state from the host.
Local row creation never counts as a user prompt. Hook envelopes contain bounded
metadata without prompts, responses, or terminal text.

Phase labels such as Ready and Working also use terminal and shell-integration
telemetry. These heuristic labels do not determine the roster indicators.

## Usage Guard

Run `Enable Claude Usage Guard…` from the app menu. Holy installs its probe and
hook helpers under `~/Library/Application Support/Holy Ghostty/`. The probe reads
the signed-in Claude account from the keychain and refreshes usage every minute.
Enable the Claude Model Indicator to supply each session's own window readings.

| Level | Default trigger | Claude action |
|---|---|---|
| Normal | Below thresholds | Continue. |
| Notice | 75%, a qualifying projected cap within 40 minutes, or provider severity | Tell the user and continue working. |
| No new spawns | 90% | Deny Agent, Task, and Workflow spawns; continue current work. |
| Wrap up | 95% or projected cap within 20 minutes | Checkpoint, report PAUSED (usage cap), and end the turn. |
| Capped | 100% | Apply wrap-up handling. |

The 40-minute notice requires usage of at least half the notice threshold.
Projected caps take precedence over lower percentage tiers. User prompts receive
context rather than a deny decision. The hook refreshes stale data while Holy
is closed. A pause instruction requires the agent to follow it.

```bash
defaults write org.holyghostty.app holy.claudeUsage.warnPercent 75
defaults write org.holyghostty.app holy.claudeUsage.restrainPercent 90
defaults write org.holyghostty.app holy.claudeUsage.criticalPercent 95
defaults write org.holyghostty.app holy.claudeUsage.leadMinutes 20
defaults write org.holyghostty.app holy.claudeUsage.pollSeconds 60
```

The tmux bar shows machine-wide Claude and Codex usage beside the clock.
`Claude Usage…` in the roster's `…` menu opens account readings, reset times,
burn rates, projected caps, Refresh, and Wrap up all sessions. Manual wrap-up
expires after one lead window or an account change. Cancel wrap-up withdraws it.

Only the signed-in Claude account is polled live. Per-session windows preserve
the session's own readings after a login elsewhere. HTTP 429 responses trigger
backoff; manual Refresh requests a forced probe. Failed probes retain marked
last-known readings. Account changes discard the previous account's snapshot.

Codex readings come from `codex app-server` rate-limit and usage calls, with
rollout snapshots as fallback. They include reported model windows and reset
credits. Codex readings do not deny tools or pause Claude sessions. Holy installs
no Codex usage-guard hook.

## GitHub Attention

`Command-P` opens the GitHub-only dock. All repositories is the default tab.
The project tab follows the selected session's owned repository. Review requests
lead the list, maintainer attention follows, and bot authors collapse into
repository digests.

The source is `agent-do gh inbox --json`. Authentication must be available to
that command. Visible polling runs every 75 seconds; the hidden badge refreshes
every five minutes. Open, foreground, and manual refresh also request a sweep.
Rows clear when the source condition clears. Loaded commands open as unsubmitted
shell input in the known local repository. Native alerts retain separate
delivery history.

## Storage and Build

Workspace state lives in `holy-ghostty.sqlite3`; conversation indexing and
research chats live in `holy-archive.sqlite3`. Both use the container
`~/Library/Application Support/org.holyghostty.app/HolyGhostty/`.
Debug builds use `org.holyghostty.app.debug`.

The workspace stores sessions, notes, profiles, templates, git snapshots, events,
and alert history. The archive uses its own writer and bounded ingest batches.
Provider source files stay in their provider directories.

See the [build instructions](../../README.md#build-and-install),
[engineering spec](engineering-spec.md), and
[interoperability boundary](agent-sessions-interoperability.md).
