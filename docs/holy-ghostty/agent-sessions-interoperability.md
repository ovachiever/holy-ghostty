# Holy Ghostty and agent-sessions Interoperability

Last updated: 2026-04-15

This document records the chosen interoperability strategy between Holy Ghostty and `agent-sessions`.

## Decision

Chosen route:

- `agent-sessions` will read Holy Ghostty data in read-only mode through a future `holy-ghostty` provider.

Holy Ghostty keeps its own SQLite database as its operational source of truth. `agent-sessions` does not own that database, does not write to it, and does not define Holy Ghostty's internal schema.

## Why This Route

This is the cleanest arrangement for both products.

Holy Ghostty needs a database for:

- live session durability
- event history
- alert history
- archive/relaunch memory
- supervision and restore

`agent-sessions` needs data for:

- browsing
- search
- annotations
- transcript reading
- resume actions

Those overlap, but they are not the same product responsibility.

This route avoids:

- one shared database owned by two apps
- duplicate write pipelines
- fragile export/import loops
- forcing Holy Ghostty's schema to become a generic session-index schema

## Core Rule

Holy Ghostty owns its internal schema.

`agent-sessions` consumes a stable read model exposed by Holy Ghostty.

The integration contract is the read model, not the raw internal tables.

## Interoperability Contract

Holy Ghostty should expose versioned, read-only compatibility views in its SQLite database.

Recommended names:

- `agent_sessions_sessions_v1`
- `agent_sessions_resume_targets_v1`
- `agent_sessions_events_v1`
- `agent_sessions_annotations_v1`

Future:

- `agent_sessions_messages_v1`

This keeps the contract explicit and versionable. Holy Ghostty can evolve its internal tables while keeping these external views stable.

## What v0.2 Must Preserve

Even if `agent-sessions` integration is not implemented in `v0.2`, the `v0.2` schema should preserve enough normalized data to support it later without a rewrite.

Minimum compatibility fields:

- stable session UUID
- runtime / harness name
- human title
- mission / objective
- created / updated / archived timestamps
- project path or worktree path
- repository root
- latest phase
- latest attention state
- latest preview text
- enough resume metadata to reopen or continue the session

## Proposed Compatibility Views

### 1. `agent_sessions_sessions_v1`

Purpose:

- provider-readable session list for browsing and filtering

Suggested columns:

- `id`
- `harness`
- `title`
- `project_path`
- `project_name`
- `repository_root`
- `worktree_path`
- `created_at`
- `updated_at`
- `archived_at`
- `phase`
- `attention`
- `preview_text`
- `content_hash`
- `extra_json`

### 2. `agent_sessions_resume_targets_v1`

Purpose:

- allow `agent-sessions` to resume or reopen a Holy Ghostty session meaningfully

Suggested columns:

- `session_id`
- `runtime`
- `working_directory`
- `repository_root`
- `resume_kind`
- `resume_payload_json`
- `preferred_command`

### 3. `agent_sessions_events_v1`

Purpose:

- allow external browsing of the Holy Ghostty event ledger

Suggested columns:

- `event_id`
- `session_id`
- `sequence`
- `occurred_at`
- `event_type`
- `phase`
- `attention`
- `payload_json`

### 4. `agent_sessions_annotations_v1`

Purpose:

- future-compatible annotation/tag bridge

Suggested columns:

- `id`
- `session_id`
- `created_at`
- `annotation_type`
- `value`
- `source`

## Transcript Compatibility

This is the one part not worth over-solving in `v0.2`.

Holy Ghostty today does not have structured provider transcript data comparable to `agent-sessions` provider logs. It has:

- session state
- preview text
- events
- runtime heuristics

So the correct sequence is:

- `v0.2`: expose sessions, resume targets, and event history
- `v0.3+`: expose richer transcript or message projections once structured telemetry is stronger

Do not distort `v0.2` just to fake a transcript model it does not yet have.

## Required v0.2 Design Constraint

The `v0.2` database plan should include these compatibility guarantees:

### 1. Stable IDs

Session IDs must remain durable and not be regenerated on every restore/import.

### 2. Stable runtime naming

Use canonical runtime names:

- `shell`
- `claude`
- `codex`
- `opencode`

### 3. Resume metadata is first-class

Do not make resume behavior reconstructible only from UI code.

Persist enough resume intent that a separate provider can use it.

### 4. Versioned external views

Never point another app directly at arbitrary internal tables and call that the contract.

### 5. Additive compatibility

If the integration shape changes, add `v2` views rather than silently changing `v1`.

## What Holy Ghostty Should Not Do

Holy Ghostty should not:

- use the same SQLite file as `agent-sessions`
- depend on Python or the `agent-sessions` package
- shape all internal data around `agent-sessions`
- promise transcript fidelity before structured telemetry exists

## What agent-sessions Will Eventually Do

Later, `agent-sessions` can add a provider named:

- `holy-ghostty`

That provider would:

- open Holy Ghostty's SQLite database read-only
- query the compatibility views
- map rows into the existing `Session` model
- provide resume behavior through `resume_payload_json` or `preferred_command`

At that point:

- Holy Ghostty becomes the live operator surface
- `agent-sessions` becomes the cross-provider browser and search layer

That is a clean relationship.

## Bottom Line

The chosen design is:

- Holy Ghostty owns its operational database
- Holy Ghostty exposes versioned, read-only compatibility views
- `agent-sessions` later consumes those views through a provider adapter

That is enough to ensure the two projects can work together without coupling them prematurely.
