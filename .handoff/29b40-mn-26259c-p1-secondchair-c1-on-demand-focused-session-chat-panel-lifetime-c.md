---
workflow: 2
manna: mn-26259c
track: mn-6e363f
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P1][SECONDCHAIR] C1: on-demand focused-session chat — panel-lifetime chair child, Holy-pushed content, intent ledger in Holy DB'
inputs: []
binding: sha256:d4a1e4e157b48dedfab764da807fc2e23b419912c3152671c4f8ba96e36a9b87
---

# Handoff: [P1][SECONDCHAIR] C1: on-demand focused-session chat — panel-lifetime chair child, Holy-pushed content, intent ledger in Holy DB

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-26259c
```

## Scope

[P1][SECONDCHAIR] C1: on-demand focused-session chat — panel-lifetime chair child, Holy-pushed content, intent ledger in Holy DB

## Inputs

- None declared.

## Work order

REVISED per Codex review 2026-07-17 (Jarvis residue removed). Pull-based: Holy spawns 'agent-do chair serve --stdio' when the panel opens and ties its lifetime to the panel — NO launchd residency, NO announcement queue, NO salience tiers, NO digest scheduler, NO watermark replay, NO heartbeat daemon. Crash = respawn + fresh context.snapshot.

Content path (fixes the blocked contradiction — mn-e59548 observe is metadata-only BY DESIGN): embedded use gets a bounded, consented screen snapshot/delta pushed by Holy directly over the C0 protocol, using Holy's existing screen-text primitives behind a deliberate privacy boundary; a separately permissioned 'holyctl sessions tail' provider is a later standalone/SSH option.

Ownership per corrected map: intent ledger + companion transcript persist in HOLY's database (durable user intent is body-side); the chair holds conversation state only for its lifetime. Privacy fence covers the cloud LLM itself, not just TTS: transcript content, branch names, manna titles leave the machine through the model provider — redaction/consent scope applies at the chair boundary.

Persona: colleague with standards — must disagree when warranted. Salience/digest machinery is PARKED with push-announcements; the pull-world equivalent is on-demand 'what's new?' briefing via C3.

Done when: open panel on a focused session → chair converses about its actual content within seconds; intent ledger entries persist across relaunch in Holy's DB; kill -9 the chair mid-conversation → panel reports degraded, respawn recovers from fresh snapshot; all exchanges audited. Depends: C0 (mn-c85876).

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-26259c`.
4. Commit with `Manna: mn-26259c` and run `agent-do manna done mn-26259c` only after the work is verified.
