---
workflow: 2
manna: mn-e6e3d0
track: mn-eb7a80
source: security review 2026-09-24; 962f13ad2; .handoff/mn-e9f9a9 report
base_commit: 962f13ad23c8f022a2b5d44d29de8085c36339de
scope: '[P1][SECURITY] Spawn URL gate: allowlist tmux session and socket names and prove every non-command field is inert at both sinks'
inputs:
- security review 2026-09-24; 962f13ad2; .handoff/mn-e9f9a9 report
binding: sha256:16671d93969dad8e934d6a9fe8ec1fadfefc25e74663badb84b7676ebe45afd4
---

# Handoff: [P1][SECURITY] Spawn URL gate: allowlist tmux session and socket names and prove every non-command field is inert at both sinks

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-e6e3d0
```

## Scope

[P1][SECURITY] Spawn URL gate: allowlist tmux session and socket names and prove every non-command field is inert at both sinks

## Inputs

- security review 2026-09-24; 962f13ad2; .handoff/mn-e9f9a9 report

## Work order

Follow-up to 962f13ad2 (mn-e9f9a9, gate suites 40 of 40 on 09-24 and re-run 40 of 40 on 09-26). Automated review flagged that tmuxSession, tmuxSocket, workingDirectory, title, and objective are not screened for shell metacharacters. Sink receipts: local launches pass workingDirectory as argv (HolyTmuxCommandBuilder.swift:136) and the SSH transport wraps a script whose every argument is single-quoted by shellCommand mapping posixQuote (HolyTmuxCommandBuilder.swift:421-425, wrapped at :572), so injection is inert at the sink today; the gate already rejects control, newline, and bidi scalars in any value. Deliver, as defense in depth: tmuxSession and tmuxSocket restricted to ^[A-Za-z0-9._-]+$ (tmux also parses : and . as target separators, so reject those too in session names); tests that put each metacharacter class into each non-command field on local and ssh transports and assert the built command carries them only inside single quotes or the gate refuses; the confirmation sheet and audit line already show every field, keep that covered by a test. Own macos/Sources/HolyGhostty/Automation/HolyAutomationURLGate.swift and macos/Tests/HolyGhostty/HolyAutomationURLGateTests.swift only.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-e6e3d0`.
4. Commit with `Manna: mn-e6e3d0` and run `agent-do manna done mn-e6e3d0` only after the work is verified.

## Report

Lane worker, 2026-09-26, worktree branch `worktree-agent-a404ef77ae9c5ab0c`, based on 962f13ad2 (the recorded base_commit). Code commit c3b5216c9 carries `Manna: mn-e6e3d0`. No board commands were run, and the seal was not re-run after this report was appended.

### What changed

- `macos/Sources/HolyGhostty/Automation/HolyAutomationURLGate.swift`. `semanticProblem` gains three checks, and `isAllowedTmuxSessionName` and `isAllowedTmuxSocketName` become static and test-reachable:
  - `tmuxSession` must match `^[A-Za-z0-9_-]+$`. ASCII only, no `:` or `.`, and none of tmux's `$ @ %` id sigils or its `= ~ ^` and glob match modifiers.
  - `tmuxSocket` must match `^[A-Za-z0-9._-]+$` and must not be only dots, so `.` and `..` cannot name the socket directory itself. This replaces the old check that only refused a `/`.
  - A `workingDirectory` ending in `;` is refused. I probed tmux 3.7c on a throwaway `-L e6e3d0probe` socket: `set-option -q -t 's1;' @x v` failed with "too few arguments", and `has-session -t 'nosuch;'` looked up `nosuch`. So tmux cuts its argv at any argument ending in an unescaped `;`, and `-c <dir>` is followed by the pane command.
- `macos/Tests/HolyGhostty/HolyAutomationURLGateTests.swift` gains a new suite, `HolyAutomationNonCommandFieldSinkTests`, plus a test-side `HolyShellLexer`:
  - **The lexer.** For each script it builds a skeleton: active shell syntax is kept and each run of quoted literal text becomes one `◊`. Double-quoted `$`, backtick and `\` stay active, and quoting restarts inside `$(`. It decodes words, groups them into simple commands, and finds the nested scripts a shell hands to another shell: `sh`/`zsh`/`bash` `-c`/`-lc <script>`, the last argument of a tmux `new-session`, and ssh's remote command after `-- <destination>`.
  - `metacharacterInANonCommandFieldIsRefusedOrOnlyQuoted(field:metacharacter:)` runs 6 fields × 31 classes = 186 cases. The fields are tmuxSession, tmuxSocket, workingDirectory, title, objective and host. The classes are `;`, `&`, `&&`, `|`, `$()`, backticks, `${}`/`$VAR`, `$(())`, `>`, `<`, subshell, brace group, glob, `!!`, ` #`, tmux `#{}#()`, single quote, double quote, backslash, space, `~`, `:`, `.`, `$0@1%2`, leading `=`, leading `-`, trailing `;`, trailing `\;`, `=%41@`, `/../`, and non-ASCII. Each case runs over local and ssh (host over ssh only). Every case must either:
    - get the verdict an independently stated rule demands (refused with `.malformed` exactly when that rule says refuse), or
    - build a command through `HolyTmuxCommandBuilder.surfaceConfiguration` whose skeleton matches the benign build of the same URL at every nested shell layer, with the hostile value present as literal word text.
    Locally, the working directory must arrive as `config.workingDirectory` (argv); over ssh that field must be nil.
  - `differentialCheckCatchesAValueSplicedOutsideItsQuotes` takes a real local builder command and splices `Benign;id`, then `"$(id)"`, outside the quotes in the nested script. The check must report a difference at `local command > 0`, and must report none for the untouched script.
  - `lexerSeparatesQuotedDataFromSyntax` covers the lexer's own rules.
  - Four allowlist tests: session names admitted (5 cases) and refused (14), socket names admitted (5) and refused (10).
  - `sheetAndAuditLineShowEveryNonCommandFieldVerbatim` sends a URL that puts metacharacters in every non-command field. The sheet's summary lines and alert text must show each value verbatim. For the prompted, confirmed and cancelled lines, the audit URL must decode back to every field.

### Where the allowlist sits in the gate's order of checks

The order from mn-e9f9a9 is unchanged up to the last semantic check:

1. Board route.
2. Non-spawn routes are unsupported.
3. `allowSpawnURL` off means refused.
4. Structural checks: userinfo, port, fragment, extra path.
5. Percent-encoded UTF-8.
6. Unknown or duplicate parameter.
7. Control, newline and bidi scalars in any value.
8. Command-bearing fields need `allowSpawnURLCommands`, and `command` plus `bootstrapCommand` is refused.
9. `semanticProblem`: runtime, host, transport, createIfMissing, then the `workingDirectory` root check, then (new) `workingDirectory` ending in `;`, then (new) the tmuxSession allowlist, then (new) the tmuxSocket allowlist.
10. Only then does the parser build the spec, and the result is still only `.confirmSpawn`.

The shipped default still refuses at step 3, before anything is parsed. Values are checked after whitespace trimming, the same trim the parser applies. Refusals are logged with `printable(...)`, so they never echo control characters.

### Test receipts

From `macos/`, serially:

`xcodebuild test -scheme Ghostty -destination 'platform=macOS' -parallel-testing-enabled NO -skip-testing:GhosttyUITests -only-testing:GhosttyTests/HolyAutomationURLGateTests -only-testing:GhosttyTests/HolyAutomationURLEntryPointTests -only-testing:GhosttyTests/HolyAutomationNonCommandFieldSinkTests -resultBundlePath /tmp/mn-e6e3d0-4.xcresult`

Counts were read with `xcrun xcresulttool get test-results summary` and `... tests`:

- **Final run, `/tmp/mn-e6e3d0-4.xcresult`:** result Passed. totalTestCount 29, passedTests 29, failedTests 0, skippedTests 0, expectedFailures 0. 391 argument-level runs passed, 0 failed.
- **By suite:**

| Suite | Functions | Runs | Failed |
|---|---|---|---|
| HolyAutomationURLGateTests | 17 | 92 | 0 |
| HolyAutomationURLEntryPointTests | 4 | 76 | 0 |
| HolyAutomationNonCommandFieldSinkTests (new) | 8 | 223 | 0 |

  The 40 recorded for mn-e9f9a9 were these 21 original functions plus the 19 HolyMannaBoardLinkTests functions that bundle also ran.
- **Earlier runs:**
  - `/tmp/mn-e6e3d0-1.xcresult` did not build: the worktree lacked `zig-out/share`. I linked it temporarily and removed the link before committing.
  - `-2` passed with 28 functions, before the teeth test existed.
  - `-3` passed with 29 functions.
- **Mutation run, `/tmp/mn-e6e3d0-mutant.xcresult`:** I cut the session allowlist to `!name.isEmpty` and ran the new suite: result Failed, 43 argument runs failed, in the matrix and the refused-names test. The gate file was then restored byte for byte, and run 4 is on the restored code. Even with the mutant gate, no structural-difference failure appeared. That agrees with the work order: the builder's quoting alone already makes these fields inert, and the allowlist is defense in depth.

### Risks and follow-ups (none fixed here; all outside this item's two files)

- **tmux prefix matching (probed).** On tmux 3.7c, `has-session -t lane` succeeded when only `lane-2` existed, and `-t '=lane'` failed. The builder passes bare session names to `has-session` and `attach` (HolyTmuxCommandBuilder.swift, `localLaunchScript`). So a spawn URL, or any launch spec, naming `lane` attaches to an existing `lane-2` instead of creating `lane`. `HolyTmuxModelLabelUpdateCommand` already uses the `=name:` form. A builder follow-up should target `=name` in `has-session`, `attach` and the `set-option -t` calls.
- **Trailing `;` in title or objective.** These still pass, because they are the last tmux argument of their `set-option`. tmux strips the `;` and runs an empty second command, so the stored value loses its final `;`. This is cosmetic, not injection.
- **What the matrix does not cover.** It checks the command that `surfaceConfiguration` builds. It does not cover `detachedCreateCommand` (restore only; spawn URLs never reach it) or the SSH control-lane commands that other features build later from a persisted spec.
- **The proof is only as good as the test lexer.** It is written for the subset the builders emit. The teeth test and the lexer test pin its key behaviors, but a future builder construct it does not model (heredocs, `$'...'`, `eval`) would need a lexer update, or the matrix could pass without proving anything.
- **Existing sessions with other names.** They are unaffected. Only URL-supplied names are restricted. `scripts/holy-spawn-session.sh` names such as `temp` and `holy` still pass.
