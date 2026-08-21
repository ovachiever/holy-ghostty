---
workflow: 2
manna: mn-0368e0
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P0][APP] Clear (detach-all) terminates the app within 80ms — flight-recorder hunt'
inputs: []
binding: sha256:f7c0a30b35e908086a14d8e39382b1ece212ce23a1a763dd8e72be76b50632f7
---

# Handoff: [P0][APP] Clear (detach-all) terminates the app within 80ms — flight-recorder hunt

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-0368e0
```

## Scope

[P0][APP] Clear (detach-all) terminates the app within 80ms — flight-recorder hunt

## Inputs

- None declared.

## Work order

Erik 2026-08-12: pressing the roster Clear closes Holy entirely. RECORDER RECEIPTS (Studio, 05:34:00): "lifecycle: detachAllSessions (Clear) archiving 16 sessions" logged by pid 62265 at .223; XPC connections invalidated (process exiting) at .302 — 80ms later; NO closeWorkspaceWindow log, NO windowWillClose log, NO crash report (.ips absent in user and system DiagnosticReports) → a clean NSApp.terminate that skips window delegates. Ruled out: core quit-timer (GHOSTTY_ACTION_QUIT_TIMER is logged "known but unimplemented" on macOS); crash. Prime suspects: GHOSTTY_ACTION_QUIT from core reaching Ghostty.App.quit → NSApplication.terminate (instrumented 2026-08-12: "core requested QUIT"), or an AppKit last-window/termination path (applicationShouldTerminate now logs window counts). NEXT: press Clear on an instrumented build; the log names the door; then gate it — an empty Holy workspace is a valid resting state and must never satisfy any "no terminals left → quit" rule. Regression window: Clear reportedly worked before the controller-retention fix (b5825fac0) — the resurrected controller may have re-enabled a quit path a dangling-nil cast previously starved.

LEDGER 2026-08-12 06:01 (Erik): Clear no longer quits the app — "it's fixed." HONEST STATE: nothing since the 05:34 death could have fixed it (subsequent commits added only instrumentation), so the bug is INTERMITTENT or was environmental. Timeline forensics: the 05:40:30 "death" was the INSTALLER's pkill mid-swap (verified: swap 05:40:40) — a red herring; only the 05:34:00 death (80ms post-Clear, clean terminate, no crash report, both window doors silent) remains unexplained. All four doors stay instrumented (detachAll, restore-sheet clear, closeWorkspaceWindow, windowWillClose, core-QUIT, applicationShouldTerminate); if it ever recurs, one log read names the path. Downgraded from P0; keep open as an armed trap, close after a quiet week.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-0368e0`.
4. Commit with `Manna: mn-0368e0` and run `agent-do manna done mn-0368e0` only after the work is verified.
