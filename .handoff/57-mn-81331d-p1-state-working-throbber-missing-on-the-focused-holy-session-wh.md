---
workflow: 2
manna: mn-81331d
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P1][STATE] Working throbber missing on the focused Holy session while its envelope says working'
inputs: []
binding: sha256:8309aa840acc8e58256c1a5e9975995a5246d7f4a8110fb959f8b19d19068d55
---

# Handoff: [P1][STATE] Working throbber missing on the focused Holy session while its envelope says working

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-81331d
```

## Scope

[P1][STATE] Working throbber missing on the focused Holy session while its envelope says working

## Inputs

- None declared.

## Work order

Erik 2026-08-11 11:24 (screenshot): the session running the build (fc450563, roster title "Holy Ghostty", tmux holy-shell-1-shell-DE183709) shows no working spinner while actively mid-turn.

EVIDENCE (live probes, 11:25): the pane-scoped envelope is HEALTHY — @holy_agent_state_v1 = "v1|claude|working|1786465475723|…|tool-complete", refreshed seconds before the probe by the session,s own PostToolUse events; @holy_model_label current; hook chain fully working. The session was crash-restored 2026-08-09 (@holy_command = claude --resume fc450563…) and the restore path is EXONERATED — the hook writes fine. Therefore the defect is downstream of the register: the tmux monitor read, the store policy, or the roster rendering.

CANDIDATES, in suspicion order: (1) selected-row rendering — Erik was focused ON this row when the spinner was absent; 40466c243 (2026-06-22) fixed the off-selection case, the selected case may have regressed or been restyled since; check HolySessionRosterView orb construction for isSelected branches. (2) monitor pane→session mapping for readopted/restored sessions — the register-ownership rule ("exactly one pane owns the register, ambiguity fails closed to nil") against whatever pane topology a restored+reattached session has; verify producer evidence for this exact session in the store. (3) policy inputs: confirm the store,s attention snapshot for this session actually carries lifecycle working while the row renders without a ring.

Diagnose with the live session before touching code; the probes above reproduce in seconds.

DIAGNOSIS DOSSIER 2026-08-11 11:30 (live probes, everything below exonerated):
- Envelope: pane register @holy_agent_state_v1 = working, refreshed per tool event. HEALTHY.
- Topology: one window, one pane (%4), exactly one register; no duplicate register anywhere on the server. The fail-closed conflict rule is NOT firing.
- Persistence: sessions row B217C0FF-7DD8-4F16-B4F6-A0A940FCBEED has latest_phase=working, latest_attention=watch, live progress signal — byte-shape identical to holy-shell-10's row, which THROBS.
- Narrowing from Erik: every other session throbs; only this one does not. The one constant: this is the row Erik is sitting on.
- Render path: HolySessionRosterView:769 passes attention.kind into the orb unconditionally animated, so the divergence is in the POLICY OUTPUT (attention.kind) for this session inside the running app, or in a selection-interaction not visible in code reads.
NEXT (needs the running app): log or inspect the policy inputs for this exact session id — the working-claim envelope the STORE holds (not the pane), its observedAt vs staleness bounds, and producer evidence. A one-line os_log at the policy call site keyed to this session would corner it in one poll. Restored-session detail worth checking there: the store's tmux identity for this row was readopted 2026-08-09; verify the monitor's observation keys (session name vs pane id) match what the store expects for readopted rows.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-81331d`.
4. Commit with `Manna: mn-81331d` and run `agent-do manna done mn-81331d` only after the work is verified.
