---
workflow: 2
manna: mn-37c1b4
track: mn-9a97cc
source: Studio tmux receipts 2026-09-10 19:39 (6 VSI workers pane_current_command=bash; 0/43 codex)
base_commit: c681f6a468251b3b262b4023e020d546de6cb5ba
scope: '[P1][ACT][DISPATCH] The worker script must exec the runtime: bash stays pane leader and every classifier goes blind'
inputs:
- Studio tmux receipts 2026-09-10 19:39 (6 VSI workers pane_current_command=bash; 0/43 codex)
binding: sha256:672d336e24451fd352a0093e87d66ee23b2a67252cef029b2551d842a17bb4cd
---

# Handoff: [P1][ACT][DISPATCH] The worker script must exec the runtime: bash stays pane leader and every classifier goes blind

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-37c1b4
```

## Scope

[P1][ACT][DISPATCH] The worker script must exec the runtime: bash stays pane leader and every classifier goes blind

## Inputs

- Studio tmux receipts 2026-09-10 19:39 (6 VSI workers pane_current_command=bash; 0/43 codex)

## Work order

Receipts from the Studio 2026-09-10: six live holy-worker sessions in versova-supply-intelligence all report pane_current_command=bash — and zero of 43 sessions on the host report codex as foreground — because the generated Claim & build script runs the runtime as a child instead of replacing itself. Consequences cascade: remote discovery and the hosts sheet cannot classify them (Erik's MacBook shows them missing entirely), runtime grouping is wrong, and pane-leader-based logic (kill, liveness, scrape gating) addresses the wrapper shell rather than the agent. Fix in the dispatch lane (mn-ec34cd machinery): the generated script's final act is exec '<absolute runtime path>' with its args — after the note/claim preamble — so the runtime IS the pane process; verify signals and exit propagation still behave (tmux session ends when the runtime exits, as with hand-run sessions). Test: a dispatched session's pane_current_command equals the runtime binary within seconds of boot. Acceptance: dispatch one worker, tmux reports codex as the pane command, and it appears correctly grouped on a remote hosts sheet.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-37c1b4`.
4. Commit with `Manna: mn-37c1b4` and run `agent-do manna done mn-37c1b4` only after the work is verified.
