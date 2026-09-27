---
workflow: 2
manna: mn-4c3eb5
track: mn-eb7a80
source: Erik 2026-09-26 19:57; codex-rs config_toml.rs and tui/src/updates.rs; codex 0.157.1 doctor
base_commit: ec3a6a110554be6746d063d3c14ba09cb438912c
scope: '[P0][RESTORE][CODEX] Codex''s startup update prompt blocks every unattended Codex launch: crash restore and board dispatch resume nothing'
inputs:
- Erik 2026-09-26 19:57; codex-rs config_toml.rs and tui/src/updates.rs; codex 0.157.1 doctor
binding: sha256:0fd6794edc25070a4ccbecb2ecbd43d1bceae4164be4f9be6531aecb1db25654
---

# Handoff: [P0][RESTORE][CODEX] Codex's startup update prompt blocks every unattended Codex launch: crash restore and board dispatch resume nothing

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-4c3eb5
```

## Scope

[P0][RESTORE][CODEX] Codex's startup update prompt blocks every unattended Codex launch: crash restore and board dispatch resume nothing

## Inputs

- Erik 2026-09-26 19:57; codex-rs config_toml.rs and tui/src/updates.rs; codex 0.157.1 doctor

## Work order

Receipt, Erik 2026-09-26 19:57: after a crash restore every Codex pane showed 'Update available · 0.156.1 → 0.157.0 … 1. Update now (runs npm install -g @openai/codex) 2. Skip 3. Skip until next version … enter continue · esc skip' and waited for a keypress, so none of the restored sessions resumed. Codex's top-level config key check_for_update_on_startup (config_toml.rs: 'When true, checks for Codex updates on startup and surfaces update prompts … Defaults to true') gates the TUI popup (tui/src/updates.rs get_upgrade_version_for_popup returns nothing when false). Verified on Codex 0.157.1: codex --config check_for_update_on_startup=false doctor reports 'startup update check false', without the override 'true'. Fix: HolyRestoreCommandBuilder.codexUnattendedLaunchOverrides = ['--config', 'check_for_update_on_startup=false'] on every Holy-built Codex command (crash restore, archive federated resume, board dispatch); the long form because -c is Claude's --continue and the builder's forbidden-flag rule keeps -c out of resume commands. User-started sessions keep Codex's default so Erik still sees updates. Tests: builder, executable discovery, restore engine, archive federation, and board suites updated; new test asserts the override precedes the subcommand and never appears for Claude.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-4c3eb5`.
4. Commit with `Manna: mn-4c3eb5` and run `agent-do manna done mn-4c3eb5` only after the work is verified.
