# Authoritative Agent Indicators — Protocol and Reliability Contract

**Status:** Canonical implementation contract, 2026-07-14.

This document supersedes the rendering and inference rules in
`2026-07-14-unseen-reply-indicator-design.md` without deleting that design
history. The product invariant is simple: a harness publishes lifecycle facts;
Holy derives one of six user-visible states from those facts plus its own
persisted seen and recency timestamps. Terminal text never decides an
operational state.

## The six states

| Glyph | State | Required evidence |
|---|---|---|
| Spinner | Working | A current structured `working` lifecycle event and a live surface process |
| Question mark | Needs you | A current structured `needs-user` or `failed` event and a live surface process |
| White dot | Unread | A structured finished/update timestamp newer than the last real user focus |
| Blue dot | Used today | No higher-priority state and structured use or real user focus less than 24 hours ago |
| Grey dot | Inactive | No higher-priority state and last use 24–48 hours ago |
| Sleeping Z | Sleeping | No higher-priority state and last use at least 48 hours ago |

Unread replaces recency; it is not a seventh overlay. An exited surface is
shown by the row's ordinary exited treatment and does not add another status
glyph. The approval hand and grey checkmark are not part of this vocabulary.

## Harness-neutral wire contract

Every producer uses the same bounded, metadata-only envelope:

```text
v1|source|lifecycle|epoch-ms|event-token|session-id|reason-code
```

- `source` is an open identifier, not an enum. Holy currently ships adapters
  for `claude`, `codex`, and `opencode`; a future harness chooses another valid
  identifier without changing the wire parser or indicator policy.
- `lifecycle` is one of `working`, `needs-user`, `finished`, `failed`, `idle`,
  or `ended`. These are producer facts, not UI glyph names.
- `event-token` is opaque and unique within a source. Holy deduplicates the OSC
  fast path and the durable tmux copy by the unambiguous
  `source|event-token` pair.
- The envelope contains no prompt, response, tool input, tool output, terminal
  text, or model-generated prose.
- Unknown versions, malformed metadata, contradictory pane values, ambiguous
  session ownership, and out-of-order events fail closed. Holy retains its
  prior valid state instead of guessing.

The producer writes the latest envelope to the pane-scoped tmux option
`@holy_agent_state_v1`. A `finished` event is also copied to
`@holy_agent_last_finished_v1`, so a later `idle` or `ended` event cannot erase
an unread completion while Holy is detached. The same envelope is sent through
Holy's reserved OSC 777 title for immediate delivery. A grouped `list-panes`
reader is the durable recovery path.

The shared helper accepts only controlled arguments:

```text
agent-state-hook.sh SOURCE LIFECYCLE [REASON-CODE] [SESSION-ID]
```

It intentionally does not read hook stdin. A new harness adapter is conformant
when it maps documented structured runtime events to those arguments and does
not infer state from terminal text. Adding that adapter may extend installation
UI, but must not modify the envelope, monitor, persistence, notification gate,
or `HolySessionIndicatorPolicy`. Repeating the same current lifecycle event is
an idempotent no-op rather than a synthetic new reply.

Claude, Codex, and OpenCode are bundled adapters, not privileged protocol
participants. Runtime identity used elsewhere for launch templates and labels
does not constrain `HolyAgentStateEnvelope.source`; the event path deliberately
keeps that field open for future harnesses.

## Reliability definition

"Reliable" means deterministic and auditable from the strongest facts the
harness exposes:

1. A committed producer event is persisted before success is reported.
2. Immediate and polling delivery collapse to one event identity.
3. OS notification requests use a deterministic event identity and a persisted
   monotonic watermark so duplicate delivery and older recovery registers do
   not schedule another alert. The roster's unread state remains the durable
   in-app notification even if macOS notification permission is disabled.
4. A session is marked seen only when Holy is active, its real window is key
   and visible, and that terminal surface actually has focus. Selecting a row
   in a background window does not clear unread.
5. The transport target is observation within two seconds after a harness emits
   a committed event. Harness-side latency is measured separately.

No terminal can truthfully manufacture an event that its upstream runtime does
not expose. In particular, Claude's authoritative non-blocking completion
signal is `Notification(idle_prompt)`, whose upstream delay has no documented
latency guarantee. Claude `Stop` is not treated as completion because another
parallel Stop hook may block the stop and continue the turn.

Codex completion uses the user-level top-level `notify` command and accepts
only an `agent-turn-complete` payload with validated `thread-id` and `turn-id`.
Raw Codex `Stop` is also only a stop attempt and never emits `finished`.
`PreToolUse` and `PermissionRequest` are pre-aggregation events: another hook
can answer or allow them, so they do not emit `needs-user`. This deliberately
leaves Codex without a question mark when no committed waiting event exists.
The Codex notifier is commit-safe when received, but Codex launches the
external command best-effort; it is not a durable or exhaustive event stream.
Holy therefore never claims that provider delivery itself is mathematically
lossless. OpenCode's structured plugin events use the same downstream contract;
a transient `session.error` remains pending through retry and becomes a failed
event only if the session reaches committed idle without recovering.

## Installation and ownership

Installation is explicit. Holy exact-merges only its own Claude and Codex hook
handlers, writes exact-owned Codex notify and OpenCode adapters, and leaves
unrelated user configuration intact. The Codex adapter reads no prompt or
response fields. Its exact-owned top-level `notify` line is inserted without
reserializing `config.toml`; a foreign or multiline notifier blocks installation
instead of being overwritten or silently chained. Modified current-generation
files and future-generation files fail closed. Codex lifecycle-hook trust
remains a manual `/hooks` approval.

Remote SSH hosts use the same generated manifest and a bounded on-host
transaction. Existing remote settings are merged on the remote machine and are
not copied back into Holy. Each host is enabled explicitly; Holy never silently
rewrites every host's dotfiles.

## Acceptance tests

- The policy exposes exactly six cases and contains no screen-text input.
- Every bundled adapter emits valid envelopes through the same helper.
- Arbitrary valid future `source` identifiers parse and render without policy
  changes.
- Duplicate, stale, malformed, conflicting, and ambiguously owned events do not
  advance state or generate notifications.
- A committed finish observed while Holy is closed produces one deterministic
  notification request after restart and one persistent white unread dot until
  actual surface focus.
- A real tmux pseudo-terminal test proves immediate DCS-wrapped OSC delivery;
  durable polling proves detached/reconnect recovery.
- A live dev server or frozen terminal spinner cannot create or sustain a
  working indicator without structured lifecycle evidence.
