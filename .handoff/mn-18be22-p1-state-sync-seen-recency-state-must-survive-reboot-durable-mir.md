---
workflow: 2
manna: mn-18be22
track: mn-eb7a80
source: Erik post-reboot report 2026-09-08 + fresh tmux server receipts (start_time post-boot, options empty)
base_commit: a416dae2ab0c865b7e6dd68a63eaed6e89dd4c8a
scope: '[P1][STATE][SYNC] Seen/recency state must survive reboot: durable mirror + option rehydration'
inputs:
- Erik post-reboot report 2026-09-08 + fresh tmux server receipts (start_time post-boot, options empty)
binding: sha256:cccb76b63f1814039f29f2ee609085e646abd396e181a76bd7626ed69146eb86
---

# Handoff: [P1][STATE][SYNC] Seen/recency state must survive reboot: durable mirror + option rehydration

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-18be22
```

## Scope

[P1][STATE][SYNC] Seen/recency state must survive reboot: durable mirror + option rehydration

## Inputs

- Erik post-reboot report 2026-09-08 + fresh tmux server receipts (start_time post-boot, options empty)

## Work order

Erik 2026-09-08 post-reboot: all recency/seen icons gone. Mechanism: mn-2c82a2 made indicators host-authoritative via tmux user options — correct for cross-machine truth, but tmux options are PER-BOOT: the server died at reboot and took every @holy_seen/finished/wire value with it, so indicators blank even though the sessions restored. Fix: the owning host keeps a durable mirror of the option-borne indicator state (the host Holy's SQLite is the natural home — a small keyed table written whenever options change via the existing hook/ack paths), and restore/adoption REHYDRATES the tmux options from the mirror before first render, so the roster paints identical dots after reboot, clear/re-attach, or adoption on any machine. The options remain the live read surface (cross-machine law unchanged); the mirror is boot insurance only, never a second source of truth while the server lives. Acceptance: mark seen states, reboot the host, restore — every dot, orb, and recency ordering identical to pre-reboot; and the mn-2c82a2 cross-machine acceptance still passes afterward.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-18be22`.
4. Commit with `Manna: mn-18be22` and run `agent-do manna done mn-18be22` only after the work is verified.

## Implementation receipt, 2026-09-08

Schema 13 journals the producer host registers, and generated hooks/acks/restore/adoption/discovery preserve and rehydrate them. Real disposable tmux servers were destroyed and recreated successfully. Installed cross-machine acceptance and an actual host reboot remain unverified.

Final focused suites: 238 PASSED, 0 FAILED, 0 SKIPPED. Separate fresh-Codex acceptance: 1 PASSED, 0 FAILED, 0 SKIPPED (two real conversations across Xcode executions). Full report, exact IDs, failed-run history, and test-isolation correction: `.dev/mn-reboot-recovery/report.md`. A legacy test initially wrote eight synthetic host-journal rows; its database target is now isolated, and no session records were modified by that journal writer.

Status remains `in_progress` for coordinated installed-app acceptance. No install or push. Do not run Clear against a live roster outside that coordinated acceptance.
