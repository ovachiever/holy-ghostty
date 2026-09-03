---
workflow: 2
manna: mn-d204ae
track: mn-eb7a80
source: Erik live report 2026-09-03 10:48 + session_events and tmux pane-option receipts, this session
base_commit: 9eec11749be7aa5504eb4e3135dc978a8300544d
scope: '[P1][STATE] Eternal spinner: conflicting wire integrity is sticky, a lost Stop leaves working forever, and ''← 1 agent'' footer reads as activity'
inputs:
- Erik live report 2026-09-03 10:48 + session_events and tmux pane-option receipts, this session
binding: sha256:326c576413fe6f78bcaf2cbe46a0b0a0ee92cbbd17f74c760207a19c37c16138
---

# Handoff: [P1][STATE] Eternal spinner: conflicting wire integrity is sticky, a lost Stop leaves working forever, and '← 1 agent' footer reads as activity

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-d204ae
```

## Scope

[P1][STATE] Eternal spinner: conflicting wire integrity is sticky, a lost Stop leaves working forever, and '← 1 agent' footer reads as activity

## Inputs

- Erik live report 2026-09-03 10:48 + session_events and tmux pane-option receipts, this session

## Work order

Live repro 2026-09-03 10:48, session 'Aldebaran Group | erik and tiff' (A8C1BDBA, pane %32, tmux holy-shell-24): roster spinner never stops though the pane shows an idle prompt and 'done 9:59 AM' residue. Three stacked findings, receipts from session_events + live pane options. (1) STICKY CONFLICT: session_events show attention='conflict' continuously since 2026-09-02 18:11 — HolyTmuxAgentStateMonitor.swift:589 sets integrity=.conflicting when >1 valid envelope (or valid+invalid mix) exists for a canonical wire key, and nothing ever repairs or expires the verdict; yesterday's keystone wire-format upgrade (session_id now rides the wire) makes mixed old/new envelopes likely across long-running sessions and multi-pane observations. Conflict must be self-healing: newest-format/newest-timestamp precedence, stale finished-wire values superseded not conflicting, and any surviving conflict surfaced as its own honest glyph with an age, never an indefinite spinner. (2) LOST FINISH: live pane options show @holy_agent_state_v1 = working|user-prompt @10:11:39 with harness id 0b15c3a3, while @holy_agent_last_finished_v1 = 10:00:40 — the turn that started 10:11 ended without its Stop/StopFailure wire write landing, so 'working' latches forever; a working state older than a lease without any hook traffic must decay to the scrape verdict (the existing working-lease expiry item mn-cf5fb6 is the sibling; wire this case into it). (3) FOOTER TREADMILL, PREDICTED CASE: the classifier reads the new Claude Code footer '⏵⏵ auto mode on (shift+tab to cycle) · ← 1 agent' as activityKind=approval (session_selected events 10:48) — background agents outlive turns exactly like the 'N shells still running' epitaph that already burned this board once (zpc les-0e740c lineage; reverted commit cdad159c8's lesson): an agent-count footer chip is presence, never busyness. Extend HolySessionLiveStatusTests with this exact captured footer line and with a two-format wire fixture. Acceptance: this session's row settles to idle/blue within one poll after repair; a synthetic conflicting wire self-heals; the footer line classifies as idle presence.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-d204ae`.
4. Commit with `Manna: mn-d204ae` and run `agent-do manna done mn-d204ae` only after the work is verified.
