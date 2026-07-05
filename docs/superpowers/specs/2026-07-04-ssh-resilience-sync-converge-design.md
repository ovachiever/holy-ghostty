# SSH Resilience + Sync Converge — Design

- **Date:** 2026-07-04
- **Status:** Approved direction (all-three-layers + converge-to-truth), pending spec review
- **Area:** macOS app — `macos/Sources/HolyGhostty`

## Problem

Two related failures, both rooted in "sessions die while you're not looking, and recovery is
manual":

1. **Sync is slower and less reliable than Clear + Hosts → Attach All.** Sync
   (`HolySessionRosterView.swift:364`) is `reattachAllSessions()`
   (`HolyWorkspaceStore.swift:573`):
   - Fires `tmux detach-client` over SSH per remote session, **serially**, via
     `HolyTmuxClientDetachCommand` (store:2777) — bare `ssh` with **no ConnectTimeout, no
     BatchMode**, blocking on `waitUntilExit()`. One unreachable host ≈ 60–75s kernel TCP
     timeout per session before any reattach begins.
   - **Record-driven**: reattaches what the roster remembers without asking hosts what exists.
     Stale tmux names / rebooted hosts spawn failing ssh panes.
   - **Churns healthy sessions**: detaches everything reattachable first.
   Hosts → Attach All works because it is **discovery-driven** — it attaches only sessions a
   fresh sweep proved alive, using fail-fast flags (`ConnectTimeout=5`, `ServerAliveInterval=5`,
   `BatchMode=yes` — `HolyRemoteTmuxDiscoveryService.swift:93-99`).

2. **Sleep kills SSH panes and nothing recovers them.** The app has zero sleep/wake/power
   handling (verified: repo-wide grep empty). The long-lived attach command is bare `ssh -tt`
   with no keepalive (`HolyTmuxCommandBuilder.swift:122`), so post-sleep connections linger as
   zombie panes (kernel TCP can take many minutes to notice) until manually rebuilt.

Everything is tmux-backed: a dropped SSH loses nothing remotely. The entire cost is dead panes
awaiting a manual ritual. Therefore the design goal is **prevent what's preventable, and make
the rest self-repairing** — not "never disconnect," which macOS does not permit (no app can
veto lid-close or forced sleep).

## Sleep taxonomy (what is preventable)

| State | SSH fate | Preventable? |
|---|---|---|
| Screen off (display sleep) | Harmless by itself | n/a |
| Idle system sleep (follows screen-off) | TCP stalls → server/NAT drops | **Yes** — power assertion |
| Lid close | Dies (unless clamshell w/ ext. display + power) | No — recovery only |
| Forced (critical battery, thermal) | Dies | No — recovery only |

## Design — one engine, three triggers

### The Converge engine (replaces `reattachAllSessions` internals)

```
converge():
  1. Sweep — discovery across all known hosts in parallel, 5s/host cap
     (reuse HolyRemoteTmuxDiscoveryService; collect per-session attached-client
     state via tmux format #{session_attached}). Local tmux sockets included
     (no network cost).
  2. Diff — match discovered sessions to roster records via
     HolyRemoteTmuxSessionKey (store:544). Four buckets:
       - discovered, not in roster            → attach (new record)
       - in roster, discovered, client dead   → repair (detach-clean + reattach)
       - in roster, discovered, client alive  → skip (never touch healthy panes)
       - in roster, not discovered:
           host reachable                     → auto-archive (recoverable in History)
           host unreachable                   → leave untouched
  3. Apply — repairs run with bounded concurrency; identity preserved
     (pins, notes, titles, linkage slots, event history stay on the record).
```

"Client dead" is decided by **local process state first, remote state as corroboration**:
dead = the pane's local ssh process has exited, OR the local pane claims attached while the
remote session reports zero attached clients (zombie). The remote attached count alone is NOT
sufficient — another machine (e.g., the MacBook) may hold its own attachment to the same tmux
session and inflate the count. In that worst case a zombie pane is skipped for ≤~60s until the
L2 keepalive kills its ssh process and Trigger 3 repairs it — the system self-corrects.

### Triggers

1. **Sync button** — runs `converge()` manually. Label stays "Sync"; button shows an
   in-progress state. Bounded runtime (parallel 5s caps) ⇒ no cancel needed in v1.
2. **Wake** — `NSWorkspace.didWakeNotification` → ~4s network-settle delay (Tailscale re-key)
   → `converge()`. Debounced: skip if a converge ran or is running within the last ~10s.
3. **Pane exit** — a remote session's ssh process exits unexpectedly → converge that single
   session with backoff (≈4s / 10s / 25s, 3 attempts), then mark failed and stop retrying
   until next wake or manual Sync. This is the autossh behavior, in-app.

### Layer 1 — Keep-awake power assertion

- `IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep, …)` held while
  **≥1 remote session is attached**; released when the last detaches/archives (and implicitly
  on quit). Display still sleeps; system does not.
- User toggle in the roster overflow menu: "Keep Mac awake while remote sessions attached."
  **Default ON.** Preference persisted in the existing app-state store. No AC/battery
  distinction in v1 (revisit if battery drain annoys).
- Small new `HolyPowerAssertionManager` wraps create/release idempotently.

### Layer 2 — Keepalive flags

- **Attach command** (`HolyTmuxCommandBuilder`): add
  `-o ServerAliveInterval=15 -o ServerAliveCountMax=4 -o TCPKeepAlive=no -o ConnectTimeout=8`.
  Survives ~60s stalls; detects true death in ~60s instead of never. **No BatchMode** — the
  pane is visible and interactive auth must remain possible.
- **Detach command** (`HolyTmuxClientDetachCommand`): add
  `-o ConnectTimeout=5 -o BatchMode=yes` (headless; this closes the infinite-hang hole).

L2 without L3 would be a regression (kills zombies faster, resurrects nothing) — they ship
together.

## Files touched

| File | Change |
|---|---|
| `Workspace/HolyWorkspaceStore.swift` | converge engine + diff buckets; debounce; retry/backoff state; rewire `reattachAllSessions()`; detach-command flags |
| `Remote/HolyRemoteTmuxDiscoveryService.swift` | expose per-session attached-client state (`#{session_attached}`) in sweep results |
| `Tmux/HolyTmuxCommandBuilder.swift` | keepalive/ConnectTimeout flags on the attach ssh |
| `App/HolyWorkspaceWindowController.swift` | wake observer → settle delay → converge; pane-exit hook for remote sessions |
| new `App/HolyPowerAssertionManager.swift` | IOPM assertion wrapper + lifecycle from session set changes |
| `Workspace/HolySessionRosterView.swift` | Sync button progress state; keep-awake toggle in overflow menu |
| Persistence (app-state) | `keep_awake_enabled` preference key |

## Edge cases

- **Wake storm / repeated wakes** — debounce window (~10s) + single-flight converge.
- **Sleep during converge** — commands fail fast on their own timeouts; next wake re-runs.
- **Reattach fails 3× ** — session marked failed (existing failed presentation); no retry loop
  until next wake/manual Sync.
- **Interactive-auth hosts** — attach retains full interactivity (no BatchMode on attach).
- **Assertion leaks** — manager is idempotent; assertion also dies with the process by OS
  contract.
- **Mid-typing user** — healthy panes are never detached by design (attached-client check).
- **Local sessions** — participate in diff; no SSH, so no timeout risk.

## Rejected alternatives

- **mosh / Eternal Terminal** — solve roaming at the protocol layer but require server-side
  installs, break port/agent forwarding, and duplicate durability tmux already provides. The
  only missing piece is reconnection, which converge supplies.
- **Literal Rebuild button** (Clear + Attach All) — guaranteed but wipes per-session identity
  (pins, notes, linkage slots) on every use.
- **Server-side sshd ClientAlive tuning** — not the lever; default servers don't kill stalled
  clients (that's why zombies, not drops).

## Testing

Unit (style of existing `HolySession*` tests):
- Diff bucketing: discovery result × roster records → expected actions (new/repair/skip/
  archive/untouched), including unreachable-host and local-socket cases.
- Command builders: attach/detach argument lists contain the exact new flags.
- Debounce + single-flight: rapid triggers coalesce.
- Backoff schedule: 3 attempts then failed-state, reset on wake/manual sync.

Manual verification: screen-off on AC and battery (assertion holds, panes live); lid-close →
open (panes self-repair within seconds); Sync button with one host asleep (completes in
seconds, healthy panes untouched); keep-awake toggle honored live.

## Out of scope

- Auto-converge on network-path change (Wi-Fi → hotspot) — natural v2 trigger.
- AC/battery-aware assertion policy — v2 if battery drain is felt.
- The parked throbber-staleness investigation (separate thread; App Nap interaction noted as a
  possible common cause).
