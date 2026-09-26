---
workflow: 2
manna: mn-8905ec
track: mn-eb7a80
source: lane mn-e6e3d0 report 2026-09-26
base_commit: 73e24330aa57e143b2a1e568a00b08416827f640
scope: '[P1][TMUX] The launch script targets tmux sessions by bare name, and tmux matches names by prefix'
inputs:
- lane mn-e6e3d0 report 2026-09-26
binding: sha256:21a0431278a61c88b256766e8470d8767391ee81b93d08e13135ef87ec58e6d1
---

# Handoff: [P1][TMUX] The launch script targets tmux sessions by bare name, and tmux matches names by prefix

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-8905ec
```

## Scope

[P1][TMUX] The launch script targets tmux sessions by bare name, and tmux matches names by prefix

## Inputs

- lane mn-e6e3d0 report 2026-09-26

## Work order

Receipt, lane mn-e6e3d0 on tmux 3.7c with a throwaway socket: has-session -t lane succeeded while only lane-2 existed, and -t '=lane' failed as it should. HolyTmuxCommandBuilder passes bare names to has-session, attach, and set-option -t in localLaunchScript, so a spawn or restore naming lane can attach to an existing lane-2 instead of creating lane; a fleet of holy-worker-<uuid> names is safe by accident, hand-named sessions are not. The builder already uses an exact target in one place (exactPaneTarget at HolyTmuxCommandBuilder.swift:506 builds =name:). Deliver: every tmux target the builder emits for a session name uses the exact form =name (and =name:window.pane where a pane is meant), on local and SSH scripts, including detachedCreateCommand and the host-state preamble; a test that builds the scripts for a name that is a prefix of another and asserts no bare -t name remains; a test on a throwaway socket (never holy) that creates lane-2, runs the built has-session for lane, and gets a miss. Own macos/Sources/HolyGhostty/Tmux/HolyTmuxCommandBuilder.swift and its test file only.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-8905ec`.
4. Commit with `Manna: mn-8905ec` and run `agent-do manna done mn-8905ec` only after the work is verified.

## Report

Lane mn-8905ec, 2026-09-26, branch `lane/mn-8905ec` from db38a7e1e.

### Finding that shaped the fix (measured, tmux 3.7c, throwaway socket)

`=name` alone is exact only for commands that resolve a session target. With only `lane-2` alive:

| command | `-t lane` | `-t =lane` | `-t =lane:` |
|---|---|---|---|
| has-session | hit lane-2 (exit 0) | miss (exit 1) | miss |
| attach-session | would join lane-2 | "can't find session: lane" | same |
| list-panes -s | listed lane-2 | listed lane-2 (prefix fallback) | "can't find session: lane" |
| set-option (lane exists) | works | "no such session: =lane", exit 1; with `-q` exit 0 and nothing set | works, lands on session lane |

A naive `=name` everywhere would have silently dropped every `set-option -q` metadata stamp and left the host-state mirror prefix-matching. The builder now emits `=name` for session targets and `=name:` for pane and window targets.

### What changed

`macos/Sources/HolyGhostty/Tmux/HolyTmuxCommandBuilder.swift`
- L106-127: new `exactSessionTarget(_:)` returning `=name` and `exactSessionPaneTarget(_:)` returning `=name:`, with the measurement in the doc comments.
- L136-137: `localLaunchScript` computes both targets once.
- L149-155: the ownership stamp is still validated by `HolyAgentStateBridge.tmuxOwnershipStampArguments(forTarget:)` on the bare name (its allowlist has no `=`), then retargeted to `=name:` by the new `retargeted(_:from:to:)` (L204-216).
- L168, L183: `has-session -t =name` (create and adopt paths).
- L170, L446, L459: metadata and initial-note `set-option -q -t =name:` (`metadataCommands` and `initialNoteCommands` now take a `target:`).
- L192: `set-option -q -t =name: @holy_host_state_db_v1`.
- L196: the host-state mirror (`list-panes -s -t`) gets `=name:`.
- L199: `exec tmux attach -t =name`.
- L548: the model-label writer uses the shared helper (same `=name:` value as before).
- Unchanged: `new-session -s name` (a name, not a target), the `@holy_session_name` value, the SSH `sessionKey`, and the in-pane preamble, which targets `$TMUX_PANE`. Public surface: additive only (two internal static helpers).

`macos/Tests/HolyGhostty/HolyTmuxCommandBuilderTests.swift` (new suite `HolyTmuxCommandBuilderTests`)
- `everyEmittedSessionTargetIsExact`, 4 cases (create or adopt, local or SSH): walks every nested shell layer with the URL-gate suite's `HolyShellLexer`; asserts no `-t lane` remains, has-session and attach use `=lane`, every other `-t` naming lane uses `=lane:`, and the mirror target is `=lane:`.
- `detachedCreateEmitsOnlyExactTargets`: the restore path, same assertions, no attach.
- `exactTargetFormsMatchTheModelLabelWriter`.
- `builtHasSessionMissesAPrefixSiblingOnALiveServer`: socket `mn-8905ec-<uuid>` (never `holy`) creates `lane-2`; a control proves bare `has-session -t lane` hits it; the built has-session misses; the built detached-create then creates `lane` itself, the sessions are exactly `[lane, lane-2]`, and `@holy_session_name` plus the ownership option land on lane and not on lane-2. The host-state DB is redirected to a temp file through `HOLY_HOST_STATE_DATABASE`; kill-server runs in a defer.

### Every emitted tmux target, before and after (session name N)

| site | before | after |
|---|---|---|
| has-session (create path) | `N` | `=N` |
| has-session (adopt path) | `N` | `=N` |
| set-option metadata (10 keys) | `N` | `=N:` |
| set-option initial note (2 keys) | `N` | `=N:` |
| set-option ownership stamp | `N` | `=N:` |
| set-option @holy_host_state_db_v1 | `N` | `=N:` |
| host-state mirror list-panes -s | `N` | `=N:` |
| attach | `N` | `=N` |
| model-label writer (set/show-options -p) | `=N:` | `=N:` |
| in-pane preamble | `$TMUX_PANE` | `$TMUX_PANE` |

### Receipts (xcresulttool summary)

- `/tmp/mn-8905ec-5.xcresult`, HolyTmuxCommandBuilderTests after the final restore: 4 tests, 7 runs passed, 0 failed, 0 skipped.
- `/tmp/mn-8905ec-3.xcresult`, adjacent suites (builder, CommandFlag, RestoreDetachedCreate, ModelStatus, HostStateMirror, AutomationURLGate, NonCommandFieldSink, MannaBoardActions): 84 tests, 408 runs passed, 1 failed.
- The one failure, `HolyMannaBoardActionsTests/dispatchNoteSurvivesTmuxDetachDiscoveryAndReadoption` ("Holy host state mirror failed: CalledProcessError"), fails identically against the base builder from db38a7e1e (`/tmp/mn-8905ec-4-base.xcresult`: 31 tests, 1 failed, same text). Pre-existing, not caused by this lane.

### Risks

- The new suite borrows `HolyShellLexer` from `HolyAutomationURLGateTests.swift`; renaming or privatizing it breaks this suite.
- A session name shaped like a pane id (`%5`) makes the bridge choose `-pq`; after retargeting it stamps the active pane of session `%5` rather than pane `%5`. The URL gate refuses `%` names.
- Emitters outside this file (Remote/, Session/, Workspace/) were not audited here; `HolyWorkspaceStore` termination already uses `=name`.
- The pre-existing dispatch-note failure is unexplained. It runs with an empty environment and the debug bundle's DB path, which is where to start.
