---
workflow: 2
manna: mn-2c82a2
track: mn-eb7a80
source: Erik request 2026-09-05 22:10
base_commit: 17ca2202649e39c329b5e8df44094569df939023
scope: '[P1][SYNC][STATE] Recency and seen indicators are host-authoritative: identical on every machine, surviving clear/re-attach'
inputs:
- Erik request 2026-09-05 22:10
binding: sha256:a0eb10d4b41a59e40173d44bf1904364d52b2e527242ce94012998c6a2769cd7
---

# Handoff: [P1][SYNC][STATE] Recency and seen indicators are host-authoritative: identical on every machine, surviving clear/re-attach

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-2c82a2
```

## Scope

[P1][SYNC][STATE] Recency and seen indicators are host-authoritative: identical on every machine, surviving clear/re-attach

## Inputs

- Erik request 2026-09-05 22:10

## Work order

Erik 2026-09-05: clearing sessions on the MacBook and re-attaching from hosts loses all recency indicators — each machine keeps its own local seen/finished/recency state in its own SQLite, so local amnesia (clear, fresh install, new machine) resets indicators while the owning host's copy is never consulted. Fix: the indicator-bearing state rides the SESSION, not the viewer — tmux user options on the owning server (the note-sync side-channel pattern; the agent-state wire @holy_agent_state_v1/@holy_agent_last_finished_v1 already lives there and carries finished timestamps + harness identity from the keystone): add a seen acknowledgment option (e.g. @holy_seen_v1 = <ts of the finish that was seen>) written by WHICHEVER Holy instance the human saw it in, and derive recency ordering from the wire's finished/updated timestamps rather than local rows. Adoption/re-attach reads options first and renders identical indicators immediately; the local DB becomes a cache that can be rebuilt from the host at any time. One-person semantics: seen anywhere is seen everywhere; question/permission indicators keep their existing demand-until-answered law (dec-3ba822 lineage) evaluated against the shared wire, not local memory. Scope note: this is the concrete recency/seen slice of the standing sync program — relates to mn-15ba3d (cross-host metadata semantics), mn-2b3a11 (note/pin sync via tmux options), and mn-56f896 (preserve identity across lifecycle); build it on the same option vocabulary so one sync grammar emerges rather than three. Acceptance: mark sessions seen on the Studio, clear ALL sessions on the MacBook, re-attach from hosts — every dot, orb, and recency ordering matches the Studio exactly, including unseen-finished blue dots for sessions neither machine has viewed since finishing.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-2c82a2`.
4. Commit with `Manna: mn-2c82a2` and run `agent-do manna done mn-2c82a2` only after the work is verified.
