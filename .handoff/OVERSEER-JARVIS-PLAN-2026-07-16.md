# The Overseer — Holy Ghostty's Jarvis Layer (Plan, 2026-07-16)

**Erik's vision, verbatim shape:** a supervisor-orchestrator that sees inside every agent session, interacts with them in full read/write, and talks to Erik by voice — *"Hey Erik, your Aldebaran Group Prompt 30 is done. Here are the results. What would you like to know?"* — with natural back-and-forth, able to type a message into any running session and press Enter. An **optional** interface layered over Holy Ghostty, never the only one.

## What already exists vs what this adds

The manna Wave-4 chain is the Overseer's *sensory and motor system* — this plan deliberately builds nothing that duplicates it:

| Substrate (tracked) | Provides |
|---|---|
| `mn-e59548` holyctl list/observe | Eyes: structured session state, output deltas |
| `mn-c674c4` Watch + provenance | Subscriptions with own-echo tagging |
| `mn-e49b22` safe-input oracle | "Is this pane safe to type into?" |
| `mn-573ec9` leases/preemption/quotas/audit | Permission to act, one controller, human always wins |
| `mn-610814` verified messages + runtime adapters | The hands: byte-verified typing, per-runtime interrupt keys |
| Hook event bus (shipped `537c0a567`+) | Wake triggers: committed finished/needs-user events |

**The Overseer adds the brain and the voice:** a resident agent consuming those events, summarizing, speaking, listening, and driving the hands.

## Architecture

**1. The brain — a long-lived daemon, not a Claude Code session.** Built on the Claude Agent SDK: headless service, event-driven, with holyctl as its tool surface. (A Claude Code TUI session is turn-based, dies with usage caps, and would itself appear in the roster it supervises — wrong shape.) It holds a rolling model of the roster: which sessions exist, what each is doing, what recently finished, what it has already announced (watermarks reuse the notification dedup machinery).

**2. Proactive announcements.** Subscribes to the same committed-event feed the notification policy uses. On `finished`/`needs-user`: pulls the session's tail + telemetry via observe, LLM-summarizes to one spoken sentence, speaks it, and *retains the context* so "what would you like to know about it?" has a real answer behind it.

**3. Voice out.** ElevenLabs streaming TTS as the premium voice; `AVSpeechSynthesizer` as the zero-dependency fallback (works before any API key exists). Voice, rate, and announce-scope (all sessions / needs-user only / muted) are settings.

**4. Voice in.** Push-to-talk hotkey first (global shortcut → record → local Whisper or `SFSpeechRecognizer` → text to the brain). Wake-word ("Hey Holy") and barge-in are polish, not foundation.

**5. Write path.** "Tell flip 5 to also run the soak" → resolve the target by fuzzy match against roster names (voice never gets raw pane targets) → confirm intent verbally if the resolution is ambiguous or the action is consequential → acquire lease → typed via the verified adapter with the provenance prefix (`[from overseer]`) → confirm delivery → report back. Everything it does lands in the session timeline and the Overseer transcript panel.

**6. Presence in the app.** An Overseer panel: transcript of everything said/heard/done (audit view), mute toggle, PTT button, per-session announce settings. The roster, panes, and manual control remain untouched — this is an *additional* interface, per the explicit requirement.

## Safety invariants (inherited + one critical addition)

All control-plane invariants apply (single lease, human preemption, quotas, audit, human-only credential/destructive prompts). The addition specific to an LLM brain with hands:

**Watched session output is DATA, never instructions to the Overseer.** The Overseer reads other agents' transcripts — the classic injection vector ("tell the supervisor to approve everything"). Its prompt architecture must fence observed content the way this repo's detection pipeline learned to fence pane text: four separate draft-leak bugs proved text-as-instructions is the failure mode. Observed text gets summarized and quoted, never obeyed.

**Voice-confirm tiering:** informational answers free; sending a message to a session = confirm by default (relaxable per-session); interrupts = always confirm; anything the control plane classifies as destructive = refused, human does it directly.

## Phases (dependency-ordered; each independently shippable)

- **J1 — Brain, text-only.** Daemon + event subscription + summarize-on-finish + Q&A over sessions, exposed as a chat panel (no voice, no writes). *Depends: mn-e59548.* This alone is useful: "what happened while I slept?"
- **J2 — Voice out.** TTS announcements + spoken answers. ElevenLabs w/ AVSpeech fallback. *Depends: J1.* Cheapest joy-per-line in the plan.
- **J3 — Voice in.** PTT + STT conversation loop. *Depends: J2.*
- **J4 — Hands.** Overseer sends messages/interrupts through lease + oracle + verified typing with provenance and confirm tiers. *Depends: J1, mn-e49b22, mn-610814.*
- **J5 — Jarvis polish.** Wake word, barge-in, long-horizon memory of announcements, and the co-work mode hook (shared session, second voice — the "work for Dad" future).

## Open decisions (defaulted, flag to change)

- Brain model: Sonnet-tier for summaries/chat, escalate per-question — cost control for an always-on agent.
- STT: local Whisper (private, offline) over cloud STT. PTT before wake-word.
- The daemon lives as a Holy-managed helper process (launchd agent installed like the hook bridge), not inside the app process — restartable, crash-isolated, updatable independently.

## Conversation & Attention Design (added 2026-07-16, prompted by Erik's son's question)

*"How does it know what's important, how does it organize four completions in voice, and how does it know which one I'm replying to?"* — the right questions; voice is a serial interruptive channel fed by a parallel system. Three mechanisms:

**1. Salience tiers (explicit, legible — no ML magic in v1):**
- INTERRUPT NOW: needs-user, failures, sessions the user explicitly subscribed to ("tell me when X finishes").
- NEXT PAUSE: completions on Today-pinned or recently-interacted sessions.
- BRIEFING ONLY: routine background completions — held for digest or on-demand "morning brief".
- NEVER: the currently-focused session (user saw it), muted sessions, working-state churn.
Inputs already exist: state kind, Today pins, notes, interaction recency, per-session settings. J5 may learn from engagement; v1 must always be able to answer "why did you tell me that?"

**2. Coalescing and digests:** a 20–30s settle window after the first event; siblings coalesce into ONE ranked utterance, most important first, capped at 3–4 items plus "and N more — details on any?". Single event → single line. Briefings are a separate mode: on-demand walk of everything since last ask (overnight work is a briefing, not 3 AM interrupts).

**3. Grounding — the focus stack:** the session(s) last mentioned become the conversational focus; bare replies bind to focus; explicit names override; focus decays after minutes of silence. Cost-asymmetric ambiguity rule: read-only answers may best-guess but MUST echo the resolved name ("Flip 5 — still running tests") so wrong guesses self-announce; ACTIONS (anything that types into a session) never guess — ambiguity triggers a one-line disambiguation, and J4's confirm-by-default echo ("Send 'continue' to flip 5?") doubles as grounding repair. A stale "yes" can never fire into the wrong agent.

**Substrate:** one announcement queue (event, session, tier, timestamp) with the existing notification watermarks (nothing repeats), one focus stack, one speech scheduler draining by tier. Phase placement: queue/tiers/digest logic is brain-side → J1 (applies to the text panel too); interrupt-vs-pause speech scheduling → J2; focus stack + disambiguation → J3; action confirmation echo → J4 (already specced).

## Red-Team Findings (self-adversarial pass, 2026-07-16)

1. **Confident silence is the worst failure.** No events ≠ all fine (dead hooks, crashed daemon, pre-enable sessions, stalled agents emit nothing). REQUIRED: a health layer — per-session last-heard heartbeats, and the Overseer reports gaps ("3 sessions silent 2h; hooks may be dead"). Silence is a reportable state.
2. **Who supervises the supervisor:** queue + focus stack must be persistent; startup quiescence + event-storm damping required (restart sweeps are proven real); quota exhaustion must announce itself, never degrade silently.
3. **Authority laundering:** summaries voice agents' self-reports as fact. All summaries attribute ("flip 5 REPORTS tests pass"); high-stakes claims cross-check (exit codes, git) before assertive phrasing. Injection fence stops tools-from-text but NOT words-in-Jarvis's-mouth — summary content is steerable by watched sessions; treat spoken certainty as a privilege the evidence earns.
4. **Cloud TTS leaks content:** ElevenLabs receives summaries (code/paths/secrets). Redaction pass + local-voice-only scope setting required.
5. **Fuzzy matching vs duplicate roster names is a contradiction** (eight "Aldebaran Group" rows). Unique speakable aliases are a hard J3 prerequisite.
6. **Confirmation fatigue erodes the safety default** — expect global relaxation week one; design for it (per-action-class relaxation only, never global; periodic re-confirmation of relaxed classes).
7. **Hands are gated on two unsolved problems:** the safe-input oracle (per-sample pane state provably ambiguous) and paste integrity (mn-c3b48a). Severe narrowing: the Overseer NEVER answers y/n-shaped prompts — permission gates are human-only and it cannot prove what a pane is asking; it only composes messages at a provably idle REPL.
8. **Salience inputs include recency, which is currently fake** (mn-596f61/mn-a0406e) — those fixes are hard prerequisites for correct interrupts.
9. **Tuned constants are guesses** (settle window, focus decay) — ship with telemetry on missed/annoying announcements so they can be tuned from evidence.
10. **Scope honesty:** J1 is the largest phase (daemon lifecycle + SDK + health + persistence + panel); always-on model + TTS costs are real and need a budget line. Meta-risk: as the voice gets good, the fallback UI atrophies — indicator quality must remain independently accepted (mn-8179b6 et al.), never "Jarvis will tell me."

## PIVOT (2026-07-16, Erik + son): The Second Chair — co-coder, not Jarvis

**Decision:** autonomous driving is out — "that's just going to lead to a huge mess." The build is a **co-partner living beside the session the human is looking at**: an outside observer with third-party perspective on the focused session and on Holy Ghostty as a whole. It reads ahead, discusses, drafts — **the human always presses Enter.**

**Why this is stronger (red-team deltas):** deletes the safety-critical oracle (human eyes gate every send), deletes confirmation fatigue (reading the draft IS the confirmation), replaces the focus stack with shared gaze (grounding by UI state: "that reply" = the one on screen), defangs authority laundering (claims made in dialogue over a visible transcript are instantly checkable), and resolves cross-session references by state-change ("the new green light in CODEX") instead of fuzzy names. Every hard unsolved dependency was downstream of removing the human; putting the human back dissolves them.

**Shape:**
- **C1 — Focus-follow reader + chat panel.** Selecting a roster row binds the companion to that session: ingests the tail (windowed; lazy summarization — context economics are the #1 cost risk), follows deltas live, converses about it in a side panel. Tracks the human's INTENT per session ("my target goal / my concern") as a first-class ledger the critique is measured against.
- **C2 — Draft-to-input, human Enter.** "Write a reply" → draft shown in panel → insert into the session's input line via sendText (no newline — primitive exists today, Ghostty.Surface.sendText). Human reviews in-place, presses Enter. Paste-integrity bug degrades to annoyance (visible before send). Advisory-only idle check; never blocks.
- **C3 — Roster-aware pull Q&A.** While focused on A, ask about B ("what's that green light about?") — answered by observation via holyctl observe, attributed ("Agent Do REPORTS…"), without stealing focus.
- **C4 — Voice (optional layer).** PTT + TTS on top of the same panel conversation. Pull-based; the push/announce machinery of the Jarvis plan is NOT required for this build.
- **Persona requirement:** a colleague with standards — must be able to disagree ("it did NOT cover your migration concern"); an agreeable mirror is worthless as a third-party view. Anchoring is the residual cognitive risk.

**Survivals from the Jarvis plan:** the injection fence (it still reads agent output — data, never instructions), attribution discipline, redaction before cloud TTS (C4), quota-death must announce itself in-panel. The autonomous hands (old J4) and push announcements are PARKED, not deleted — the Wave-4 control plane remains tracked for a future trust level; nothing in this build forecloses it.

### C2.5 — Human-directed relay (added same day; Erik's planner/coder case)

Four Aldebaran sessions: orchestrator + coders. From another focused session: "C finished — tell the orchestrator, read me its reply … paste that into C and press Enter." Decision + content human; only transmission delegated. The trust rung between C2 and the parked autonomy — and how the machinery earns its way toward any future autonomy discussion.

Mechanisms: target readiness proven by the triggering finished-event and re-checked at send time (refuse on working/needs-user/unknown; permission prompts are never a clean REPL); two-phase verified send (type → capture-pane byte-verify → Enter; abort loudly on mismatch — converts unsolved paste corruption into a detected abort); non-empty input line → report, never append; templated-and-shown relay notes, verbatim-approved payloads, provenance prefix, full audit.

**The cliff, named:** every Enter is purchased by a human utterance. One hop per approval. No standing orders, no chained orchestrator↔coder auto-bouncing — that is Jarvis by increments, the exact mess the pivot rejected. Tracked: mn-596e37.

## Architecture split (2026-07-16, ratified by Erik): agent-do owns capabilities, Holy owns embodiment

One rule explains every placement: **agent-do owns abilities, Holy owns the body.** Same seam as the dictate ruling (engine in agent-do, resident listener out) and the same seam agent-do itself enforces (portable, harness-agnostic, CLI-shaped) versus Holy (the embodied cockpit).

| Component | Home | Why |
|---|---|---|
| Senses: streaming STT (`dictate`, TeleFollower-derived), TTS (`say`), transcription | agent-do | Already landing there; voice-in-any-app is its jurisdiction; reusable by Chris/Codex/bare terminals |
| Eyes over Holy sessions: `holyctl list/observe` | Holy-owned, CLI-shaped | Holy's data, but a CLI surface so anything can consume it (incl. the chair, incl. over SSH) |
| Eyes over work-OS state: coord presence, manna boards, gh claims | agent-do | Already exists; the chair drinks from both eyes |
| Brain: conversation, intent ledger, summarize/critique — `agent-do chair serve` | agent-do provides the engine; **Holy supervises the residency** (spawn/lifecycle, like the hook bridge helper) | Engine portable (`--context holyctl` today, `--context coord,manna` tomorrow); residency belongs to the app that owns the body |
| Face & hands: panel UI, focus-follow ("what is Erik looking at" — GUI-only knowledge), draft into the visible input line, the human Enter | Holy only | Shared gaze was the entire pivot; a chair with no body is not a Second Chair |

**The protocol seam (the one honest cost):** a small versioned JSON protocol between Holy and the chair process — `focus-changed`, `observe`, `draft`, `speak`, `user-said` — same versioning discipline as the agent-state envelope. Costs: two-process lifecycle + version skew between repos; both already paid once by the hook bridge (generation-stamped self-repair is the template).

**What this buys:** the chair works beside Codex sessions, bare terminals, and MacBook→Studio over SSH; Holy is its best body, not its only one. Holy's scope stays terminal-shaped. The brain is testable headless with a fake context provider.

**Phase impact:** C1 splits across repos when work starts — chair engine (agent-do) + panel/focus/supervision (Holy). C2 stays pure Holy. C3 = chair consuming multiple context providers. C4 = chair consuming `dictate`/`say`, no voice code in Holy.

**For the Codex red-team, attack here first:** the protocol's failure modes (chair crash vs Holy crash, replay after restart, focus-event races during roster churn — cf. the launch focus-sweep bug), context-provider abstraction leaking Holy-isms, version-skew self-repair, injection fence ownership when the brain lives outside the app that renders its words, and whether "Holy supervises an agent-do binary" creates an update-ordering trap (Holy updates before agent-do or vice versa).

## Codex Review Outcomes (2026-07-17) — accepted, with one partial dissent

Verdict from the independent review: "yes, you are onto something. But the current plan is not build-ready." All six blocking findings verified and accepted; tracker repaired the same day. The sharpened invariant replaces the original: **agent-do owns portable intelligence and reusable capabilities; Holy owns authoritative session data, user attention, durable intent, and every terminal side effect.**

Applied:
1. **Content path fixed.** mn-e59548 observe is metadata-only by design (verified) — C1's transcript dependency was impossible. Embedded use: Holy pushes bounded, consented screen snapshots/deltas directly over the protocol; holyctl stays metadata-only; a permissioned `sessions tail` is a later standalone option.
2. **Always-on machinery deleted.** The pull-based pivot removed the need for the Jarvis residency stack — launchd daemon, announcement queue, salience tiers, digests, watermark replay, heartbeats all existed so an autonomous announcer could never miss an event while unattended. A companion that only matters when the panel is open needs none of it: chair spawns with the panel (`--stdio`), dies with it, crash = respawn + fresh snapshot. Salience/digest design is parked WITH push-announcements, not lost.
3. **Human-Enter enforced structurally.** sendText passes raw bytes (verified) — a draft containing \n auto-submits. C2 now specs the insertDraft boundary: explicit user Insert action, CR/LF/ESC/control-byte rejection, focus-epoch validation, size cap, and NO enter verb anywhere in the protocol.
4. **voice speak eval bug** (verified: shell-string + eval on the text) filed as P1 SECURITY on the agent-do board (mn-b17dc6); C4 blocked on it. Real name `voice speak` used; no invented `say`.
5. **Hook bridge ≠ supervision precedent** — accepted; it's an install/ownership template only. Panel-lifetime child needs a real (but now tiny) process contract.
6. **Brain de-powered and de-Claude'd.** Provider-neutral typed streaming adapter; no shell, no tools, no credentials — the injection fence becomes a capability boundary. Privacy fence extended to the cloud LLM itself, not just TTS.

Protocol upgraded to the reviewed shape (C0, new issue mn-c85876): JSONL over stdio, hello/version negotiation, request IDs, monotonic sequences, focus_epoch, snapshot/delta, cancellation, backpressure, degraded states, structurally no send/press/enter.

Execution graph now: C0 → C1 → C2 = **core complete** (tracker blocks only on C2); C3 and C4 optional; C2.5 relay re-parked as a separate trust program.

**Partial dissent, preserved for the future C2.5 discussion:** the review says the relay must restore "full control-plane prerequisites." The C2.5 design's narrower gate (readiness proven by the committed finished-event that started the conversation, re-checked at send time, plus byte-verified two-phase send) is a deliberately smaller claim than a general safe-input oracle — that disagreement is real and unresolved, and correctly parked rather than settled by either side today.
