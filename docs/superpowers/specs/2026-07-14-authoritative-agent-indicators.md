# Authoritative Agent Indicators — Protocol and Reliability Contract

**Status:** Canonical implementation contract. Updated 2026-07-21.

The product invariant is simple: a harness publishes lifecycle facts; Holy
derives one of six user-visible states from those facts plus its own persisted
seen and recency timestamps. Terminal text never decides an operational state.

## The six states

| Glyph | State | Required evidence |
|---|---|---|
| Spinner | Working | A current structured `working` lifecycle event inside its 30-minute lease. Process evidence may extend or invalidate the claim, never create one: a live non-shell producer process with pane output fresher than three minutes extends past the lease (a working agent TUI redraws continuously), while a provably dead producer — dead pane or a bare shell foreground — invalidates the claim on the next one-second poll |
| Question mark | Needs you | A current structured `needs-user` or `failed` event inside its 30-minute lease and a live surface process |
| Green dot | Unread | A structured finished timestamp newer than the last real user focus. Rendered with a glow so the live green separates from the aging family at 9 px |
| Blue dot | Used today | No higher-priority state and a committed `user-prompt` envelope less than 24 hours ago. Blue is earned by the operator alone: agent events, finish registers, seen-marks, restores, focus sweeps, and boot baselines never advance this axis, which makes it immune to fake-stamp bugs by construction |
| Grey dot | Inactive | No higher-priority state, no operator prompt in 24 hours, and activity on some axis — prompt, agent event, or the operator reading the session — within 48 hours |
| Sleeping Z | Sleeping | No higher-priority state and every axis quiet for at least 48 hours. A session whose agent replied an hour ago is never "sleeping" merely because the operator has not prompted it |

Unread replaces recency; it is not a seventh overlay. An exited surface is
shown by the row's ordinary exited treatment and does not add another status
glyph.

One independent presentational channel sits beside the six states: the
**watcher eye**, a static `eye.fill` mark in the row's trailing cluster for a
session armed with a scheduled `/loop` wakeup. It composes with every center
state, carries the fire time in its tooltip, and is deliberately motionless —
motion stays reserved for burning compute, and a promise to wake is not
burning. It renders only while the armed fire time is in the future plus a
ten-minute reschedule grace, is voided when the producer process is provably
dead, and self-expires within an hour worst-case because wakeup delays clamp
to 3600 seconds. It is presentation only and never feeds
`HolySessionIndicatorPolicy`.

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
reader is the durable recovery path; each poll also carries `pane_dead`,
`pane_current_command`, and `window_activity`, the process evidence that
extends or invalidates working claims. Evidence is trusted only when exactly
one pane owns the latest-state register; ambiguity fails closed to lease-only
behavior.

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

### The watcher register

The watcher eye has its own independent pane register with a five-field wire:

```text
@holy_watcher_v1 = v1|source|watching|fire-at-ms|reason-code
```

Its producer is the one deliberate exception to the stdin rule: an inline
program embedded in a `ScheduleWakeup`-matched PostToolUse hook command reads
exactly two fields from the tool input — `delaySeconds` (numeric, bounded) and
`stop` (boolean) — and nothing else. The loop prompt never reaches it. A
schedule arms the register with the computed fire time; `stop: true` unsets
it; every failure path exits zero so the register can never block the tool.
Living inside the hook command means no second installed artifact exists;
ownership keys on an embedded marker so merges stay idempotent and uninstall
strips the hook. The monitor reads the register in the same grouped poll and
fails closed to nil on malformed or conflicting claims.

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
not expose. Claude's `Stop` hook publishes `finished` at turn end. A parallel
sibling Stop hook can block the stop and force continuation, making that
`finished` transiently false — but the error self-corrects in seconds when the
next tool or prompt event publishes a newer `working` envelope and newest-wins
ordering repairs the state. The inverse design (completion only via
`Notification(idle_prompt)`) proved unbounded in the field: idle_prompt has no
documented latency guarantee and does not fire while the terminal is focused,
which left every watched turn-end stuck on `working`. idle_prompt remains as
the non-blocking confirmation path.

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

Installation is explicit and consent-gated behind the app's
"Enable Authoritative Agent Indicators" menu action. Holy exact-merges only
its own Claude and Codex hook handlers, writes exact-owned Codex notify and
OpenCode adapters, and leaves unrelated user configuration intact. The Codex
adapter reads no prompt or response fields. Its exact-owned top-level `notify`
line is inserted without reserializing `config.toml`. A foreign or multiline
notifier blocks installation instead of being overwritten — with one
delegation exception: a foreign single-line notifier whose own assignment
references Holy's adapter file name (the Codex Computer Use pattern, which
chains the adapter via `--previous-notify`) is accepted untouched by both
install and uninstall, because committed-turn events still reach the register
through the chain. Modified current-generation files and future-generation
files fail closed. Codex lifecycle-hook trust remains a manual `/hooks`
approval.

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
  notification request after restart and one persistent green unread dot until
  actual surface focus.
- A real tmux pseudo-terminal test proves immediate DCS-wrapped OSC delivery;
  durable polling proves detached/reconnect recovery.
- A live dev server or frozen terminal spinner cannot create or sustain a
  working indicator without structured lifecycle evidence.
- Blue advances only on committed `user-prompt` envelopes; agent events,
  finish registers, seen-marks, and migrations never advance it.
- A provably dead producer drops a within-lease working claim on the next
  poll; a live producer with fresh output keeps a tool-less turn spinning past
  the lease; a live process idling at a static prompt expires on the lease.
- Reading an old session's fresh reply lands on plain grey, never sleeping-Z.
- The watcher register parses one distinct valid claim per session and fails
  closed on malformed or conflicting values; the eye never feeds policy.
- A delegated Codex notifier (foreign command referencing Holy's adapter file
  name) passes install and uninstall untouched; a truly foreign notifier still
  blocks.
