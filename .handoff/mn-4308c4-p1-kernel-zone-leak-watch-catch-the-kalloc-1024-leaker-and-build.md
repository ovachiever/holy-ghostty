---
workflow: 2
manna: mn-4308c4
track: mn-eb7a80
source: 'Kernel-panic/SSH-saturation joint diagnosis 2026-09-02 (forwarded MacBook agent analysis + Studio-side verification this session). Receipts: /System/Library/LaunchDaemons/ssh.plist inetdCompatibility.Instances=42 VERIFIED via plutil; panic-base+socd-2026-08-26-201523 panicString: zalloc zone map exhausted, zone data.kalloc.1024, 20G / 21,184,272 elements; Sep-1 file is the watchdog stub.'
base_commit: b5ffc3a81634ed9f0e847b02457011b542096982
scope: '[P1][KERNEL] Zone-leak watch: catch the kalloc.1024 leaker and build the Apple feedback packet'
inputs:
- 'Kernel-panic/SSH-saturation joint diagnosis 2026-09-02 (forwarded MacBook agent analysis + Studio-side verification this session). Receipts: /System/Library/LaunchDaemons/ssh.plist inetdCompatibility.Instances=42 VERIFIED via plutil; panic-base+socd-2026-08-26-201523 panicString: zalloc zone map exhausted, zone data.kalloc.1024, 20G / 21,184,272 elements; Sep-1 file is the watchdog stub.'
binding: sha256:58ddef5b8d34e7b329f2d9e58d9819f6bee2bc62a7ce16c63cf68f811a342a76
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

## Continuation state: watcher active, observation window open

### Delivered on 2026-09-02

- `scripts/holy-kernel-zone-watch.sh` samples every `data.kalloc.*` size class
  into a 21-field TSV. Each row binds the kernel value to UTC time, boot epoch,
  uptime, `ssh`/`sshd`/`tmux` process counts, and visible launchd SSH counters.
- Current bytes are derived from the stable element-size and in-use fields.
  Sparse `zprint -t` lifetime columns and trailing `P`/`C` flags are recorded
  without being mistaken for the current allocation.
- `scripts/install-holy-studio-guards.sh` installs the root-owned helper and a
  low-priority LaunchDaemon with `RunAtLoad=true` and `StartInterval=3600`.
  It validates SSH, samples once synchronously, verifies launchd admission,
  preserves replaced artifacts, and rolls back installed configuration on any
  failure.
- `scripts/test-holy-studio-guards.sh` proves parsing, process correlation,
  missing-data behavior, short-window rate suppression, launchd shape,
  protected-file invariance, idempotent replacement, and rollback.
- The fixture suite and a live unprivileged sample pass. `git diff --check`
  passes. `shellcheck` is unavailable on this host.

### Live install receipts

- LaunchDaemon: `system/org.holyghostty.kernel-zone-watch`, admitted with
  one-hour interval, last exit code `0`, no stderr.
- Helper:
  `/Library/PrivilegedHelperTools/org.holyghostty.kernel-zone-watch`.
- Samples:
  `/Library/Logs/Holy Ghostty/kernel-zone-watch/samples.tsv`.
- Root install receipt:
  `/Library/Logs/Holy Ghostty/kernel-zone-watch/install-receipt.txt`.
- First four startup samples placed `data.kalloc.1024` between 242.945 and
  243.860 MiB, compared with roughly 20 GiB in the 2026-08-26 panic.
- The four startup samples span only 128 seconds. The repo report therefore
  exposes their raw delta but correctly reports `rate_window_status=insufficient`
  and withholds an hourly extrapolation until at least 1,800 seconds exist.

### Installed-source note

The installed helper SHA-256 is
`a2388d7e70734efda137ed8ef7082d1762c79fe93e3ede48a7486ddcd8c4c240`.
It includes the complete sampling path and the sparse `zprint` parser fix. The
current repo source SHA-256 is
`52a96160af22b884fc3e893fafd75d3fcb1b8a7a56b57bb17ef3e07838524ab9`;
the only later behavior change is the 30-minute guard in the interactive
report command. A follow-up administrator dialog to synchronize that
report-only change was canceled, so it was not retried. The scheduled sampler
does not call `report`, and the repo report reads the installed log safely.

### Needed next

- Keep this Manna item open until at least one week of hourly samples exists.
- Use `scripts/holy-kernel-zone-watch.sh report` for the latest-boot curve.
- After the observation window, compare zone growth with the recorded process
  and launchd counters. If `data.kalloc.1024` keeps growing after churn is
  bounded, capture targeted `lsmp` and file-descriptor censuses, then assemble
  the two panic files, this log, and the reproduction description for Apple.
- Synchronize the report-only helper revision during the next approved
  privileged maintenance. It is not required for scheduled sampling.
