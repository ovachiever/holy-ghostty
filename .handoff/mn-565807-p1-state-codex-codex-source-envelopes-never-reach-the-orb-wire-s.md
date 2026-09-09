---
workflow: 2
manna: mn-565807
track: mn-eb7a80
source: Erik screenshot 2026-09-09 12:57 + live pane %31 wire receipts this session
base_commit: 1b9e7ee09b4408e7ebd65abcb0ba4743c6dadf65
scope: '[P1][STATE][CODEX] Codex-source envelopes never reach the orb: wire says working, roster shows idle'
inputs:
- Erik screenshot 2026-09-09 12:57 + live pane %31 wire receipts this session
binding: sha256:0ee9c6a44ba4a2b6f045ec5bc00e291a5e6458ae4ad3913f4a8bf552fc2954e2
---

# Handoff: [P1][STATE][CODEX] Codex-source envelopes never reach the orb: wire says working, roster shows idle

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-565807
```

## Scope

[P1][STATE][CODEX] Codex-source envelopes never reach the orb: wire says working, roster shows idle

## Inputs

- Erik screenshot 2026-09-09 12:57 + live pane %31 wire receipts this session

## Work order

Erik 2026-09-09 12:57: a codex session visibly working ('• Working (1m 23s • esc to interrupt)' in-pane, braille spinner in the tmux title) shows an idle/seen dot in the roster. Receipt from the live pane (%31, holy-worker-bf685295): @holy_agent_state_v1 = 'v1|codex|working|1788976557066|...|01a086b7-...' — current, working, correct codex identity; the hooks and wire are doing everything right (and the codex identity capture from b5287393c is proven live here). The defect is display-side: the envelope-to-indicator path evidently consumes only claude-source wires (pane-scrape vocabulary for codex's Working line and the braille title exist in HolySession but are outvoted or gated), so codex rows fall back to idle. Fix: the six-state indicator pipeline treats a valid envelope identically regardless of source runtime — codex working lights the throbber, codex finished earns the unread dot, needs-user/failed behave exactly as claude's; keep the d204ae precedence/decay laws source-agnostic. Extend HolySessionLiveStatusTests/monitor tests with this exact captured codex wire triplet (state/last_used/last_finished above) asserting the orb outcome per state. Acceptance: a dispatched codex worker shows the working throbber within one poll of the wire flipping, on the live app. Relates: mn-f0b1cc (codex hooks degraded-state surfacing) stays separate — hooks here are healthy.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-565807`.
4. Commit with `Manna: mn-565807` and run `agent-do manna done mn-565807` only after the work is verified.
