# Session Indicators, From First Principles — Design Handoff (2026-07-14)

**Mission:** Redesign Holy Ghostty's roster activity indicators so they are *boring and correct*, the way mail badges and CI dots are. Free yourself from the current implementation's frame entirely. This document gives you the evidence of why the current approach cannot be patched into correctness, the inventory of stronger signals already available, and the invariants any design must satisfy. It deliberately stops short of a full design — that's your job.

## 0. The first principle

Every app with indicators that work — Mail, Slack, CI dashboards, iOS badges — has one property in common: **the state is emitted by the thing that knows, not inferred by the thing that displays.** The sender publishes an event ("message arrived", "build failed"); the UI renders a state machine fed by those events.

Holy Ghostty does the opposite: it reconstructs agent state by regex-matching the *visible text* of a terminal pane. That is inference from a surface that mixes program output, streamed AI prose that *discusses the indicators themselves*, the user's unsent draft, quoted transcripts, and footer chrome — all in one undifferentiated string. Today proved this is not a hardening problem; it is a category error.

## 1. Evidence: one day of patching the inference approach (8 commits)

| Commit | What broke | The deeper lesson |
|---|---|---|
| `4c00eadbe` | Workflow sessions showed no spinner; gerund/glyph vocabulary gaps | Vocabulary always lags the CLI's UI language |
| `ef0bb1ef4` | Agent's own prose quoting footer phrases lit the swarm state; frozen spinner glyph in *title* read as busy; user's draft raised the approval hand | The surface contains adversarial-by-accident text |
| `938b6f621` | Draft leaked to the hand via a *second* path (signal detail) | Every consumer of pane text is an independent leak |
| `3d5262615` | Detection read only the last 8 lines; spinner above a todo list was invisible | The matchers' input was silently truncated |
| `6338c4227` | Codex review: *third* draft-leak path (parser hints); freshness window narrower than scan depth | Independent extraction sites keep leaking |
| `01aa152e7` | (naming, adjacent) resumed-idle sessions starve of OSC evidence | Screen-derived evidence is absent exactly when sessions are idle |
| `cdad159c8` | Agent's own streamed reply containing "confirm" raised the hand (*fourth* leak); a new footer variant misread | The treadmill again, hours after the review |
| `1f03d069b` | **Revert:** the fix above pinned a *permanent* false throbber — "1 shell still running" also decorates the IDLE residue line because background shells outlive turns | Some footer lines are per-sample ambiguous; no lexical rule can ever classify them |

Four distinct leak paths for untrusted text into one indicator. A line ("`✻ Churned for 7m 12s · 1 shell still running`") that is *provably unclassifiable* from a single sample. This is the ceiling of the scraping approach.

## 2. Signal inventory, strongest first

**Tier 1 — the agent tells us (authoritative, implemented):**
- **Harness adapters.** Claude Code hooks, a Codex committed-turn notify adapter, and an OpenCode plugin now publish the same versioned lifecycle envelope. The source field is deliberately open, so a future harness implements the protocol instead of growing another UI-specific parser. Claude completion is committed from `Notification(idle_prompt)`, not raw `Stop`: another concurrent Claude Stop hook can block stopping and continue the turn. Codex completion comes only from top-level `notify` after `agent-turn-complete`; raw `Stop`, `PreToolUse`, and `PermissionRequest` are not committed evidence and cannot paint finished/needs-user.
- **The tmux user-option channel already in production.** This codebase already round-trips per-session/per-pane state through tmux options: `@holy_working_directory`, `@holy_title`, `@holy_model_label` (written via `HolyTmuxCommandBuilder`/`HolyTmuxModelLabelUpdateCommand` with retry — `HolySession.swift:847`, `HolyWorkspaceStore.swift:3721` — and read by discovery, `HolyRemoteTmuxDiscoveryService.swift:702,764`). Hooks now persist the latest event in pane-scoped `@holy_agent_state_v1`; finished events also persist independently in `@holy_agent_last_finished_v1`, so detach or a later idle transition cannot erase unread work.
- Claude Code also exposes per-session JSONL transcripts and statusline integration if a file-based channel is preferred.

**Tier 2 — the system tells us (robust, runtime-agnostic):**
- Exact foreground process/pane facts can invalidate a stale claim. "Any descendant process" is explicitly insufficient: a dev server outlives turns and cannot prove the agent is working.
- Ghostty's OSC plumbing the app already parses: `progressReport` (OSC 9;4 — `HolySession.swift` `activeProgressReport`), OSC 7 pwd, OSC 0/2 title, bell.

**Tier 3 — the screen suggests (today's approach, demoted to hint):**
- Text heuristics remain useful *only* as a fallback for un-instrumented runtimes, and only for states that are cheap to be wrong about (never as the sole source for "working" vs "waiting").

## 3. The target vocabulary (user-specified, canonical)

Erik defined the indicator language directly (2026-07-14). This is the product requirement; design to it, not to the current 15-state enum:

| Glyph | Meaning | Evidence needed |
|---|---|---|
| **Spinner** | Agent actively working | Tier 1 committed turn-in-flight event; process facts may invalidate it but never create it |
| **Question mark** | Agent has questions / genuinely needs the user (fold today's "approval hand" into this — one cue for "waiting on me and why") | Tier 1 committed needs-user or failed event; no prompt-text inference |
| **Little white dot** | Unread — agent finished something the user hasn't looked at | `lastAgentFinishedAt` > `lastSeenAt` (exists; Tier 1 makes `finishedAt` exact) |
| **Blue dot** | Used today (seen, recent) | `lastSeenAt`/activity within the day |
| **Muted grey dot** | 24–48 h inactive | timestamps |
| **Sleeping Z + grey dot** | 48 h+ inactive | timestamps |

Explicitly killed: the **hand** ("I don't even know what it means at this point") and the **grey circle with check** ("no idea what this means or how it appears"). Every state must pass the test the user set: *at a glance — what am I working on, what am I not, what is genuinely waiting on me, and why.* If a proposed state can't be explained in those terms in one phrase, it doesn't ship.

Rendering decisions now closed: **unread replaces the recency dot**, preserving exactly six mutually exclusive states. A dead/exited surface invalidates working/needs-user evidence and uses the row's ordinary exited treatment; it does not introduce a seventh status glyph.

## 4. Constraints and invariants for the new design

1. **Explicit state machine.** The Section-3 states are the complete vocabulary: working / needs-user / unread / used-today / inactive / sleeping. No operational state is entered from Tier-3 evidence.
2. **Precedence, not blending.** Tier 1 supplies operational state; Tier 2 may invalidate a stale or impossible claim; Tier 3 cannot enter an operational state. A hook-reported "turn ended" beats any spinner the screen appears to show.
3. **Staleness is first-class.** Every event carries a timestamp and opaque token. A working claim expires after a bounded lease and degrades to the honest recency state; screen text cannot extend it.
4. **Untrusted text stays untrusted.** Nothing rendered by an agent or typed by the user may flow into state classification, telemetry hints, or explicitness checks. (Four leak paths above; assume a fifth exists.)
5. **Unknown means unsafe.** Downstream consumers (the planned cross-session control bus) will gate *typing into panes* on this oracle. False "waiting" must be treated as the most expensive error, not a cosmetic one.
6. **Unread (white dot) appears ≤ 2 s after the harness emits its committed finish event; zero sustained false spinners over a 24 h soak with a dev server running.** Producer latency is tested separately from transport latency so a delayed upstream notification cannot be mislabeled as transport success.
7. **Runtime coverage:** Claude Code, Codex, and OpenCode are Tier 1 through adapters; unknown future harnesses use the same open protocol; shells have recency only and never fabricate agent activity.

## 5. What survives from today (don't rebuild these)

- The **seen/unseen storage shape** survives, but the old no-op seen updater did not. Seen tracking is now restored, versioned, and baselined once so historical rows do not create a rollout badge storm.
- The **`session_events` forensic loop** survives as an audit trail. Legacy heuristic events may retain their diagnostic preview, while authoritative lifecycle events record only source, state, reason, opaque token, and observation time—never terminal text.
- The **presentation layer** (`attentionPresentation` → orb vocabulary) — the rendering is fine; feed it a better state.
- The tmux option delivery/read plumbing and the 26 detection tests (they become the Tier-3 fallback's spec).

## 6. Resolved architecture and remaining deployment question

- **Transport:** pane-scoped `@holy_agent_state_v1` is durable truth; reserved OSC 777 is the immediate delivery path; a grouped `list-panes` reader closes the loss window without one process per session.
- **Install UX:** an explicit Holy menu action exact-merges only Holy-owned Claude/Codex lifecycle handlers, creates exact-owned Codex notify and OpenCode adapters, and exact-inserts the Codex top-level `notify` line without reserializing comments. It preserves unrelated settings, blocks on foreign/multiline notifiers rather than overwriting or chaining them, rolls back multi-file failures, and never bypasses Codex's `/hooks` trust review. The same manifest now installs transactionally on one explicitly selected SSH host.
- **Heartbeat:** new working events refresh a bounded lease; silence expires rather than trusting screen glyphs. Repeating the same current event is idempotent and cannot manufacture unread replies.
- **Remaining deployment question:** remote producers must be explicitly installed on each SSH host. The reader and protocol are remote-capable, but Holy must never silently rewrite remote dotfiles.

## 7. Related material

- `.handoff/SESSION-HANDOFF-2026-07-14.md` — full commit-by-commit forensics of today, the debugging technique, and the Codex review findings.
- Cross-session control review (this session's transcript): the "state oracle is the weakest layer" argument — this redesign is its prerequisite.
- Memory: `roster-activity-detection.md` (leak paths, footer ambiguity proof).

## 8. Implementation snapshot (2026-07-14)

- `AgentState/HolyAgentStateEnvelope.swift`: strict, versioned, metadata-only protocol with open producer names, bounds, ordering, and dedupe.
- `AgentState/HolyAgentStateBridge.swift`: Claude/Codex/OpenCode adapters and the Holy-pane-gated producer helper.
- `AgentState/HolyCodexNotifyConfiguration.swift`: byte-preserving, exact-owned user-level Codex `notify` installation with foreign/multiline fail-closed behavior.
- `AgentState/HolyAgentStateBridgeInstaller.swift`: explicit local installation/removal with exact ownership and rollback.
- `Remote/HolyRemoteAgentStateBridgeService.swift`: bounded per-host SSH installation using the same generated manifest; remote user configuration never returns to Holy.
- `HolySessionIndicatorPolicy`: pure six-state reducer; no preview/screen field exists in its input type.
- `HolySessionAttentionMetadata`: restored seen tracking, one-time legacy baseline, and token-idempotent finish timestamps.
- `session_events`: `session_agent_state_changed` records source/state/reason/token/observed time, never prompt or response text.
- Agent notifications now key off authoritative event tokens; phase/regex changes no longer create agent alerts.
