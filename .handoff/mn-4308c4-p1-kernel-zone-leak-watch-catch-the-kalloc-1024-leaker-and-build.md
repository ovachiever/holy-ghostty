---
workflow: 2
manna: mn-4308c4
track: mn-eb7a80
source: 'Kernel-panic/SSH-saturation joint diagnosis 2026-09-02 (forwarded MacBook agent analysis + Studio-side verification this session). Receipts: /System/Library/LaunchDaemons/ssh.plist inetdCompatibility.Instances=42 VERIFIED via plutil; panic-base+socd-2026-08-26-201523 panicString: zalloc zone map exhausted, zone data.kalloc.1024, 20G / 21,184,272 elements; Sep-1 file is the watchdog stub.'
base_commit: b5ffc3a81634ed9f0e847b02457011b542096982
scope: '[P1][KERNEL] Zone-leak watch: catch the kalloc.1024 leaker and build the Apple feedback packet'
inputs:
- 'Kernel-panic/SSH-saturation joint diagnosis 2026-09-02 (forwarded MacBook agent analysis + Studio-side verification this session). Receipts: /System/Library/LaunchDaemons/ssh.plist inetdCompatibility.Instances=42 VERIFIED via plutil; panic-base+socd-2026-08-26-201523 panicString: zalloc zone map exhausted, zone data.kalloc.1024, 20G / 21,184,272 elements; Sep-1 file is the watchdog stub.'
binding: sha256:fc3fc82f552850daa7f61f6fb22bf676aa7384357ee46ea1c443e00032d741c3
---

# Handoff: [P1][KERNEL] Zone-leak watch: catch the kalloc.1024 leaker and build the Apple feedback packet

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-4308c4
```

## Scope

[P1][KERNEL] Zone-leak watch: catch the kalloc.1024 leaker and build the Apple feedback packet

## Inputs

- Kernel-panic/SSH-saturation joint diagnosis 2026-09-02 (forwarded MacBook agent analysis + Studio-side verification this session). Receipts: /System/Library/LaunchDaemons/ssh.plist inetdCompatibility.Instances=42 VERIFIED via plutil; panic-base+socd-2026-08-26-201523 panicString: zalloc zone map exhausted, zone data.kalloc.1024, 20G / 21,184,272 elements; Sep-1 file is the watchdog stub.

## Work order

The overnight panics are kernel zone exhaustion, NOT directly the SSH cap: panic-base+socd-2026-08-26-201523 panicString = 'zalloc: zone map exhausted while allocating from zone [data.kalloc.1024], likely due to memory leak... (20G, 21,184,272 elements allocated)'. A userland cap cannot panic the kernel; the same overnight churn (per-connection inetd sshd spawns, thousands of rejected handshakes, KeepAlive LaunchAgent respawn loop, unbounded discovery sweeps) is the suspected FEEDER. Deliver: (1) a lightweight sampler (launchd or Holy-side) logging 'sudo zprint' (or footprint --zones) for data.kalloc.* hourly with timestamps + concurrent ssh/sshd process counts, to a durable log; (2) after the churn-reduction items land, correlate: if kalloc.1024 growth tracks churn, name the consumer (sockets/mach ports/ptys) via lsmp/fd census of the top holders; (3) if the leak persists with churn bounded, assemble the Apple Feedback packet (both panic files + zone growth log + repro description) — kernel memory that never returns is Apple's bug even when we pull the trigger. Do not tune kernel limits as a fix. Acceptance: a week of samples exists, growth attributed or ruled churn-independent, packet filed or explicitly not needed.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-4308c4`.
4. Commit with `Manna: mn-4308c4` and run `agent-do manna done mn-4308c4` only after the work is verified.
