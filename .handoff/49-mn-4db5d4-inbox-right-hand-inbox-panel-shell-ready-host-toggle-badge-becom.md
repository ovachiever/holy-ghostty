---
workflow: 2
manna: mn-4db5d4
track: mn-70875b
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[INBOX] Right-hand inbox panel: shell-ready host, toggle, badge; becomes the alerts surface'
inputs: []
binding: sha256:37f3e9734d0b866270fec83943e71b00f68f8c2c532b214d4a9b50d81d2e5c9f
---

# Handoff: [INBOX] Right-hand inbox panel: shell-ready host, toggle, badge; becomes the alerts surface

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-4db5d4
```

## Scope

[INBOX] Right-hand inbox panel: shell-ready host, toggle, badge; becomes the alerts surface

## Inputs

- None declared.

## Work order

> Legacy migration source: "/Users/erik/Custom-Coding/agent-sessions/.dev/session-prompts/07-INBOX-V1.md"

# 07 INBOX-V1 — the inbox for humans: GitHub attention pane in Holy Ghostty

Repo: `/Users/erik/Custom-Coding/holy-ghostty` (cd there first; it has its own .manna board). Two issues, one lane, sequential claim: `agent-do manna claim mn-378d42` first (data engine), `agent-do manna claim mn-4db5d4` when you reach the UI slice. Set `agent-do coord focus set "human inbox v1" --path macos/Sources/HolyGhostty/Inbox --path macos/Tests/HolyGhostty` and `agent-do coord claim macos/Sources/HolyGhostty/Workspace/HolyWorkspaceView.swift --reason "inbox panel insertion"` plus the same for `HolyWorkspaceStore.swift` before touching either (other lanes share them; coord arbitrates).

## Mission
Holy shows what agents are doing; nothing shows what needs Erik. Build the mirror: a native SwiftUI right-hand panel where every row passes one admission test — addressed to the human, actionable, and self-clearing when reality changes. v1 sources: GitHub PR attention (via `agent-do gh inbox`) plus the existing DB `alerts` table, which today has NO in-app rendering surface (verified: `reconcileAlerts` at HolyWorkspaceStore.swift:4012 is write-side; macOS notifications fire from the surface view; no view renders alert rows). The inbox becomes the in-app alerts surface. Manna triage rows are the fast-follow lane (08-INBOX-MANNA.md), NOT yours: structure row sources as a protocol so lane 08 plugs in without touching your files.

## THE ROW LAW (design invariant, not a preference)
A row that lingers after Erik acted trains him to ignore the pane, and then it is a dashboard, which is where attention goes to die. Every source declares its clear condition and the pane enforces it:
- GitHub rows: gone when the next poll no longer returns them (review submitted, PR merged/closed). No local dismissed-state for GitHub rows in v1 — GitHub is the truth.
- Alert rows: acknowledge action writes `acknowledged_at` (alerts table, schema at HolyDatabaseMigrator.swift:146-159); acknowledged rows leave the pane.
- zpc lessons are explicitly EXCLUDED (no completion state = permanent residents). At most a one-line footer digest "this session: N lessons, M decisions" — optional, not rows.

## GitHub source (verified against the live CLI 2026-08-03)
- Invocation: `agent-do gh inbox --json --limit <N>` (flags verified via --help: --json, --limit, --ceremony-only). Table output live-verified; reason values observed: `review_requested`, `maintainer_unreviewed`, `maintainer_review_stale`, `authored_open`, `bot_author` (a row carries a list, e.g. review_requested + maintainer_review_stale). Fields in table mode: REF (org/repo#n), REASONS, STATE, AUTHOR, UPDATED_AT (ISO8601), TITLE. FIRST TASK of the engine slice: run `--json` once, pin the exact field names in the decoder + a code comment; do not trust this prompt for JSON key spelling.
- Binary discovery: login-shell `command -v agent-do` + well-known fallbacks — copy the pattern from `HolyRestoreResolveClient.swift` (the resolve bridge built 2026-08-03; same subprocess-JSON-decode-degrade shape). Missing binary or nonzero exit → one quiet "GitHub inbox unavailable" degraded row, never a crash, never invented emptiness.
- Sectioning (attention-first, from live reason semantics):
  1. "Needs your review" — reasons contain `review_requested`.
  2. "Unreviewed in repos you maintain" — `maintainer_unreviewed` or `maintainer_review_stale` (without review_requested).
  3. "Yours, open" — `authored_open`, collapsed by default.
  - `bot_author` rows (dependabot et al.) collapse to one digest row per repo ("5 dependabot PRs — palantir"), expandable.
- Scope law: `gh inbox` is cross-repo by design. Do NOT filter to the focused repo — what waits on Erik elsewhere still waits on Erik. SORT the focused session's repo first: match REF's repo against the focused session's `repository_root` remote (derive org/repo from `git -C <root> remote get-url origin`; cache per root).
- Poll cadence: 75s while the panel is visible; 5min while hidden (the unread badge must not lie); immediately on panel open, app foreground, and manual refresh. Serialize polls; a poll in flight absorbs the next request.
- Row action: click opens the PR in the browser (`open https://github.com/<org>/<repo>/pull/<n>` via NSWorkspace). Alert rows: click selects the owning session (roster selection path), acknowledge button writes acknowledged_at.

## UI slice (mn-4db5d4)
- Insertion: `standardContent` HStack at HolyWorkspaceView.swift:222, after `mainWorkspaceContent` (:268). Orphaned right-panel precedent `standardContextPanel` :691 (its HSplitView/toolbar history is in commit b2806b36d — mine for patterns, do not resurrect it).
- SHELL-READY CONTAINER (cross-lane contract): the right-hand region will later also host the agent-sessions archive surface (mn-fe1b48, prompt 02-HOLY-PANEL.md). Build the panel as an enum-driven host (`case inbox` today) with a place for a sibling tab, so mn-fe1b48 adds a case instead of a second panel. One right-hand region, ever.
- Toggle: `@Published` bool on HolyWorkspaceStore (pattern: `historyPresented` near :101) + command palette entry (`holyWorkspaceJumpOptions`, Features/Command Palette/TerminalCommandPalette.swift) + key equivalent in `handleWorkspaceKeyEquivalent` (HolyWorkspaceWindowController.swift:193-221). Unread badge (count of section-1 rows + unacknowledged alerts) on the toggle affordance and palette entry.
- Width: resizable via a second `HolyWorkspaceSplitHandle` (HolyWorkspaceView.swift:17-33), persisted `@AppStorage` like `holy.workspace.rosterWidth.v3` (:131). Native rows are compact; default ~360pt, min ~300pt.
- Design: load artful-ux + artful-colors + artful-typography before UI work; DPT hook may score edits. Prime Rule: the pane shows what the terminal cannot (cross-repo attention state); minimal chrome; restraint over decoration. Row = one line of primary text + repo/time metadata line + reason chip; no cards-in-cards.

## Verification
- Tests first per behavior (swift-testing, #expect, macos/Tests/HolyGhostty/): JSON decode against a fixture of the pinned --json shape; degraded-binary row; section admission per reason combination; bot collapse; focused-repo-first sort; poll serialization; alert acknowledge lifecycle; badge count. Suites: HolyInboxSourceTests, HolyInboxRowLifecycleTests, HolyInboxPanelStateTests (or similar).
- Run: `xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' -only-testing:GhosttyTests/<YourSuites>`. Full-suite check before done; the ONLY tolerated failure is pre-existing mn-54c1ae (HolyRemoteAgentStateBridgeServiceTests/remoteTransactionPreservesUnrelatedSettingsWithoutReturningThem).
- Build + install: `scripts/install-holy-ghostty.sh` (routine; anchored pkill, sessions reattach; never rebuild the Zig core locally — CI owns it). Open the app, toggle the panel, confirm live rows against `agent-do gh inbox` table output.
- Screenshot-verify the panel per the design workflow (baseline → change → screenshot → Quick-5) before calling the UI done.

## Out of scope
- Manna/zpc rows (lane 08). agent-sessions repo. The archive panel itself (mn-fe1b48). Webhooks/GitHub App auth. Notification Center changes (existing macOS notification path stays). Removing reconcileAlerts write-side.

## Rules
Conventional Commits per slice, stage only claimed/owned files, `Manna: mn-378d42` / `Manna: mn-4db5d4` trailers. NEVER git push. `agent-do manna done` each issue only when its own criteria are verified; honest deviations go into the issue description via `agent-do manna update` before done.


## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-4db5d4`.
4. Commit with `Manna: mn-4db5d4` and run `agent-do manna done mn-4db5d4` only after the work is verified.
