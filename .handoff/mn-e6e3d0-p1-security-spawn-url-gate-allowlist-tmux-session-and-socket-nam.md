---
workflow: 2
manna: mn-e6e3d0
track: mn-eb7a80
source: security review 2026-09-24; 962f13ad2; .handoff/mn-e9f9a9 report
base_commit: 962f13ad23c8f022a2b5d44d29de8085c36339de
scope: '[P1][SECURITY] Spawn URL gate: allowlist tmux session and socket names and prove every non-command field is inert at both sinks'
inputs:
- security review 2026-09-24; 962f13ad2; .handoff/mn-e9f9a9 report
binding: sha256:16671d93969dad8e934d6a9fe8ec1fadfefc25e74663badb84b7676ebe45afd4
---

# Handoff: [P1][SECURITY] Spawn URL gate: allowlist tmux session and socket names and prove every non-command field is inert at both sinks

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-e6e3d0
```

## Scope

[P1][SECURITY] Spawn URL gate: allowlist tmux session and socket names and prove every non-command field is inert at both sinks

## Inputs

- security review 2026-09-24; 962f13ad2; .handoff/mn-e9f9a9 report

## Work order

Follow-up to 962f13ad2 (mn-e9f9a9, gate suites 40 of 40 on 09-24 and re-run 40 of 40 on 09-26). Automated review flagged that tmuxSession, tmuxSocket, workingDirectory, title, and objective are not screened for shell metacharacters. Sink receipts: local launches pass workingDirectory as argv (HolyTmuxCommandBuilder.swift:136) and the SSH transport wraps a script whose every argument is single-quoted by shellCommand mapping posixQuote (HolyTmuxCommandBuilder.swift:421-425, wrapped at :572), so injection is inert at the sink today; the gate already rejects control, newline, and bidi scalars in any value. Deliver, as defense in depth: tmuxSession and tmuxSocket restricted to ^[A-Za-z0-9._-]+$ (tmux also parses : and . as target separators, so reject those too in session names); tests that put each metacharacter class into each non-command field on local and ssh transports and assert the built command carries them only inside single quotes or the gate refuses; the confirmation sheet and audit line already show every field, keep that covered by a test. Own macos/Sources/HolyGhostty/Automation/HolyAutomationURLGate.swift and macos/Tests/HolyGhostty/HolyAutomationURLGateTests.swift only.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-e6e3d0`.
4. Commit with `Manna: mn-e6e3d0` and run `agent-do manna done mn-e6e3d0` only after the work is verified.
