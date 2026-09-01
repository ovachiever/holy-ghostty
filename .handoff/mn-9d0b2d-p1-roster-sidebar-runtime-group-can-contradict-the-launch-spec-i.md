---
workflow: 2
manna: mn-9d0b2d
track: mn-eb7a80
source: Erik live report 2026-09-01 + session_events payload evidence, sessions 7A72011F/5A1CA3C1
base_commit: 7867293926941b4bcf018ee7c9cc7b42d543d8f7
scope: '[P1][ROSTER] Sidebar runtime group can contradict the launch spec; inference must not outvote an explicit runtime'
inputs:
- Erik live report 2026-09-01 + session_events payload evidence, sessions 7A72011F/5A1CA3C1
binding: sha256:3e367707233b43b0e49a56c83ae49737bfcb94f73c0d5ca93a908dd820d42665
---

# Handoff: [P1][ROSTER] Sidebar runtime group can contradict the launch spec; inference must not outvote an explicit runtime

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-9d0b2d
```

## Scope

[P1][ROSTER] Sidebar runtime group can contradict the launch spec; inference must not outvote an explicit runtime

## Inputs

- Erik live report 2026-09-01 + session_events payload evidence, sessions 7A72011F/5A1CA3C1

## Work order

Live repro 2026-09-01 10:58: two codex workers spawned with launch_spec_json.runtime='codex' (sessions 7A72011F and 5A1CA3C1, tmux holy-shell-24/25); sessions.runtime persisted correctly as codex for BOTH, yet the roster grouped 7A72011F under CLAUDE while 5A1CA3C1 landed under CODEX. session_events for both show the live evidence engine cycling runtime 'shell' readings off Codex chrome ('tab to queue message', '100% context left', 'gpt-5.6-sol max · ~/…' footer, box-border lines — seq 3-7 payloads), i.e. Codex's footer vocabulary is not in any structural allowlist and early misreads feed HolySession.inferredRuntime, whose one-way latch (nil-never-resets) then pins the sidebar section forever. Fix in two layers: (1) AUTHORITY — when launch_spec_json.runtime names a real agent runtime, the sidebar group follows it, full stop; inference exists only for runtime='shell' sessions where an agent may appear later, and must never override an explicit spec. (2) VOCAB — add Codex v0.151 structural chrome ('OpenAI Codex' banner line-anchored, 'tab to queue message', context-left footer) to the codex evidence lane so hand-started codex-in-a-shell classifies correctly; extend HolySessionLiveStatusTests with the exact captured lines (per house rule). Also reconcile the latch: on a persisted sessions.runtime update, the in-memory group must converge instead of holding the stale latch (the DB and sidebar currently disagree on the same session).

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-9d0b2d`.
4. Commit with `Manna: mn-9d0b2d` and run `agent-do manna done mn-9d0b2d` only after the work is verified.
