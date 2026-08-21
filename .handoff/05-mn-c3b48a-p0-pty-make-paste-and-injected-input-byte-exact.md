---
workflow: 2
manna: mn-c3b48a
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P0][PTY] Make paste and injected input byte-exact'
inputs: []
binding: sha256:8445f589d740dcba29d1125e84482513d5c23288f8d079821e685aac8541e5c2
---

# Handoff: [P0][PTY] Make paste and injected input byte-exact

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-c3b48a
```

## Scope

[P0][PTY] Make paste and injected input byte-exact

## Inputs

- None declared.

## Work order

Known open bug: large cross-session paste loses/truncates chunks and can interleave terminal UI text. Local 64-byte pacing is not proof; the drop point remains unknown.

Scope and done criteria:
- Build deterministic local, tmux, and SSH reproductions with large multiline, Unicode, and bracketed-paste payloads.
- Instrument app buffer -> PTY -> tmux -> SSH -> receiver with byte counts and checksums.
- Identify the exact loss/interleaving layer before choosing flow control, writable-drain, or tmux load/paste-buffer transport.
- Verify bracketed paste end to end.
- Delivery is checksum-exact, retryable, and fails visibly rather than silently corrupting input.

This is a hard blocker for agent-to-agent writing and autonomous control.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-c3b48a`.
4. Commit with `Manna: mn-c3b48a` and run `agent-do manna done mn-c3b48a` only after the work is verified.
