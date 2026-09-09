---
workflow: 2
manna: mn-b09383
track: mn-eb7a80
source: Board audit 2026-09-09; successor to mn-4308c4 whose week ended today
base_commit: 43d1be88ad2e9363c744661d91cce3d3908dee0e
scope: '[P1][KERNEL] Zone-watch verdict: correlate the week, name the leaker or clear it, file or skip the Apple packet'
inputs:
- Board audit 2026-09-09; successor to mn-4308c4 whose week ended today
binding: sha256:122c9dd606201ea776bc154ec430a4adf4e87caba362a8302164e7c2ac6254c2
---

# Handoff: [P1][KERNEL] Zone-watch verdict: correlate the week, name the leaker or clear it, file or skip the Apple packet

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-b09383
```

## Scope

[P1][KERNEL] Zone-watch verdict: correlate the week, name the leaker or clear it, file or skip the Apple packet

## Inputs

- Board audit 2026-09-09; successor to mn-4308c4 whose week ended today

## Work order

The kernel-zone watcher (installed 2026-09-02, closed on receipts as mn-4308c4) completed its one-week evidence window 2026-09-09; the correlation task lost its board home when that item closed — this is it. Deliver: correlate data.kalloc.1024 growth in /Library/Logs/Holy Ghostty/kernel-zone-watch/samples.tsv against the captured ssh/process counters across the week; verdict = (a) leak tracks churn -> name the consumer via lsmp/fd census of top holders, or (b) leak is gone since the SSH transport/admission fixes -> say so with the flat growth curve as receipt, or (c) leak persists churn-independent -> assemble the Apple Feedback packet (both panic files + growth log + repro description). Zero panics since 2026-09-01 is itself evidence — weigh it. Also fix the nonblocking gap from the install report: the report-only 30-minute safety guard was never recopied after its admin dialog was canceled.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-b09383`.
4. Commit with `Manna: mn-b09383` and run `agent-do manna done mn-b09383` only after the work is verified.
