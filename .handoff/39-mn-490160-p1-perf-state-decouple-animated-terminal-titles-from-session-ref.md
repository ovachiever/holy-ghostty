---
workflow: 2
manna: mn-490160
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P1][PERF][STATE] Decouple animated terminal titles from session refresh and persistence'
inputs: []
binding: sha256:74ea29243f16e87dca3f67f96e3d9c5f747d6e3c6a0be9e7202b0a9806e30dcd
---

# Handoff: [P1][PERF][STATE] Decouple animated terminal titles from session refresh and persistence

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-490160
```

## Scope

[P1][PERF][STATE] Decouple animated terminal titles from session refresh and persistence

## Inputs

- None declared.

## Work order

Independent finding from the July 17 read-only selection audit. The reported cross-app drag failure was traced to damaged mouse hardware and is NOT a reproduction of this issue.

Evidence:
- Active Codex terminal titles changed about 9-10 times per second; Claude was about 0-1 per second.
- macos/Sources/HolyGhostty/Session/HolySession.swift title subscription sends objectWillChange and forces derived-state refresh for each distinct title.
- A five-second process sample contained 615 persistence stack samples, including 265 database-save and 151 JSON-encoding samples.
- Spinner-only presentation churn is therefore crossing into semantic session state, main-thread invalidation, and durable work.

Invariant:
Presentation animation must never become durable session metadata or force whole-roster work. Semantic title and working-directory changes must still propagate reliably for Claude, Codex, OpenCode, and future harnesses.

Done when:
- Spinner-only or frame-only title changes cause zero durable mutations and zero full-roster invalidations.
- Semantic title and cwd changes propagate within a documented bound without being dropped.
- Persistence is coalesced and kept off the interactive drag/render path.
- A busy-Codex installed-app soak measures bounded refresh and persistence rates with no stale titles or lost metadata.
- Regression tests distinguish presentation churn from semantic title changes.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-490160`.
4. Commit with `Manna: mn-490160` and run `agent-do manna done mn-490160` only after the work is verified.
