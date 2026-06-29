# Split-View Linkage — Design

- **Date:** 2026-06-29
- **Status:** Approved design, pending implementation plan
- **Area:** macOS app — `macos/Sources/HolyGhostty`

## Problem

Holy can already show 2–4 roster sessions side-by-side: `HolyPaneLayout { kind, sessionIDs }`
drives a grid in `HolyWorkspaceView`, toggled by the bottom-bar layout buttons
(`store.splitPaneRight/Down/showQuadPaneLayout`). The layout already persists
(`pane_layout` in the DB).

Two gaps make it unusable for deliberate multi-session viewing:

1. **No curation.** `paneSeedSessionIDs` (HolyWorkspaceStore.swift:1499) fills panes from
   the selected session, then walks the roster top-to-bottom. That roster-order fill is the
   "it picked random ones" behavior.
2. **Selection bleeds into the set.** `reconcilePaneLayoutForSelection` (line 1523)
   overwrites the last pane with whatever session you click. The set silently mutates as you
   navigate.

`File → Split Right` does nothing because it targets Ghostty's upstream terminal controller
(`BaseTerminalController.splitRight`), which Holy's workspace window
(`HolyWorkspaceWindowController`) does not use. Holy is a session *multiplexer*, not a
surface-splitter; we build on Holy's grid, not Ghostty's `SplitTree`.

## Goals

- Curate which sessions occupy the split, by direct slot assignment.
- Keep the linkage **durable**: it survives navigating away to a single non-member session.
- Make the linkage **visible** in the roster (shared color, chain icon, slot number).
- Support break-off-one, break-all, and maximize-one-while-keeping-the-linkage.
- Support 2, 3, and 4 panes.

## Non-goals

- Ghostty-style recursive surface splitting within a single terminal.
- More than 4 panes.
- Cross-window linkages (single workspace window only).

## Model — two concepts replacing one

Today `paneLayout` *is* the viewport. Split it:

- **Linkage** — the durable, persisted group of up to 4 ordered slots of session IDs. This is
  `HolyPaneLayout`, extended with a `.triple` kind. The linkage is "active" when
  `kind != .single`.
- **Viewport** — a `soloSessionID: UUID?` override. `nil` → render the split from the linkage;
  set → render that one session full-window while the linkage persists in the background.

### State (HolyWorkspaceStore)

```
paneLayout: HolyPaneLayout   // the linkage — persisted (already is)
soloSessionID: UUID?         // viewport override — ephemeral (resets to split on launch)
focusedPaneSlot: Int?        // which pane has keyboard focus — net-new, for swap-by-focus
```

`selectedSessionID` (existing) continues to mean "the active session" for actions like
close/kill and terminal focus. `soloSessionID` is set/cleared explicitly by the transitions
below — it is NOT derived from selection, so changing linkage membership never flips the
viewport unexpectedly.

## Behaviors

| Action | Result |
|---|---|
| `⌘1..4` (from anywhere) | bind current session → slot N (add/replace, deduped), clear solo → **jump into the split** |
| Click a **member** in the roster | clear solo → enter the split (that member focused) |
| Click a **non-member** | set `soloSessionID` = it → single view; linkage persists; chain stays in roster |
| Double-click a pane | `soloSessionID` = that member (maximize, keep linkage) |
| Right-click row → "Add to Split / Pane N" | same as `⌘N` |
| Right-click row → "Remove from Split" | drop that slot (4→3→2); at 1 member, linkage dissolves to single |
| Right-click row → "Break Split" | clear all slots → plain single sessions |
| Focus a pane → click a roster session | replace the focused slot (alternative to `⌘N`) |
| Bottom-bar buttons (existing) | flip 2-pane orientation (right/down), jump to quad — retained |

The behavioral fix: `reconcilePaneLayoutForSelection` no longer overwrites the last pane on
every click. Clicking either *enters* the split (member) or *solos* (non-member). The set
changes only through explicit slot assignment / removal.

### Hotkey

`⌘1..4` added to `HolyWorkspaceWindowController.handleWorkspaceKeyEquivalent` (line 178), the
same path that already claims Tab/⌘W/⌥Q before the terminal surface. ⌘1..4 is currently
unbound — no conflict. ⌘ chosen over ⌃ because ⌃+digit is consumed inside tmux/TUIs.

### Slot semantics — positional

Slots are **positional** (pane 1..4), matching "make this pane number 2." `⌘N` assigns to
position N. The rendered pane count = highest occupied slot. Unfilled interior slots render as
the existing "Empty pane" placeholder (HolyWorkspaceView.swift:435). In practice the set is
built 1→2→3→4, so interior gaps are rare. (Alternative considered: packed/no-gap slots —
rejected as it contradicts positional `⌘N` addressing.)

### Layout kind by slot count

- 2 → `.splitRight` (default; flip to `.splitDown` via existing button)
- 3 → `.triple` — **big left + two stacked right**:

```
+----------+-------+
|          |   2   |
|    1     +-------+
|          |   3   |
+----------+-------+
```

- 4 → `.quad` (2x2)

## Roster marker (HolySessionRosterView)

Linkage members display: a shared accent color + the chain icon (`link`, already referenced at
line 868) + a small **slot-number badge (1–4)**. A non-member single session being soloed shows
no chain. The marker reads off `paneLayout.sessionIDs` membership and index.

## Components / files touched

| File | Change |
|---|---|
| `Domain/HolyModels.swift` | add `.triple` to `HolyPaneLayoutKind` (maxPaneCount 3); `countToKind` helper |
| `Workspace/HolyWorkspaceStore.swift` | `soloSessionID`, `focusedPaneSlot`; `assignCurrentSessionToSlot(_:)`, `removeFromLinkage(_:)`, `breakLinkage()`, `maximize(_:)`, `enterSplit()`; rework `reconcilePaneLayoutForSelection`; retire auto-seed as the primary path |
| `App/HolyWorkspaceWindowController.swift` | `⌘1..4` → `store.assignCurrentSessionToSlot(n)` in `handleWorkspaceKeyEquivalent` |
| `Workspace/HolySessionRosterView.swift` | linkage marker (color + chain + slot badge); right-click items (Add to Pane N / Remove / Break); click rule (member → split, non-member → solo) |
| `Workspace/HolyWorkspaceView.swift` | `.triple` rendering; focus ring on `focusedPaneSlot`; double-click pane → maximize; slot-number overlay on panes |

## Data flow

- Roster click → `store.handleRosterSelect(id)`: member → `soloSessionID = nil` (enter split, focus that slot); non-member → `soloSessionID = id`.
- `⌘N` → `store.assignCurrentSessionToSlot(N)`: `paneLayout.sessionIDs[N-1] = selectedSessionID`; normalize; `soloSessionID = nil`; kind = `countToKind(count)`.
- Pane double-click → `store.maximize(memberID)`: `soloSessionID = memberID`.
- `HolyWorkspaceView` renders: `soloSessionID != nil` → single surface; else → grid from `normalizedPaneLayout`.

## Edge cases

- A linked session dies/closes → `HolyPaneLayout.normalized()` already drops dead IDs; linkage shrinks; dissolves to single at 1 member.
- Solo target dies → fall back to the split.
- Assigning a session already in another slot → it moves (dedup already in `normalized()`).
- Empty workspace / no current session on `⌘N` → no-op.
- Persistence: linkage (`paneLayout`) persists across relaunch (already does); `soloSessionID` is ephemeral — launch shows the split.

## Testing

Store linkage logic is pure-ish and unit-testable in the style of the existing
`HolySession*Tests` (operate on session-ID arrays):

- `assignCurrentSessionToSlot`: add, replace, dedup, position N.
- `removeFromLinkage`: shrink 4→3→2, dissolve at 1.
- `normalized()` with a dead session ID present.
- member click → enters split (solo cleared); non-member click → solos (linkage intact).
- slot assignment from a solo view → enters split with the new member in place.
- `countToKind`: 2→splitRight, 3→triple, 4→quad.

Rendering (`.triple` shape, focus ring, maximize, slot badges) verified by running the app and
screenshots — not unit tested.

## Open decision for review

- **Positional vs packed slots** (see "Slot semantics"). Designed as positional. Flag if you
  want packed instead.
