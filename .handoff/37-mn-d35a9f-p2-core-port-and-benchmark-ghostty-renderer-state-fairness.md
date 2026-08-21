---
workflow: 2
manna: mn-d35a9f
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P2][CORE] Port and benchmark Ghostty renderer-state fairness'
inputs: []
binding: sha256:4b1a2f9e5971c7f4f1d8c45c3948ed4f422236ff29c792e11155276781ec097c
---

# Handoff: [P2][CORE] Port and benchmark Ghostty renderer-state fairness

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-d35a9f
```

## Scope

[P2][CORE] Port and benchmark Ghostty renderer-state fairness

## Inputs

- None declared.

## Work order

Independent hardening finding from the July 17 read-only audit. The original drag complaint occurred outside Holy because of damaged mouse hardware; do not cite it as evidence that this issue caused selection loss.

Evidence:
- Holy core is based on an older Ghostty state and lacks upstream July 9 commit 11b9a6ef1, which adds renderer demand handoff so sustained PTY parsing cannot starve frames on the macOS unfair mutex.
- Holy PTY parsing, renderer snapshots, mouse selection updates, and wheel callbacks contend on renderer_state.mutex.
- A live active-output sample caught renderer frame updates waiting in _os_unfair_lock_lock_slow.
- Upstream documents starvation lasting for the duration of sustained output.

Invariant:
Sustained PTY output must not indefinitely starve renderer or interactive surface work, while terminal throughput and correctness remain intact.

Done when:
- The upstream fairness design is adapted to Holy older Exec loop rather than blindly cherry-picked.
- A repeatable sustained-output benchmark covers parser throughput, renderer frame progress, mouse-selection latency, and scroll latency.
- Renderer and interactive wait times have explicit bounded acceptance thresholds.
- Stress tests cover local and SSH panes across Claude, Codex, OpenCode, and a generic high-output process.
- The installed build passes the benchmark without throughput, deadlock, or rendering regressions.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-d35a9f`.
4. Commit with `Manna: mn-d35a9f` and run `agent-do manna done mn-d35a9f` only after the work is verified.
