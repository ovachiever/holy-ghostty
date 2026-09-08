---
workflow: 2
manna: mn-3a03e3
track: mn-eb7a80
source: Erik live report 2026-09-08 11:05; forensics this session (no crash logs both machines; retention verified intact)
base_commit: 5c8c9ddaea6a319e6bbca29785519d3e877dc26d
scope: '[P0][APP] Clear (detach all) closes the entire app — clean exit, no crash, the August ghost by a new road'
inputs:
- Erik live report 2026-09-08 11:05; forensics this session (no crash logs both machines; retention verified intact)
binding: sha256:83ceb8a26af1fb66d618ced7d0c76923260e995cb471e08415550f721115f288
---

# Handoff: [P0][APP] Clear (detach all) closes the entire app — clean exit, no crash, the August ghost by a new road

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-3a03e3
```

## Scope

[P0][APP] Clear (detach all) closes the entire app — clean exit, no crash, the August ghost by a new road

## Inputs

- Erik live report 2026-09-08 11:05; forensics this session (no crash logs both machines; retention verified intact)

## Work order

Erik 2026-09-08 ~11:00: pressing the roster's Clear button ('Detach every session from this roster without stopping tmux' -> HolyWorkspaceStore.detachAllSessions, RosterView:363) closes Holy completely. Evidence so far: ZERO crash reports on either machine's DiagnosticReports -> a clean close/terminate, not a crash. Historical twin: the Aug-11 assign-property ghost (b5825fac0 'retain the workspace controller') — its Self.retain(self) fix is VERIFIED still present (controller :113, isReleasedWhenClosed=false :87), so this is a NEW path to the same outcome. Suspects, newest first, all touching window/hosting lifecycle since the ghost was fixed: 5c8c9ddae (federated archive — window controller init reshaped), 40eac9bc5 (hosting view minSize collapse fix), a70fa953e (restored frame on visible screen), plus the empty-roster state after detachAllSessions interacting with applicationShouldTerminateAfterLastWindowClosed (AppDelegate :525, driven by derivedConfig.shouldQuitAfterLastWindowClosed — check Erik's config value). Reproduce the way the original ghost was caught: an instrumented build + synthetic sessions + one synthetic Clear (never on a live roster); the lifecycle flight recorder logs 'lifecycle: detachAllSessions (Clear) archiving N' and 'lifecycle: workspace windowWillClose — sessions=N' — the ordering between those two lines plus whatever invokes close()/terminate names the culprit. Fix must include a regression test: detach-all with a populated store leaves the window open, key, and re-attachable via Sync; and the empty-roster state renders the empty state, never a closed window. NOTE for the human meanwhile: avoid Clear; individual detach and Sync are unaffected.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-3a03e3`.
4. Commit with `Manna: mn-3a03e3` and run `agent-do manna done mn-3a03e3` only after the work is verified.
