# Plan / Handoff — Session notes (tags) + resizable/collapsible roster sidebar

**Date:** 2026-06-03
**Repo:** /Users/erik/Custom-Coding/holy-ghostty (fork of Ghostty)
**Type:** feature plan for another agent. Two independent features; ship as two commits.

## Build / run / verify
- Build: `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration ReleaseLocal build` (engine xcframework is prebuilt ReleaseFast — no zig).
- Install + launch: quit running app, `ditto` the built `Holy Ghostty.app` from `~/Library/Developer/Xcode/DerivedData/Ghostty-*/Build/Products/ReleaseLocal/` over `/Applications/Holy Ghostty.app`, then `env -u TMUX -u TMUX_PANE -u TMUX_TMPDIR open "/Applications/Holy Ghostty.app"`. If the old instance won't quit, `kill -9` it first (it can hold a deleted bundle and `open` will just re-activate it).
- This is UI work — load the **artful-ux**, **artful-colors**, **artful-typography** skills and verify visually (screenshot → evaluate hierarchy/spacing/color → adjust). The user explicitly wants the note "artistically done well, not as an afterthought."

## House constraints
- Keep session identity (name/runtime) from launch intent + stable sources; do not scrape live screen content. (Recent bug history — see other `.handoff/` docs.)
- No commits/pushes without owner say-so. The remote `main` is diverged (carries a stale commit); local has a large uncommitted batch already.

---

# FEATURE 1 — Per-session notes ("a few words" tag), shown in orange under the name

### Goal (user's words)
With dozens of sessions (e.g. four all named "Agent Do"), right-click a session → **"Add Session Note"** → type e.g. `contracts work` → it shows in **orange**, small, on a second line under the session name. Persists. Editable/clearable.

### 1. Persistence (no DB migration needed)
- Add `var note: String?` to **`HolySessionLaunchSpec`** (macos/Sources/HolyGhostty/Domain/HolyModels.swift:942). It's `Codable` and persisted whole as the `launch_spec_json` column (sessions table, HolyDatabaseMigrator.swift:72) — a new optional Codable field decodes to `nil` for existing rows, so **no schema migration**. Put it near `objective` (line 945). Confirm `Equatable`/`Codable` synthesis still holds (it will).
  - Alternative (heavier, not recommended now): the unused `annotations` table (HolyDatabaseMigrator.swift:157) exists but has NO Swift read/write layer; building one is more work and unnecessary for a single free-text note. Mention but don't pursue unless multi-note/history is wanted later.

### 2. Model API (mirror the existing `rename` path)
In `HolySession` (HolySession.swift):
- Add `var note: String? { record.launchSpec.note?.holyTrimmed.nilIfEmpty }`.
- Add `func setNote(_ note: String?)` mirroring `rename(to:)` (line 377): set `record.launchSpec.note = note?.holyTrimmed.nilIfEmpty`, `markUpdated()`, `objectWillChange.send()`.
- IMPORTANT: ensure `applyDiscoveredLaunchMetadata` (line 383) NEVER overwrites `note` from discovery — note is user-authored only.

In `HolyWorkspaceStore`:
- Add `func setNote(_ session: HolySession, to note: String?)` mirroring `rename(_:to:)` — call `session.setNote(note)` then persist (the store's persist path; rename is the template).

### 3. UI — entry point (the "..." menu)
In `HolyRosterRow` (HolySessionRosterView.swift:491 menu) add, near Rename:
- `Button("Add Session Note…")` (or "Edit Note" when one exists) → triggers an inline editor. Reuse the existing inline-rename pattern: there's `@State isRenaming`/`renameText`/`commitRename` (line ~468-640). Add a parallel `@State private var isEditingNote` / `noteDraft` and an `onSetNote: (String?) -> Void` closure on the row (wired by the parent at HolySessionRosterView.swift:56 to `store.setNote(session, to:)`, like `onRename` at line 71).
- The editor: a compact `TextField` ("Add a note…") that commits on Enter / blur, Esc cancels, empty clears the note. Keep it consistent with the rename field's styling.
- Optional nicety: also expose it in the surface right-click context menu (SurfaceView_AppKit makeContextMenu) — but the roster "..." is the primary ask.

### 4. UI — rendering the note (the "artistic" part)
The roster row renders `displayLine` (HolySessionRosterView.swift ~line 482 area, inside `body`'s HStack). Today it shows the name (and pane label / project). Change the name area from a single line to a 2-line VStack:
- Line 1: session name (unchanged — `primaryTitle`, `HolySessionRosterOrdering.primaryTitle`).
- Line 2 (only if `session.note` non-empty): the note, in **orange/amber**, ~10–11pt, medium weight, single line, `.truncationMode(.tail)`, tight leading under the name (≈2pt spacing), secondary opacity so it reads as a tag not a title.
- Color: add an accent to `HolyGhosttyTheme` (macos/Sources/HolyGhostty/DesignSystem/HolyGhosttyDesignSystem.swift) — e.g. `HolyGhosttyTheme.noteAccent` ~ a warm amber/orange (check artful-colors for a value that sits well on the dark bg and is distinct from the existing `halo`/`danger`/`workingBlue`). Don't hardcode `.orange`.
- Respect `compact` mode (the roster has a compact variant): in compact, either hide the note or show a tiny dot/abbreviation — decide via artful-ux (don't crowd).
- Verify selected-row and unselected-row contrast both read well.

### 5. Edge cases / acceptance
- Add, edit, clear (empty → nil) a note; survives app restart (persisted in launch_spec_json).
- Note never overwritten by discovery/refresh; never affects sorting/grouping/runtime.
- Multiple same-named sessions are now distinguishable by note (the core use case).
- Long note truncates cleanly; no layout shift of the status orb / "..." button.

---

# FEATURE 2 — Resizable + collapsible roster sidebar

### What ALREADY exists (verify first — don't rebuild)
`HolyWorkspaceView.swift`:
- `HolyWorkspaceLayout.rosterMinWidth=180`, `rosterDefaultWidth=272`, `rosterMaxWidth=560` (lines 8-10).
- `@AppStorage("holy.workspace.rosterWidth.v3")` persists the width (line 55), with `rosterDragStartWidth` (56) and a custom drag handle (lines 145-154) + `clampedRosterWidth(for:)` (125). So **drag-to-resize larger/smaller already works.** First step: confirm it works and whether the handle is discoverable enough (it's a thin capsule that brightens on hover, line 24-26). If the user couldn't find it, improving the handle's hit target / affordance may be most of the "resize" ask.

### What's MISSING — collapse/expand
1. **Collapsed state**: add `@AppStorage("holy.workspace.rosterCollapsed.v1") private var rosterCollapsed = false`. When true, render the roster at width 0 (or a thin ~28pt rail) and give the main pane the space. Animate the transition (`.animation(.easeInOut(duration: 0.18), value: rosterCollapsed)` on the width).
2. **Toggle control(s)** — make expand/collapse "easy at will":
   - A button in the roster header (near the "New | Clear | Sync | Hosts" toolbar) with a sidebar-toggle SF Symbol (`sidebar.left` / `sidebar.leading`).
   - A keyboard shortcut — `⌘⌥S` or `⌘\` (verify no conflict with existing Holy/Ghostty binds; the menu work added items — check MainMenu.xib and HolyWorkspaceWindowController.handleWorkspaceKeyEquivalent). Consider adding a **View menu item** "Toggle Sidebar" wired through AppDelegate→keyWindow workspace (same pattern the recent menu work used for splits) so it's discoverable + has a shortcut.
   - When collapsed, a **persistent thin re-expand affordance** on the left edge (a slim clickable strip or a floating chevron button) so the roster is always recoverable without hunting — this is the "easy way to expand/dexpand at will" requirement.
3. Preserve the last expanded width across a collapse cycle (collapse → expand restores prior `rosterWidthRaw`, not the default).
4. Edge: when collapsed, ensure the main terminal pane + command palette still lay out correctly (the body is a `GeometryReader`-driven HStack, line 125-161); collapsing must not break `clampedRosterWidth` math (guard width 0).

### Acceptance
- Drag handle resizes smoothly within [min,max]; width persists across restart (already).
- Toggle (button + shortcut + optional menu item) collapses to 0/thin and back; collapsed state persists across restart; re-expand is obvious and one action; transition animates; restores prior width.

---

## Suggested order & commits
1. **Feature 1** (notes): model field → store/session API → "..." menu entry + inline editor → orange 2nd line render → visual polish pass with screenshots. Commit: "Add per-session notes shown under the roster name".
2. **Feature 2** (sidebar): verify existing resize → add collapse state + toggle (button + shortcut + edge re-expand affordance) → animate + persist. Commit: "Add collapsible roster sidebar with toggle".

## Key file anchors
- macos/Sources/HolyGhostty/Domain/HolyModels.swift:942 (`HolySessionLaunchSpec`), :1074 (`HolySessionRecord`)
- macos/Sources/HolyGhostty/Session/HolySession.swift:377 (`rename` — template for `setNote`), :100 (`rosterTitleOverride`), title/displayProjectName ~:55-121
- macos/Sources/HolyGhostty/Workspace/HolySessionRosterView.swift:56 (row instantiation/wiring), :491 ("..." menu), :468-640 (row body + inline rename pattern), :294 (`HolySessionRosterOrdering`)
- macos/Sources/HolyGhostty/Workspace/HolyWorkspaceView.swift:8-10 (layout constants), :55 (width AppStorage), :125-161 (roster+handle layout), :1-30 (drag-handle view), :263 (`leftRailViewControls`/toolbar)
- macos/Sources/HolyGhostty/DesignSystem/HolyGhosttyDesignSystem.swift (`HolyGhosttyTheme` colors — add `noteAccent`)
- macos/Sources/HolyGhostty/Database/HolyDatabaseMigrator.swift:72 (`sessions` table, `launch_spec_json`) — confirms no migration needed
- macos/Sources/App/macOS/MainMenu.xib + HolyWorkspaceWindowController.swift (if adding a View-menu "Toggle Sidebar" item, mirror the recent AppDelegate-targeted split-menu wiring)

## Out of scope / parked (other handoffs)
- Menu Split Right/Down still broken: `.handoff/2026-06-02-menu-splits-and-tab-titles.md`.
- Hosts-sheet polluted title + restart roster dropout: `.handoff/2026-06-03-hosts-title-and-restore-dropout.md`.
