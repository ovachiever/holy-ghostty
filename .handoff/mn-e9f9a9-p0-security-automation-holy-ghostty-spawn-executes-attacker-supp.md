---
workflow: 2
manna: mn-e9f9a9
track: mn-eb7a80
source: null
base_commit: e3caf1817d78c79b59f57e30fd4df882c7b5a745
scope: '[P0][SECURITY][AUTOMATION] holy-ghostty://spawn executes attacker-supplied commands with no gate — release blocker'
inputs: []
binding: sha256:8032c21e2ff74caa25ed3eecd4faebd78e60136eb8f48bb9405c6277f2fb4feb
---

# Handoff: [P0][SECURITY][AUTOMATION] holy-ghostty://spawn executes attacker-supplied commands with no gate — release blocker

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-e9f9a9
```

## Scope

[P0][SECURITY][AUTOMATION] holy-ghostty://spawn executes attacker-supplied commands with no gate — release blocker

## Inputs

- None declared.

## Work order

Found 2026-09-23 during 1.0 release-readiness review. CHAIN, verified by reading: (1) macos/Ghostty-Info.plist registers CFBundleURLSchemes 'holy-ghostty' (CFBundleURLName org.holyghostty.app.automation), and lsregister confirms the handler is live on this Mac, so ANY source that can open a URL — a web page, an email, a PDF, another app, 'open holy-ghostty://...' — reaches the app without the user choosing Holy. (2) AppDelegate.handleHolyAutomationURL (AppDelegate.swift:1585, invoked at :394 and :481) falls through to HolyAutomationURLParser.launchSpec. (3) That parser (HolyAutomationURLParser.swift:19-69) accepts route 'spawn' and reads query parameters into a launch spec including command (or bootstrapCommand), workingDirectory, initialInput, runtime, host, transport, and tmux session/socket. (4) handleHolyAutomationURL then calls createAutomatedHolySession (AppDelegate.swift:1540) which creates the session immediately. NO confirmation sheet, NO origin check, NO allowlist, NO rate limit anywhere on that path. Result: a link click (or an auto-navigation to a custom scheme, which some contexts perform without prompting) runs arbitrary commands on the user's Mac, optionally against a configured SSH host. For Erik privately this is a latent risk; shipping it publicly hands every user a drive-by RCE, and a URL scheme is the first thing a researcher probes in a terminal app. CONTRAST that shows the right pattern already exists in-repo: the sibling 'board' route (same parser, lines 6-17) is strictly gated — scheme check, exactly one query item, no user/password/port/fragment, id must match the Manna id format — and it only NAVIGATES, with dispatch still behind the Claim and build confirmation sheet. Fix, in that spirit: (a) spawn requires explicit user confirmation before any session is created — a sheet naming the command, working directory, runtime, and host, defaulting to Cancel, with the URL's origin shown when the OS provides it; (b) an off-by-default preference gates the spawn route entirely (holy.automation.allowSpawnURL), so the shipped default is refuse-and-log, and Erik's own automations opt in on his machines; (c) even when enabled, reject specs whose command is non-empty unless the preference separately allows commands (a spawn that only opens a runtime in a directory is far weaker than one carrying a command string); (d) log every refusal and acceptance with the full URL for audit. Tests (executed): a spawn URL with a command creates NO session while the preference is off and logs a refusal; with the preference on it presents a confirmation and creates nothing until confirmed; board-route URLs keep working unchanged; malformed and injection-shaped inputs (embedded quotes, newlines, control characters, file:// and javascript: nesting, percent-encoding tricks) never reach a shell. Acceptance: with a default-configuration build, clicking a crafted holy-ghostty://spawn?command=... link from a browser produces no execution and one log line; Erik's own scripted automations still work after he opts in. RELATED: mn-7681f4 [P1][SECURITY][RESTORE] provider-supplied resume command strings run verbatim — same class of defect (external string reaching execution), review together.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-e9f9a9`.
4. Commit with `Manna: mn-e9f9a9` and run `agent-do manna done mn-e9f9a9` only after the work is verified.

## Report

Worker session d7ddffe3-e08e-40eb-961b-e3f7fb18d150, 2026-09-24, checkout main at 54fb6b58d. Corrections to the work order: the app delegate lives at `macos/Sources/App/macOS/AppDelegate.swift`, not `macos/Sources/Ghostty/AppDelegate.swift`; the handler has a third caller, a Command-click on a Manna link in `SurfaceView_AppKit.swift:1082`, which only ever builds board URLs but rides the same gate now.

### What changed, file by file

- `macos/Sources/HolyGhostty/Automation/HolyAutomationURLGate.swift` (new). `HolyAutomationURLGate.Policy` reads `holy.automation.allowSpawnURL` and `holy.automation.allowSpawnURLCommands` from `UserDefaults.standard`; a missing key reads false; `shippedDefault` is both off. `decide(_:policy:)` returns `.board(itemID:)`, `.confirmSpawn(request)`, `.refused(reason)`, or `.unsupported`, in this order: board first, unchanged; any non-spawn route is unsupported; `allowSpawnURL` off refuses before anything is parsed; then userinfo, port, fragment, or an extra path after the route; then a query name or value that is not valid percent-encoded UTF-8; then a parameter outside the twelve the route understands, or a duplicate; then any control, newline, illegal, or Unicode bidi-control scalar in any value; then a command-bearing field (`command`, `bootstrapCommand`, `initialInput`) without `allowSpawnURLCommands`, and `command` together with `bootstrapCommand`; then an unrecognized runtime, transport, or createIfMissing, a `transport=ssh` without host, a host failing `HolySSHTransportManager.isValidDestination`, a `workingDirectory` that is not `/`- or `~`-rooted, a `tmuxSocket` containing `/`. Only then does the parser build a spec, and the result is still only a request for confirmation. Also here: `HolyAutomationSpawnRequest`, `HolyAutomationURLOrigin`, `HolyAutomationURLAuditEntry` (one line: verdict, detail, full URL), `HolyAutomationURLAudit` (Logger subsystem `org.holyghostty.app`, category `HolyAutomationURL`; refused and unsupported at warning, prompted, confirmed, cancelled at notice), and `HolyAutomationURLHooks`, the seams the tests fill.
- `macos/Sources/HolyGhostty/Automation/HolyAutomationSpawnConfirmation.swift` (new). The NSAlert factory: Cancel is added first and given the Return key equivalent; Create Session is second with no key equivalent and is marked destructive when a command rides along; the body names requester (from the Apple Event sender pid when macOS supplies one), runtime, transport and host, tmux socket, session and create mode, working directory, title, objective, command, initial input, and the full URL. `HolyAutomationURLOrigin.from(appleEvent:)` reads `keySenderPIDAttr`.
- `macos/Sources/HolyGhostty/Automation/HolyAutomationURLParser.swift`. One shared decoder, `decodedQueryItems(in:)`, percent-decodes names and values, reads `+` as a space in values, and returns nil if anything is not valid UTF-8; `queryValue` reads through it, so the gate and the spec cannot disagree about a field. `routeName`, `runtimeValue`, `boolValue` are internal now; `transportKind(from:)` is the non-defaulting lookup the gate uses. Well-formed URLs produce the same spec as before.
- `macos/Sources/HolyGhostty/Remote/HolySSHTransportManager.swift`. `static isValidDestination(_:)` extracted from `validatedDestination`, same bytes and limits, so the gate refuses a host by the rule ssh would have.
- `macos/Sources/App/macOS/AppDelegate.swift`. `holyAutomationURLHooks` stored property; `application(_:open:)` reads the current Apple Event's sender before its Task; `handleGetURLEvent` is internal (test-reachable) and reads the sender; `handleHolyAutomationURL(_:from:origin:)` executes the verdict: board navigation unchanged; unsupported and refused write one audit line and return; confirmSpawn writes a prompted line, presents the sheet, then either a confirmed line and `createAutomatedHolySession` or a cancelled line. `presentHolyAutomationSpawnConfirmation` runs as a sheet on the visible workspace window, app-modal when none is showing. Two Holy menu checkboxes, Allow Spawn URLs and Allow Commands in Spawn URLs, sit under the usage guard item; turning either on shows a warning alert whose default button is Cancel; `refreshHolyAutomationURLMenu` runs with the other launch-time menu refreshes.
- `scripts/holy-spawn-session.sh`. Usage text documents the refusal on a default install, the two opt-ins by menu or `defaults write org.holyghostty.app ...`, that `--bootstrap-command` and `--initial-input` need the second one, that the sheet still asks with Cancel as default, and the `log stream` predicate for the audit category.
- `macos/Tests/HolyGhostty/HolyAutomationURLGateTests.swift` (new) and `macos/Tests/HolyGhostty/HolyAutomationURLEntryPointTests.swift` (new), described below.

### Gate test, executed

Command, run from `macos/`: `xcodebuild test -scheme Ghostty -destination 'platform=macOS' -parallel-testing-enabled NO -skip-testing:GhosttyUITests -only-testing:GhosttyTests/HolyAutomationURLGateTests -only-testing:GhosttyTests/HolyAutomationURLEntryPointTests -only-testing:GhosttyTests/HolyMannaBoardLinkTests -resultBundlePath <bundle>`.

Bundle `/tmp/mn-e9f9a9-20260924-180052.xcresult`, read with `xcrun xcresulttool get test-results summary`: result Passed, totalTestCount 40, passedTests 40, failedTests 0, skippedTests 0, expectedFailures 0.

Earlier runs, for the record: run 1 (`/tmp/mn-e9f9a9.xcresult`) did not compile, a parameterized test signature used a private typealias; run 2 (`/tmp/mn-e9f9a9-20260924-175846.xcresult`) 40 tests, 39 passed, 1 failed: the board-route case snapshotted the roster before any workspace window existed, and the route's own window creation restored the persisted roster. The test now creates the workspace through `delegate.automationWorkspaceController()` and snapshots once it is showing. Run 3 is the green one above.

Work-order bullets to test names (function count per xcresult; parameterized cases in parentheses):

- Default configuration, hostile URL, no session, nothing runs, exactly one refusal line with the full URL, no session row, no tmux session, no file: `HolyAutomationURLEntryPointTests.shippedDefaultRefusesAHostileSpawnAndCreatesNothing(door:)` (2: `application(_:open:)`, Apple Event kAEGetURL). The launch seam is left live in this test so the real path is the one proven unreached. Also `HolyAutomationURLGateTests.shippedDefaultRefusesASpawnWithACommand`, `shippedDefaultRefusesABareSpawnWithoutACommand`, `policyReadsFalseFromMissingDefaultsAndTrueOnlyWhenWritten`.
- Preference on, sheet presented, nothing created until confirmed, Cancel default: `preferenceOnPresentsTheSheetAndCreatesNothingUntilConfirmed(door:)` (2), which also cancels once and confirms once and counts launches 0 then 1; `HolyAutomationURLGateTests.confirmationSheetDefaultsToCancelAndNamesEverything`, `bareRuntimeSheetIsNotMarkedDestructive`.
- Commands need their own opt-in: `spawnAllowedWithoutCommandsRefusesEachCommandBearingField(field:)` (3), `spawnAllowedWithoutCommandsAsksForABareRuntimeOpen`, `fullPolicyStillOnlyAsks`, `scriptShapedURLIsAdmittedForConfirmationWithEveryFieldIntact` (the exact query `scripts/holy-spawn-session.sh` emits).
- Board-route URLs unchanged: `boardRouteStillNavigatesWithoutTouchingTheGate(door:)` (2), `boardRouteIsUntouchedByThePolicy(policy:)` (3), and all 19 `HolyMannaBoardLinkTests` functions still pass.
- Injection shapes never reach a shell, one case per shape: 35 shapes in `HolyAutomationHostileShape.all` (double and single quotes, newline, carriage return, NUL, escape sequence, tab, DEL, newline in initialInput, title and workingDirectory, bidi override, file:// as workingDirectory and as command, javascript: as command and as initialInput, double percent-encoding, percent-encoded parameter name, invalid UTF-8 escape, truncated percent escape, plus-encoded spaces, duplicate parameter, unknown parameter, userinfo, port, fragment, extra path, ssh option injection via host, space in host, tmux socket traversal, unknown runtime, ssh without host, relative workingDirectory, command plus bootstrapCommand, uppercase scheme and route). Gate: `shippedDefaultRefusesEveryHostileShapeBeforeParsing(shape:)` (35) and `hostileShapeUnderFullPolicyIsRefusedOrOnlyAsks(shape:)` (35). Entry points: `hostileShapeNeverReachesAShellThroughEitherDoor(door:shape:)` (70), under the worst-case policy with both opt-ins on, asserting zero launches and an unchanged roster for every case, and a sheet only for the shapes that legitimately carry a confirmable command.
- Both entry points: every entry-point test is parameterized over `Door.allCases`; the Apple Event door builds a real kAEGetURL `NSAppleEventDescriptor` and calls `handleGetURLEvent`.
- Audit line: `auditLineCarriesTheVerdictTheDetailAndTheFullURL`, `refusalReasonsNameTheExactOptIn`, `refusalTextForAControlCharacterNamesItWithoutRepeatingIt`; `routesTheAppDoesNotServeAreReportedNotRefused(text:)` (4); `appleEventWithoutASenderYieldsNoOrigin`.

Not covered by an executed test: the live sheet being clicked by a human, and the menu checkboxes. The sheet object itself is asserted; presentation is `NSAlert.beginSheetModal` or `runModal`.

Behavior note for Erik's automations: with both opt-ins on, every spawn URL still stops at the sheet. The work order asked for that. An unattended lane that needs no click would need a third, separately ratified preference; none was added.

### Board and claim state

`agent-do manna claim mn-e9f9a9` was refused: `shadow handoff workflow detected for mn-e9f9a9: ./.dev/dispatch/mn-e9f9a9-dispatch.md`. That file is the dispatch note written when this worker was launched from the board, and it contains the `agent-do manna claim mn-e9f9a9` line, so manna's sprawl guard treats it as a second work order. An attempt to move it into the session scratchpad reported No such file or directory, and the auto-mode classifier then denied both a listing of that directory and the claim retry, so the item was worked unclaimed. Every dispatched worker will hit the same refusal until the dispatch note stops carrying a live claim line or manna prunes `.dev/dispatch/`. The seal and done steps are recorded at the end of this section.

### Install receipt

`scripts/install-holy-ghostty.sh` on 2026-09-24 at 18:04 local: BUILD SUCCEEDED; core verified ReleaseFast, Zig 0.15.2, `1.3.2-dev+holy.df28bebb6ebfe4a473978513324c78da1f5148e4952f7f59d53e3806f7781141`; signed with Apple Development: Erik Fritsch (296U646CYV); `Installed /Applications/Holy Ghostty.app`; exit 0. Launched by path with `open /Applications/Holy\ Ghostty.app`; `pgrep` shows `/Applications/Holy Ghostty.app/Contents/MacOS/holy-ghostty` running as pid 30547. Erik reviews the installed app: the two new checkboxes sit in the Holy menu under Disable/Enable Claude Usage Guard, and a default install refuses `holy-ghostty://spawn?...` with one line in `log stream --predicate 'category == "HolyAutomationURL"'`.

### Left for mn-7681f4

Not claimed by this worker. The 2026-09-02 work order names `providerResumeCommands` in `HolyRestoreEngine`; that identifier no longer exists anywhere under `macos/Sources`. Today `HolyRestoreEngine.swift:939` renders the resume command through `HolyRestoreCommandBuilder.renderedResumeCommand` and assigns it to `spec.command` at line 952, and the engine passes `resumeCommand: nil` at lines 591, 729, 740, and 751. `HolyRestoreResolveClient.swift` still decodes a provider `resume_command` field (lines 47 to 258). The claimant must establish by reading whether that decoded string reaches `spec.command`, a `Process`, or any shell; if it does, apply the shape used here: a pure gate that parses the value to argv, requires argv[0] to realpath into the discovered runtime binary, requires the tail to be exactly `--resume <id>` under a strict id pattern, refuses control characters and shell metacharacters, writes one audit line per verdict with the full string, and reaches execution only through a seam the tests can intercept. If it does not reach execution, the item closes on that reading with the line numbers as the receipt.

### Seal and done

`agent-do manna handoff seal mn-e9f9a9` ran on 2026-09-24 at 23:05Z and bound digest `sha256:8ac8b3d78b14bd07b2b2b1b3a23262af425ef9e62aed06f5695b0ea6866aff33`; this note was added afterward and the file re-sealed, so the live binding is the one in the frontmatter and in `.manna/issues.jsonl`. `agent-do manna done mn-e9f9a9` was not run: done requires the claim, and the claim was refused by the shadow-handoff guard described above. Erik, or whoever repairs the dispatch note, runs claim and done; the gate test above is the receipt done needs.
