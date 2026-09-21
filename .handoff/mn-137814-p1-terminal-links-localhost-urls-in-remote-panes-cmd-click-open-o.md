---
workflow: 2
manna: mn-137814
track: mn-9a97cc
source: null
base_commit: 0c5bc7829593c31f296ea889d5f583ff75914f9f
scope: '[P1][TERMINAL][LINKS] Localhost URLs in remote panes cmd-click open on the viewing Mac against the session''s real host — rewrite first, SSH forward when loopback-bound'
inputs: []
binding: sha256:706777c09aac662a5e49e5bab1b421dc9dfd2fe933c5d2bb0b2d39820e2056d5
---

# Handoff: [P1][TERMINAL][LINKS] Localhost URLs in remote panes cmd-click open on the viewing Mac against the session's real host — rewrite first, SSH forward when loopback-bound

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-137814
```

## Scope

[P1][TERMINAL][LINKS] Localhost URLs in remote panes cmd-click open on the viewing Mac against the session's real host — rewrite first, SSH forward when loopback-bound

## Inputs

- None declared.

## Work order

Erik 2026-09-20 (receipt: a Studio-hosted agent printed http://localhost:11111/wall.html and http://localhost:11111/wall-list.html; clicked from the MacBook those point at the MacBook — the agent had to hand-translate to eriks-mac-studio.tail2b07fa.ts.net:11111, which worked). Plain URLs already open on the viewing Mac (the macOS host fires the browser open), so the defect is purely that loopback URLs from remote panes are textually wrong for the viewer. Feature, three stages in one gesture: (1) DETECT — on the URL-open path for a pane whose session transport is SSH (Holy knows hostLabel/sshDestination on the launch spec and discovery metadata), a URL whose host is localhost, 127.0.0.1, ::1, or 0.0.0.0 is a session-host reference. Non-loopback URLs pass through untouched (verify with a regression that they still open unmodified). Local panes untouched. (2) REWRITE — swap only the host component for the session's sshDestination hostname (the name THIS Mac already reaches the host by — Tailscale MagicDNS names ride free), preserving scheme/port/path/query/fragment; then a fast bounded TCP reachability probe to host:port. Reachable → open in the default browser. (3) FORWARD FALLBACK — probe refused (service bound to loopback on the remote) → open an SSH local forward through HolySSHTransportManager's existing control master (admission via the control lane; a forward is not a new interactive channel), pick a free local port, open http://localhost:<localport>/<path> in the browser, keep the forward alive with a bounded idle TTL and tear it down on session end or app quit; a second click on the same remote host:port reuses the live forward. Errors surface as the existing link-caption UI, never a dialog. Works symmetrically (Studio Holy viewing a MacBook session). No engine/Zig change — the intercept lives on the macOS open-url path (where the browser open currently fires), upstream behavior untouched for local panes. Tests (executed): rewrite mapping table incl. ports/paths/IPv6/fragment; non-loopback passthrough; probe-branch with injected prober; forward lifecycle (create, reuse, TTL expiry, session-end teardown) against an isolated sshd or faked transport per the SSH test fixtures' pattern; admission accounting. Acceptance: Erik on the MacBook cmd-clicks the wall.html localhost link in a Studio pane and the wall renders in the MacBook browser with zero hand-translation — first via rewrite when the server listens broadly, and via the forward when it is loopback-only.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-137814`.
4. Commit with `Manna: mn-137814` and run `agent-do manna done mn-137814` only after the work is verified.
