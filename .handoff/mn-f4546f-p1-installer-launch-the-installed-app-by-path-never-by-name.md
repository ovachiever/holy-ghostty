---
workflow: 2
manna: mn-f4546f
track: mn-eb7a80
source: .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 6; 8a5ac58ec
base_commit: 54fb6b58d3bcd289aef8411084d393826437a172
scope: '[P1][INSTALLER] Launch the installed app by path, never by name'
inputs:
- .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 6; 8a5ac58ec
binding: sha256:fc08eb6d03d54bc2c5869aecd1bcb4cd86cd97bbdae64d4161b6de89741766fd
---

# Handoff: [P1][INSTALLER] Launch the installed app by path, never by name

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-f4546f
```

## Scope

[P1][INSTALLER] Launch the installed app by path, never by name

## Inputs

- .handoff/SESSION-HANDOFF-2026-09-24.md §4 item 6; 8a5ac58ec

## Work order

09-23 incident (handoff commit 8a5ac58ec): launching with open -a by name let LaunchServices substitute another registered bundle for the freshly installed one. Rule: every script and doc launches with open /Applications/Holy\ Ghostty.app. Receipt 09-24: grep -rn 'open -a' over scripts/, docs/holy-ghostty/, README.md finds exactly one hit, README.md:129 (open -a "Holy Ghostty"), the public README. Done when that grep returns nothing, the README and the engineering spec §Build and Validation show the by-path launch, and scripts/install-holy-ghostty.sh ends with a by-path launch or none.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-f4546f`.
4. Commit with `Manna: mn-f4546f` and run `agent-do manna done mn-f4546f` only after the work is verified.

## Report

2026-09-29, worker `codex-01a0ef08b72e75d0`, parent gate `mn-8100d4`.

- Verified the original content binding against canonical Manna state before
  editing: `sha256:fe8a661e721389406549d40260ce154e5c75ef48c89aae9d9c9f762b39c083dd`.
- Commit: `3a61d4f5e` (`fix(docs): launch the installed Holy bundle by path`),
  with trailer `Manna: mn-f4546f`.
- README Build and Install and engineering-spec Build and Validation now use
  `open /Applications/Holy\ Ghostty.app`.
- Inspected `scripts/install-holy-ghostty.sh` through its final statement. It
  already ends with the installed-path receipt and no launch, satisfying the
  work order's allowed no-launch case. No installer change was needed.
- `rg -n -- 'open -a' scripts docs/holy-ghostty README.md`: no matches (exit 1,
  the required negative-search result).
- `rg -n -F 'open /Applications/Holy\ Ghostty.app' README.md docs/holy-ghostty/engineering-spec.md`:
  both documents matched (exit 0).
- `sh -n scripts/install-holy-ghostty.sh`: passed (exit 0).
- `git diff --check -- README.md docs/holy-ghostty/engineering-spec.md` and
  `git diff --cached --check`: passed (exit 0).
- Named Xcode suites: none in this work order. App-hosted tests compiled: 0;
  executed: 0. No application, installer, screenshot, or live session was run.
- Child acceptance is complete. Installed and visual release acceptance is
  reserved for Erik's coordinated ceremony after the other release gates close.
