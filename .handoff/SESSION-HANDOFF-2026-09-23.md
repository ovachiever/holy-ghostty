# Holy Ghostty: Session Handoff (2026-09-23)

Window: 2026-09-21 evening through 2026-09-23 evening, session "AIO" (claude-17a022e177104975).
Repos touched: holy-ghostty (primary), yed-prior (new), business-plan-builder, agent-do (board only).
Installed app: built from `278b1a8ff` on 2026-09-23 19:00 (`.dev/install-2026-09-23-1900.log`),
engine payload df28bebb (CI artifact from `d1d0c1100`). Every claim below has a receipt path.

## 1. Architecture changes (doctrines ratified, in force)

| Doctrine | Ruling | Where it lives |
|---|---|---|
| One grid, one painter | Text-anchored styling belongs in the core render pass, never an AppKit overlay polling the grid (overlay reverted `b5c7f1763..9699989dd`; core rule shipped as manna-gold ids, config `holy-manna-highlight`, `holy-manna-highlight-color` default `#FFB86C`) | les-3ee592; engine commits `85b2ae0b8`, `03ad7d309` |
| Vendors sell features, you keep the protocol | Nothing Claude-specific is built; the estate speaks agent-do; a lab feature is a transport or a test oracle, never protocol | discussion 09-20/21; Yed Prior README |
| No message plane | Ledger-only coordination: no inboxes, no DMs, no payload in transit. Only latency concession is the doorbell, a payload-free turn-boundary nudge | `~/Custom-Coding/yed-prior/README.md` "Coordination doctrine"; agent-do item mn-dd4384 |
| Mid-claim coordination is not reopening | A live claim may be amended (update + reseal); a closed item never reopens; the doorbell serves live claims only | discussion 09-21 |
| Full report on the ledger, note is a pointer | Worker's full final report belongs in the sealed handoff; the coord drop note only points; orchestrators read the handoff | discussed 09-23, NOT yet filed (see §10) |

## 2. Files created

| Path | Purpose | Notes |
|---|---|---|
| `~/Custom-Coding/yed-prior/` (repo, board mb-139346ab9ce790187135ebe9fa06ab31) | Product home for the governed agentic-AI platform | born at ovachiever per repo lifecycle; no GitHub remote yet |
| `~/Custom-Coding/yed-prior/README.md` | Founding design: five pillars, no-message-plane doctrine, Tauri+xterm.js face, market position, name lore | em-dash-free per house rule |
| `~/Custom-Coding/yed-prior/docs/founding-brief.md` | Cold-start brief for any agent: Windows discovery, market sweeps, plan, board, sequencing, open decisions | 8 sections |
| `macos/Tests/HolyGhostty/HolyModeClipboardTests.swift` (worker) | Clipboard suite, 11 cases at HEAD | 2 remaining failures are key-window-bound |
| `.dev/mn-0b49e9-receipt.md`, `.dev/acceptance-c2b133-f4ab17/RECEIPT.md` | Coordinated-execution receipts (local, ignored) | referenced by coord drops |

## 3. Files modified (holy-ghostty, since 2026-09-21)

| Commit | Files | What / why |
|---|---|---|
| `d1d0c1100` (worker, engine) | `src/Surface.zig`, `src/surface_mouse.zig`, CI workflow | cmd-click on URLs during tmux mouse capture: cmd is host-side, protocol cannot encode it; press-to-release ownership with cancel paths. Root cause of "links never worked": tmux mouse mode captured clicks |
| `e3caf1817` (worker) | `HolyWorkspaceWindowController.swift`, Board/Archive stores and views | Surface resigns first responder while a mode is presented; `makeFirstResponder` refuses SurfaceView under overlays; board row-copy fallback |
| `e57ec0afa` (worker) | `HolyModeClipboardTests.swift` | Fixture keeps window+core alive; nil surfaces traced to Core Video zero displays → `window-vsync = false` |
| `278b1a8ff` (worker) | `HolyWorkspaceWindowController.swift` | Routes cmd-V/C/X/A + undo to the focused responder directly; Ghostty marks default clipboard bindings *performable* and excludes them from menu-shortcut lookup, so Edit>Paste can never carry cmd-V |
| `2d6ef8417`, `e6bb87b81` | `.manna/issues.jsonl`, `.handoff/*` | Board bookkeeping for mn-e9f9a9, mn-0b49e9 |
| `~/.claude/CLAUDE.md` (global) | (instructions file, not repo) | Added Starry Labs/Versova/Aldebaran context and repo-lifecycle rule (born at ovachiever → promoted; Versova gets a fork descendant) |

## 6. Bugs fixed

| Broken | Root cause (receipt) | Fix |
|---|---|---|
| URL cmd-click dead in workspace panes "for a long time" | tmux mouse capture on Holy sessions swallowed clicks before the engine's link hit-test; the mn-9b5b5b patch was at the wrong layer | `d1d0c1100`, CI-built engine, installed 09-22 |
| Paste in Board/Archive went into hidden terminal panes | HolyKeyDebug tape: `fr=SurfaceView superHandled=true` on every cmd-V since 09-11: the surface behind the overlay owned the keyboard | `e3caf1817` |
| After that: paste beeped, copy did nothing | Tape: `fr=_SystemTextFieldFieldEditor superHandled=false`: nobody dispatched; Paste menu has no cmd-V because performable bindings are excluded from lookup | `278b1a8ff`, installed 09-23 19:00 |
| "315 failures" in the full test suite | One host death cascades: every queued test on the dead host is marked failed at 0.000s. Killer was the new clipboard suite closing its window → `applicationShouldTerminateAfterLastWindowClosed` quit the host | fixture repair `e57ec0afa`; lesson les-898c86 |
| Clipboard fixture: nil surface in fresh host | Core Video reports zero active displays in the test host | `window-vsync = false` in fixture config |

## 7. Features built / shipped to the installed app

- cmd-click URLs in any pane (engine). cmd-hover shows caption; plain click still selects.
- Manna ids rendered manna-gold at rest by the renderer; cmd-click lands on the Board item, estate-wide resolution, confirm gate before dispatch.
- Board/Archive: text selectable; cmd-V/C/X/A route to the focused field; board row copy (id + title) when nothing is selected.
- Intelligence-level picker on Claim & build (low/med/high/xhigh/max, default max) mapping to `--effort` (claude) / `-c model_reasoning_effort` (codex): mn-d9e12d, installed 09-17.
- Roster instant kill: hold cmd → indicators become X; cmd-Delete kills selected: mn-7c56c0.

## 8. Configuration changes

- Global `~/.claude/CLAUDE.md`: Starry↔Versova section (JT-approved resource sharing, overlapping owners, Erik majority in Starry, advisory-only on Versova policy) and repo-lifecycle rule. Project memory file for this was deliberately removed (Erik: global, not project).
- zpc (holy): les-3ee592 one-painter; les-898c86 parallel-cascade diagnosis; les-dd697b **challenged** (its "clicks already work" premise was false); les-8c4eed visibleRect.
- Board rule (agent-do, shipped mn-0364a0): `done` now releases dependents inline.

## 9. Audit results

**1.0 release readiness (09-23):**
- BLOCKER found and filed: `holy-ghostty://spawn?command=…` runs attacker-supplied commands with no gate (Info.plist registers the scheme; `AppDelegate.handleHolyAutomationURL` → `HolyAutomationURLParser.launchSpec` → `createAutomatedHolySession`, no confirmation/allowlist/preference; both `application(_:open:)` and the Apple Event handler feed it). Item **mn-e9f9a9** (P0). The sibling `board` route is correctly gated and is the model fix.
- Secrets scan of tracked files: clean.
- Full suite: serial run (`-parallel-testing-enabled NO -skip-testing:GhosttyUITests`) = 4 real issues before the clipboard repair; clipboard suite now 9/11. `GhosttyUITests` target crashes on bootstrap and must be skipped (unfiled: §10).
- Screenshot review: the Old Model Detector frame (CleanShot 2026-09-23 10.28.04) is the keeper for the fleet/terminal image (crop above "5. In-Flight Work" to drop the API_KEY mention); Board mode should be the lead image; Erik declined to sanitize project names (his call, recorded).

**Market research (09-18, three sweeps, receipts in yed-prior founding brief):** nobody ships per-person capability grants or ledger-as-audit; everything governed runs server-side.

**Name clearance (09-18):** Starry Labs: STARRY Reg. 5223910 live, incontestable, IC 9 includes software, now Verizon's; junior user starrylabs.io. Regulus: registrable but regulus-labs.ai sells our category; retired. Aldebaran Group: both legacy robotics registrations dead; blocker is suspended Maxtronics application SN 79367132 (cl. 9/42 AI software); DC IT firm "Aldebaran Group, Inc." owns the .com. Yed Prior: unswept (mn-d396fa).

## 10. Known remaining issues and UNFILED items

**Filed, open, release-gating:**

| Item | Board | Why it gates |
|---|---|---|
| mn-e9f9a9 [P0] spawn-URL RCE | holy | drive-by command execution in a public build |
| mn-7681f4 [P1] resume strings run verbatim | holy | same defect class |
| mn-ca1805 [P1] session_events unbounded growth | holy | new user's disk fills ~11 MB/day |
| mn-a0406e [P0] all dots blue after restart | holy | signature feature lies on first launch |
| mn-c3b48a [P0] paste byte-exactness | holy | terminal credibility |
| mn-cf5fb6 [P0] stalled-agent alerts | holy | wedged agents look busy forever |
| mn-cf5f48 [P1] host state mirror fails on isolated socket | holy | real failing test; `dispatchNoteSurvives…` red since 09-15 |
| mn-137814 [P1] localhost rewrite for remote panes | holy | was blocked by mn-5a0ca3 (done); status desync: run `agent-do manna reconcile --fix` |

**Closed by workers, live confirmation NOT recorded from Erik** (if either fails in hand, file a successor; nothing reopens): mn-5a0ca3 (cmd-click URLs), mn-0b49e9 (copy/paste in Board/Archive: his last report: highlight works, copy unconfirmed, paste beeped; a newer build with `278b1a8ff` is installed since).

**Discussed and ratified but NOT filed anywhere: file these first:**
1. Holy: dispatch-brief rule "full standard report appended to the sealed handoff before reseal; coord note is a pointer" + orchestrator reads the handoff. (Erik typed "file both ideas" in a screenshot but the message never arrived.)
2. Holy: roster ✓ "done-done" indicator derived from session note (mn id) → board status `done`; cmd-hold X is the human cleanup gesture; ✓ follows the current note; coexists with unread green.
3. agent-do mn-dd4384: add the "done-done" handshake sentence (orchestrator drop + bell; worker runs `done` itself).
4. Holy: green-dot redesign: dispatched sessions are born-seen; green fires only on a completed, unseen turn (discussed 09-11 and 09-21, never filed).
5. Holy: `GhosttyUITests` target crashes at bootstrap ("Early unexpected exit… crashed with signal kill before establishing connection"); either repair or document `-skip-testing:GhosttyUITests` in the release runbook.
6. Holy: full serial run still has a second host death in `HolyRosterInstantKillTests` (`commandDelete…` cases, three relaunches in `.dev/mn-0b49e9-serial2.log`) after the clipboard fixture started retaining a window: needs its own item now that mn-0b49e9 is done.
7. Holy: `HolyWorkspaceClearLifecycleTests` `isKeyWindow` expectations fail in a non-frontmost host (`.dev/rr-clear-alone.log`): test hygiene.
8. Holy: "certify a full green unit run" as an explicit 1.0 gate (serial command below), and the 1.0 release ceremony item itself (CHANGELOG 1.0 header "One ledger, two faces: the terminal became the whole surface", marketing version, tag v1.0, README screenshots into `docs/holy-ghostty/assets/`, push only on Erik's word).
9. Yed Prior: the Yed Prior name clearance sweep (mn-d396fa) is filed but unclaimed; the Windows employee-rollout items (golden WSL2 image, trimmed company CLAUDE.md, per-person accounts, Win11 field check) exist only in the founding brief, not on any board.
10. holy-ghostty screenshot set: Board-mode lead image + fleet image (chosen) + Archive + Hosts: no item.

## 11. Verification commands

```bash
# installed build and engine
tail -2 .dev/install-2026-09-23-1900.log; git log -1 --format=%h   # expect 278b1a8ff
# board state
agent-do manna list --status in_progress            # expect none (holy)
agent-do manna reconcile                            # expect blocker_desync for mn-137814 until --fix
# full unit suite, the only trustworthy form (serial, UI target skipped)
/usr/bin/xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .dev/DerivedData \
  -skip-testing:GhosttyUITests -parallel-testing-enabled NO -resultBundlePath .dev/serial.xcresult test CODE_SIGNING_ALLOWED=NO > .dev/serial.log 2>&1
# count from the result bundle (Swift Testing suites; `grep -c "' failed"` prints 0 — corrected 09-24)
xcrun xcresulttool get test-results summary --path .dev/serial.xcresult
# clipboard suite alone (expect 9 pass / 2 key-window-bound failures at 278b1a8ff)
... -only-testing:GhosttyTests/HolyModeClipboardTests -parallel-testing-enabled NO test ...
# keyboard tape (real binary; the shell aliases `log`)
/usr/bin/log show --last 1h --predicate 'category == "HolyKeyDebug"' --style compact | grep "key=v"
# spawn-URL exposure (read-only proof)
grep -n "launchSpec\|createAutomatedHolySession" macos/Sources/App/macOS/AppDelegate.swift
```

Never report a raw failure count from a parallel run (les-898c86). `log` in this shell is a user function: always `/usr/bin/log`.

## 13. Next steps (ordered)

1. `agent-do manna reconcile --fix` (clears mn-137814's stale blocked status).
2. File §10 items 1–8 as manna (Holy board; item 3 on agent-do). Erik's rulings for each are in §1 and §10: no re-discussion needed.
3. Dispatch mn-e9f9a9 (spawn-URL gate: off-by-default preference, confirmation sheet naming command/cwd/host, refusals logged; board route unchanged) and mn-7681f4 together as the security pass.
4. Erik's live confirmations on cmd-click URLs and Board/Archive copy in the installed build; file successors on any failure.
5. Trust items mn-ca1805, mn-a0406e, mn-c3b48a, mn-cf5fb6; then a certified serial green run.
6. Screenshots (Board lead, fleet, Archive, Hosts) → release ceremony → push and tag only on Erik's explicit word.
7. Yed Prior: claim mn-204dcb (grant schema is the keystone) and mn-d396fa (name sweep) first; attorney engagement mn-067dc8 on the business board when Erik green-lights.
