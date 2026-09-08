---
workflow: 2
manna: mn-455be1
track: mn-eb7a80
source: MacBook mirror agent report 2026-09-03 13:41, raw ssh stderr from session_events
base_commit: 028b2a7d4dccc73c6189d909ba8037e84ec71de0
scope: '[P0][REMOTE] ControlPath exceeds the Unix socket limit — every SSH master fails on every Mac'
inputs:
- MacBook mirror agent report 2026-09-03 13:41, raw ssh stderr from session_events
binding: sha256:d474d3522e77b6ea0a8a6e125b41d0d00f2ebf768c571b25d731ab9a81e14c33
---

# Handoff: [P0][REMOTE] ControlPath exceeds the Unix socket limit — every SSH master fails on every Mac

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-455be1
```

## Scope

[P0][REMOTE] ControlPath exceeds the Unix socket limit — every SSH master fails on every Mac

## Inputs

- MacBook mirror agent report 2026-09-03 13:41, raw ssh stderr from session_events

## Work order

Found by the MacBook mirror agent 2026-09-03: HolySSHTransportManager.controlPath() renders ~/Library/Caches/org.holyghostty.app/ssh-control/<24hex>-<lane>.sock (114-120 bytes); OpenSSH's mux listener binds path+'.'+16 random chars against the 104-byte sun_path cap, so the configured path must stay <=86 bytes. Every master fails at unix_listener, the fail-closed ProxyCommand=/usr/bin/false wrapper reports 'SSH exited before Holy could prove whether it reached the host', and on the MacBook this recovery-archived 25 remote sessions at launch. Fix: socket dir ~/.holy/ssh (0700, ~36-byte rendered paths), 8-hex host hash, lane tokens i0/i1/c; pre-flight length guard throwing a typed over-limit error naming the path and cap; pinned test asserting the rendered default stays under 80 bytes plus the guard's refusal case. Regression on mn-effdbd (its tests never asserted path length).

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-455be1`.
4. Commit with `Manna: mn-455be1` and run `agent-do manna done mn-455be1` only after the work is verified.
