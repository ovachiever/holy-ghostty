# Holy Ghostty and agent-sessions Interoperability

Holy Ghostty owns its conversation archive and production crash resolver.
Archive browsing, search, and restore do not require the `agent-sessions`
executable or its database.

## Provider Boundary

`HolyArchiveProviderRegistry` reads Claude Code, Codex, Droid, Cursor, and
OpenCode history directly. It normalizes sessions, messages, parent-child
relationships, provider IDs, and project paths into Holy's archive database.
The source history remains owned by each provider.

Archive displays command-style labels such as `agent-sessions list` and
`agent-sessions search`. These labels describe the view; they do not execute
an external indexer.

## Restore Contract

`HolyWorkspaceStore` supplies `HolyArchiveRestoreResolver` to the restore engine.
The resolver implements the single and batch resolution protocols in process.
Single resolution is lookup-only. Batch resolution refreshes stale provider and
project scopes before looking up candidates.

Captured conversation identity takes precedence over time-based matching.
Fallback queries carry a working directory, harness, and activity timestamp in
Unix seconds. Results distinguish exact, ambiguous, absent, and unavailable.
`HolyRestoreAssignment` assigns candidates uniquely across the restore group.
An unavailable resolver keeps the row retryable.

The resume command builder selects provider-specific arguments from the runtime
and conversation ID. Claude, Codex, and OpenCode support roster resume.
Droid and Cursor remain archive providers without a Holy launch runtime.

`HolyRestoreResolveClient.swift` retains external CLI data types and a process
client for compatibility. The production workspace injects the native resolver.

## Database Ownership

Holy owns `holy-ghostty.sqlite3` for workspace state and `holy-archive.sqlite3`
for provider history, search, annotations, and research chats. Both live in
Holy's application-support container. The standalone `agent-sessions` index
remains separate. Neither product requires access to the other's database.

## Remote Archives

Federation reads the existing Holy archive on configured SSH hosts through
Python 3 and SQLite in read-only mode. It preserves the source host and provider
ID, caches bounded pages, and exposes stale results and host failures.
It does not execute the standalone `agent-sessions` CLI or reindex remote
provider history.

Remote resume builds a Holy launch specification for the source host's SSH
destination and tmux socket. Remote annotations are edited on that host.

See the [guide](README.md#archive) for user controls and the
[engineering spec](engineering-spec.md#archive) for storage and search details.
