---
workflow: 2
manna: mn-d856ee
track: mn-eb7a80
source: 'Kernel-panic/SSH-saturation joint diagnosis 2026-09-02 (forwarded MacBook agent analysis + Studio-side verification this session). Receipts: /System/Library/LaunchDaemons/ssh.plist inetdCompatibility.Instances=42 VERIFIED via plutil; panic-base+socd-2026-08-26-201523 panicString: zalloc zone map exhausted, zone data.kalloc.1024, 20G / 21,184,272 elements; Sep-1 file is the watchdog stub.'
base_commit: b5ffc3a81634ed9f0e847b02457011b542096982
scope: '[P1][OPS][SSH] Host hygiene: retire the KeepAlive tmux LaunchAgent, raise Studio MaxSessions, repair MacBook multiplex config'
inputs:
- 'Kernel-panic/SSH-saturation joint diagnosis 2026-09-02 (forwarded MacBook agent analysis + Studio-side verification this session). Receipts: /System/Library/LaunchDaemons/ssh.plist inetdCompatibility.Instances=42 VERIFIED via plutil; panic-base+socd-2026-08-26-201523 panicString: zalloc zone map exhausted, zone data.kalloc.1024, 20G / 21,184,272 elements; Sep-1 file is the watchdog stub.'
binding: sha256:6f893b833c4fac0006cd08964b8288a9b6b830f75b2f83884918851049e3fd87
---

# Handoff: [P1][OPS][SSH] Host hygiene: retire the KeepAlive tmux LaunchAgent, raise Studio MaxSessions, repair MacBook multiplex config

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-d856ee
```

## Scope

[P1][OPS][SSH] Host hygiene: retire the KeepAlive tmux LaunchAgent, raise Studio MaxSessions, repair MacBook multiplex config

## Inputs

- Kernel-panic/SSH-saturation joint diagnosis 2026-09-02 (forwarded MacBook agent analysis + Studio-side verification this session). Receipts: /System/Library/LaunchDaemons/ssh.plist inetdCompatibility.Instances=42 VERIFIED via plutil; panic-base+socd-2026-08-26-201523 panicString: zalloc zone map exhausted, zone data.kalloc.1024, 20G / 21,184,272 elements; Sep-1 file is the watchdog stub.

## Work order

Ops item; needs Erik or sudo at two points. (1) STUDIO: ~/Library/LaunchAgents/com.erik.tmux.plist (present, dated Mar 9) runs 'tmux start-server' with KeepAlive=true; the command exits immediately so launchd respawn-throttles it forever, it targets the default tmux server (not Holy's -L holy) so it protects nothing — bootout and remove, or convert to a one-shot; given the zone-leak suspicion, eliminating continuous spawn churn is prudent. (2) STUDIO (sudo): /etc/ssh/sshd_config raise MaxSessions to ~110 so multiplexed masters can carry ~100 channels each; do not touch the sealed ssh.plist. (3) MACBOOK (~/Documents/AI path, TCC constraints per house memory — work via a session ON that machine): ~/.ssh/config enables ControlMaster only for aliases studio/studio-lan while Holy stores the literal 'eriks-mac-studio-1', bypassing it; add a Host block covering the literal names (and MagicDNS variants) with ControlMaster auto, ControlPersist, and a ControlPath under a 0700 dir — belt-and-suspenders until the Holy transport manager (P0 sibling) makes client config irrelevant. Acceptance: LaunchAgent gone from launchctl, sshd_config change active (sshd -T shows maxsessions), MacBook config verified with 'ssh -O check' against the literal hostname.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-d856ee`.
4. Commit with `Manna: mn-d856ee` and run `agent-do manna done mn-d856ee` only after the work is verified.
