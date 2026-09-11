---
workflow: 2
manna: mn-7df240
track: mn-9a97cc
source: null
base_commit: 1c7c3ffbb8cda20fa99396f439dda76f164dc315
scope: '[P2][BOARD] Compact hides nothing on the board topbar line — via-host and status labels render at every width'
inputs: []
binding: sha256:6bc9612df1c8ac89b5af02f35834751aa4d38a479e2eb26f8c0173d850b13c89
---

# Handoff: [P2][BOARD] Compact hides nothing on the board topbar line — via-host and status labels render at every width

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-7df240
```

## Scope

[P2][BOARD] Compact hides nothing on the board topbar line — via-host and status labels render at every width

## Inputs

- None declared.

## Work order

Erik 2026-09-10 follow-up to mn-61fb80 (terminal crumb): 'compact mode doesn't need to hide anything on that line, there's tons of blank space.' Remove the remaining if-not-compact gates on the topbar: the crumb's 'via <host>' suffix and topbarRight's 'updated Ns ago' + connection labels render unconditionally; crumb and topbarRight lose their compact parameter (call sites in boardTopbar and estateSurface). The grep field keeps its width yielding — compression, not hiding, is the valve for narrow windows. Verification: SwiftLint strict, build, three Board suites executed green. Visual acceptance rides the held install.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-7df240`.
4. Commit with `Manna: mn-7df240` and run `agent-do manna done mn-7df240` only after the work is verified.
