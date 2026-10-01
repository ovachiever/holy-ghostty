---
workflow: 2
manna: mn-8b31bf
track: mn-9a97cc
source: Erik 2026-09-29 17:08; verified call sites 2026-09-29
base_commit: d3a2a94a9102c08f569cc0629db58f24e1a981c9
scope: '[P2][BOARD][TERMINAL] Command-click on an mn-id opens a popover: digest, status, host, intelligence level and model, Claim & build'
inputs:
- Erik 2026-09-29 17:08; verified call sites 2026-09-29
binding: sha256:e54a136ed3c85e3349306515ba48a806da910736dad82f84327ffd0dda1ff360
---

# Handoff: [P2][BOARD][TERMINAL] Command-click on an mn-id opens a popover: digest, status, host, intelligence level and model, Claim & build

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-8b31bf
```

## Scope

[P2][BOARD][TERMINAL] Command-click on an mn-id opens a popover: digest, status, host, intelligence level and model, Claim & build

## Inputs

- Erik 2026-09-29 17:08; verified call sites 2026-09-29

## Work order

Erik, 2026-09-29, building it himself. Today Command-click on a Manna id resolves it estate-wide (HolyMannaBoardLink.swift, HolyMannaBoardStore.swift:397-418) and switches the terminal area to Board mode. Instead, anchor a native popover at the clicked id's cell rect and compose it from parts that already exist: the per-item AI digest (HolyMannaBoardStore.presentationDigest(for:) at :933, shown today in ledger rows at HolyMannaBoardView.swift:597 and detail at :1125), the item title, status, claim, readiness and which board and host it lives on, the intelligence level picker and model override (HolyMannaBoardView.swift:1149-1155, store.workerLevel and store.workerModel), and the Claim & build button (HolyMannaBoardView.swift:84, store.confirmWorker()), plus an Open in Board link. Rules: when the digest is not prewarmed show 'summary pending' and trigger generation for that item only; Claim & build is disabled with the reason shown for a claimed, unready, or unsealed item, the same gates the Board applies; Return never launches anything and Escape dismisses, keeping the Cancel-default ethos of every dispatch sheet; the launch is the existing confirmed dispatch path in-app, never a URL route; the popover is an AppKit window over the surface, so the one-grid-one-painter rule (text styling only in the core render pass) is untouched. Done when: a Command-click on a sealed, ready, unclaimed id shows the popover within one frame with digest or pending state, picking a level and pressing Claim & build creates the worker exactly as the Board's button does (same brief, same roster row), a claimed id shows the disabled button with its reason, Escape closes it, and Return does nothing. Tests: popover content from a fixture item with and without a digest; disabled states for the three gates; key handling. Not a 1.0 gate.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-8b31bf`.
4. Commit with `Manna: mn-8b31bf` and run `agent-do manna done mn-8b31bf` only after the work is verified.
