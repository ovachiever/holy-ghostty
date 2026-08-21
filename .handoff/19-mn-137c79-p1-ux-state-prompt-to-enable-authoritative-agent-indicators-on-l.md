---
workflow: 2
manna: mn-137c79
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P1][UX][STATE] Prompt to enable authoritative agent indicators on launch'
inputs: []
binding: sha256:3d9700fdc03702601554249c61fb2c90b1dd44d73ccc76f9ea6b9e8e3e92c14d
---

# Handoff: [P1][UX][STATE] Prompt to enable authoritative agent indicators on launch

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-137c79
```

## Scope

[P1][UX][STATE] Prompt to enable authoritative agent indicators on launch

## Inputs

- None declared.

## Work order

State-driven one-time prompt when HolyAgentStateBridgeInstaller.currentUserInstallationState() == .notInstalled: offer Enable directly instead of requiring the app-menu item (invisible fullscreen; user could not find it). Closes the review gap where legacy indicators are deleted but the new system is opt-in — no operational indicators until enabled, with nothing telling the user. Menu item remains the manual override/disable path. Ref: AppDelegate.swift installAgentStateIndicatorMenuIfNeeded (~:1250), xhigh review finding on enable-gating.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-137c79`.
4. Commit with `Manna: mn-137c79` and run `agent-do manna done mn-137c79` only after the work is verified.
