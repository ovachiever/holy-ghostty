---
workflow: 2
manna: mn-40f637
track: mn-eb7a80
source: Live DB check 2026-09-01; follow-up to mn-26e29e
base_commit: 7867293926941b4bcf018ee7c9cc7b42d543d8f7
scope: '[P1][KEYSTONE][CODEX] harness_session_id never lands for codex sessions'
inputs:
- Live DB check 2026-09-01; follow-up to mn-26e29e
binding: sha256:fa18446f700859e9cbfd04634f1fa2f50399ec4809541f083751cce0c6ce9fe9
---

# Handoff: [P1][KEYSTONE][CODEX] harness_session_id never lands for codex sessions

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-40f637
```

## Scope

[P1][KEYSTONE][CODEX] harness_session_id never lands for codex sessions

## Inputs

- Live DB check 2026-09-01; follow-up to mn-26e29e

## Work order

Live check 2026-09-01: claude session 81917CE4 (Aug 31 22:47) carries harness_session_id a866aad0-…, proving the keystone path works for Claude; both live codex worker sessions (7A72011F, 5A1CA3C1, created 10:58, actively running turns) have EMPTY harness_session_id. mn-26e29e's completion claimed Codex capture is first-class via command hooks receiving session_id on stdin — live data says the codex wire never delivers it (hook not registered for codex on this machine, codex hook payload shape differing from the doc the worker cited — a learn.chatgpt.com URL of dubious provenance — or the capture argument failing silently in the codex shell context). Diagnose against a REAL codex session's hook traffic, not documentation; fix registration or capture; acceptance = a fresh codex session shows a populated harness_session_id row and joins to its coord peer (codex-<hex> ↔ session row) the way claude sessions do. The identity join (board mode click-through, badge dedup) silently degrades for codex sessions until this lands.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-40f637`.
4. Commit with `Manna: mn-40f637` and run `agent-do manna done mn-40f637` only after the work is verified.
