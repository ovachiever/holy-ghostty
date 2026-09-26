---
workflow: 2
manna: mn-3c4b23
track: mn-eb7a80
source: Erik 2026-09-26 11:37 with screenshot; zone-watch samples; sessions table
base_commit: 962f13ad23c8f022a2b5d44d29de8085c36339de
scope: '[P0][RESTORE] After a kernel panic the restore sheet scatters live sessions into older groups, hides some, and records no restore run'
inputs:
- Erik 2026-09-26 11:37 with screenshot; zone-watch samples; sessions table
binding: sha256:eb264759877f223c02546db5d5e8d7594bd578c5b0958699710ee82d9703be09
---

# Handoff: [P0][RESTORE] After a kernel panic the restore sheet scatters live sessions into older groups, hides some, and records no restore run

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-3c4b23
```

## Scope

[P0][RESTORE] After a kernel panic the restore sheet scatters live sessions into older groups, hides some, and records no restore run

## Inputs

- Erik 2026-09-26 11:37 with screenshot; zone-watch samples; sessions table

## Work order

Receipt 2026-09-26 11:25 after the 06:16 kernel panic (boot epoch 1790421414): the sheet showed 5 interrupted by the last shutdown plus 38 older in 11 shutdown groups, while the fleet at the panic held 39 tmux sessions (zone-watch samples.tsv, tmux_process_count at 05:47). Egora, SubDub, and Yed Prior were live at the panic and appeared nowhere in the fresh section; Erik re-created them by hand at 16:34Z (sessions A3A93E22, 8202FBC3, F338E42E). The 12-session group two days ago is the 09-24 18:04 relaunch (installer kill); rows adopted from tmux after that relaunch never got a new interruption record, so the panic left them in the old group. Freshness is decided by the adapter that builds rows (HolyRestoreEngine.swift:349-384 plannedRow isFresh) and HolyRestoreCrashGrouping.groups(from:) only subdivides older. Deliver: (1) freshness keyed on reality: every session whose tmux server died with the last boot, or that was live at the last app exit, is interrupted by the last shutdown, whatever its last interruption record says; kern.boottime or an equivalent boot identity is the authority for a panic; (2) a session live at any relaunch gets its interruption record renewed so adoption never strands it; (3) a restore run is recorded as a history entry (when, how many rows, which ids, outcomes and errors) and the Session History sheet shows it; Erik restored about 38 sessions today and history shows nothing; (4) a row whose working directory no longer exists names the source of the path and still offers restore into the last known valid directory from resume metadata when that exists (row 985BC829 today: /Users/erik/Custom-Coding/Research Comprehensive App Security | Custom-Coding). Tests: grouping fixtures for panic, clean quit, and installer relaunch; history entry written and rendered. Own macos/Sources/HolyGhostty/Restore/, macos/Sources/HolyGhostty/Workspace/HolySessionHistorySheet.swift, the restore-related regions of macos/Sources/HolyGhostty/Workspace/HolyWorkspaceStore.swift, and their tests; do not touch Archive/ or Board/. Related open items mn-569b91, mn-12801a, mn-56f896.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-3c4b23`.
4. Commit with `Manna: mn-3c4b23` and run `agent-do manna done mn-3c4b23` only after the work is verified.
