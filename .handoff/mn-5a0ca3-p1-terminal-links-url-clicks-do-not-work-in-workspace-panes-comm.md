---
workflow: 2
manna: mn-5a0ca3
track: mn-eb7a80
source: null
base_commit: d9f5b0d9bae60dbb42f390715887f4ab4cd31f56
scope: '[P1][TERMINAL][LINKS] URL clicks do not work in workspace panes — command-click or plain — the mn-9b5b5b field check failed'
inputs: []
binding: sha256:5912c4d848437dbd9d19470151c53ddf9a2ff659366f6ac55dd98aec0f327acd
---

# Handoff: [P1][TERMINAL][LINKS] URL clicks do not work in workspace panes — command-click or plain — the mn-9b5b5b field check failed

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-5a0ca3
```

## Scope

[P1][TERMINAL][LINKS] URL clicks do not work in workspace panes — command-click or plain — the mn-9b5b5b field check failed

## Inputs

- None declared.

## Work order

Erik live 2026-09-20: clicking URLs in Holy panes does nothing, with or without command. Context and receipts: mn-9b5b5b (link detection dead in workspace surfaces) was patched at 4b8b079e0 and closed 2026-09-11, but Erik's cmd-hover/cmd-click URL field check from that item's acceptance was never reported passing — this is that check failing, filed fresh per the no-reopen doctrine. Contrast that matters for the bisect: mn- id cmd-click (the HolyMannaLink machinery, mn-5a26f9) is a SEPARATE macOS-side path — establish immediately whether mn- id clicks still work today; if yes, the break is isolated to the core URL link path. Diagnostic ladder from the mn-9b5b5b handoff, still valid: (1) bare surface first — open a QuickTerminal (no Holy workspace wrapper), print a URL, cmd-hover: underline+pointer there but not in workspace panes → the defect is Holy's hosting/event routing; dead there too → core/config territory. (2) Split the symptom: does cmd-hover show the underline and the hover-URL caption (hoverUrl / displayedHoverURL in SurfaceView) but click not open — open-action path — or is there no hover response at all — detection/tracking delivery. (3) Suspect set from the intervening commits, to bisect not assume: the modifier-forwarding changes (973fc5355 then 61da5f002 frame-overlap check) touched flagsChanged delivery; the mn-5a26f9/mn-4be59b work added and then reverted (b5c7f1763, 6d6c2d2b1, 9699989dd) mouse-path code in SurfaceView_AppKit — verify the revert left the URL hover/click plumbing whole; and the mn-4be59b hover-underline removal commit (daee37c57) edited the same overlay region that displays hoverUrl. Fix restores stock behavior: cmd-hover underlines with pointer and caption, cmd-click opens in the browser on the viewing Mac, plain click still selects. Regression test at whatever layer the bisect lands, executed not compiled. Acceptance: Erik cmd-clicks a printed URL in a workspace pane and the browser opens; the QuickTerminal control case also passes.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-5a0ca3`.
4. Commit with `Manna: mn-5a0ca3` and run `agent-do manna done mn-5a0ca3` only after the work is verified.

## Continuation receipts: 2026-09-21 03:15 UTC

**Outcome: implementation candidate committed; required acceptance remains unverified.**
The item remains in progress. Do not mark it done on these source-only receipts.

### Authority and ownership

- Initial claim succeeded for `codex-01a0c1e47ec67023`. The normalized document binding, frontmatter binding, canonical Manna digest, and requested digest all matched `sha256:796e03dd2803bddf419372ac34448080817c4c46897b2f971a3b1b43cfb55b71` before editing.
- Canonical Manna's updated description supersedes the older suspect list above: Manna-ID Command-click works, and the URL failure predates the recent mouse/overlay changes. The earlier mn-9b5b5b implementation is not accepted evidence that URL clicks worked.
- Coordination focus and exact path claims preceded edits. Implementation is isolated in `/Users/erik/Custom-Coding/holy-ghostty-codex-mn-5a0ca3`, branch `fix/mn-5a0ca3-terminal-url-clicks`, based on `5d9ae305c`. Manna and Coord operations remain in the primary checkout.
- Candidate commit: `3c360a6a7f7aa7fd6e6de3ac76b4b9ffee3f53df`, `fix(terminal): allow command URL clicks during mouse capture`, with exact trailer `Manna: mn-5a0ca3`. This candidate has not been integrated into the primary branch, pushed, or installed.

### Evidence and candidate behavior

1. Source inspection shows Holy enables tmux mouse capture in `HolyTmuxCommandBuilder.swift`. Read-only `tmux -L holy show-options -gv mouse` returned `on`; existing attached clients reported `xterm-ghostty`. No session was created or altered.
2. The core's keyboard and pointer hover paths previously skipped URL detection whenever the terminal requested mouse reports unless Shift escaped capture. Command alone did not escape that gate. That source-observed incompatibility explains a plausible workspace-versus-bare-surface discriminator, but the QuickTerminal comparison and actual event delivery have not been observed in this lane.
3. The candidate centralizes capture eligibility in the existing core link matcher. macOS Command permits normal regex URL and OSC 8 detection during capture. Ordinary input and the existing Shift capture preference remain in effect; disabling mouse reporting is also respected by link detection.
4. A matched Command-link press during capture stays owned by the terminal through release. Dragging, leaving the surface, releasing Command, screen changes, or changed destinations cancel opening without sending an unmatched press/release to tmux. The existing `open_url` action and local macOS opener remain the destination path. No independent Swift URL parser or tmux configuration workaround was added.
5. Modifier changes invalidate the hover-cell cache. Regression fixtures use the actual core matcher, terminal grid, and VT mouse/OSC 8 input, with no PTY or app creation. Existing renderer/Manna and selection cases are retained in the focused workflow selection.

### Validation commands and actual results

All local compilation attempts used the existing pinned executable:

```text
/Users/erik/Custom-Coding/holy-ghostty/.dev/toolchains/zig-aarch64-macos-0.15.2/zig
```

Its `version` result was `0.15.2`. Both PATH `zig` and `/opt/homebrew/opt/zig@0.15/bin/zig` actually reported `0.16.0`, so neither was used for the candidate checks.

Executed source checks passed:

```bash
zig fmt --check src/Surface.zig src/surface_mouse.zig
zig ast-check src/Surface.zig
zig ast-check src/surface_mouse.zig
git diff --check
```

The workflow YAML parsed successfully with the existing agent-do Python environment. Its shell command contains all intended focused filters and both no-app emission flags. AST checks validate syntax, not full compilation or runtime behavior.

The focused canonical test command was attempted:

```bash
zig build test \
  -Dtest-filter='Surface: URL' \
  -Dtest-filter='Surface: selection' \
  -Dtest-filter='Surface: rectangle selection' \
  -Dtest-filter=surface_mouse \
  -Dtest-filter=renderer.link \
  -Dtest-filter=holy-manna-highlight \
  -Demit-macos-app=false -Demit-xcframework=false --summary all
```

Result: exit **2**, before project/test compilation. Zig's build runner failed to link libSystem symbols including `_getenv`, `_getcwd`, `_sigaction`, and `_waitpid`. The unmodified baseline failed at the same stage. Selecting the already installed macOS 15.4 SDK with `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk` also failed there.

The canonical ReleaseFast core command was attempted with `HOLY_GHOSTTY_ZIG` set to the pinned executable:

```bash
scripts/build-holy-ghostty-core.sh build
```

Result: exit **1**, same build-runner link failure. The wrapper reported its supported `Build Holy macOS core` CI artifact path. No receipt was fabricated and no previous framework was substituted for the changed source.

**Tests compiled: 0. Tests executed: 0. App-hosted test builds: not attempted**, because no matching candidate core was produced. No app launches, installations, screenshots, live session spawning, pushes, or pull requests occurred.

Raw receipts are in `.dev/mn-5a0ca3/` in the isolated worktree and copied to the primary checkout: `baseline-tests.log`, `baseline-tests-sdk15.log`, `focused-tests.log`, `core-build.log`, `format-check.log`, `surface-ast-check.log`, `mouse-ast-check.log`, and `diff-check.log`.

### Required coordinated acceptance

Coord dependency: `mn-5a0ca3-core-and-live-acceptance`. Publishing authority remains with the coordinator/user; this lane has no push authorization.
Run the validation, artifact import, and candidate installation commands below from the isolated candidate worktree so the source fingerprint matches. Keep Manna lifecycle and seal operations in the primary checkout.

1. Run the focused core tests above on the exact candidate with a working canonical Zig 0.15.2 toolchain. The updated `Build Holy macOS core` workflow selects these tests. Record actual nonzero executed counts and repair any failures before producing the receipt-bound ReleaseFast core artifact.
2. Import the matching artifact using `scripts/build-holy-ghostty-core.sh import <archive>` and verify it with `scripts/build-holy-ghostty-core.sh verify`. Build the app and the two focused app-hosted suites against that core. Keep outputs separate from the installer's `macos/build`:

   ```bash
   xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty \
     -configuration Debug -destination 'platform=macOS' \
     -derivedDataPath .dev/mn-5a0ca3/DerivedData \
     SYMROOT="$PWD/.dev/mn-5a0ca3/build" \
     -only-testing:GhosttyTests/HolyWorkspaceTerminalMouseTests \
     -only-testing:GhosttyTests/HolyMannaBoardLinkTests \
     build-for-testing CODE_SIGNING_ALLOWED=NO
   ```

3. Only in the coordinated launch window, execute those exact suites with `test-without-building` and record the executed counts and xcresult. A successful build-for-testing is not execution. Use the supported install path for the candidate before field acceptance.
4. Erik's live acceptance: a printed URL in a workspace pane gets Command-hover underline, pointer, and caption; Command-click opens the browser on the viewing Mac; ordinary click/drag still selects; the QuickTerminal control passes; gold Manna-ID Command-click still navigates correctly. Also check a cancelled Command-link drag and an OSC 8 link. Record the actual observations. If the source hypothesis does not explain the installed behavior, instrument the delivery/detection/action boundary and continue the prescribed bisect.
5. Integrate the verified candidate locally, attach all receipts, reseal this handoff, and mark done only after the required acceptance passes.

Lessons logged: 3 (new) | Decisions logged: 1 (new).
