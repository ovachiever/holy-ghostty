---
workflow: 2
manna: mn-697c73
track: mn-eb7a80
source: security-guidance automated review 2026-08-31 + this session's E:-expansion verification
base_commit: 7a4f1cd5ea272a387d112de0d1658c2b6d426b66
scope: '[P1][SECURITY] Usage meter: sanitize API-derived text before tmux E: format expansion'
inputs:
- security-guidance automated review 2026-08-31 + this session's E:-expansion verification
binding: sha256:e71bbeca9877f45b239d3fff8a8cfa2f0bd55fe2bb0f95f9ce275d943894d111
---

# Handoff: [P1][SECURITY] Usage meter: sanitize API-derived text before tmux E: format expansion

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-697c73
```

## Scope

[P1][SECURITY] Usage meter: sanitize API-derived text before tmux E: format expansion

## Inputs

- security-guidance automated review 2026-08-31 + this session's E:-expansion verification

## Work order

Automated security review finding, verified 2026-08-31 with the render-side receipt that elevates it. Sink chain: the usage probe embeds bucket labels from the Claude usage API into the meter segment (HolyClaudeUsageBridge.swift:584 short_label, :612 text = label+percent, :655 set-option -g @holy_usage_v1 segment); HolyTmuxCommandBuilder.swift renders the option with the E: prefix ('#[nolist align=centre]#{E:...}'), which RE-EXPANDS the stored value as a tmux format — so '#(cmd)' inside any API-derived key would run as a shell command in the tmux status line. Threat model: hostile/compromised usage-API response or MITM; low likelihood, high impact, cheap fix — defense in depth is warranted because the E: expansion is deliberate (the composer emits its own #[...] attributes). Fix: sanitize DATA fields only, preserving composer-emitted format codes — allowlist the label charset (e.g. [A-Za-z0-9 ._-], clamp length) and/or double '#' -> '##' on every API-derived substring (key, weekly_scoped suffix) before composition; validate bucket keys against the known set (session, weekly_all, weekly_scoped:*) with the scoped suffix sanitized. Add a test that a bucket key containing '#(touch /tmp/pwned)' renders inert in the segment. Also sweep for the same pattern anywhere else API/pane-derived text reaches an E:-expanded or status-format context.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-697c73`.
4. Commit with `Manna: mn-697c73` and run `agent-do manna done mn-697c73` only after the work is verified.
