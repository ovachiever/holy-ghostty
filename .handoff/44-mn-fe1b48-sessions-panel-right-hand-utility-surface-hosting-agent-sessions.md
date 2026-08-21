---
workflow: 2
manna: mn-fe1b48
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: 'Sessions panel: right-hand utility surface hosting agent-sessions'
inputs: []
binding: sha256:87e887ac0c99aaaffa3ca14d94ec2a0e9ddfc31bda9fbd2cb59d9ae3faa9c044
---

# Handoff: Sessions panel: right-hand utility surface hosting agent-sessions

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-fe1b48
```

## Scope

Sessions panel: right-hand utility surface hosting agent-sessions

## Inputs

- None declared.

## Work order

> Legacy migration source: "/Users/erik/Custom-Coding/agent-sessions/.dev/session-prompts/02-HOLY-PANEL.md"

# 02 HOLY-PANEL — right-hand sessions panel in Holy Ghostty

Repo: `/Users/erik/Custom-Coding/holy-ghostty` (cd there first; it has its own .manna). Claim `agent-do manna claim mn-fe1b48`; mn-a98f88 (handoff wiring + e2e verify) is blocked on it and cross-repo-dependent on agent-sessions mn-b7efa6. Set `agent-do coord focus set "sessions panel" --path macos/Sources/HolyGhostty/Workspace/HolyWorkspaceView.swift --path macos/Sources/HolyGhostty/Workspace/HolyWorkspaceStore.swift` plus the palette/window-controller files before editing.

## Mission
A toggleable right-hand panel in the Holy workspace hosting the agent-sessions TUI in an embedded terminal surface, so archived AI-coding sessions can be searched (including its AI chat) and resumed INTO Holy sessions.

## Map (verified against source 2026-07-20)
- Layout is a manual `HStack(spacing: 0)` in `standardContent`, HolyWorkspaceView.swift:219-272. Insert the panel after `mainWorkspaceContent` (:266). A right panel PRECEDENT exists orphaned: `standardContextPanel` :680-688 (usage removed in commit b2806b36d, which had HSplitView + toolbar toggle — mine it for patterns).
- Embedded surface WITHOUT session tracking — QuickTerminal precedent (Features/QuickTerminal/QuickTerminalController.swift:372-377): bare `Ghostty.SurfaceConfiguration` → `Ghostty.SurfaceView(ghostty_app, baseConfig:)` → `Ghostty.SurfaceWrapper` (SurfaceView.swift:35). No HolySession, no DB row, no supervisor. `SurfaceConfiguration` supports `command`, `workingDirectory`, `environmentVariables` (SurfaceView.swift:646-667).
- Panel surface command: wrap in a restart loop so TUI exit doesn't kill the pane, e.g. `while true; do agent-sessions; sleep 0.3; done` via `zsh -lc`. Holy sets `waitAfterCommand = false` elsewhere (HolyTmuxCommandBuilder.swift:29); the loop makes that moot.
- Env for the surface (contract with agent-sessions lane 01, fixed):
  `AGENT_SESSIONS_ON_RESUME=open "holy-ghostty://spawn?runtime={runtime}&workingDirectory={cwd_q}&command={cmd_q}"`
  Placeholders are substituted by agent-sessions; runtime arrives pre-mapped (claude/codex/opencode/shell). The URL route is already live: parser HolyAutomationURLParser.swift, flow AppDelegate.swift:373-379 → :1453-1463 → :1427-1434 → createSession — session lands in roster selected, window activated. Works today; you can verify the URL half immediately with a manual `open` command.
- Toggle wiring: `@Published` bool on HolyWorkspaceStore (pattern: `historyPresented`, HolyWorkspaceStore.swift:101) + command palette entry (`holyWorkspaceJumpOptions`, bottom of Features/Command Palette/TerminalCommandPalette.swift — CommandOptions take arbitrary Swift closures) + key equivalent in `handleWorkspaceKeyEquivalent` (HolyWorkspaceWindowController.swift:193-221). Persist width/visibility via `@AppStorage` like `holy.workspace.rosterWidth.v3` (HolyWorkspaceView.swift:131).
- Width: agent-sessions is unusable below ~60 columns (fixed 36-col row prefix). Panel default ≥450pt, min ~420pt, resizable via a second `HolyWorkspaceSplitHandle` (HolyWorkspaceView.swift:17-33). Lane 04 is adding a compact mode to lower this floor later; do not wait for it.

## Rules
- Honor the interop doc (docs/holy-ghostty/agent-sessions-interoperability.md): no Python dependency, no shared DB — the panel embeds a subprocess only. Respect the Prime Rule framing (CHANGELOG 0.25): this panel shows what the terminal cannot (archive + search), keep chrome minimal.
- If `agent-sessions` binary is missing, surface a quiet placeholder in the panel, not a crash.
- mn-a98f88 (e2e verification) stays blocked until agent-sessions mn-b7efa6 merges; until then verify the panel + URL halves separately (manual `open "holy-ghostty://spawn?..."` proves the receive side).
- This repo has active parallel work (daily commits): check `agent-do coord status` and stage only your claimed files. Follow existing Swift patterns; build with the repo's standard macOS build before claiming done. `agent-do manna done mn-fe1b48` when the panel stands.


## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-fe1b48`.
4. Commit with `Manna: mn-fe1b48` and run `agent-do manna done mn-fe1b48` only after the work is verified.
