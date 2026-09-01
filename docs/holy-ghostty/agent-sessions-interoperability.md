# Holy Ghostty and agent-sessions Interoperability

Last updated: 2026-09-01

Holy Ghostty uses `agent-sessions` for one narrow boundary: resolving an
interrupted Holy session to the exact provider conversation that can be
resumed. Holy owns its roster and archive natively. `agent-sessions` remains
a standalone CLI and legacy cross-provider index.

## Crash-Restore Resolution

The Holy implementation lives in
`macos/Sources/HolyGhostty/Restore/HolyRestoreResolveClient.swift`.
`agent-sessions` owns the corresponding `resolve` and `resolve-batch` verbs.

Contract:

- Holy sends the whole restore sheet through one `resolve-batch --json` call.
- `agent-sessions` performs its own scoped reindex of the relevant harness and
  project scopes, with a per-scope hold-off so repeated restore attempts do not
  thrash the index.
- Runtime names are translated at the boundary. Holy calls them `claude`,
  `codex`, and `opencode`; the index calls them harnesses.
- Holy fails closed. A missing executable or verb, subprocess failure,
  timeout, or undecodable payload leaves rows retryable. It never invents a
  conversation match.
- Holy assigns returned candidates globally and uniquely. Two rows cannot
  receive the same conversation identity.
- The final resumable identity is the exact argv, such as
  `claude --resume <id>`, `codex resume <id>`, or
  `opencode --session <id>`. Nothing re-resolves after launch.

## Database Boundary

Holy's SQLite schema is private to Holy. Migration 10 drops the historical
`agent_sessions_sessions_v1`, `agent_sessions_resume_targets_v1`,
`agent_sessions_events_v1`, and `agent_sessions_annotations_v1` views.
The planned `agent-sessions` provider for those views is retired.

`agent-sessions` does not read Holy's database, and Holy does not read the
index's internal files. The supported seam is the versioned CLI and JSON
contract above.

## Ownership

- Holy owns active sessions, the native archive, persistence, assignment,
  restore UI, and final launch argv.
- `agent-sessions` owns provider-history indexing and candidate resolution.
- Neither product writes the other's database.
- Holy does not promise transcript fidelity from preview text or telemetry.
