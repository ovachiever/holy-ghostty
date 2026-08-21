---
workflow: 2
manna: mn-c3a823
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P1][SYNC] Remote-ward sync never ran automatically (dead periodic path) — wired at 300s; bring to ≤30s'
inputs: []
binding: sha256:8ae60c2ebc08f6ecee7afc2a117daae67e67f0408756d51567ece13532f3c77c
---

# Handoff: [P1][SYNC] Remote-ward sync never ran automatically (dead periodic path) — wired at 300s; bring to ≤30s

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-c3a823
```

## Scope

[P1][SYNC] Remote-ward sync never ran automatically (dead periodic path) — wired at 300s; bring to ≤30s

## Inputs

- None declared.

## Work order

CORRECTED root cause (Erik's acceptance testing, 2026-07-20): not slow cadence — the automatic path NEVER ran. refreshActiveTmuxSessionMetadata() (HolyWorkspaceStore.swift:2751), the periodic remote-metadata refresh, had zero callers (same dead code flagged in the 01aa152e7 naming investigation; the local half got the 15s timer then, the remote half stayed orphaned). refreshRemoteSessions only fired from manual UI (Hosts Refresh button, sheet-open, attach). Converge(.periodic) reconciles identity but does not re-read attached sessions' synced metadata.

FIXED (wired to the 300s timer alongside convergeRoster) — automatic remote-ward sync now works at ≤300s worst case. REMAINING SCOPE: bring to ≤30s via the agent-state monitor piggyback (HolyTmuxAgentStateMonitor already polls every remote endpoint ~1s over SSH; add the four @holy_note/@holy_today_pin options to its existing read — near-zero marginal cost, no new SSH connections per the no-ControlMaster constraint in mn-8749ca). Also refresh on app-activation + session-focus so human-visible moments are always fresh. Beware App Nap throttling background timers on laptops. Acceptance: edit on host A visible on host B ≤30s with app frontmost, both directions, no SSH storm.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-c3a823`.
4. Commit with `Manna: mn-c3a823` and run `agent-do manna done mn-c3a823` only after the work is verified.
