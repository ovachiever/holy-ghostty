---
workflow: 2
manna: mn-7681f4
track: mn-eb7a80
source: null
base_commit: 60e772d16f1389d2d52f1139f29e8fe52162bdc4
scope: '[P1][SECURITY][RESTORE] Provider-supplied resume command strings run verbatim in HolyRestoreEngine'
inputs: []
binding: sha256:c2b3333dd49878cf7122c35840146a9f846f156c3e2a735498ea3e84cd073225
---

# Handoff: [P1][SECURITY][RESTORE] Provider-supplied resume command strings run verbatim in HolyRestoreEngine

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-7681f4
```

## Scope

[P1][SECURITY][RESTORE] Provider-supplied resume command strings run verbatim in HolyRestoreEngine

## Inputs

- None declared.

## Work order

Automated security review (2026-09-02, on the pushed batch) flags HolyRestoreEngine.swift: 'providerResumeCommands[providerSessionID]' is preferred over the builder-rendered command and executed as given — a provider/index-supplied command string is a shell-injection surface (same class as the mn-697c73 tmux E: sink and the 0.50 manna-id fix). Suggested hardening from the review: treat the provider value as data — parse to argv, require argv[0] to realpath into the discovered/allowlisted runtime binary (or match discovery.pinnedArgvPath), require the tail to be exactly '--resume <id>' with a strict id regex, reject shell metacharacters; or have the provider return only an executable prefix and re-render through HolyRestoreCommandBuilder.renderedResumeCommand. NOT investigated beyond the flag — restore is the restore lane's territory; whoever claims this should check whether providerResumeCommands values ever originate outside agent-sessions' own index.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-7681f4`.
4. Commit with `Manna: mn-7681f4` and run `agent-do manna done mn-7681f4` only after the work is verified.
