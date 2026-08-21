---
workflow: 2
manna: mn-9a6145
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P0][RECOVERY] Add Restore All, Restore Selected, and Recovery Backups UI'
inputs: []
binding: sha256:1abd90147ca7f51a356be54021a97d45f2550a12265e676a6b64f3146360b990
---

# Handoff: [P0][RECOVERY] Add Restore All, Restore Selected, and Recovery Backups UI

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-9a6145
```

## Scope

[P0][RECOVERY] Add Restore All, Restore Selected, and Recovery Backups UI

## Inputs

- None declared.

## Work order

> Legacy migration source: "/Users/erik/Custom-Coding/agent-sessions/.dev/session-prompts/06-CRASH-RESTORE.md"

# 06 CRASH-RESTORE — resume exact conversations after tmux-server death (Holy Ghostty)

Repo: `/Users/erik/Custom-Coding/holy-ghostty` (cd there first; it has its own .manna board). Claim `agent-do manna claim mn-84c0eb` (restore engine) and, when you reach the UI slice, `agent-do manna claim mn-9a6145` (Restore All/Selected UI). Set `agent-do coord focus set "crash restore" --path macos/Sources/HolyGhostty/Restore --path macos/Sources/HolyGhostty/Supervisor/HolySessionSupervisor.swift --path macos/Sources/HolyGhostty/Workspace/HolySessionHistorySheet.swift` and `agent-do coord claim macos/Sources/HolyGhostty/Workspace/HolyWorkspaceStore.swift --reason "restore relaunch path"` before editing the store (lane 02-HOLY-PANEL also touches it; coord arbitrates).

CROSS-REPO GATE: requires mn-7dfdb0 on the agent-sessions board (the `resolve` CLI, prompt 05-RESOLVE-CLI.md). Until it lands you can build everything behind a protocol and test with a stubbed resolver; do not claim mn-84c0eb done without an end-to-end run against the real CLI.
SAME-BOARD GATE: mn-84c0eb is blocked by mn-495322 (verified kill/live-duplicate primitive). Preflight's "no live duplicate" check depends on it; if it is still open when you start, build preflight against `HolyTmuxLifecycleIdentity` directly and keep the block honest.

## Mission
When the Mac Studio crashes, the tmux server and every pane dies, but two things survive: Holy's SQLite DB (each session's cwd, runtime, title, tmux name, last activity) and the providers' jsonl stores (every conversation, indexed by agent-sessions). Join them at restore time: for each cold-boot-archived session, ask agent-sessions which conversation was running in that cwd at that time, then recreate the tmux session in that cwd running the exact resume command (`claude --resume <id>` / `codex resume <id>`), never a fresh conversation, never `--continue`.

## THE CONTRACT (pinned verbatim — must match 05-RESOLVE-CLI.md exactly)
```
INVOCATION
  agent-sessions resolve --cwd <abs path> --harness <claude|codex|opencode|claude-code> \
    --near <unix seconds> [--window 172800] [--limit 5] [--no-reindex] --json

STDOUT — single JSON object:
{
  "matched": true | false,
  "id": "<provider session id>" | null,
  "harness": "claude-code" | "codex" | "opencode",
  "runtime": "claude" | "codex" | "opencode",
  "project_path": "<normalized abs path>",
  "resume_command": "<exact command>" | null,
  "confidence": "exact" | "ambiguous" | "none",
  "candidates": [
    {"id": "...", "timestamp_end": <unix seconds>, "preview": "<first_prompt_preview, ≤120 chars>"}
  ]
}
```
Holy passes its runtime name (`claude|codex|opencode`) as --harness and the archived session's last-activity time as --near. Treat `confidence` as law: "exact" → restore; "ambiguous" → per-session candidate picker in the UI (show preview + timestamp); "none" → offer shell-only recreate, clearly labeled, never called a resume. Resume commands execute as argument arrays; the id is data, never shell-interpolated.

## Ground truth (verified against source and the live DB 2026-08-03)
- Cold boot today: `HolySessionSupervisor.swift:143-198` archives dormant local sessions with a recoveryReason when the tmux server is unavailable; real `session_recovered` events exist in the live DB. Revival of still-live sessions: `liveArchivedLocalSessions` at :367.
- Relaunch path: `HolyWorkspaceStore.swift:1613` `relaunch(_:)` → `createSession(origin: .archiveRelaunch, relaunchedFrom:)` (:552, :1921). Today it replays the ORIGINAL launch command — a fresh conversation. Your engine swaps in the resolved resume command here.
- History/recovery UI: `HolySessionHistorySheet.swift:187` (relaunch button), `recoverySection` :225. mn-9a6145's Restore All/Selected surface extends this plus a cold-boot banner.
- Resume metadata: `HolyResumeMetadata` (`HolyWorkspaceDatabasePersistence.swift:890`) carries cwd + preferredCommand but NO provider conversation id — that is the gap this lane closes via the resolve CLI.
- Runtime enum `HolyModels.swift:39` (shell/claude/codex/opencode); launch spec `HolyModels.swift:1344` (command, workingDirectory, tmux, environment). tmux create/attach scripting: `HolyTmuxCommandBuilder.swift:81-104`; ownership stamps :294. Identity matching: `Tmux/HolyTmuxLifecycleIdentity.swift`.
- DB: `~/Library/Application Support/org.holyghostty.app/HolyGhostty/holy-ghostty.sqlite3`; resume-targets view already published at `HolyDatabaseMigrator.swift:429` (`agent_sessions_resume_targets_v1`).
- Agent-state bridge deliberately never reads hook stdin (`HolyAgentStateBridge.swift:386`) — Claude session ids do NOT arrive via hooks today. The watcher hook (:549) shows the sanctioned pattern for reading a single stdin field if you implement the id-confirmation step below.

## Engine requirements (mn-84c0eb's done-list, verbatim intent)
- Preflight per session: cwd/worktree exists, provider executable + auth present, provider history file exists (resolve returned matched=true), execution host matches, tmux identity free, no live duplicate.
- Claude exact `--resume <id>`, Codex exact `resume <id>`, OpenCode exact `--session <id>`, as argument arrays. Never `--last`, `--continue`, a picker, an invented target, or a fresh conversation while claiming success.
- Shell rows recreate cwd/explicit command only and are labeled honestly.
- Bounded batches; attach surfaces lazily. Retries adopt already-restored sessions instead of duplicating (idempotency via tmux ownership stamps + Holy session id).
- "A returning hook confirms the same provider ID; mismatches block": v1 mechanism is your choice — a SessionStart-scoped stdin read of `session_id` stamped into a pane option (watcher-hook pattern) is the sanctioned route; if deferred, re-run resolve after restore and compare, and say so in the issue on done.

## UI requirements (mn-9a6145, summarized)
Cold-boot banner with interrupted count; Restore All / Restore Selected / Keep for Later; rows distinguish exact-resume, shell-only, missing history, wrong host, already restored, conflict, blocked; preserve Holy UUID, tmux name, note, title, Today pin, roster order; selected sessions attach first, the rest stay headless; partial failures visible and retryable; no automatic mass-launch without confirmation.

## Verification
- Build: `scripts/install-holy-ghostty.sh` (standard build; engine/Zig artifacts come from CI, do not rebuild the core locally).
- Swift tests: add coverage under `macos/Tests/HolyGhostty/` following the existing swift-testing (#expect) files; discover the test invocation with `xcodebuild -list -project macos/Ghostty.xcodeproj` (naming it is part of the lane if no scheme is wired).
- Crash drill (the real acceptance test): with 2+ live Claude sessions in the SAME cwd plus 1 Codex session elsewhere, `tmux kill-server`, relaunch the GUI, run Restore All, then verify in each restored pane that the conversation history is the original one (ask the agent what it was doing). The same-cwd pair is the case that breaks naive `--continue` approaches; it must resolve via timestamps or surface the ambiguity picker.
- `agent-do manna done mn-84c0eb` and `mn-9a6145` only after the drill passes.

## Out of scope
- The sessions panel (mn-fe1b48 / prompt 02-HOLY-PANEL.md) and its files.
- Generational recovery manifests (mn-3cdfa0) — superseded as the v1 id source by the resolve CLI; stays open as hardening.
- Remote hosts (restore is local-tmux only for v1), the July 15 salvage (mn-3cd266), agent-sessions internals (lane 05 owns the CLI).


## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-9a6145`.
4. Commit with `Manna: mn-9a6145` and run `agent-do manna done mn-9a6145` only after the work is verified.
