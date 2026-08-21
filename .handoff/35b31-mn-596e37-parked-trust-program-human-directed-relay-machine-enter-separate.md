---
workflow: 2
manna: mn-596e37
track: mn-6e363f
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[PARKED][TRUST-PROGRAM] Human-directed relay (machine Enter) — separate program outside Second Chair core'
inputs: []
binding: sha256:9c474c018f9163076fb100bf0bfd16a70171cf68104bbb61777e985c31d64c02
---

# Handoff: [PARKED][TRUST-PROGRAM] Human-directed relay (machine Enter) — separate program outside Second Chair core

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-596e37
```

## Scope

[PARKED][TRUST-PROGRAM] Human-directed relay (machine Enter) — separate program outside Second Chair core

## Inputs

- None declared.

## Work order

Erik's planner/coder case (2026-07-16): four Aldebaran sessions — orchestrator + coders A/B/C. While focused elsewhere: 'C finished — tell the orchestrator, read me its reply' → approve → 'paste into C and press Enter.' Decision and content are human; only TRANSMISSION is delegated. Distinct from parked autonomy (mn-70a8ac): no standing orders, no chained relays — every Enter is purchased by a human utterance; the companion never auto-bounces orchestrator↔coder.

Safety mechanisms:
- Target readiness proven by the triggering event: only sends into sessions whose latest committed envelope is finished/idle, RE-CHECKED at send time; any working/needs-user/unknown since → refuse and report. Never sends at permission prompts (not a clean REPL → abort).
- Two-phase verified send: sendText → capture-pane byte-verify the typed text → only then Enter; mismatch → abort loudly (converts unsolved paste corruption mn-c3b48a from silent hazard to detected abort — does NOT require the root fix).
- Non-empty input line at target → report, never append.
- Relay notifications are templated and shown before sending; payloads into coder sessions are verbatim-approved. All sends carry [relayed by second chair on Erik's behalf] provenance and land in timeline + transcript.
- One in-flight relay at a time.

Done when: the full loop (C finishes → notify orchestrator → read reply to Erik → approved paste+Enter into C) works from another focused session with every hop human-approved, byte-verified, audited — and a deliberately induced mid-send working event or pane mismatch aborts with a spoken/printed explanation.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-596e37`.
4. Commit with `Manna: mn-596e37` and run `agent-do manna done mn-596e37` only after the work is verified.
