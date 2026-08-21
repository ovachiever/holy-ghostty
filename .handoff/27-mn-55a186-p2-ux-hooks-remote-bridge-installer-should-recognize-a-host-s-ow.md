---
workflow: 2
manna: mn-55a186
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P2][UX][HOOKS] Remote bridge installer should recognize a host''s own local Holy installation'
inputs: []
binding: sha256:d933256161b7a92f29492f4181956499e746288a0707d31743a363f8c7885fb4
---

# Handoff: [P2][UX][HOOKS] Remote bridge installer should recognize a host's own local Holy installation

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-55a186
```

## Scope

[P2][UX][HOOKS] Remote bridge installer should recognize a host's own local Holy installation

## Inputs

- None declared.

## Work order

Observed 2026-07-15: MacBook Hosts sheet reports the Studio's authoritative-indicator bridge as blocked ('a guarded user setting already has a different value') — but the Studio has a complete, healthy, Holy-owned v3 LOCAL install. Root cause: local installs write notify as ~/Library/Application Support/Holy Ghostty/holy-codex-turn-complete.py while remote installs use ~/.local/share/holy-ghostty/; same guarded key (codex top-level notify), different Holy-owned value, so the remote guarded-merge fails closed (correct — otherwise two Holy apps would flip-flop the line). Fix: when the existing guarded line carries Holy's ownership marker with the LOCAL path convention, report the host as 'locally managed by Holy Ghostty on that host' (informational, not blocked) and skip remote management for that harness. Never let two installers co-manage one guarded key. Ref: HolyAgentStateBridge.swift guardedTextDocuments (~:248), HolyRemoteAgentStateBridgeService.swift foreign-guarded-setting (~:565).

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-55a186`.
4. Commit with `Manna: mn-55a186` and run `agent-do manna done mn-55a186` only after the work is verified.
