---
workflow: 2
manna: mn-effdbd
track: mn-eb7a80
source: 'Kernel-panic/SSH-saturation joint diagnosis 2026-09-02 (forwarded MacBook agent analysis + Studio-side verification this session). Receipts: /System/Library/LaunchDaemons/ssh.plist inetdCompatibility.Instances=42 VERIFIED via plutil; panic-base+socd-2026-08-26-201523 panicString: zalloc zone map exhausted, zone data.kalloc.1024, 20G / 21,184,272 elements; Sep-1 file is the watchdog stub.'
base_commit: b5ffc3a81634ed9f0e847b02457011b542096982
scope: '[P0][REMOTE][SSH] HolySSHTransportManager: three ControlMasters per host, every raw ssh call site routed through it'
inputs:
- 'Kernel-panic/SSH-saturation joint diagnosis 2026-09-02 (forwarded MacBook agent analysis + Studio-side verification this session). Receipts: /System/Library/LaunchDaemons/ssh.plist inetdCompatibility.Instances=42 VERIFIED via plutil; panic-base+socd-2026-08-26-201523 panicString: zalloc zone map exhausted, zone data.kalloc.1024, 20G / 21,184,272 elements; Sep-1 file is the watchdog stub.'
binding: sha256:bf57df877fa621e3991b84663aebd8598d1b3ca4b86e7302fe081f3085de4420
---

# Handoff: [P0][REMOTE][SSH] HolySSHTransportManager: three ControlMasters per host, every raw ssh call site routed through it

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-effdbd
```

## Scope

[P0][REMOTE][SSH] HolySSHTransportManager: three ControlMasters per host, every raw ssh call site routed through it

## Inputs

- Kernel-panic/SSH-saturation joint diagnosis 2026-09-02 (forwarded MacBook agent analysis + Studio-side verification this session). Receipts: /System/Library/LaunchDaemons/ssh.plist inetdCompatibility.Instances=42 VERIFIED via plutil; panic-base+socd-2026-08-26-201523 panicString: zalloc zone map exhausted, zone data.kalloc.1024, 20G / 21,184,272 elements; Sep-1 file is the watchdog stub.

## Work order

macOS runs sshd inetd-style with a hard 42-instance cap (verified: ssh.plist inetdCompatibility.Instances=42). Holy holds one TCP connection per remote surface (~37 persistent) plus bursts for discovery/kill/probe/metadata, so overnight swarms hit 42 and launchd resets new handshakes during kex — the observed 'kex_exchange_identification: Connection reset by peer' on LAN and Tailscale. Build a host-scoped HolySSHTransportManager: TWO interactive ControlMasters for terminal surfaces + ONE reserved control master for discovery/kill/roster/metadata (lifecycle must survive interactive saturation); app-owned ControlPath sockets in a private 0700 directory; health via 'ssh -O check'; locked stale-socket removal and master recreation; bounded reconnect backoff after sleep, network change, or Tailscale reconvergence. Route EVERY raw ssh call site through it: HolyTmuxCommandBuilder.swift:164-176 (interactive attach), HolyRemoteTmuxDiscoveryService.swift:152-177 (discovery), HolyTmuxLifecycleService.swift:381-398 (kill/probe), HolyRemoteAgentStateBridgeService.swift:211-226 (agent-state bridge). Capacity ~100 channels per interactive master -> ~200 surfaces on 3 of 42 instances. Do NOT: edit the sealed ssh.plist, raise ptmx_max or maxproc (audited non-limiting: PTYs 89/511, procs far under 10666/16000), rely on MaxSessions alone, or kill random connections. Acceptance: with 40+ attached remote surfaces plus a concurrent discovery storm, the server-side sshd instance count for the host stays <=3; saturation test exists; Holy's stored destination may be a literal MagicDNS name (HolyRemoteHostImportService.swift:63-100 imports bypass user ssh aliases) and must still multiplex — the manager owns multiplexing, never the user's ssh config.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-effdbd`.
4. Commit with `Manna: mn-effdbd` and run `agent-do manna done mn-effdbd` only after the work is verified.
