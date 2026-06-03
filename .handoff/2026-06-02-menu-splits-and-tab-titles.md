# Handoff — Holy Ghostty: menu Split Right/Down do nothing + roster tab-title instability

**Date:** 2026-06-02
**Repo:** /Users/erik/Custom-Coding/holy-ghostty (fork of Ghostty)
**Status:** unresolved, two bugs. Prior agent (me) made changes that did NOT fix the splits and only partially addressed titles. Do not trust my prior assumptions — verify empirically.

---

## Ground rules (hard constraints from the user)

- **Do NOT reintroduce scroll throttling.** Scrolling was fixed at the engine level (the bundled `macos/GhosttyKit.xcframework` is a ReleaseFast build; that was the real fix). Any "poll less / debounce refresh / suspend during scroll / cache the title" approach is explicitly rejected — that machinery is what caused these regressions in the first place.
- **Verify, don't assume.** The user (rightly) called out shipping changes without confirming the actual runtime path. Trace how things interoperate end-to-end; add logging and confirm which branch fires before claiming a fix.
- **Build:** `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration ReleaseLocal build` (no zig needed — the engine xcframework is prebuilt). Then install: quit running app, `ditto` the built `Holy Ghostty.app` from DerivedData over `/Applications/Holy Ghostty.app`, and launch with `env -u TMUX -u TMUX_PANE -u TMUX_TMPDIR open` (clearing TMUX avoids a separate discovery-duplicate bug).
- Keep technical identifiers untouched (`Ghostty.Shell`, `GhosttyKit`, module names, `~/.config/ghostty/...`).

---

## Architecture you must hold in your head

- Holy windows are **`HolyWorkspaceWindowController`** (macos/Sources/HolyGhostty/App/HolyWorkspaceWindowController.swift), NOT Ghostty's `TerminalController`. The window is a `HolyWorkspaceWindow: NSWindow` whose `contentViewController` is an `NSHostingController` rendering `HolyWorkspaceRootView` (SwiftUI). `super.init(window:)` links `window.windowController`; there is ALSO a custom `window.holyWorkspaceController` weak prop (line 64).
- Terminal surfaces are `Ghostty.SurfaceView` (AppKit `NSView`) embedded in SwiftUI via `SurfaceWrapper`/`SurfaceRepresentable`. They become first responder via `Ghostty.moveFocus(to:)`.
- "Splits" in Holy are NOT Ghostty surface splits. They are a **pane LAYOUT of sessions**: `HolyPaneLayout` (`.single/.splitRight/.splitDown/.quad`) in `HolyWorkspaceStore` (`@Published var paneLayout`). The view renders `store.normalizedPaneLayout.kind` in `HolyWorkspaceView.swift:180` (`.splitRight` → `HSplitView { paneView(0); paneView(1) }`).

---

## BUG 1 — Menu "Split Right"/"Split Down" do nothing

### What I changed (and it did NOT fix it)
- `MainMenu.xib`: retargeted `splitRight:`/`splitDown:` actions from First Responder (`target="-1"`) to AppDelegate (`target="bbz-4X-AYv"`).
- `AppDelegate.swift:1077-1084`: added `@IBAction splitRight/splitDown` → `menuTargetWorkspace?.workspaceStore.splitPaneRight()/splitPaneDown()`.
- `menuTargetWorkspace` (AppDelegate.swift:1059) = `NSApp.keyWindow?.windowController as? HolyWorkspaceWindowController ?? .preferred ?? .all.first`.
- Also (earlier) `SurfaceView_AppKit.swift:1656/1671` `splitRight/splitDown` have a Holy branch → `holyWorkspaceController?.splitPaneRight()`.

User reports: still nothing happens.

### The split data path (trace these, with file:line)
1. `HolyWorkspaceStore.splitPaneRight()` (HolyWorkspaceStore.swift:186) → `applyPaneLayout(.splitRight, preferredPaneCount: 2)` (line 1420).
2. `applyPaneLayout`: seeds `paneSeedSessionIDs()` (line 1449 — returns selected session + ALL sessions), fills to 2 via `createSession(from: nil)` if needed, sets `paneLayout = HolyPaneLayout(kind:.splitRight, sessionIDs: finalIDs).normalized(...)` (line 1442), sets `selectedSessionID = finalIDs.last`.
3. `HolyPaneLayout.normalized` (HolyModels.swift:1116): **collapses `kind` to `.single` if fewer than 2 unique *available* session IDs** (line 1138-1143). With the user's ~6 sessions this should keep `.splitRight`, so "not enough sessions" is probably NOT the cause — but CONFIRM.
4. View: `HolyWorkspaceView.swift:180` switches on `store.normalizedPaneLayout.kind`.

### What I did NOT verify — DO THIS FIRST (ground truth)
- **Does the left-rail split button work?** `HolyWorkspaceView.swift:293` (`store.splitPaneRight()`) is the SAME call as the menu now uses. **If the rail button also fails to split, the bug is in `applyPaneLayout`/`normalized`/pane-rendering — not menu wiring.** If the rail works but the menu doesn't, the bug is in the menu→AppDelegate→workspace resolution. This single test bisects the whole problem and I never ran it.
- **Is `AppDelegate.splitRight` even being called?** Add `os_log`/`AppDelegate.logger` at the top of `splitRight`/`splitDown` and check Console.app. Confirms whether the xib retarget actually took effect in the compiled nib (xib edits were done via text perl on `MainMenu.xib` — verify the nib recompiled and the connection is live; a malformed action element could silently revert to no-op).
- **Does `menuTargetWorkspace` resolve to the VISIBLE workspace?** Log its identity. When the menu bar is clicked, is `NSApp.keyWindow` the workspace window?
- **Does `paneLayout` actually change and re-render?** Log `store.paneLayout` before/after, and `store.normalizedPaneLayout.kind`. Confirm `@Published` fires and `primaryWorkspaceContent` re-evaluates. Check whether `createSession(from: nil)` inside `applyPaneLayout` returns non-nil (if it returns nil and there's only 1 real session, `finalIDs` stays 1 → normalized to `.single`).

### Hypotheses, ranked (test, don't assume)
1. Pane split fundamentally works from the rail but the menu action isn't firing (xib/nib connection or keyWindow resolution). → log AppDelegate.splitRight.
2. `applyPaneLayout` runs but `normalized()` collapses to `.single` (session-count/availability edge) → splits never render even from the rail.
3. The view re-renders but `paneView(at: 1)` shows nothing usable (second session surface not mounted) → looks like "nothing happened."

---

## BUG 2 — Roster tab titles switch oddly / show garbage (e.g. "Lives")

### Evidence
A session whose real name is "Versova Supply Intelligence" displayed as **"Lives"** — scraped from on-screen chat text ("…the repo **lives** under the Versova-Intelligence-Division org…"). Titles also flip/switch during agent output. User says this "always worked instantly and never failed" before the scroll-fix saga.

### Key finding (verified)
`git diff 4c18965c1 -- HolySession.swift` shows the **title-derivation code is essentially UNCHANGED from the pre-scroll baseline.** So this is NOT a title-code regression. The behavioral change is **refresh cadence**: I restored the live observer (`HolySession.bind()` → `surfaceView.objectWillChange` → `objectWillChange.send()` + direct `refreshDerivedState()`), so `displayTitle` is recomputed on every surface output, and its **content-based inference** re-runs and bounces.

### The title path (trace)
- Roster shows `session.displayTitle` (HolySessionRosterView.swift:328).
- `HolySession.displayTitle` (HolySession.swift ~72): returns `record.launchSpec.resolvedTitle` IF it's not a "default" title (`isDefaultTitle`); otherwise infers from `surfaceView.title` + `Self.inferredRuntime(...)`.
- "Lives" almost certainly comes from `inferredAgentProjectCandidates` regexes (HolySession.swift ~1419 region, e.g. the `\b(?:in|inside|within|for|on)\s+...` / `...itself\b` patterns) matching chat prose.

### What to investigate / likely correct fix
- Why does the "Lives" session fall into inference at all? Check its `record.launchSpec.resolvedTitle` / `isDefaultTitle`. If a session has a real launch title or `objective`, that should be **authoritative and never overridden by screen-content inference**. The likely fix: make configured/objective title win, and only use content inference for genuinely-untitled shells.
- Stability WITHOUT throttling: the title flips because inference reads live, mutable screen text. Fix by making the *derived* title stable (e.g., once a confident runtime/title is inferred, don't let a lower-confidence content scrape replace it; or only treat the OSC/`surfaceView.title` as the source and stop scraping arbitrary prose for project names). Do NOT solve this by slowing the refresh — that's the rejected path.
- Compare against how it behaved at `4c18965c1` in practice: since the code is the same, figure out what *runtime* difference (cadence) makes it visible now, and neutralize the instability at the inference layer, not the refresh layer.

---

## Repo state / context

Uncommitted working-tree changes (this session, NOT committed, NOT pushed):
- macos/Sources/App/macOS/AppDelegate.swift (New tmux + split handlers + menuTargetWorkspace)
- macos/Sources/App/macOS/MainMenu.xib (menu cleanup, rename, split retarget, "New tmux")
- macos/Sources/Features/Command Palette/TerminalCommandPalette.swift (Holy session jump entries)
- macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift (Holy-aware split/font/palette/fullscreen/close branches)
- macos/Sources/HolyGhostty/App/HolyWorkspaceWindowController.swift (splitPaneRight/Down, toggleCommandPalette, fullscreen, closeWorkspaceWindow)
- macos/Sources/HolyGhostty/Workspace/HolyWorkspaceStore.swift (commandPaletteIsShowing)
- macos/Sources/HolyGhostty/Workspace/HolyWorkspaceView.swift (command palette rendering + Holy jump action)

Already committed locally earlier (NOT pushed): roster-icon live-detection fix, user-facing "Holy Ghostty" rename, env-scrub for discovery, backtick tmux prefix.

Note on history: `main` on the remote (`upstream` = github.com/ovachiever/holy-ghostty) still carries an earlier bad commit `c7ca77416`; the local tree is corrected but diverged. Don't push without the user's explicit instruction.

### Recommended first move for the next agent
Add logging to `AppDelegate.splitRight`, `HolyWorkspaceStore.applyPaneLayout` (log paneLayout in/out + finalIDs), and test BOTH the menu item and the rail split button. That one experiment tells you whether Bug 1 is menu-wiring or pane-engine. Don't write a fix until that's known.
