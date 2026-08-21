---
workflow: 2
manna: mn-737aa0
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P2][STATE] Restore notification click ownership guard without breaking relaunch replay'
inputs: []
binding: sha256:29756b7dede6515d2ec6ea762cc10330b484c99378c1094f594173c7a8fa35f7
---

# Handoff: [P2][STATE] Restore notification click ownership guard without breaking relaunch replay

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-737aa0
```

## Scope

[P2][STATE] Restore notification click ownership guard without breaking relaunch replay

## Inputs

- None declared.

## Work order

xhigh review finding (PLAUSIBLE, SurfaceView_AppKit.swift:1890): handleUserNotification dropped the notificationIdentifiers.remove(id) ownership check to allow Holy's relaunch replay (in-memory set empty after restart), but that also lets clicks on stale generic banners (command-finished, bell) yank focus to a surface hours later mid-typing. Scope the guard: holy-agent| prefixed identifiers may replay without ownership; generic surface notifications require it.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-737aa0`.
4. Commit with `Manna: mn-737aa0` and run `agent-do manna done mn-737aa0` only after the work is verified.
