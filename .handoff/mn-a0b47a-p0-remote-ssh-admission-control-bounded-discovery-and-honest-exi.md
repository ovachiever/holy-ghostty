---
workflow: 2
manna: mn-a0b47a
track: mn-eb7a80
source: 'Kernel-panic/SSH-saturation joint diagnosis 2026-09-02 (forwarded MacBook agent analysis + Studio-side verification this session). Receipts: /System/Library/LaunchDaemons/ssh.plist inetdCompatibility.Instances=42 VERIFIED via plutil; panic-base+socd-2026-08-26-201523 panicString: zalloc zone map exhausted, zone data.kalloc.1024, 20G / 21,184,272 elements; Sep-1 file is the watchdog stub.'
base_commit: b5ffc3a81634ed9f0e847b02457011b542096982
scope: '[P0][REMOTE][SSH] Admission control, bounded discovery, and honest exit-255 diagnostics'
inputs:
- 'Kernel-panic/SSH-saturation joint diagnosis 2026-09-02 (forwarded MacBook agent analysis + Studio-side verification this session). Receipts: /System/Library/LaunchDaemons/ssh.plist inetdCompatibility.Instances=42 VERIFIED via plutil; panic-base+socd-2026-08-26-201523 panicString: zalloc zone map exhausted, zone data.kalloc.1024, 20G / 21,184,272 elements; Sep-1 file is the watchdog stub.'
binding: sha256:852eba144281bf43054e9c42ca0d0fca3a4a069eaa5e7bca4106538c34e111f2
---

# Handoff: [P0][REMOTE][SSH] Admission control, bounded discovery, and honest exit-255 diagnostics

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-a0b47a
```

## Scope

[P0][REMOTE][SSH] Admission control, bounded discovery, and honest exit-255 diagnostics

## Inputs

- Kernel-panic/SSH-saturation joint diagnosis 2026-09-02 (forwarded MacBook agent analysis + Studio-side verification this session). Receipts: /System/Library/LaunchDaemons/ssh.plist inetdCompatibility.Instances=42 VERIFIED via plutil; panic-base+socd-2026-08-26-201523 panicString: zalloc zone map exhausted, zone data.kalloc.1024, 20G / 21,184,272 elements; Sep-1 file is the watchdog stub.

## Work order

Companion to the transport manager (sequence the budget enforcement after it lands; the bounding and diagnostics work even against raw ssh and should not wait). (1) Track surface channels and control operations per host; reserve capacity for lifecycle commands; refuse or queue new launches before the channel budget exhausts. (2) Serialize or bound concurrent discovery sweeps — today they open unbounded simultaneous handshakes and a burst alone can reach the 42-instance cap. (3) Diagnostics honesty: detect kex_exchange_identification resets and report SSH instance saturation explicitly; stop printing 'could not reach' for every exit 255 — split network failure vs launchd rejection vs authentication failure vs remote-command failure into distinct, logged, user-visible states (this conflation has already cost debugging time on this board). Acceptance: a synthetic saturation run produces the explicit saturation diagnosis, queued launches instead of failures, and discovery concurrency stays within its bound.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-a0b47a`.
4. Commit with `Manna: mn-a0b47a` and run `agent-do manna done mn-a0b47a` only after the work is verified.
