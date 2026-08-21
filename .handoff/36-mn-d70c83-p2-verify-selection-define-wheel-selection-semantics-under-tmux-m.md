---
workflow: 2
manna: mn-d70c83
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P2][VERIFY][SELECTION] Define wheel-selection semantics under tmux mouse reporting'
inputs: []
binding: sha256:1c7426258a3e6edf13a9bc0f140d6e8f1c101e2739216edbea53cee17d479bc6
---

# Handoff: [P2][VERIFY][SELECTION] Define wheel-selection semantics under tmux mouse reporting

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-d70c83
```

## Scope

[P2][VERIFY][SELECTION] Define wheel-selection semantics under tmux mouse reporting

## Inputs

- None declared.

## Work order

Fresh verification item preserved from the July 17 audit. The original selection complaint is closed as damaged mouse hardware and MUST NOT be used as reproduction evidence.

Evidence:
- Current Surface.scrollCallback clears selection when application mouse reporting is active.
- Live Claude tmux panes had mouse reporting enabled while live Codex panes did not, making this a separate runtime-path concern rather than the reported Codex-heavy failure.
- Scroll-wheel and momentum events can therefore erase selection by code path, but desired product behavior and real-world severity have not yet been established with known-good hardware.

Invariant:
Selection behavior while scrolling must be deliberate, documented, and consistent enough that users can copy long terminal regions without unexplained loss.

Done when:
- Reproduce with a known-good mouse and trackpad across local and SSH sessions, primary and alternate screens, and tmux mouse on and off.
- Record raw drag, wheel, momentum, mouseUp, reporting-mode, and clearSelection events.
- Define when selection is intentionally cleared versus preserved.
- Add deterministic tests for the approved behavior.
- Do not implement a selection-specific fix until this clean reproduction distinguishes terminal protocol requirements from accidental momentum behavior.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-d70c83`.
4. Commit with `Manna: mn-d70c83` and run `agent-do manna done mn-d70c83` only after the work is verified.
