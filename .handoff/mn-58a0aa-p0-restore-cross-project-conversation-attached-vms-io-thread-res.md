---
workflow: 2
manna: mn-58a0aa
track: mn-eb7a80
source: null
base_commit: 5a9e471f8f962f856bccceb774d0c5023a448826
scope: '[P0][IDENTITY] Foreground conversation swapped in-process: FleetView attach replaced a Holy row''s conversation with a vms.io background session'
inputs: []
binding: sha256:fab802367225d5d8099e50570ba49261ed6e752c275b8aca16c9d1c76f63e8bb
---

# Handoff: [P0][RESTORE] Cross-project conversation attached: vms.io thread restored into a Holy Ghostty row

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-58a0aa
```

## Scope

[P0][RESTORE] Cross-project conversation attached: vms.io thread restored into a Holy Ghostty row

## Inputs

- None declared.

## Work order

Observed 2026-09-01 ~12:49 by Erik (screenshot in session 5b8c630f): a roster row titled Holy Ghostty carries the vms.io Claude conversation (Chris / Strety / PR #103 thread, last exchange Aug 20 — a 12-day-old conversation resumed). The in-pane model itself states 'this is the vms.io session'. The green bar shows the backing tmux session is helper-shell-named (holy-shell-31-shell-90444E76, title 'Review GitHub pull'), so a machine helper-shell session appears to have received claude --resume with a vms.io conversation id and been presented under a Holy Ghostty identity. This is the exact class 0.50 claimed fixed ('restored sessions can no longer receive another session's conversation' — unique assignment via agent-sessions resolve --cwd/--near). Investigate: which restore/relaunch path produced this (Session Restore batch vs roster relaunch vs helper-shell adoption), what cwd/near the resolver was given, whether cwd collision or helper-shell generic cwd defeated the unique-assignment guarantee, and why no candidate picker appeared. Evidence to pull: agent-sessions resolve logs, session_events for the row, .dev restore receipts, tmux @holy_* metadata of holy-shell-31-shell-90444E76. NOT yet investigated — filed at usage-cap pause.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-58a0aa`.
4. Commit with `Manna: mn-58a0aa` and run `agent-do manna done mn-58a0aa` only after the work is verified.
