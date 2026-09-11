---
workflow: 2
manna: mn-6160c9
track: mn-9a97cc
source: Erik live report 2026-09-10 15:22; companion defect to mn-ec34cd's dispatch flow
base_commit: b74e8fc7d4fb43f8cfcb48135cf59435920cf42e
scope: '[P1][BOARD][UX] Claim & build leaves the row frozen in next: no feedback until navigation forces a refresh'
inputs:
- Erik live report 2026-09-10 15:22; companion defect to mn-ec34cd's dispatch flow
binding: sha256:a943c742638e9363fe8ce760aa6a12151445fd83704f943f7251ec7fee121a54
---

# Handoff: [P1][BOARD][UX] Claim & build leaves the row frozen in next: no feedback until navigation forces a refresh

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-6160c9
```

## Scope

[P1][BOARD][UX] Claim & build leaves the row frozen in next: no feedback until navigation forces a refresh

## Inputs

- Erik live report 2026-09-10 15:22; companion defect to mn-ec34cd's dispatch flow

## Work order

Erik 2026-09-10: clicking Claim & build dispatches fine, but the item stays in $ manna next looking untouched until he leaves the page or dispatches something else — the board only picks up the claim on its next incidental refresh. Root cause shape: the worker performs the claim AFTER it boots (by design — a failed spawn must leave the board untouched, mn-ec34cd law), so there is nothing synchronous for the view to read; the view also runs no post-action refresh. Fix in two honest layers: (1) OPTIMISTIC CHROME, not optimistic state — the instant dispatch is confirmed, the clicked row shows a transient 'dispatched · worker booting' chip (and the Claim & build affordance disables) WITHOUT moving the row: the row moves only when the real claim lands; (2) CONVERGENCE — after a confirmed dispatch, the board refreshes immediately and then on a short cadence (a few seconds, bounded ~60s) until the claim appears (row moves to $ manna now with the claimant) or the window expires — expiry clears the chip and surfaces 'worker did not claim within 60s' with the session link, because a silent revert is how this bug feels today. Never mark in_progress locally before the board says so (the board is the only truth; optimistic STATE would recreate the paper-open we just outlawed). Same treatment for the inspector's other mutation verbs if any share the fire-and-forget shape. Tests: chip appears on dispatch and clears on claim-seen; convergence poll stops on claim or expiry; a spawn failure clears the chip and reports; the row never moves without board evidence. Acceptance: Erik clicks Claim & build and within seconds watches the row wear the chip, then slide to $ manna now on its own.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-6160c9`.
4. Commit with `Manna: mn-6160c9` and run `agent-do manna done mn-6160c9` only after the work is verified.

## Build receipt, 2026-09-10

Implementation is complete and compiled in commit `c681f6a468251b3b262b4023e020d546de6cb5ba`. Erik explicitly directed closure on 2026-09-10: completed work closes without a human-verification gate; any subsequently found defect gets a new ticket. This supersedes the original live acceptance requirement and the earlier instruction to keep this item `in_progress`.

- Claimed with `agent-do manna claim mn-6160c9` as `codex-01a08d0beeb473f1`. No claim was stolen.
- Before editing, verified the complete-content Manna binding against the expected `sha256:a3547a9c5d6d7342e7b34e7ce4296d74be841bfbf3394ccba5a13134e3bd80fb`, handoff frontmatter, and `agent-do manna state --json`. Manna normalizes its one frontmatter `binding:` line to `binding: ''` before hashing. The raw file hash is not the binding.
- Read the applicable parent `AGENTS.md`, repo README, Xcode scheme/project, and Build and Validation work order. There is no project-local AGENTS.md or CLAUDE.md.
- Set coord focus and claimed only the four Swift files below plus this handoff. Preserved foreign documentation edits, terminal-mouse lane changes, and other Manna rows.
- Baseline: `f1931e5ba`. Validation checkout: `/Users/erik/Custom-Coding/holy-ghostty-fix-mn-6160c9-board-dispatch`, created with `agent-do git worktree add fix/mn-6160c9-board-dispatch`. Existing ignored GhosttyKit and generated resources were copied into that checkout; no app was installed or launched. Manna/coord operations stayed in the primary checkout.

### Implemented behavior

1. A confirmed successful launch records the real Holy session UUID in feedback scoped by host, repository, and item. The row displays `dispatched · worker booting`; Claim & build is disabled while waiting. Neither the item status nor its section is changed locally.
2. The originating board refreshes immediately and every three seconds. Reads coalesce while a CLI read is in flight. A canonical `in_progress` item with a claimant, or a canonical completed item, clears the feedback and cancels convergence. Section membership continues to come from Manna's payload.
3. An independent 60-second deadline stops convergence even if a read is slow or failing. Expiry removes the waiting state and displays `Worker did not claim within 60s.` with an `open worker session` action. The link selects the captured session through the existing workspace focus path. Navigating to another board cannot display or apply the originating board's feedback there.
4. Launch/refusal errors create no waiting feedback and continue to report the error without claiming anything. Inspector mutation verbs already await their CLI result and request a refresh. Their required forced refresh is now queued once when another read is in flight, so the earlier read cannot swallow it. Periodic convergence ticks never queue a read beyond their window.

Changed files and SHA-256 of the verified build inputs (byte-identical in primary and validation checkout):

```text
4eb58e821432a57858eb7a8b38c01e80c30cca525a6ccba74ffba752717d8772  macos/Sources/HolyGhostty/Board/HolyMannaBoardStore.swift
a84944a39192d4aa872e18a85b04a4abd33204aed8d1e9da6420f582ef5fd20f  macos/Sources/HolyGhostty/Board/HolyMannaBoardView.swift
da2a270d59b0fd555c9877eb3e66c13cfa094227afcf130f850e51c7e9a91a3c  macos/Sources/HolyGhostty/Workspace/HolyWorkspaceView.swift
b8392252bd4d77b6d81b9bf98784c2782aa6179e93a04eca04ac1f7150dce635  macos/Tests/HolyGhostty/HolyMannaBoardActionsTests.swift
```

### Focused validation actually performed

From the primary checkout:

```bash
swiftlint lint --strict --config macos/.swiftlint.yml macos/Sources/HolyGhostty/Board/HolyMannaBoardStore.swift macos/Sources/HolyGhostty/Board/HolyMannaBoardView.swift macos/Sources/HolyGhostty/Workspace/HolyWorkspaceView.swift macos/Tests/HolyGhostty/HolyMannaBoardActionsTests.swift
git diff --check -- macos/Sources/HolyGhostty/Board/HolyMannaBoardStore.swift macos/Sources/HolyGhostty/Board/HolyMannaBoardView.swift macos/Sources/HolyGhostty/Workspace/HolyWorkspaceView.swift macos/Tests/HolyGhostty/HolyMannaBoardActionsTests.swift
```

Both exited 0. SwiftLint reported 0 violations in four files.

From the isolated validation checkout:

```bash
xcodebuild build-for-testing -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug -destination 'platform=macOS' -derivedDataPath .dev/mn-6160c9/DerivedData -only-testing:GhosttyTests/HolyMannaBoardActionsTests -only-testing:GhosttyTests/HolyMannaBoardTests -only-testing:GhosttyTests/HolyMannaBoardPresentationTests CODE_SIGNING_ALLOWED=NO
```

Exited 0 with `** TEST BUILD SUCCEEDED **`. The app and test bundle compiled. The log has 0 error lines and 984 warning lines, none referencing the four changed files. This was a Debug test build using the existing core payload, not a ReleaseLocal production-core provenance or installation acceptance.

Added six regression tests for pending feedback and canonical movement, expiry and session linkage, a slow in-flight read at the deadline, failed reads, host/board navigation, and a forced refresh during an existing read. Extended the existing failed-spawn test to assert no feedback remains. The fixture's `now` and `next` arrays now reflect its canonical claim state.

**Executed test cases: 0.** All app-hosted tests were compiled only. No app launch, install, screenshot, live worker/session spawn, push, or pull request occurred.

Build log and source hashes are under `.dev/mn-6160c9/` in the primary checkout. The original isolated build log and test artifacts are under the same relative directory in the validation checkout. The ignored receipts are supplementary; this tracked handoff contains the commands, results, and closure direction.

### Closure direction, 2026-09-10

Erik: "close it, we do not human verify things, we close when the work is done and open a new ticket if needed".

The implementation and build-only validation satisfy closure under that direction. Remove the `mn-6160c9-live-acceptance` coord dependency and close through the canonical `agent-do manna done mn-6160c9` command. No human verification or additional launch is required for this item's closure. Any concrete defect discovered later belongs in a new ticket; none is invented here.

The evidence remains unchanged: SwiftLint and build-for-testing passed, app-hosted tests were compiled but not executed, and no live UI verification occurred. This closure does not represent those checks as performed. No source code changed during closure, so build and lint were not repeated.

Lessons logged: 3 (new) | Decisions logged: 0 (new). Lesson IDs: `les-ec3da3`, `les-ccbdf7`, `les-674c50`.
