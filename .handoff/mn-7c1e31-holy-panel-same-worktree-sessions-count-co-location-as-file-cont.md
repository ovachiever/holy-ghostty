---
workflow: 2
manna: mn-7c1e31
track: mn-70875b
source: agent-do session investigation 2026-08-21, Erik screenshot 14:04
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: 'Holy panel: same-worktree sessions count co-location as file contention'
inputs:
- agent-do session investigation 2026-08-21, Erik screenshot 14:04
binding: sha256:8bd77d2f05c8aa774a5230e88e8622404cfd48be1ef1941217234fc4786be9bd
---

# Handoff: Holy panel: same-worktree sessions count co-location as file contention

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-7c1e31
```

## Scope

Holy panel: same-worktree sessions count co-location as file contention

## Inputs

- agent-do session investigation 2026-08-21, Erik screenshot 14:04

## Work order

Verified 2026-08-21 against live state (two agent-do sessions, one shared checkout): the footer read '30 overlapping files · Same worktree with 1 session · Same branch with 1 session' while the true number of co-edited files was zero — all 30 dirty files belonged to one session's in-flight work.

Mechanism: each session's gitSnapshot.changedFiles comes from git status --porcelain=v1 --untracked-files=all of its working directory (HolyGitClient.swift:32). Coordination overlap is the intersection of two sessions' changed-file sets (HolyWorkspaceStore.swift:4338, sessionFiles at :4304). For sessions in DIFFERENT worktrees of one repo that intersection is meaningful — each worktree has its own dirty set. For sessions sharing ONE checkout the two git-status runs see the same repo, the sets are identical by construction, and intersection degenerates to 'every dirty file in the shared checkout' regardless of who touched what. The overlap stat and the same-worktree warning double-report a single fact dressed as file-level contention.

Fix shape (display semantics, not detection): when sharedWorktreeSessionIDs is non-empty for the pair, stop presenting the intersection as 'overlapping files' — render 'N uncommitted files in the shared checkout' (attribution impossible from git status alone), or suppress the file count and let the same-worktree warning carry the fact. True per-session attribution would need transcript-derived touched-file sets; that is an enhancement, not this fix. Different-worktree math stays as is.

Receipts: git status --porcelain | wc -l == 30 in the shared checkout at observation time; coord peers showed exactly two active sessions there; observer session had zero uncommitted files of its own.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-7c1e31`.
4. Commit with `Manna: mn-7c1e31` and run `agent-do manna done mn-7c1e31` only after the work is verified.
