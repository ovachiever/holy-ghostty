---
workflow: 2
manna: mn-b61389
track: mn-9a97cc
source: Erik request 2026-09-03 13:42 (mid-turn during the ControlPath fix)
base_commit: d83eef0bf0b3db678b8b9b552d0755dd5def776a
scope: '[P1][ARCHIVE][REMOTE] Federated archive: browse and restore sessions on the host that owns them'
inputs:
- Erik request 2026-09-03 13:42 (mid-turn during the ControlPath fix)
binding: sha256:33de0f754a6e2e2da485cb64721c3fcb7354547c2cd189b7d6787f87941d0f42
---

# Handoff: [P1][ARCHIVE][REMOTE] Federated archive: browse and restore sessions on the host that owns them

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-b61389
```

## Scope

[P1][ARCHIVE][REMOTE] Federated archive: browse and restore sessions on the host that owns them

## Inputs

- Erik request 2026-09-03 13:42 (mid-turn during the ControlPath fix)

## Work order

Erik 2026-09-03: on the MacBook, 99.99% of sessions are hosted on the Studio — Archive mode must see every configured remote host's archive, not just local stores, and restore remote sessions ON their owning host. Design: per-host archive sources — local stores as today, plus each remote host's holy-archive.sqlite3 queried READ-ONLY over the managed SSH transport's control lane (never raw ssh; the transport manager owns multiplexing and the new sun_path-safe sockets from mn-455be1). Rows carry host provenance in list, search, and detail; hybrid search federates results across hosts with the host label visible; remote index pages cache locally with staleness marked honestly (offline shows the cache, never errors blank). RESTORE: a remote session's resume executes on the owning host through the existing remote spawn bridge (runtime + cwd + host ride the launch spec) — restoring a Studio session from the MacBook lands it on the Studio, attached into the local roster like any remote session. Never write a remote archive; ingest stays host-local (each machine indexes its own stores). Respect the write pacer for cache pulls. Acceptance: from the MacBook, Archive lists Studio sessions with provenance, a search hits both hosts, one Studio session restores and attaches live on the Studio — including the 25 recovery-archived rows from the 2026-09-03 transport outage re-attaching cleanly.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-b61389`.
4. Commit with `Manna: mn-b61389` and run `agent-do manna done mn-b61389` only after the work is verified.
