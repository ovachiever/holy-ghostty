---
workflow: 2
manna: mn-510a47
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P2][UX] Sidebar header gear menu for Holy feature toggles'
inputs: []
binding: sha256:135648526556148725a73ffa164c6c02f3813b1f0039843e01482d37cea4ab52
---

# Handoff: [P2][UX] Sidebar header gear menu for Holy feature toggles

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-510a47
```

## Scope

[P2][UX] Sidebar header gear menu for Holy feature toggles

## Inputs

- None declared.

## Work order

Add a small gear menu to the roster/sidebar header (the surface the user actually inhabits, especially fullscreen where the menu bar is hidden) carrying Holy app-level toggles: authoritative agent indicators, Claude model indicator, hosts. Mirrors — does not replace — the macOS app-menu items. Ref: HolySessionRosterView.swift header (~:220 moreMenu) for placement.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-510a47`.
4. Commit with `Manna: mn-510a47` and run `agent-do manna done mn-510a47` only after the work is verified.
