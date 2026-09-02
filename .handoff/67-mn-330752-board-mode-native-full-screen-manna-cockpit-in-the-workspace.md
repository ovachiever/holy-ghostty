---
workflow: 2
manna: mn-330752
track: mn-9a97cc
source: Erik ratified inline 2026-08-31 (One Ledger Two Faces); see track mn-9a97cc
base_commit: 0c6ba8bc635e3fcd76909c5e163e48fa53fa6e85
scope: 'Board mode: native full-screen manna cockpit in the workspace'
inputs:
- Erik ratified inline 2026-08-31 (One Ledger Two Faces); see track mn-9a97cc
binding: sha256:ad4865c74115ff36aaa9da4ede43c376fb66e4dea3bef15cf03c71035cbc9d08
---

# Handoff: Board mode: native full-screen manna cockpit in the workspace

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-330752
```

## Scope

Board mode: native full-screen manna cockpit in the workspace

## Inputs

- Erik ratified inline 2026-08-31 (One Ledger Two Faces); see track mn-9a97cc

## Work order

The workspace's second face: a full-screen native (SwiftUI) board view — one key to enter, Escape returns the terminal — plus the estate strip on top (every registered board, needs-you first). Sheets: now / next / waiting-in-waves / asks / coordination / dreams / decisions; inspector with AI digest, body, track, claimant, commits, handoff path. Data: agent-do 'manna state --json' and 'manna estate --json' (tickets filed on agent-do's board — cross-repo dependency; until they land, do not build on manna list --json, which is a retired contract). Every mutation is a real CLI verb (claim/done/unblock/close/sync/fix/promote) run under Holy's own manna actor identity + claim proof, confirm-gated: a glance never moves the board. Digests/summaries via Holy's fast model-routing role, content-hash cached in Holy's SQLite. One badge: gh your-move + board asks + sessions needing a human, deduplicated by harness_session_id. Claimant rows join to roster sessions via the keystone — click a peer, focus its session. Remote: run the CLI where the session lives over Holy's existing bridge.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-330752`.
4. Commit with `Manna: mn-330752` and run `agent-do manna done mn-330752` only after the work is verified.

## Continuation (2026-09-02, presentation rebuild)

The first native cut got the data right and the design wrong. The presentation layer was rebuilt to the manna serve web cockpit (`agent-do/tools/agent-manna/serve/static`: styles.css, app.js, index.js, view.js), which is the ratified reference; the client/contract layer kept its shape.

What landed:

- `HolyMannaBoardPresentation.swift` (new): the page's tokens (palette, 26px rows, 300px inspector 220–600, 12px mono, 1440px measure, breakpoints) and its rendering rules (rowText = digest || title, state labels, `BLOCKED · ids`, needs-you override from the claimant pulse, shortTrack, date/ago/updated formatting, filter sections, inbox rows, estate order, column fitting) as pure functions.
- `HolyMannaBoardView.swift`: topbar crumb `estate › board` + inbox | board | coordination tabs + grep field + `updated Ns ago | ● live | refresh`; one continuous ledger (`$ manna now/next/waiting`) with ID/DIGEST/TRACK/STATE/# columns; filter chips live/done/dreams/recent/all + track ▾; inspector (head, collapsible AI summary, title, body, meta table, `copy: [handoff] [id] [show cmd]`, confirm-gated `act:` verbs); inbox verb rows; coordination sections; debug sheet; bottom strip (root path, drift, debug toggle); estate table as the landing surface.
- `HolyMannaBoardClient.swift`: `{success, error}` envelope decoded first; refusals surface the CLI's words plus the directory tried; contract misses name the failing field (do/catch, no `try?`).
- `HolyMannaBoardStore.swift`: estate/board surface with estate fallback when the focused session has no board; filters, track, grep, peer selection; live re-read on the visible-panel cadence while presented.
- Models: sheets are asks/board/coordination(/debug); state decodes `all`/`unlayered`; items carry an optional `digest`; drops carry `for`/`created_at`; asks include drops and read like the web inbox.
- Keys: ⌘F or `/` focus grep; Escape in grep clears it, Escape elsewhere leaves the board.

Verification: `HolyMannaBoardTests` (14), `HolyMannaBoardPresentationTests` (14), `HolyMannaTrackDecodeRegressionTests` (1), `HolyMannaBoardRenderSmokeTests` (1) green via build-for-testing + test-without-building. The render test writes PNGs of every face offscreen; point `TEST_RUNNER_HOLY_BOARD_RENDER_STATE_JSON` / `_ESTATE_JSON` / `_DIR` at captured `manna state --json` / `manna estate --json` files to see the live board without launching the app.

Remaining deltas from the web (reasons): row digests fall back to titles because the CLI emits no `digest` (serve's digest.py attaches them); `list | timeline` mode, draggable column grips, the `view ▾` font/size popover, `ask AI` (separate item), and item `relations` are not built. The 1440px measure centers the cockpit on wide windows exactly as the page does (`HolyMannaBoardMetrics.measure`).

Open until Erik's production visual pass; keep the item in_progress.
