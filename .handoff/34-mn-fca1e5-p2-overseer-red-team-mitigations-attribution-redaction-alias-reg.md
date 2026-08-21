---
workflow: 2
manna: mn-fca1e5
track: mn-6e363f
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P2][OVERSEER] Red-team mitigations: attribution, redaction, alias registry, fatigue-resistant confirms, tuning telemetry'
inputs: []
binding: sha256:197533461989e0e7f7aeaa9b8d2b9d162c32bc4839382c417062a5c7946ef378
---

# Handoff: [P2][OVERSEER] Red-team mitigations: attribution, redaction, alias registry, fatigue-resistant confirms, tuning telemetry

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-fca1e5
```

## Scope

[P2][OVERSEER] Red-team mitigations: attribution, redaction, alias registry, fatigue-resistant confirms, tuning telemetry

## Inputs

- None declared.

## Work order

Companion issue carrying the red-team findings (plan §Red-Team Findings) that cut across phases: (1) all spoken summaries ATTRIBUTE agent self-reports, high-stakes claims cross-check exit codes/git before assertive phrasing; (2) redaction pass before cloud TTS + local-voice-only scope for sensitive sessions; (3) unique speakable alias registry (roster has 8x 'Aldebaran Group' — fuzzy matching over duplicates is a contradiction, aliases are a J3 prerequisite); (4) confirmation relaxation is per-action-class only, never global, with periodic re-confirmation (fatigue erodes safe defaults); (5) announcement telemetry (missed/annoying/dismissed) so settle-window and focus-decay constants are tuned from evidence, not guesses; (6) quota exhaustion and hook-silence announce themselves — the Overseer's degraded modes are never silent.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-fca1e5`.
4. Commit with `Manna: mn-fca1e5` and run `agent-do manna done mn-fca1e5` only after the work is verified.
