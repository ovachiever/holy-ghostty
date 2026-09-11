---
workflow: 2
manna: mn-61fb80
track: mn-9a97cc
source: null
base_commit: a5b24f978bbfc2a83998a251bedff7babfcda76a
scope: '[P2][BOARD] The terminal crumb is always a labeled clickable item — never elided to a bare chevron'
inputs: []
binding: sha256:3766466c44473db849b4de8b9e81aa1071513f4e6629305aff95d6f1d5529bdf
---

# Handoff: [P2][BOARD] The terminal crumb is always a labeled clickable item — never elided to a bare chevron

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-61fb80
```

## Scope

[P2][BOARD] The terminal crumb is always a labeled clickable item — never elided to a bare chevron

## Inputs

- None declared.

## Work order

Erik 2026-09-10 (screenshot, ~1000pt window): board topbar reads '‹ › estate › holy-ghostty' — the compact branch (width < Metrics.measure 1440) collapses the terminal exit to an unlabeled '‹'. Ruling: the way back to the terminal is always shown as a clickable, labeled menu item at every width. Note Metrics.measure is documented as web-reference-only (Holy does not apply the 1440 measure, Erik 2026-09-02), so using it as the crumb breakpoint was drift. Fix: render the labeled '‹ terminal' crumb unconditionally in HolyMannaBoardView.crumb; compact continues to drop only the 'via host' suffix. Verification: SwiftLint strict on changed file, build-for-testing green, three Board suites executed green. Visual acceptance rides the held install.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-61fb80`.
4. Commit with `Manna: mn-61fb80` and run `agent-do manna done mn-61fb80` only after the work is verified.
