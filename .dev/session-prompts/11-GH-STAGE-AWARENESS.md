# 11 — GH stage awareness: every PR row knows whose move it is

Ratified by Erik 2026-08-13 (~11:55): "approve the enrichment, build 1+2+3".
Options from the design conversation: (1) deterministic stage verb per PR
row, (2) Your move / Waiting on others split with an honest badge, (3) a
loaded shell command behind a human Enter. Option 4 (stage deltas) was
explicitly deferred.

The gap, with receipts (2026-08-13): `agent-do gh pr 88` already returns
`review_decision: APPROVED`, `merge_state: CLEAN`, `checks: 3/3 passed`,
`review_requests: []` — but `gh inbox --json` (what the panel consumes)
carries only title/author/reasons/age. Stage awareness exists one layer
down and is dropped at the sweep. This is a carry-through problem.

Seam (same law as ever): agent-do owns portable intelligence — the
deterministic verb mapping lives in the ENGINE so CLI users get it too;
Holy renders the pinned contract fail-closed and degrades honestly when
the fields are absent (old CLI = today's rendering, no error).

## Cross-repo gate

- agent-do board carries the sweep enrichment (work order below).
- holy-ghostty board carries the rendering slice, gated on the enriched
  contract landing in a LIVE invocation (mn-2a7544 law: pin from live,
  never memory). Holy may build ahead against the spec below, but the
  final fixture must be re-pinned from a real `gh inbox --json` run
  before the item closes.

## WORK ORDER — agent-do lane (paste from here down)

Mission: enrich `agent-do gh inbox --json` PR items with stage fields and
a deterministic next-action verb. The GraphQL sweep already fetches each
PR node — add fields to the SAME query; zero additional API calls. The
REST fallback path emits the new fields as null (honest absence, never a
guess).

Contract — each PR item gains exactly these keys:

```json
"review_decision": "APPROVED" | "CHANGES_REQUESTED" | "REVIEW_REQUIRED" | null,
"merge_state": "CLEAN" | "DIRTY" | "BLOCKED" | "BEHIND" | "UNSTABLE" | "DRAFT" | "HAS_HOOKS" | "UNKNOWN" | null,
"checks": {"passed": 0, "failed": 0, "pending": 0, "total": 0} | null,
"review_requests": 0,
"next_action": {"verb": "…", "detail": "…", "yours": true, "command": "agent-do gh merge 88"} | null
```

`next_action` mapping — deterministic, first match wins, engine-owned
(consumers must never re-derive it):

1. draft → `{"Draft", "still being written", yours: false, command: null}`
2. merge_state DIRTY → `{"Resolve conflicts", "branch cannot merge",
   yours: <authored by viewer>, command: null}`
3. authored + review_decision CHANGES_REQUESTED → `{"Address review",
   "changes requested", yours: true, command: "agent-do gh pr <n>"}`
4. authored + checks.failed > 0 → `{"Fix checks", "<failed> of <total>
   failing", yours: true, command: "agent-do gh checks <n>"}`
5. authored + APPROVED + merge_state CLEAN → `{"Merge", "approved,
   checks green", yours: true, command: "agent-do gh merge <n>"}`
6. not authored + reason review_requested → `{"Review", "your review
   requested", yours: true, command: "agent-do gh pr <n>"}`
7. authored, none of the above → `{"Awaiting review", "no review yet" |
   "<k> reviewer(s) pending", yours: false, command: null}`
8. anything else → null

Laws:
- `yours` means exactly "the ball is in the viewing user's court".
- `command` is DATA. Consumers type it into a shell behind a human
  Enter; nothing ever executes it. Command strings use the agent-do gh
  verbs only (pr / checks / merge).
- Numbers in `checks` come from the check rollup, never invented; a PR
  with no checks gets `checks: null`, not zeros (bounds discipline).
- Enrich bot-authored rows uniformly (consumers may collapse them).
- Add `"stage_contract": 1` inside the existing `sweep` envelope so
  consumers can gate on it explicitly.
- Old consumers must be untouched: additive keys only, no renames, no
  reordering semantics.

Verification before done:
- Fixture pinned from a LIVE `gh inbox --json` run carrying at least one
  row in each of states 1, 5, 6, 7 (create scratch PRs if needed).
- Unit tests over the mapping table — one per precedence rule plus the
  precedence collisions (draft+approved stays Draft; DIRTY+approved
  stays Resolve conflicts).
- Sweep wall time within noise of the current ~3.7s baseline (measure
  before/after, record both numbers in the item ledger).
- `./test.sh` green including `harness contracts validate` (95/95).

Board: claim the item created for this on the agent-do board before
work; commit with its `Manna:` trailer (trailer shares one paragraph
with Co-Authored-By).

## Holy rendering slice (this repo)

- `HolyGitHubInboxItem` decodes the five new keys via decodeIfPresent —
  absent fields = legacy contract, rendering unchanged.
- Row anatomy gains a stage line: verb (semibold) — detail, tinted only
  when `yours` (words + position first; tint reinforces, never carries).
  Reason chips the stage line restates are suppressed; draft chip stays.
- Sectioner, when items carry `next_action`: two groups — "Your move"
  (badge-counted) and "Waiting on others" — plus the existing bot digest
  and Other attention. Without `next_action`: legacy sections unchanged.
- Shell button renders only when the row's repo matches the focused
  session's repo (an honest cwd exists); it spawns via
  `HolyBriefSpawn.typedCommandURL` with the engine's `command` string —
  typed, never executed.
- Badge law upheld: only "Your move" feeds the badge.

## Explicitly out of scope

- Stage deltas / since-last-look (option 4) — deferred until pulled.
- Any change to the alerts or manna sources.
- AI phrasing of verbs — the mapping is pure and lives in the engine.
