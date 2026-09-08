---
workflow: 2
manna: mn-9a9728
track: mn-eb7a80
source: Erik post-reboot report 2026-09-08 16:37 + DB receipts this session (64/73 NULL identity; 15:18 workspace_restore events; archive 514 codex rows)
base_commit: a416dae2ab0c865b7e6dd68a63eaed6e89dd4c8a
scope: '[P0][RESTORE][CODEX] Reboot restore recovery-archives every codex session: identity-only pairing meets the open codex identity gap'
inputs:
- Erik post-reboot report 2026-09-08 16:37 + DB receipts this session (64/73 NULL identity; 15:18 workspace_restore events; archive 514 codex rows)
binding: sha256:3cfd697f88112fea3c52778a605e1927d190f2607cac7b55e25ce06af83270c7
---

# Handoff: [P0][RESTORE][CODEX] Reboot restore recovery-archives every codex session: identity-only pairing meets the open codex identity gap

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-9a9728
```

## Scope

[P0][RESTORE][CODEX] Reboot restore recovery-archives every codex session: identity-only pairing meets the open codex identity gap

## Inputs

- Erik post-reboot report 2026-09-08 16:37 + DB receipts this session (64/73 NULL identity; 15:18 workspace_restore events; archive 514 codex rows)

## Work order

Erik 2026-09-08, post-reboot: zero codex sessions restored; all 73 recovery-archived while claude/shell restored fine. Receipts: sessions table shows 64/73 codex rows with NULL harness_session_id (the codex half of the keystone, mn-40f637, failed live acceptance 2026-09-01 and remains open — claude identity captures, codex never does); the identity-keyed restore rework (mn-2a3305 lineage, 'crash restore pairs by identity — capture claude session id') therefore finds nothing to pair for codex and archives instead, even though this machine's archive holds 514 indexed codex conversations with resume commands. TWO-PART FIX: (1) finish mn-40f637 for real — diagnose against live codex hook traffic and prove a fresh codex session lands a populated harness_session_id (fold that item's closure into this one or close both together); (2) restore must DEGRADE, never skip: when identity is absent, fall back to the honest (cwd, harness, nearest-end) oracle with the standing confidence law (exact/ambiguous/none; ambiguity shows the candidate picker) instead of recovery-archiving wholesale. Acceptance: a synthetic reboot fixture with identity-less codex rows restores them via the fallback with correct resume commands; a live fresh codex session shows captured identity; and the next real reboot restores codex alongside claude.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-9a9728`.
4. Commit with `Manna: mn-9a9728` and run `agent-do manna done mn-9a9728` only after the work is verified.

## Implementation receipt, 2026-09-08

Independent Codex identity capture and native restore candidate handling are implemented. Two real Codex conversations completed through the generated notification adapter and native persistence with non-null harness_session_id values. Current mn-40f637 was already done; this receipt supplies fresh provider evidence for its old acceptance gap. The next real machine reboot remains unverified.

Final focused suites: 238 PASSED, 0 FAILED, 0 SKIPPED. Separate fresh-Codex acceptance: 1 PASSED, 0 FAILED, 0 SKIPPED (two real conversations across Xcode executions). Full report, exact IDs, failed-run history, and test-isolation correction: `.dev/mn-reboot-recovery/report.md`. A legacy test initially wrote eight synthetic host-journal rows; its database target is now isolated, and no session records were modified by that journal writer.

Status remains `in_progress` for coordinated installed-app acceptance. No install or push. Do not run Clear against a live roster outside that coordinated acceptance.
