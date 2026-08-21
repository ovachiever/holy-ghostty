---
workflow: 2
manna: mn-5016e9
track: mn-6e363f
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P1][SECONDCHAIR] C2: proposal review + control-byte-safe insertDraft — human Enter enforced structurally'
inputs: []
binding: sha256:bed39f6037a4ce8228a24a12241d881362f32e58731f67e766dda86d6abf90b6
---

# Handoff: [P1][SECONDCHAIR] C2: proposal review + control-byte-safe insertDraft — human Enter enforced structurally

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-5016e9
```

## Scope

[P1][SECONDCHAIR] C2: proposal review + control-byte-safe insertDraft — human Enter enforced structurally

## Inputs

- None declared.

## Work order

REVISED per Codex review 2026-07-17. sendText passes raw bytes (Ghostty.Surface.swift:38) — a draft containing \n, \r, or ESC could submit or manipulate the terminal despite the product promise. Holy gains a narrow insertDraft boundary: requires an explicit user Insert action (chair proposes via draft.proposed; only the human inserts); rejects CR/LF/ESC and all control bytes; verifies session ID and focus_epoch still match at insert time (epoch N draft dies at epoch N+1); caps draft size; NO enter/submit operation exists in the chair protocol (C0 guarantee). Single-line insertion v1; multiline later via a verified runtime-aware paste path. Done when: discuss → 'write it' → draft shown in panel → user clicks Insert → sanitized text lands in the input line → user edits/presses Enter; adversarial drafts (embedded newlines, ANSI escapes, oversized) are rejected with visible explanation; stale-epoch drafts refuse to insert. Core Second Chair is COMPLETE at C2 acceptance.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-5016e9`.
4. Commit with `Manna: mn-5016e9` and run `agent-do manna done mn-5016e9` only after the work is verified.
