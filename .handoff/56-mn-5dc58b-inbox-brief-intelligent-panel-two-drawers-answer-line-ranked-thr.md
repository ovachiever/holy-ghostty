---
workflow: 2
manna: mn-5dc58b
track: mn-70875b
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[INBOX][BRIEF] Intelligent panel: two drawers, answer line, ranked threads — renders `agent-do brief holy`'
inputs: []
binding: sha256:d58f268d36a4973f7a06648f5e01b7e542842020f61f364ac70d3944649cba4c
---

# Handoff: [INBOX][BRIEF] Intelligent panel: two drawers, answer line, ranked threads — renders `agent-do brief holy`

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-5dc58b
```

## Scope

[INBOX][BRIEF] Intelligent panel: two drawers, answer line, ranked threads — renders `agent-do brief holy`

## Inputs

- None declared.

## Work order

PROMPT: /Users/erik/Custom-Coding/holy-ghostty/.dev/session-prompts/10-INTELLIGENT-INBOX.md — the ratified design, REVISED 2026-08-11: the V1/V2/V3 ladder is dead per Erik ("build v3 from the get-go; find what done looks like and work backwards"). This item renders the FULL contract, one target.

Scope: the panel becomes the brief's renderer. Two-drawer split (Needs me = verb-phrased, badge-counted; Library = collapsed one-line browse of everything); the answer line renders the contract's paragraph with its grounding mode visible (model vs deterministic, annotated); thread rows replace scattered per-source rows (rank decides density: hero/standard/compact); since-you-last-looked seam from the delta block; suggestions render as loaded verbs behind a human Enter (the command is data — display, copy, prefill; NEVER execute); headers earn their row (name · count · sweep-age · health from sources/annotations — a degraded source is a header note, not a fake content row); ⌘P lens with question mode (mn- jumps to board row, # to PR, prose routes to brief ask); pin/snooze/read-state wired to the contract's read_state; quiet aging (contrast decay, auto-collapse into counts).

GATE STATUS 2026-08-11 10:57: mn-f79edc (agent-do board) is functionally complete and LIVE — the contract is pinned from a real invocation at .dev/brief-holy-capture-2026-08-11.json (12,164 bytes, contract:1, keys: annotations, caller, contract, delta, generated_at, paragraph, ranking, read_state, receipts, sources, suggestions, suggestions_total, threads, threads_total; paragraph mode "model", delta mode "read_state", sources coord/git/github/manna/reconcile/sessions). Its commit awaits the full agent-do suite; do not close THIS item until the engine's commit lands and the render runs against the committed CLI.

Disciplines: parse fail-closed on contract drift with full-error logging (mn-b2e2e9 lesson); the capture file is the fixture seed, but done-when includes rendering the real CLI output; alert delivery path untouched; collision alerts stay dead; manna scope stays focused-only.

KNOWN ENGINE NIT to feed back to mn-f79edc: the suggestion engine reads any Manna: trailer as landed work — a board-staging chore commit (e.g. this item's own staging commit) triggers a "close it" suggestion for unstarted work. Same trailer≠landed class the 2026-08-07 audit flagged in reconcile.

PIVOT 2026-08-12 06:05 (Erik, decisive): "I don't like the right-menu any more than it was before, probably less... I simply want: GH notifications for the project I'm in, manna for the project I'm in, and a gh-global tab." The brief-instrument rendering (sentence, NEXT horizon, drawers, suggestions) is REMOVED from the panel — two critique rounds produced something that says nothing he needs. The panel is now three surfaces: [This project] tab = focused repo's GitHub rows (slug-filtered with boundary-safe matching) + focused board's manna + alerts; [All GitHub] tab = the full global sweep. HolyBriefFeed goes dormant in the app (no panel refresh, no idle model spend); the contract, feed, triage, and views files remain for CLI consumers and any future re-entry. Lesson: the design reviews optimized presentation of a feed Erik never wanted — the spec was three sentences long all along and came from him.

> Legacy migration source: ".dev/session-prompts/10-INTELLIGENT-INBOX.md"

# 10 — The intelligent right-hand bar (`agent-do brief` + Holy rendering)

Design ratified in conversation with Erik 2026-08-11 (~09:50-10:00). This file
is the campaign's source of truth; board items point here. Naming settled by
Erik: the engine is the public agent-do tool **`brief`**; Holy is a TARGET
(`agent-do brief holy`), not the namespace — brief works with any tooling AND
Holy specifically.

## The thesis

The panel stops being a feed you read and becomes a colleague who already
read everything. Correlation happens before pixels: the bar opens with a
computed paragraph, renders threads instead of scattered rows, learns what
Erik acts on, pre-writes next moves behind a human Enter, and answers
questions about the whole estate with receipts.

## Architecture (ratified seam, from the Second Chair review)

agent-do owns portable intelligence; Holy owns attention surfaces and side
effects. The brain is `agent-do brief` (public tool, taxonomy blessed by
Erik 2026-08-11 in conversation — "agent-do brief holy... that way brief can
be used with any tooling AND holy specifically"). Holy renders a pinned JSON
contract exactly like `gh inbox` today: fail-closed parse, degraded row on
contract drift, full-error logging (lesson of mn-b2e2e9: the comments:null
drift cost three diagnosis rounds — version the contract explicitly).

## Verb family (agent-do side)

- `brief now` — human-readable estate brief for any terminal user.
- `brief threads [--json]` — joined thread objects. A thread links:
  gh PR ↔ manna item (Manna: trailers + branch/lane inference) ↔ live
  session (coord + sessions index) ↔ last commit ↔ claim state.
- `brief ask "<question>"` — question over the estate (sessions search,
  git log, board ledgers, zpc lessons); every claim carries a receipt id.
- `brief holy --json` — composite contract for the Holy panel: threads,
  delta-since-timestamp, suggestions, paragraph. Caller passes context:
  `--focused-repo <repo root PATH>` `--focused-board <path>` `--since <iso8601>` — PATHS, not slugs (engine resolves relative; verified 2026-08-11).

## The honesty covenant (non-negotiable)

The brief asserts only what a receipt supports (commit hash, mn-id, PR ref,
event id). Unknown stays unknown. A degraded source is an annotation on the
brief, never a guess and never silence. No model output enters the contract
unless grounded in the structured inputs — the paragraph cites the same
receipts the threads carry. Numbers come from the joined data, never the
model (bounds discipline applies).

## Definition of done (revised 2026-08-11: the ladder is dead)

Erik, same day the ladder was ratified: no V1/V2/V3 — "just build v3 from
the get-go; find what done looks like and work backwards from that."
Versioned ladders breed muck: interim contracts, throwaway renderers,
drift between rungs. One target, one contract, shaped for the finished
colleague from the first commit.

Done means, sitting at the bar:
- The answer line is a model-voiced paragraph grounded in receipts — or,
  with no model configured, the deterministic sentence from counts,
  annotated as such. Same contract field either way; the grounding mode
  travels with the text.
- Threads join everything: gh PR ↔ manna item (Manna: trailers,
  branch/lane inference) ↔ live session (coord + sessions index) ↔ last
  commit ↔ claim state.
- Threads are ranked and every rank explains itself — reasons ride with
  the score, learned from observed behavior (acted-fast vs ignored vs
  snoozed), recorded zpc-style.
- Delta since the caller's last look sits above the seam; calm below.
- Suggestions are loaded verbs behind a human Enter (unblock, claim,
  convert — reconcile desyncs), each carrying its exact command as data,
  never executed.
- `brief ask "<question>"` answers over the estate (sessions search, git
  log, board ledgers, zpc lessons), every claim carrying a receipt id.
- Pin/snooze hold; snooze-until-changed clears itself; stale rows age
  quietly into counts (contrast decay, auto-collapse).
- Read-state survives: DB first, cross-machine later via the tmux
  user-option channel notes/pins already use.

## Build order (a dependency graph, not phases)

Trunk — everything hangs off it:
1. The receipts spine + thread join model. Every fact carries its receipt
   id (commit hash, mn-id, PR ref, event id); every event is timestamped
   so ranking has features from day one.
2. The contract, full shape, version 1, once: threads (with rank +
   reasons), delta, suggestions, paragraph + grounding mode
   (model|deterministic), annotations, read-state. A capability not yet
   live is an honest degradation in the payload (`"ranking": {"mode":
   "recency"}`), never an absent field — Holy renders one contract
   forever and drift never happens.

Fan-out — parallel once the trunk stands:
- **Voice**: chair-kernel model adapter behind `brief now` / `brief ask` /
  the paragraph. Provider-neutral per the C0 protocol work; no shell, no
  tools, no credentials in the model's hands.
- **Judgment**: behavior journal (acted/ignored/snoozed, with reasons)
  feeding the ranker; the ranker must be able to explain itself.
- **Continuity**: pin/snooze/read-state store; snooze-until-changed.
- **Rendering**: Holy renders the real contract — two drawers, answer
  line, density ladder, seam, ⌘P lens with question mode (`mn-` jumps to
  board row, `#` to PR, prose asks), quiet aging.

## Holy rendering principles (from the 13-idea session, Erik-picked spine)

1. Two drawers: "Needs me" (verbs, badge-counted) vs "Library" (nouns,
   collapsed one-liner, browse anytime). If a row can't be phrased as an
   action, it is inventory.
2. Answer line first; "Nothing needs you." is the proudest state.
3. Density ladder: hero (top item) / standard / compact-collapsed — rank
   decides pixels.
4. Since-you-last-looked seam (hairline divider; delta above, calm below).
5. ⌘P is a lens: type-to-filter everything; j/k/enter triage.
6. Headers earn their row: name · count · sweep-age · health annotation
   (a degraded source is a header note, not a fake content row).
7. Focus change: manna drawer crossfades with one announcement line;
   GitHub visibly holds still.

## Sequencing and boards

agent-do board carries the `brief` tool build (full verb family + contract). The
holy-ghostty board (track mn-70875b) carries the panel rendering slices,
gated on the agent-do contract landing. Cross-repo gate documented in both
descriptions (pattern: mn-84c0eb ↔ mn-7dfdb0). Contract pinning rule: build
against a LIVE invocation, never memory (mn-2a7544 lesson), and version the
payload (`"contract": 1`) so drift degrades honestly.

## Explicitly out of scope

- Any control-plane action execution (Second Chair human-Enter covenant:
  the bar loads actions, the human fires them).
- Widening manna scope beyond the focused project (ratified).
- Collision alerts in any form (retired 2026-08-10).

## Remote estates (mn-7fbb07, added 2026-08-11)

The estate is host-local by nature: boards, coord, the sessions index, and
repos live where the tmux session lives. So the brief EXECUTES on the
focused session's host, resolved from the session's existing transport
descriptor — local transport runs the local agent-do; ssh transport wraps
the identical arguments in the same BatchMode SSH rail the remote
discovery service rides, with one `zsh -lc` so the REMOTE login shell
resolves agent-do and its own voice key. Generalization rules (public
repos): no hardcoded hosts; credentials never cross the wire (each host
owns its secrets); a host without agent-do degrades honestly, naming the
host; path context is host-local by construction (it derives from the
remote session's discovered cwd). Documented requirement: install
agent-do on any host whose sessions you want briefed. Suggestion rows for
a remote estate spawn their shells on that host via the automation URL's
existing host/transport params (follow-up slice if not yet wired).

## Panel v2: the fixed decision instrument (external critique, adopted 2026-08-11)

An external design review (Erik-commissioned, screenshot-based) was adopted
nearly whole. The law it adds:
- The resting panel NEVER scrolls: one state sentence, one dominant NEXT
  move, five compact runners-up, then closed disclosure lines (changes /
  Housekeeping / Library). Rank becomes physically true — a horizon.
- State sentence is mechanically honest: "2 decisions here. 30 reviews
  elsewhere." / "Nothing needs you." / degraded variants name what is
  unreadable. Computed deterministically; the voiced paragraph is secondary.
- Labels: engine deterministically maps the verified attention reason to a
  human VERB ("Review {subject}", "Resume or release {subject}"); AI may
  compress only the noun phrase, never invent intent; original title, ids,
  and receipts live in disclosure. Client meanwhile strips [TAGS] and
  commit prefixes deterministically.
- Scope is words + position, never color alone: "Everywhere" for
  cross-project GitHub, the focused project's name for board rows; amber
  keyline as reinforcement. The words Global/Local/Session are banned.
- One row anatomy: glyph · verb+object · age / scope · why-it-waits ·
  shell button. One monochrome glyph lane; no per-source card species.
- Housekeeping bundles replace classifier vocabulary: "11 finished tasks
  ready to close", never "LANDED_OPEN".
- Typography ladder: 17/14/13/11/10, SF Pro; mono reserved for machine
  truth in details.
- Deletions: visible tags/ids/prefixes, "counts · in 0s", the advertised
  filter syntax (placeholder becomes "Search or ask…").
Engine-side slice (contract v2: per-thread verb label + scope + state
sentence) staged on the agent-do board; Holy renders client-side interim.

## PIVOT 2026-08-12: the panel is three surfaces (supersedes Panel v2 rendering)

Erik, after living with the instrument: "I simply want GH notifications for
the project I'm in, manna for the project I'm in, and a gh-global tab."
The panel now renders exactly that; the brief instrument (sentence, NEXT,
drawers, suggestions) is removed from the panel and the feed is dormant
in-app. `agent-do brief` remains a live CLI product (now/threads/ask/holy)
and mn-43932b's contract-2 work continues for CLI consumers; the panel may
re-adopt pieces later, but only pulled by need, never pushed by design.


## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-5dc58b`.
4. Commit with `Manna: mn-5dc58b` and run `agent-do manna done mn-5dc58b` only after the work is verified.
