---
workflow: 2
manna: mn-c2b133
track: mn-eb7a80
source: Executed-test run 2026-09-10 21:23 (FAILED 3/PASSED 111 batch; isolated repro confirmed); cites mn-9b5b5b
base_commit: abe1f1e556d28622655191d9a12fc43a383dedd9
scope: '[P1][MOUSE] releaseFromAnotherWindowClearsHoverButSkipsUnmountedPanes fails consistently — mn-9b5b5b closed on compiled-only verification'
inputs:
- Executed-test run 2026-09-10 21:23 (FAILED 3/PASSED 111 batch; isolated repro confirmed); cites mn-9b5b5b
binding: sha256:77afa3915eff3c344392907eecda2247fbbd2646aa67007a1040ab2bcb27481e
---

# Handoff: [P1][MOUSE] releaseFromAnotherWindowClearsHoverButSkipsUnmountedPanes fails consistently — mn-9b5b5b closed on compiled-only verification

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-c2b133
```

## Scope

[P1][MOUSE] releaseFromAnotherWindowClearsHoverButSkipsUnmountedPanes fails consistently — mn-9b5b5b closed on compiled-only verification

## Inputs

- Executed-test run 2026-09-10 21:23 (FAILED 3/PASSED 111 batch; isolated repro confirmed); cites mn-9b5b5b

## Work order

The mn-9b5b5b terminal-mouse patch (4b8b079e0) was closed (abe1f1e55) while its own report said 'zero tests executed; remains in_progress' — first executed run (this session, twice, both parallel hosts, 0.02s) fails its new regression releaseFromAnotherWindowClearsHoverButSkipsUnmountedPanes. Claim, run the suite FOR REAL, fix code or test to match true behavior, and only then re-close. The install of the link-detection patch is HELD until this is green — Erik's cmd-click acceptance (and the blocked mn-5a26f9 clickable-ids feature) queue behind it. Assertion detail did not surface via xcodebuild console; run in Xcode or capture the result bundle.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-c2b133`.
4. Commit with `Manna: mn-c2b133` and run `agent-do manna done mn-c2b133` only after the work is verified.
