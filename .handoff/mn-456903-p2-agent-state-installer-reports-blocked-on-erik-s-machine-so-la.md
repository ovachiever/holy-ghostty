---
workflow: 2
manna: mn-456903
track: mn-eb7a80
source: null
base_commit: 0c18571dee5ec091422ff32924f1c32e136b6957
scope: '[P2][AGENT-STATE] Installer reports blocked on Erik''s machine, so launch auto-repair cannot refresh agent-state-hook.sh'
inputs: []
binding: sha256:19d37fc42594cec25e2a8eb0d397ab65e75c9a6338c3cc271626977ef5b64894
---

# Handoff: [P2][AGENT-STATE] Installer reports blocked on Erik's machine, so launch auto-repair cannot refresh agent-state-hook.sh

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-456903
```

## Scope

[P2][AGENT-STATE] Installer reports blocked on Erik's machine, so launch auto-repair cannot refresh agent-state-hook.sh

## Inputs

- None declared.

## Work order

Observed 2026-09-01 13:2x: app menu shows 'Authoritative Agent Indicators Need Attention…' while helper/hooks are Holy-owned (marker v4) and only stale by one line; the launch auto-repair (0c18571de) handles .needsRepair only and correctly stood aside. installationState therefore returned .blocked(...) — most likely mergingCodexConfiguration on ~/.codex/config.toml, whose notify is Computer Use's SkyComputerUseClient chaining Holy's adapter via --previous-notify with JSON-escaped slashes (\/Users\/erik\/…holy-codex-turn-complete.py); HolyCodexNotifyConfiguration says a chained delegation is accepted, so either the escaped form defeats the match or another check throws. Reproduce: call HolyAgentStateBridgeInstaller.installationState(paths: currentUserPaths()) and read the blocked reason (the menu does not show it). Fix: accept the escaped chained form, and surface the blocked reason in the menu/Hosts sheet so a stuck bridge is diagnosable. Stopgap applied by hand this session: the helper file was rendered from the embedded script and replaced atomically (byte-exact, v4 marker). Touches the Codex identity lane (mn-40f637): coordinate before editing HolyCodexNotifyConfiguration.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-456903`.
4. Commit with `Manna: mn-456903` and run `agent-do manna done mn-456903` only after the work is verified.
