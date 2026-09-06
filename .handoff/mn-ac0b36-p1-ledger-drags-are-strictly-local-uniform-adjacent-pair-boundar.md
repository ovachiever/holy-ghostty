---
workflow: 2
manna: mn-ac0b36
track: mn-9a97cc
source: Erik live pass 2026-09-06 12:17 + direct code read of HolyLedgerColumns.swift this session
base_commit: 4295f14118dafe493a1fa04eec8a83b460c99623
scope: '[P1][LEDGER] Drags are strictly local: uniform adjacent-pair boundaries, zero mid-drag refit'
inputs:
- Erik live pass 2026-09-06 12:17 + direct code read of HolyLedgerColumns.swift this session
binding: sha256:a4d8200f18d9459083b915be421e469fe812da377fdf4ea74d1686feea72c79e
---

# Handoff: [P1][LEDGER] Drags are strictly local: uniform adjacent-pair boundaries, zero mid-drag refit

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-ac0b36
```

## Scope

[P1][LEDGER] Drags are strictly local: uniform adjacent-pair boundaries, zero mid-drag refit

## Inputs

- Erik live pass 2026-09-06 12:17 + direct code read of HolyLedgerColumns.swift this session

## Work order

Erik's live pass 2026-09-06: resizing STATE on the board visibly moves TRACK into DIGEST, and grips/inspector 'shake violently while resizing'. Humans solved table resizing decades ago; the port over-thought it. Receipts from HolyLedgerColumns.swift:219-291: the boundary model has THREE behaviors (fixedBeforeFlexible, fixedAfterFlexible with inverse delta, fixedPair) — any boundary that routes compensation through the flexible DIGEST column causes distant columns to translate mid-drag, and the responsive re-fit (columns(...) at :153) renormalizes widths DURING the drag, so even honest pair exchanges get re-laid out per frame (the shake, per the live-pass-shake coord drop of 12:02). Replace with the boring standard, uniformly: (1) EVERY grip is an adjacent-pair exchange between the two columns physically touching that divider — including pairs where DIGEST is a member (id|digest, digest|track) with digest's floor honored; one case, no inverse-delta special forms; delete fixedBeforeFlexible/fixedAfterFlexible. (2) While a drag is active, NO renormalization, no re-fit, no proportion writes — raw pair math against bounds captured at drag start; persist and renormalize exactly once on release; epsilon-guard width writes. (3) Window resize (not drags) remains the only place DIGEST flexes to absorb. (4) Tests: per-grip cases asserting ONLY the divider's two neighbors change and every other column's frame is identical before/after each intermediate drag frame; a monotonicity test (no width ever reverses against pointer direction); one-normalization-per-drag-lifecycle. Same model for archive. Relates to mn-f044d0 (still open for the overall visual pass) and supersedes the drag portions of mn-6842ed's implementation.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-ac0b36`.
4. Commit with `Manna: mn-ac0b36` and run `agent-do manna done mn-ac0b36` only after the work is verified.
