# Unseen-Reply Indicator — Design Spec (2026-07-14)

## Goal

A session whose agent finished something the user hasn't looked at yet gets a small, unmistakable visual mark in the roster. The existing blue dot stays purely time-based (recency); the new mark is purely seen-based. Two independent axes.

Chosen treatment (from visual comparison of state-tinted ring, neutral ring, halo glow, corner badge): **D — corner badge**. A tiny fixed-color pip at the orb's upper-right. The user noted A (state-tinted ring) as runner-up; treatments are deliberately swappable (see Rendering).

## Out of Scope

- Heat gauge ("used a lot in the last 24 h") — explicitly deferred by the user.
- Fixing the near-identical `waitingReply` / `workingBlue` colors — separate known issue.
- New persistence or schema — none needed.

## Derivation (single source of truth)

`HolySessionAttentionPresentation` gains `let isUnseen: Bool`.

Computed in `HolyWorkspaceStore.attentionPresentation(for:coordination:)` from the already-persisted `HolySessionAttentionMetadata`:

```
unseen ⇔ lastAgentFinishedAt != nil
       && (lastSeenAt == nil || lastSeenAt < lastAgentFinishedAt)
```

The flag is applied **only** when the presentation kind is one of the eligible states below; all other kinds set `isUnseen: false`.

Implement the comparison as a pure helper on `HolySessionAttentionMetadata` (e.g. `hasUnseenAgentReply`) so it is unit-testable without the store.

## Eligible states

`newReply`, `waitingQuiet`, `sleepingReply`, `dormantReply`, `overdueReply`, `staleReply`, `approvalNeeded`, `planningQuestion`, `failed`.

Excluded: `working`, `swarming` (nothing is "ready"), `conflict` (ongoing condition, not a landed event), `stalled`, `done`, `quiet`.

Badge persists through the dot's time decay (10 min fresh → quiet → 2 h sleeping → 24 h dormant) until the session is visited — per user decision "ring persists until visited."

## Seen semantics (existing machinery, unchanged)

- Selecting/visiting a session already updates `lastSeenAt` via the store's `markSeen` path (`updateAttentionMetadata(markSeen:)`, `scheduleSelectedSessionSeenMark`) → badge clears reactively.
- A reply landing while the session is selected is marked seen on the same path → never badges.
- `bindSessions(seedMissingAsSeen: true)` seeds unknown sessions as seen → no badge storm on first launch after this feature ships.
- Metadata is persisted → badge state survives relaunch.

## Rendering

In `HolySessionRosterView.swift`:

- `HolyAgentStatusOrb` gains `var isUnseen: Bool = false`.
- When true, overlay a pip aligned to the orb slot's top-right: 6×6 pt circle, fill near-white (`Color(white: 0.93).opacity(0.9)`), stroked 1.5 pt in the fixed roster background color (`HolyGhosttyTheme.bg` — NOT the selection-dependent row highlight) so it separates cleanly from any orb underneath in every row state. Static — no animation; motion stays reserved for working/swarm states.
- The pip is additive and state-agnostic: it must not alter the orb's own size, color, or layout. Implemented as a single `.overlay(alignment: .topTrailing)` on the existing orb container so swapping treatment later (ring, glow) is a one-view change.
- `HolyRosterRow` passes `attention.isUnseen` through. All four layouts (classic, calm, triage, focus) inherit via the shared row; calm's state-collapsing (`displayActivityState`) does not touch the flag.

## Testing

- Unit tests on the pure derivation helper: unseen when finished-after-seen; nil `lastSeenAt` with a finish ⇒ unseen; seen-at-or-after-finish ⇒ seen; nil `lastAgentFinishedAt` ⇒ never unseen.
- Presentation-level test if cheap: working/swarming kinds never carry `isUnseen`.
- No SwiftUI snapshot tests (repo has none; logic-level testing is the convention).

## Risks / Notes

- If `lastAgentFinishedAt` updates on states beyond "reply finished" (verify during implementation via `lastAttentionWasActiveWork` transition in `updateAttentionMetadata`), the eligible-states gate above still bounds where the badge can appear.
- 18×18 pt orb slot is tight; verify the pip doesn't clip against the row's `.frame` or overlap the swarm spinner's 16 pt variant (excluded states make this moot, but check `working` → decay transitions).
