---
workflow: 2
manna: mn-e9f9a9
track: mn-eb7a80
source: null
base_commit: e3caf1817d78c79b59f57e30fd4df882c7b5a745
scope: '[P0][SECURITY][AUTOMATION] holy-ghostty://spawn executes attacker-supplied commands with no gate — release blocker'
inputs: []
binding: sha256:201f595f45517c8f80525cc90bdf1477e0649c13d33527ee4f12044a36c1ba32
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
