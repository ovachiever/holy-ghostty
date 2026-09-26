---
workflow: 2
manna: mn-a7baaa
track: mn-eb7a80
source: session_events 985BC829 seq 166-167; lane mn-9682f6 report
base_commit: 86874c4c760c01889ef349a037ecded06d9bcd53
scope: '[P1][DISCOVERY][SESSION] tmux discovery turns a pane title into a path component and overwrites the session''s recorded working directory'
inputs:
- session_events 985BC829 seq 166-167; lane mn-9682f6 report
binding: sha256:a1915f9d6fdd7cc5a28e9245bdc7b4b82f6d5529920e70258b1e25c87abe02e7
---

# Handoff: [P1][DISCOVERY][SESSION] tmux discovery turns a pane title into a path component and overwrites the session's recorded working directory

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-a7baaa
```

## Scope

[P1][DISCOVERY][SESSION] tmux discovery turns a pane title into a path component and overwrites the session's recorded working directory

## Inputs

- session_events 985BC829 seq 166-167; lane mn-9682f6 report

## Work order

Receipt, row 985BC829 (versova-supply-intelligence, codex, created 2026-09-23T13:40Z with working directory /Users/erik/Custom-Coding/versova-supply-intelligence, kept through event 165): event 166 at 2026-09-24T20:58:33Z session_runtime_updated carries workingDirectory /Users/erik/Custom-Coding (the pane had moved to the parent), event 167 at 20:58:49Z carries /Users/erik/Custom-Coding/⠸ Research Comprehensive App Security | Custom-Coding, which is the parent plus the Codex window title with its spinner glyph; the row and its resume metadata lastKnownWorkingDirectory still hold that string (without the glyph) and the restore sheet showed the row as unrestorable on 2026-09-26. Source, established by lane mn-9682f6: HolyRemoteTmuxDiscoveryService.swift:717-721 inferred_working_directory appends a candidate taken from pane_title or window_name when pane_current_path ends in a generic folder name (custom-coding, projects, and similar); the candidate filter rejects only a slash; HolySession.swift:653-655 then writes the inferred value into record.launchSpec.workingDirectory. Deliver: (1) inferred_working_directory never emits a path that does not exist on the host: a title-derived candidate is accepted only when base/candidate is an existing directory there (local FileManager, or test -d over the managed control lane for remote hosts, the same probe shape lane mn-9682f6 added to Board), otherwise the pane's real path stands; titles carrying spinner or status glyphs or a pipe are never path material; (2) HolySession never overwrites a launch spec working directory that Holy set at creation with an inferred one; an observed pane directory is recorded as observed state (resume metadata lastKnownWorkingDirectory) only when it exists, and the launch spec keeps the creation value; (3) tests: a discovery fixture whose pane reports cwd /tmp/<base> and title '⠸ Research Comprehensive App Security | Custom-Coding' yields /tmp/<base>; the same fixture with an existing /tmp/<base>/Research directory and title 'Research' yields that directory; a session created with directory X keeps X after discovery reports a non-existent Y, and records Y as observed when Y exists. Own macos/Sources/HolyGhostty/Remote/HolyRemoteTmuxDiscoveryService.swift, macos/Sources/HolyGhostty/Session/HolySession.swift, and their test files only; Restore/, Archive/, Board/, and Workspace/ belong to other lanes.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-a7baaa`.
4. Commit with `Manna: mn-a7baaa` and run `agent-do manna done mn-a7baaa` only after the work is verified.

## Report

Lane worker, branch `lane-mn-a7baaa` (started at 02500da58; the original worktree branch sat on an unrelated upstream Ghostty commit, so a new branch was cut at 02500da58 and the old one left untouched).

### Changes

- `macos/Sources/HolyGhostty/Remote/HolyRemoteTmuxDiscoveryService.swift`
  - L705-718: new `path_component_candidate`, which runs `project_candidate` and then rejects any value with a character outside `A-Za-z0-9 . _ + - space` (so spinner/status glyphs and `|` never qualify, in any locale including C over SSH) and any value starting with `.` (no `.`/`..` traversal).
  - L720-742: `inferred_working_directory` rewritten. If the pane directory's name is not generic it is returned as is. Otherwise each title/window/session candidate is tried, and one is accepted only when `[[ -d base/candidate ]]` holds; if none does, the pane's real path is returned. The script runs on the host itself (local `/bin/zsh`, or `zsh -lc` over the managed SSH control lane), so `-d` is the host's own answer.
- `macos/Sources/HolyGhostty/Session/HolySession.swift`
  - L172-175: new `@Published private(set) var observedWorkingDirectory: String?` (observed state, in memory).
  - L640-673: new `static func resolvedDiscoveredWorkingDirectory(recorded:discovered:transport:directoryExists:)` and `localDirectoryExists(_:)`.
  - L690-704: `applyDiscoveredLaunchMetadata` uses that resolution in place of the old unconditional overwrite (old L653-656).
  - L847: `archiveSnapshot()` sets `lastKnownWorkingDirectory` to `observedWorkingDirectory ?? workingDirectory`.
- `macos/Tests/HolyGhostty/HolyDiscoveredWorkingDirectoryTests.swift` (new): 8 tests. Three drive real discovery against a scratch tmux server on a unique `holy-a7baaa-<uuid>` socket (never `holy`), pane cwd `/tmp/holy-a7baaa-<uuid>/Custom-Coding`. The leaf is a generic name so that inference is armed. Four cover the pure resolution rule. One runs a live `HolySession` built from a temporary Ghostty config.

### Rules now applied

- Title-derived candidates: a pane title, window name, or session name can only replace a generic pane directory (custom-coding, projects, repos, workspace, ...) with `base/candidate`. That happens only when the candidate passes `project_candidate`, contains only `A-Za-z0-9._+ -`, does not start with `.`, and `base/candidate` is an existing directory on the host. Otherwise the pane's real `pane_current_path` stands.
- Launch-spec overwrites: discovery never overwrites a non-blank `launchSpec.workingDirectory`. It fills a blank one (an adopted session) only when the discovered directory exists. Any discovered directory that exists is stored as `observedWorkingDirectory`, and archive snapshots carry it as `lastKnownWorkingDirectory`. A directory that does not exist is dropped entirely. For local sessions, existence is checked with FileManager. For remote (`.ssh`) sessions it relies on the host-side script.

### Test runs (xcresulttool summary)

- `/tmp/mn-a7baaa-2.xcresult`, new suite: 8 passed, 0 failed, 0 skipped.
- `/tmp/mn-a7baaa-3-oldscript.xcresult`, new suite with the pre-fix discovery script restored (discriminating run): 5 passed, 3 failed. The spinner test's failure shows the old script emitting `/private/tmp/.../Custom-Coding/⠸ Research Comprehensive App Security | Custom-Coding`, which is the receipt string.
- `/tmp/mn-a7baaa-4-oldsession.xcresult`, new suite with the pre-fix launch-spec overwrite restored (discriminating run): 7 passed, 1 failed (the live-session test: the launch spec became `.../moved`).
- `/tmp/mn-a7baaa-5.xcresult`, new suite plus HolyRemoteTmuxDiscoveryTimeoutTests, HolyHostsDiscoveryTests, HolyTmuxLifecycleIdentityTests, HolyTmuxSessionMetadataSyncTests, HolySessionLiveStatusTests, and HolySessionRuntimeInferenceTests: result Passed, totalTestCount 106, 0 failed, 0 skipped. The device row reports 118 passed, presumably from parameterized cases counted separately; not checked.
- `/tmp/mn-a7baaa-6.xcresult`, new suite after the teardown fix: 8 passed, 0 failed, 0 skipped.

### Risks and open items

- `observedWorkingDirectory` lives in memory only. It reaches persistence only through `archiveSnapshot()`. The active-row resume metadata (`HolyResumeMetadata.active`, in Persistence/) still writes `lastKnownWorkingDirectory: nil`. Persisting observed state for live rows would require a change in Persistence/, which is outside this lane.
- For remote sessions, the pane's own `pane_current_path` is trusted as existing. The script does not `-d` it, because the work order says the pane's real path stands. A pane whose cwd was deleted on the host would still be recorded as observed.
- Adopted tmux sessions (`createIfMissing == false`) used to follow the pane's cwd through launch-spec overwrites. They now keep their first recorded directory for display and project name, and later moves show up only as observed state. This is intended by the work order, but it is a behavior change on the roster.
- Existing bad rows (such as 985BC829) are not repaired here. Their launch spec and `lastKnownWorkingDirectory` still hold the corrupt string, and fixing them belongs to Restore/ or a data lane.
- Not done, by lane rule: `agent-do manna handoff seal`, claim/done, push, installer.
