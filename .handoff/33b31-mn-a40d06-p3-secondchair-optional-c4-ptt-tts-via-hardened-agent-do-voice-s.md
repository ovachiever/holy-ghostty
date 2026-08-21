---
workflow: 2
manna: mn-a40d06
track: mn-6e363f
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P3][SECONDCHAIR][OPTIONAL] C4: PTT + TTS via hardened agent-do voice speak + future dictate'
inputs: []
binding: sha256:4de1ebfa9d7c9ef15d3a06c0fccc96cfffb2cd9fd0540c20461954494ab48ef1
---

# Handoff: [P3][SECONDCHAIR][OPTIONAL] C4: PTT + TTS via hardened agent-do voice speak + future dictate

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-a40d06
```

## Scope

[P3][SECONDCHAIR][OPTIONAL] C4: PTT + TTS via hardened agent-do voice speak + future dictate

## Inputs

- None declared.

## Work order

REVISED per Codex review 2026-07-17: optional voice layer only — wake word, barge-in, announcement memory, and co-work mode all REMOVED from scope (they were Jarvis residue; co-work is a separate future program). PTT via future agent-do dictate (open side-quest on the agent-do board, TeleFollower-derived streaming); TTS via agent-do voice speak — which is BLOCKED until hardened: agent-voice line ~63 builds a shell string and evals it, so model text containing $(...) executes; must move to argument arrays with adversarial tests (tracked on the agent-do board). Use the real tool name 'voice speak', not an invented 'say'. Redaction before cloud TTS per mn-fca1e5.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-a40d06`.
4. Commit with `Manna: mn-a40d06` and run `agent-do manna done mn-a40d06` only after the work is verified.
