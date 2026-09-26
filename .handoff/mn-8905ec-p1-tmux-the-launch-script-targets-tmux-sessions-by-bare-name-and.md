---
workflow: 2
manna: mn-8905ec
track: mn-eb7a80
source: lane mn-e6e3d0 report 2026-09-26
base_commit: 73e24330aa57e143b2a1e568a00b08416827f640
scope: '[P1][TMUX] The launch script targets tmux sessions by bare name, and tmux matches names by prefix'
inputs:
- lane mn-e6e3d0 report 2026-09-26
binding: sha256:f8012fe989467cf52364bef95b74d596ecfe47243fcced9762e1d2cb50d9b6bb
---

# Handoff: [P1][TMUX] The launch script targets tmux sessions by bare name, and tmux matches names by prefix

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-8905ec
```

## Scope

[P1][TMUX] The launch script targets tmux sessions by bare name, and tmux matches names by prefix

## Inputs

- lane mn-e6e3d0 report 2026-09-26

## Work order

Receipt, lane mn-e6e3d0 on tmux 3.7c with a throwaway socket: has-session -t lane succeeded while only lane-2 existed, and -t '=lane' failed as it should. HolyTmuxCommandBuilder passes bare names to has-session, attach, and set-option -t in localLaunchScript, so a spawn or restore naming lane can attach to an existing lane-2 instead of creating lane; a fleet of holy-worker-<uuid> names is safe by accident, hand-named sessions are not. The builder already uses an exact target in one place (exactPaneTarget at HolyTmuxCommandBuilder.swift:506 builds =name:). Deliver: every tmux target the builder emits for a session name uses the exact form =name (and =name:window.pane where a pane is meant), on local and SSH scripts, including detachedCreateCommand and the host-state preamble; a test that builds the scripts for a name that is a prefix of another and asserts no bare -t name remains; a test on a throwaway socket (never holy) that creates lane-2, runs the built has-session for lane, and gets a miss. Own macos/Sources/HolyGhostty/Tmux/HolyTmuxCommandBuilder.swift and its test file only.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-8905ec`.
4. Commit with `Manna: mn-8905ec` and run `agent-do manna done mn-8905ec` only after the work is verified.
