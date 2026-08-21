---
workflow: 2
manna: mn-8749ca
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P1][PERF] Scroll not butter-smooth on MacBook-class hardware (local AND remote) — execute attack plan v2'
inputs: []
binding: sha256:8377f4396bdbb1bd7354ef6be9cca78eee44261d996be96b7835530bd96e30da
---

# Handoff: [P1][PERF] Scroll not butter-smooth on MacBook-class hardware (local AND remote) — execute attack plan v2

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-8749ca
```

## Scope

[P1][PERF] Scroll not butter-smooth on MacBook-class hardware (local AND remote) — execute attack plan v2

## Inputs

- None declared.

## Work order

Plan v2: .handoff/SCROLL-PERF-ATTACK-PLAN-2026-07-19.md. MacBook execution completed through the first causal fix. On Erik MacBook Pro at measured 120 Hz with the real 14-session roster, baseline idle was about 36.3% CPU and the main-thread sample showed SwiftUI TimelineView/AttributeGraph work rooted in HolyAgentWorkingSpinner. Capping all row animations at 15 Hz was only about 32%; limiting animation to the selected row produced a 6.5% settled snapshot and removed the spinner stack from the sample. Repo semantics also confirmed that the 1.25-second detector read GHOSTTY_POINT_VIEWPORT, whose origin moves with scrollback. The candidate now reads bounded GHOSTTY_POINT_ACTIVE for preview/model/activity detection, so scrolling presentation state cannot churn derived state. Signed ReleaseLocal candidate installed on the MacBook; ReleaseFast receipt, build contract, SwiftLint, and relevant session detector suites passed. Evidence: .dev/scroll-traces/MACBOOK-SCROLL-PERF-RESULTS-2026-07-19.md. KEEP IN PROGRESS: acceptance still requires physical final-build scrolling and vanilla comparison on the MacBook, the 120-vs-60 Hz probe, and Chris confirmation on his local repro. SSH polling remains remote-only follow-up if local acceptance passes.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-8749ca`.
4. Commit with `Manna: mn-8749ca` and run `agent-do manna done mn-8749ca` only after the work is verified.
