---
workflow: 2
manna: mn-31aaf2
track: mn-70875b
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: 'Post-merge cleanup: unify HolyMannaProcessRunner into the shared restore runner (add currentDirectoryPath)'
inputs: []
binding: sha256:618604c3deebdf6a23ae934429077b12e1476c64e4cbb762b3a97c9429cc10ad
---

# Handoff: Post-merge cleanup: unify HolyMannaProcessRunner into the shared restore runner (add currentDirectoryPath)

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-31aaf2
```

## Scope

Post-merge cleanup: unify HolyMannaProcessRunner into the shared restore runner (add currentDirectoryPath)

## Inputs

- None declared.

## Work order

Lane 08 duplicated HolyRestoreProcessRunner as HolyMannaProcessRunner because the shared runner has no currentDirectoryURL hook and lives in the crash-restore lane's file (env -C rejected: deployment target macOS 13.0). Fix: add currentDirectoryPath: String? = nil to HolyRestoreProcessRunner.run, migrate HolyMannaInboxSource, delete the duplicate. Also note: HolyMannaInboxSource depends on HolyRestoreProcessResult + holyDetailedProcessLaunchErrorDescription from Restore/HolyRestoreResolveClient.swift — renames break it at compile time.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-31aaf2`.
4. Commit with `Manna: mn-31aaf2` and run `agent-do manna done mn-31aaf2` only after the work is verified.
