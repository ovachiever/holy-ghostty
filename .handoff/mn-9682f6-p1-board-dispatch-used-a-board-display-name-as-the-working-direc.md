---
workflow: 2
manna: mn-9682f6
track: mn-eb7a80
source: sessions row 985BC829; restore sheet 2026-09-26
base_commit: 962f13ad23c8f022a2b5d44d29de8085c36339de
scope: '[P1][BOARD] Dispatch used a board display name as the working directory; a worker was created into a path that does not exist'
inputs:
- sessions row 985BC829; restore sheet 2026-09-26
binding: sha256:fcb97b8ddd47331b9714a3f8ec64e7fc0aa414ad2ddb5fbd1d82c668c7731933
---

# Handoff: [P1][BOARD] Dispatch used a board display name as the working directory; a worker was created into a path that does not exist

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-9682f6
```

## Scope

[P1][BOARD] Dispatch used a board display name as the working directory; a worker was created into a path that does not exist

## Inputs

- sessions row 985BC829; restore sheet 2026-09-26

## Work order

Receipt: session 985BC829 (title versova-supply-intelligence, codex, created 2026-09-23T13:40:28Z, note mn-cb43d9, objective Claim and build mn-cb43d9) has working_directory and resume lastKnownWorkingDirectory equal to /Users/erik/Custom-Coding/Research Comprehensive App Security | Custom-Coding; the sibling dispatch 336655AA five minutes later got /Users/erik/Custom-Coding/versova-supply-intelligence. HolyMannaBoardWorker.swift:244 sets spec.workingDirectory = context.boardRoot and :180 only checks the / prefix, so a root composed from a board display name passes. Deliver: find where boardRoot is composed for that board (federation or estate entry whose name carries a pipe) and make it the board's real repository path; dispatch refuses with a named reason when the directory does not exist on the target host; the row title and objective keep the item id. Test: a board whose display name differs from its path dispatches into the path; a missing directory refuses. Own macos/Sources/HolyGhostty/Board/ and the HolyMannaBoard test files only.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-9682f6`.
4. Commit with `Manna: mn-9682f6` and run `agent-do manna done mn-9682f6` only after the work is verified.

## Report

Lane worker, 2026-09-26, base 3cf78d258. Not sealed and not closed; the orchestrator owns board commands.

### Where the display name entered the path

The Board code did not build the bad path from a board display name. The evidence:

- The estate registry (`~/.agent-do/manna/serve/boards.json`) has no entry with a pipe in it; every root is a real folder. This repo's `.manna/federation.yaml` has `relations: []`.
- `manna state` runs with `boardRoot` as the process's working directory (`HolyMannaBoardClient.swift:332`, `:433`). `confirmWorker` also requires `fresh.root == request.context.boardRoot`. So a root that does not exist fails before any spawn.
- The row title is set at dispatch from `lastPathComponent(boardRoot)` (`HolyMannaBoardWorker.swift:302`). Row 985BC829's title is `versova-supply-intelligence`, so the root at dispatch ended in `versova-supply-intelligence`.
- mn-cb43d9 is "MRO-only database role for the level-3 SQL tool". The text "Research Comprehensive App Security" is not from that item.

Only one piece of code in the app builds `<parent>/<free text>`: tmux discovery's `inferred_working_directory`, at `macos/Sources/HolyGhostty/Remote/HolyRemoteTmuxDiscoveryService.swift:717-721`. When a pane's `pane_current_path` ends in a generic folder name (`custom-coding`, `projects`, `repos`, ...), it appends the first `project_candidate` from `pane_title`, `window_name`, or the session name. `project_candidate` rejects values containing `/` but accepts `Research Comprehensive App Security | Custom-Coding`. `HolySession.swift:653-655` then writes the discovered directory into `record.launchSpec.workingDirectory`, which also feeds the resume `lastKnownWorkingDirectory`.

Not verified, because the rules keep me out of the live data and the `holy` socket: which pane's title was used, and how row 985BC829 ended up bound to a pane running in `/Users/erik/Custom-Coding`. A restore that re-bound the row to another pane is one candidate (see mn-3c4b23). To verify, read that row's history in `session_events` and the `holy` socket's pane cwd and title for its tmux session.

### Changes, file by file

- `macos/Sources/HolyGhostty/Board/HolyMannaBoardWorker.swift`
  - New error case `HolyMannaWorkerLaunchError.workingDirectoryMissing(path:host:)`. It reads: "The board's repository directory <path> does not exist on <host or this Mac>. No worker was opened."
  - New `HolyMannaWorkerDirectoryProbe`:
    - Locally, it checks for a directory with `FileManager`.
    - On a remote host, it runs `test -d '<path>'` through the managed SSH control lane. It keeps the same host validation and admission permit as the runtime lookup.
    - Exit 0 means the directory exists and exit 1 means it does not. Any other exit, such as ssh's 255, is thrown as a transport failure, never treated as "missing".
  - The runtime probe's existing literal `15` and its SSH options became the named constants `probeTimeout` and `sshProbeOptions`. The values did not change, and both probes share them.
  - Comment on the title: the title stays the repository folder (roster ruling 2026-08-22), and the item id goes in the objective and note.
- `macos/Sources/HolyGhostty/Board/HolyMannaBoardStore.swift`
  - Adds the injectable `workerDirectoryProbe` (default `.live`).
  - `confirmWorker` now checks `fresh.root` on the execution host after the fresh state read and before `launchSpec` and spawn (line 583). A missing directory shows "Worker not started: ...does not exist on ...", with no spawn and no claim.
- `macos/Tests/HolyGhostty/HolyMannaBoardActionsTests.swift`
  - Three new tests:
    - `boardDisplayNameNeverBecomesTheWorkerDirectory`: a real temporary folder `.../versova-supply-intelligence`, a board named `Research Comprehensive App Security | Custom-Coding`, and the live probe. The worker gets that folder as its working directory, the title `versova-supply-intelligence`, the objective `Claim and build mn-123456`, and the note `mn-123456`. The display name appears nowhere.
    - `missingBoardDirectoryRefusesWithNamedReasonBeforeSpawn`: the live probe on a folder that does not exist. The notice is exactly the named error, with zero spawns, no claim, and the item still open.
    - `remoteDirectoryCheckRunsOnTheHostQuotedAndNamesTheHost`: the ssh wrapper targets the host, option-injection hosts are refused, and a remote "absent" becomes the named error with the host in it.
  - Fixture changes: the state fixture and client fixture take `name` and `root`, and the stores built for dispatch get a fixture probe, because `/synthetic/board` is not on disk.
- `macos/Tests/HolyGhostty/HolyMannaBoardLinkTests.swift`: `linkStore` gets a fixture probe for the same reason.

### Test results (read with `xcrun xcresulttool get test-results summary`)

`-only-testing:GhosttyTests/HolyMannaBoardActionsTests -only-testing:GhosttyTests/HolyMannaBoardLinkTests`, serial:

- `/tmp/mn-9682f6-2.xcresult`: 50 total, 49 passed, 1 failed. The failure was my new test's own over-broad check for " | " across the whole command; the brief carries " | " by design. I narrowed the check.
- `/tmp/mn-9682f6-4.xcresult` and `/tmp/mn-9682f6-5.xcresult`: 50 total, 49 passed, 1 failed, 0 skipped. All three new tests passed. The failure was `dispatchNoteSurvivesTmuxDetachDiscoveryAndReadoption`, with `created.exitCode 1: Holy host state mirror failed: CalledProcessError`.
  - The same test passed in run 2, on code that was identical along its path.
  - It calls `launchSpec` directly and creates a real tmux server. This change touches neither `launchSpec`'s output nor the tmux builder nor the mirror.
  - Cause not verified. A likely mechanism: the pane runs `exec /usr/bin/true` and exits, racing the mirror's `list-panes`.
  - I did not rerun it on base 3cf78d258 to discriminate. That test's mirror can write to `HolyDatabasePaths.databaseURL`, and I am barred from touching live data.
  - To verify: run that one test on base 3cf78d258 in an isolated environment.

### Risks and what is left

- The root cause is still in code outside this lane. A follow-up item for Remote/Session owners: `inferred_working_directory` should never turn a pane title into a path component. At minimum, it should refuse a candidate unless `<base>/<candidate>` exists as a directory. And `HolySession.swift:653` should not overwrite a Holy-created session's recorded working directory with an inferred one.
- The work order asks that "the row title and objective keep the item id". The title stays the repository folder name, per the 2026-08-22 roster ruling; the objective and note carry the item id. If the title was also meant to carry the id, that conflicts with the ruling and needs Erik.
- A remote dispatch now makes one more SSH round trip (`test -d`) on the control lane.
