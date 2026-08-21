---
workflow: 2
manna: mn-f2a0b1
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P2][STATE] Background-work orbit: one census for agents, workflows, and tasks'
inputs: []
binding: sha256:3aa8bfe8327960ca89a6a01d2b619589ab9fac4b2f48b486a40322f753f12776
---

# Handoff: [P2][STATE] Background-work orbit: one census for agents, workflows, and tasks

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-f2a0b1
```

## Scope

[P2][STATE] Background-work orbit: one census for agents, workflows, and tasks

## Inputs

- None declared.

## Work order

REWRITTEN 2026-08-10 (Erik-directed, replaces the stale orbit spec below). Ruling, per Erik's earlier decision plus today's: the PLAIN working spinner means the main agent is mid-turn; the EYE (eye.fill) means an armed /loop wakeup only; background shells/terminals get their OWN glyph — a literal seashell (fossil.shell.fill). Eye and shell render independently in the trailing cluster and may show together (today an armed wakeup hides the shell census entirely). Both glyphs must be VISIBLE — the current 8.5pt textTertiary 0.65-opacity eye is easy to miss (Erik screenshot 2026-08-10).

SLICE 1 (building now, session fc450563):
- Codex background-terminal census: the existing footer census is hard-gated `effectiveRuntime == .claude ? census : 0` (HolySession.swift:909-911) and its regex matches Claude's "· N shells ·" only; Codex's live footer says "· 1 background terminal running ·". Add a codex pattern with the same middle-dot fenceposts and last-three-lines live-chrome rule; gate becomes claude|codex. OpenCode stays out until its footer vocabulary is sighted.
- Glyph split + visibility: seashell for backgroundShellCount > 0 with per-runtime tooltip (shells vs terminals); eye keeps wakeup semantics and grace; both brighter and larger than today's mark.

STILL OPEN AFTER SLICE 1 (the census this issue is named for): a harness-side, kind-agnostic census of subagents/workflows/tasks at turn end. Hard prerequisite recorded by the 2026-08-07 audit: Tier 1 ("Stop publishes working|background-work") requires reversing the deliberate Stop-publishes-finished decision (7cb14daa2) — do not start it without deciding that conflict. Screen-scraped footer censuses are the interim truth.

--- superseded orbit spec (history) ---
Supersedes mn-da993c (swarm throbber), broadened per Erik 2026-07-21: the orbit channel means 'this session owns live autonomous work beyond the main loop', kind-agnostic. Swarms, single background agents, workflows, background Bash/Monitor loops all render as the same orbiting-satellites overlay on the unchanged six-state center; kind and count go in the tooltip only. Design pinned by live probe (zpc lesson 2026-07-21): subagent tool calls are hook-silent, so the census must be explicit. Tier 1: Stop hook publishes working|background-work (one reason family, optional count) instead of finished when the session owns ANY live harness-tracked work; SubagentStop re-runs the census. RESEARCH: what the harness exposes on disk at hook time to distinguish running from completed work (output files persist after completion, presence is not a running marker); whether SubagentStop fires reliably in the main session. Tier 2 / v1: extend the existing screen-telemetry parser (agentSwarmEvidence) with workflow-progress and background-task status patterns; presentation-only, never policy input. Orbit gets its own lease/extend/invalidate discipline so satellites cannot ghost. Deliberate exclusions: scheduled future work (loop/cron wakeups) is armed, not burning, and stays off the orbit; remote/cloud work is telemetry-only for now.

SLICE 1 ACCEPTED 2026-08-10 (Erik, live sighting): seashell confirmed on the codex row (background terminal census, widened window + liveness marker, commit 99f737032) and on a claude row (existing shells census made visible). Flicker on burst gaps is the designed honest retraction; a ~30s cool-down was offered and remains Erik's call. Remaining scope unchanged: harness-side kind-agnostic census at turn end, gated on the Stop-hook decision recorded above.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-f2a0b1`.
4. Commit with `Manna: mn-f2a0b1` and run `agent-do manna done mn-f2a0b1` only after the work is verified.
