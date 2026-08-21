# Holy Ghostty — Session Handoff (2026-07-14)

**Audience:** Codex agent, fresh-eyes review of the sidebar activity-detection saga.
**Ask:** Audit the four fixes below for correctness and for the next latent false positive/negative. The detection is text heuristics over pane content; every fix this session was reactive to a live-observed failure. A skeptical re-derivation of the whole pipeline is wanted.

## 1. Architecture (unchanged, but now fully mapped)

Sidebar activity orb pipeline, all in `macos/Sources/HolyGhostty/`:

```
Ghostty.SurfaceView.cachedVisibleContents (visible pane text)
  └─ HolySession.refreshDerivedState()            Session/HolySession.swift:697
       ├─ previewText()      — 8-line tail, DISPLAY + persistence only
       ├─ detectionText()    — 40-line tail, feeds everything below   [NEW]
       ├─ updateVisibleActivity() — 4s freshness gate (sig = 16 meaningful lines + title)
       ├─ detectSignals()    — regex/marker heuristics → [HolySessionSignal]
       │    rank: approval=0 < progress=1 < failure … (first = primary)
       ├─ classifyPhase()    — signals → phase (working/waitingInput/…)
       └─ HolySessionRuntimeTelemetryParser.telemetry() — primary signal → activityKind
  └─ HolyWorkspaceStore.attentionPresentation()   Workspace/HolyWorkspaceStore.swift:2162
       priority: failed > planningQuestion > approvalLooksExplicit(hand) >
                 swarming > stalled > working(throbber) > newReply(blue dot,
                 needs fresh lastAgentFinishedAt) > waitingQuiet/sleeping/dormant > done > quiet
  └─ HolySessionRosterView — orb rendering        Workspace/HolySessionRosterView.swift:1524
```

Key gates: most busy evidence requires `previewChangedRecently` (pane changed within 4s — note **user typing at the prompt keeps this gate open**). `approvalLooksExplicit` scans telemetry headline+detail+nextStepHint for {approval, approve, confirm, allow, permission, continue?, [y/n]} — and the generated headline "needs approval or confirmation" self-satisfies it.

## 2. Files Modified

| File | Change |
|---|---|
| `macos/Sources/HolyGhostty/Session/HolySession.swift` | All four fixes (details §3) |
| `macos/Tests/HolyGhostty/HolySessionLiveStatusTests.swift` | 2 tests → 20 tests, every fix has regression coverage with real captured lines |
| `.gitignore` | added `.handoff/` |

## 3. Bugs Fixed (chronological, each observed live before fixing)

| Commit | Symptom | Root cause | Fix |
|---|---|---|---|
| `4c00eadbe` | Workflow-running session showed no spinner; working sessions flickered throbber↔blue dot | Vocabulary gaps: "Waiting for N dynamic workflow to finish", ticker "2/5 agents done · 7m 12s · ↓ 598.5k tokens", spinner frames ✳✶✽ missing from strip set, invented gerunds ("Finagling…") not in verb list | New rules in `isLiveAgentStatusLine` (workflow-wait phrase, elapsed+token counter), `[0-9]+/[0-9]+ agents` swarm rule, full flower frame set, glyph+gerund+ellipsis busy rule |
| `ef0bb1ef4` | Idle session flicked hand↔throbber while user typed; no blue dot | (a) Claude Code freezes last spinner frame into terminal title ("✳ Fix missing activity") — adding ✳ to title prefixes made frozen titles busy whenever preview changed (= typing). (b) Own transcript prose quoting "2/5 agents done" matched the swarm rule. (c) Marker scan read the user's draft: typing "fix confirmed" matched `confirm` | Flower frames removed from title set (title-exempt, still strip from line bodies); new rules glyph-anchored to line starts (`agentLiveStatusGlyphPrefixes`); `❯` (U+276F) recognized as prompt line; prompt lines excluded from marker scans |
| `938b6f621` | Hand STILL appeared on fixed build with draft "blue dot confirmed…" | `agentWaitingEvidence` returned the prompt line **verbatim** as signal detail → flowed into telemetry detail → `approvalLooksExplicit` matched "confirm**ed**" there. Second leak path around the first fix | Waiting signal returns canonical "Prompt is ready for your next message"; planning-question evidence also filters prompt lines |
| `3d5262615` | Actively-working session (flip 5) with todo checklist showed no throbber | **`previewText()` caps detection input at 8 non-empty lines** — every `suffix(14/16/18)` in the matchers scanned a window that never held >8 lines. Claude Code renders the spinner ABOVE todo checklists; 6 todos + prompt + footer pushed it out | New `detectionText()` 40-line window feeds detection; display preview stays 8; busy scan depth 14→24 |
| (post-review) | Codex findings 1+2: telemetry parser extracted next-step hints from prompt drafts ("confirm" → "Review the prompt and confirm approval" → hand); freshness signature watched only 16 lines while busy scans read 24 (spinner at 17–24 could flap the gate) | Parser's `lastMeaningfulLine` had no prompt-line filter; signature/scan depths drifted | Parser skips prompt lines when picking evidence; shared `agentDetectionScanDepth = 24` constant for both signature and scans |
| `cdad159c8` | Hand shown mid-turn while agent streamed its reply (session_events 14:02–14:04 proved approval classification during active work) | (a) Background-shell wait footer "✻ Sautéed for 1m 34s · 1 shell still running" matched no working rule (past tense, no parens/tokens); (b) `extractNextStepHint` harvested from arbitrary last-line text — the agent's own streamed prose containing "confirm" became an approval hint (fourth prose-leak path) | Glyph-anchored "N shell/task/agent still running" rule; hints derive only from an actual approval signal's own detail |

## 4. Debugging Technique (the load-bearing discovery)

Ground truth for attention flips lives in the workspace DB — no instrumentation needed. **Caveat (per Codex review):** `payload_json.preview` stores `session.preview` — the **8-line display preview** (`HolySessionEvent.swift:186`), NOT the 40-line detection window. It cannot retrospectively show a spinner that sat above those 8 lines; for that, capture the live pane via tmux. Deliberately not widened: event volume made the DB hit 49 GB once ([[db-maintenance-ops]]).

```bash
DB=~/Library/"Application Support"/org.holyghostty.app/HolyGhostty/holy-ghostty.sqlite3
# Find session id from tmux identity (get uuid via: tmux display-message -p '#{session_name}')
sqlite3 "$DB" "select id from sessions where launch_spec_json like '%<TMUX-UUID>%'"
# payload_json records activityKind, evidence, AND the full pane preview at every flip
sqlite3 "$DB" "select datetime(occurred_at,'localtime'),
  json_extract(payload_json,'\$.activityKind'), payload_json
  from session_events where session_id='<SID>' order by occurred_at desc limit 20"
```

Live pane capture: `tmux capture-pane -p -t <pane>` (agent shells inherit `$TMUX_PANE`).

## 5. Verification Commands

```bash
cd macos
# 20 detection tests (each encodes a real captured line)
xcodebuild test -scheme Ghostty -only-testing:GhosttyTests/HolySessionLiveStatusTests -destination 'platform=macOS' -quiet
# Full suite — was green (~370 cases) after every commit
xcodebuild test -scheme Ghostty -only-testing:GhosttyTests -destination 'platform=macOS' -quiet
# Running build freshness (install script pkills only the GUI; tmux server detached, sessions survive)
pgrep -f '^/Applications/Holy Ghostty.app/Contents/MacOS/holy-ghostty' | xargs -I{} ps -p {} -o lstart=
stat -f '%Sm' '/Applications/Holy Ghostty.app/Contents/MacOS/holy-ghostty'
```

Installed and running at session end: `3d5262615` build (process + binary 11:22:50). Rebuild+install: `./scripts/install-holy-ghostty.sh && open -a "Holy Ghostty"` — routine, safe mid-swarm.

## 6. Known Remaining Issues / Review Targets for Codex

Ordered by suspicion level:

1. **The pipeline is reactive whack-a-mole by construction.** Four live failures, four patches. Attack surfaces a fresh reviewer should re-derive: (a) transcript **code blocks** quoting a footer line verbatim at line start (glyph anchor does NOT protect — e.g. this saga's own commit messages rendered in a pane); (b) interrupted turns — does Esc leave a frozen `✻ …(… tokens)` line that stays "busy" while the user types (typing holds the 4s gate open)?; (c) Codex/OpenCode footer shapes — all new rules are Claude-Code-shaped; verify CODEX-group sessions still detect via the older "esc to interrupt" rules.
2. **Deeper windows widen false-positive surface.** `detectionText` 40 lines + busy scan 24 + planning scan 16: older transcript remnants ("plan mode", stale spinner lines) now stay in range longer. Nothing observed yet; worth adversarial thought.
3. **`agentWaitingEvidence` now returns a constant string** — anything downstream that displayed the prompt context (tooltips via `attentionDetail`) now shows "Prompt is ready for your next message". Check for UI regressions.
4. **`newReply` blue (0.30,0.76,1.0) ≈ `workingBlue` (0.25,0.72,1.0)** — `HolySessionRosterView.swift:1259`. Static "recent reply" dot is visually near-identical to the working throbber's color. Design fix pending; Erik aware.
5. **`previewStability`, budget parser, `inferredRuntime` still consume the 8-line `nextPreview`** — deliberate (their evidence is bottom-anchored), but evaluate whether stability's stall detection should share the 40-line window.
6. **`isTmuxStatusLine` only filters lines starting with `[`** — other tmux status formats would leak into meaningful lines.

## 7. Next Steps

1. Codex: adversarial review of `HolySession.swift` detection functions (lines ~1400–1750) against §6; every new rule has a test hook (`*ForTesting` in the `#if DEBUG` block, ~line 1990).
2. Watch flip-5-style sessions (spinner above tall checklist) and workflow-wait sessions on the `3d5262615` build; `session_events` will record any residual misclassification.
3. If another false positive appears: capture pane + query `session_events` FIRST (§4), then extend `HolySessionLiveStatusTests` with the exact line before touching matchers.

## 8. Related Memory

Claude-side memory notes (not in repo): `roster-activity-detection.md`, `db-maintenance-ops.md` under `~/.claude/projects/-Users-erik-Custom-Coding-holy-ghostty/memory/` — same facts as §4/§6 in condensed form.
