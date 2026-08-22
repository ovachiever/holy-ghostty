# Holy Ghostty and agent-sessions Interoperability

Last updated: 2026-08-22

This document describes the interoperability contract between Holy Ghostty and `agent-sessions`. The integration has two directions, each with its own contract surface.

## The Two Directions

1. **Crash restore (implemented, Holy consumes agent-sessions).** Holy Ghostty's Session Restore uses the `agent-sessions` CLI as its conversation oracle: one `resolve-batch` call resolves every interrupted session on the restore sheet to a resumable provider conversation.
2. **Read model (Holy side shipped, consumer pending).** Holy Ghostty exposes versioned, read-only compatibility views in its SQLite database for a future `agent-sessions` `holy-ghostty` provider. The views ship in Holy's schema; `agent-sessions` does not yet include a provider that reads them.

## Core Rule

Holy Ghostty owns its internal schema.

`agent-sessions` consumes a stable read model exposed by Holy Ghostty, and Holy Ghostty consumes a stable CLI contract exposed by `agent-sessions`.

The integration contract in each direction is the external surface — views on one side, CLI verbs and JSON on the other — never the raw internal tables or index files.

This arrangement avoids:

- one shared database owned by two apps
- duplicate write pipelines
- fragile export/import loops
- forcing either product's internal schema to become the other's contract

## Direction 1: Crash-Restore Resolution

Implemented in `macos/Sources/HolyGhostty/Restore/HolyRestoreResolveClient.swift` on the Holy side and `agent_sessions/resolve.py` on the agent-sessions side.

Contract:

- `agent-sessions` exposes `resolve` (one session) and `resolve-batch` (many) as CLI verbs. Holy uses `resolve-batch --json`: the whole restore sheet's questions ship in a single call, and the reply is one JSON object on stdout.
- `resolve-batch` performs its own scoped reindex of the relevant harness/project scopes, with a per-scope hold-off (120 seconds) so restore attempts cannot thrash the index.
- Naming is mapped at the boundary: Holy Ghostty names runtimes (`claude`, `codex`, `opencode`); the agent-sessions index names harnesses. The resolve layer translates.
- Holy fails closed on this contract: a missing CLI, a missing `resolve-batch` verb, a crash, a timeout, or an undecodable payload makes rows retryable — it never fabricates a conversation match.
- Downstream of resolution, assignment of conversations to restore rows is Holy's job and is globally unique: no two rows can receive the same conversation id. The resumable identity Holy persists is the final argv (`claude --resume <id>`, `codex resume <id>`, `opencode --session <id>`); nothing re-resolves after restore.

## Direction 2: The Read-Model Views

Holy Ghostty's schema defines four versioned, read-only SQL views (created in the initial schema and maintained by later migrations; all four exclude sessions pending purge):

### 1. `agent_sessions_sessions_v1`

Provider-readable session list for browsing and filtering.

Columns:

- `id`
- `harness` (Holy's runtime name)
- `title`
- `project_path` (worktree path, else working directory, else repository root)
- `project_name` (currently `NULL`)
- `repository_root`
- `worktree_path`
- `created_at`
- `updated_at`
- `archived_at`
- `phase`
- `attention`
- `preview_text`
- `content_hash` (currently `NULL`)
- `extra_json` (the launch-spec JSON)

### 2. `agent_sessions_resume_targets_v1`

Enough resume metadata for an external provider to reopen or continue a Holy session.

Columns:

- `session_id`
- `runtime`
- `working_directory`
- `repository_root`
- `resume_payload_json`
- `preferred_command`
- `resume_kind` (`active_session` or `archived_session`)

### 3. `agent_sessions_events_v1`

External browsing of the Holy Ghostty event ledger.

Columns:

- `event_id`
- `session_id`
- `sequence`
- `occurred_at`
- `event_type`
- `phase`
- `attention`
- `payload_json`

### 4. `agent_sessions_annotations_v1`

Annotation/tag bridge over Holy's `annotations` table.

Columns:

- `id`
- `session_id`
- `created_at`
- `annotation_type`
- `value`
- `source`

## Guarantees Behind the Views

- **Stable IDs.** Session IDs are durable and are not regenerated on restore or import.
- **Stable runtime naming.** Canonical runtime names are `shell`, `claude`, `codex`, `opencode`.
- **Resume metadata is first-class.** Resume intent is persisted (`resume_payload_json`, `preferred_command`), not reconstructible only from UI code.
- **Versioned external views.** No external consumer is pointed at internal tables.
- **Additive compatibility.** If the integration shape changes, `v2` views are added; `v1` views are not silently changed.

## Transcript Compatibility

Holy Ghostty does not maintain structured provider transcript data comparable to `agent-sessions` provider logs. It has session state, preview text, events, and runtime telemetry. The views therefore expose sessions, resume targets, events, and annotations — not a message/transcript projection. A richer `agent_sessions_messages_v1` remains unbuilt and is not faked.

## Boundaries

Holy Ghostty does not:

- use the same SQLite file as `agent-sessions`
- depend on Python or the `agent-sessions` package (the CLI is invoked as an external process and its absence degrades gracefully)
- shape internal data around `agent-sessions`
- promise transcript fidelity that structured telemetry cannot back

## The Pending Provider

A future `agent-sessions` provider named `holy-ghostty` would open Holy's database read-only, query the compatibility views, map rows into the existing `Session` model, and resume through `resume_payload_json` or `preferred_command`. At that point Holy Ghostty is the live operator surface and `agent-sessions` the cross-provider browser and search layer. The views above are the complete contract that provider needs.
