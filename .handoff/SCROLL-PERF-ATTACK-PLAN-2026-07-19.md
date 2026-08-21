# Scroll Performance Attack Plan v2 — Holy on MacBook-class Hardware (2026-07-19)

**Corrected problem statement (supersedes v1's framing):** scrolling is not butter-smooth on **MacBooks** — Erik's (attached to Studio sessions over SSH) *and* his employee Chris's (purely **local** sessions, no network). The Studio never shows it. Therefore: the network is at most a *compounding* factor for Erik, not the root. The root is **Holy overhead that an $8K Studio absorbs and a MacBook cannot** — likely made worse by ProMotion: a 120Hz MacBook has an 8.3ms frame budget, half the Studio display's 16.6ms, so the weaker machine must ALSO render twice as often.

**Mission:** instrument on a MacBook, find where the frame budget goes, fix what Holy owns, guard against regression. All measurement happens on a MacBook — the Studio masks the disease.

**Acceptance:** on a MacBook, 10-second sustained scroll of a 50k-line buffer in Holy matches vanilla Ghostty in the same scenario on the same machine: p99 frame time within the display budget, zero hangs > 50ms, no visible hitching — for both a local session and (secondarily) a remote one.

## The unified prime suspect (test this first after setup)

Scrolling *changes the visible pane content every frame*. Holy's derived-state machinery keys off visible content: the 1.25s refresh tick reads `cachedVisibleContents`, recomputes the 40-line detection text, runs the regex scans, updates preview/stability, can fire `markUpdated` → `objectWillChange` → roster row re-render → `session_events` DB writes. **During a scroll, every tick sees "changed" content and does maximum work — concurrently with the Metal surface trying to hit 120fps.** Vanilla Ghostty does none of this. The Studio eats it; an M-series laptop drops frames. The three `TimelineView(.animation)` spinners (RosterView:1504/1544/1584) add continuous SwiftUI commits at display refresh whenever any session is working. This predicts: hitches align with tick boundaries, worsen with session count and active spinners, improve with sidebar collapsed, and halve in severity at a locked 60Hz.

## Step 0 — cheap evidence before instruments (1 hour)

1. **Interview Chris:** session count, MacBook model/year, sidebar visible or collapsed, plugged in or battery, Low Power Mode, external display or built-in (60 vs 120Hz). His config bounds the minimum-repro case.
2. **On any MacBook:** confirm the build is post-`ac7148c18` verified-ReleaseFast (30 seconds — don't let May's ghost linger unexamined even if it's unlikely now).
3. **The 60Hz probe:** System Settings → Displays → lock the MacBook panel to 60Hz. If hitching drops dramatically, the ProMotion-budget hypothesis is confirmed as an amplifier and every fix gets measured at 120Hz.

## Step 1 — instrumentation kit (on the MacBook)

- `MTL_HUD_ENABLED=1` for both apps: live FPS/frame-time on the Metal surface.
- Instruments: **Time Profiler + Hangs + Core Animation FPS**; save a trace per experiment row.
- `sample "holy-ghostty" 5` *during* scroll for a cheap main-thread picture.
- os_signpost (add if absent) around: `refreshDerivedState`, `detectSignals`, roster body re-evaluation, agent-state monitor tick, and `session_events` writes — the point is seeing their timeline overlap with scroll gestures.
- Record per row: hardware, Hz, power state, session count, spinner count, p99 frame time, hang count, trace path.

## Step 2 — bisection matrix (MacBook, identical scroll workload per row)

| # | Scenario | Isolates |
|---|---|---|
| V1 | Vanilla Ghostty, local, no tmux | absolute baseline on this hardware |
| V2 | Vanilla + tmux `mouse on` + 50k history (Holy's managed config), local | tmux copy-mode tax, no network |
| H1 | Holy, 1 local session, sidebar visible | Holy minimum (≈ Chris's shape — confirm with his numbers) |
| H2 | Holy, N sessions matching Chris, ≥1 spinner | the employee's real complaint |
| H3 | H2 with **sidebar collapsed** | SwiftUI roster + TimelineView animation cost |
| H4 | H2 with detection quiesced (env flag stubbing the 1.25s coordinator tick + 0.75s monitor) | detection churn cost |
| H5 | H2 at locked 60Hz | ProMotion amplifier |
| R1 | Holy, remote SSH session to Studio (Erik's case) | network compounding on top of whatever H-rows show; also check `tailscale status` for DERP relay vs direct, and whether monitor SSH polls (no ControlMaster found in the codebase — every 0.75s poll may be a fresh ssh spawn) pile onto the same path |

Deltas tell the story: H2−H3 = roster/animation. H2−H4 = detection churn. H2−H5 = ProMotion amplification. R1−H2 = the network's true share (Erik-only). V2−V1 = tmux tax (the fair floor Holy cannot beat).

## Step 3 — ranked hypotheses, signatures, fix directions

1. **Scroll-driven detection churn on the main thread** (the unified suspect above). Signature: hitches at tick boundaries; Time Profiler shows capture/regex/AttributeGraph during hitches; H4 markedly smoother. Fixes: suspend derived-state refresh for the focused session *during active scroll gestures*, debounce content-change handling, move capture+regex off the main thread, skip non-visible sessions.
2. **SwiftUI same-window contention.** `TimelineView(.animation)` spinners force display-rate commits; objectWillChange storms re-evaluate rows mid-scroll. Signature: H3 smoother; SwiftUI frames in profiles. Fixes: pause spinner animation during scroll or cap spinner FPS (a 13px spinner needs ~15fps, not 120), coalesce roster invalidation.
3. **ProMotion halves the budget** (amplifier, not cause). Signature: H5. Fix: none needed if 1–2 land; otherwise consider surface-level frame pacing.
4. **Monitor subprocess churn** (worse for Erik: possible fresh SSH handshake per 0.75s poll per endpoint — no ControlMaster/ControlPersist anywhere in Sources). Signature: R1 ≫ H2 with ssh/handshake frames in samples; Erik-only. Fixes: SSH connection multiplexing (ControlMaster auto + ControlPersist), batch endpoints per host, slow the remote cadence.
5. **tmux copy-mode tax** (structural floor). Signature: V2 ≈ H-rows. Then Holy is at parity and the report says so honestly.

## Step 4 — deliverables

1. Filled matrix + traces (`.dev/scroll-traces/`), measured on MacBook hardware.
2. Confirmed causes ranked by measured contribution; fixes for each Holy-owned one with before/after p99 at 120Hz.
3. Regression guard: repeatable scripted scroll benchmark documented in-repo; engine provenance surfaced in diagnostics.
4. Chris verifies the fix on his machine — installed-app acceptance on the *afflicted* hardware class, not the Studio.

## House rules

Engine rebuilds via CI only (local Zig link broken on macOS 26). Install only through `scripts/install-holy-ghostty.sh`. Mid-swarm rebuilds are safe (tmux detached; sessions reattach). Full suite before commits. Claim `mn-8749ca` before starting.
