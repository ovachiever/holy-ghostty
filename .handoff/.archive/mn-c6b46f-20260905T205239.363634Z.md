---
workflow: 2
manna: mn-c6b46f
track: mn-eb7a80
source: observed 2026-09-05 during the admission budget fix
base_commit: f7b32b4db599595c576dc15310a305a621d85193
scope: '[P3][TESTFLAKE] filesystemSurfaceGateQueuesBeforeExecutingTheNextClient starves under suite load'
inputs:
- observed 2026-09-05 during the admission budget fix
binding: sha256:c11d65bbdac8e89b76729c42de5e307823d7f6ec10d9fbc0dbca0a7b3fb78981
---

# Handoff: [P3][TESTFLAKE] filesystemSurfaceGateQueuesBeforeExecutingTheNextClient starves under suite load

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-c6b46f
```

## Scope

[P3][TESTFLAKE] filesystemSurfaceGateQueuesBeforeExecutingTheNextClient starves under suite load

## Inputs

- observed 2026-09-05 during the admission budget fix

## Work order

Passes in isolation, fails (~2.2s, timing-sensitive queue handoff) when the transport+admission suites run together — same family as mn-0532e8. Deflake with a virtualized clock or generous release polling; do not loosen the assertion.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-c6b46f`.
4. Commit with `Manna: mn-c6b46f` and run `agent-do manna done mn-c6b46f` only after the work is verified.
