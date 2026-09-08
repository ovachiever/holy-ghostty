---
workflow: 2
manna: mn-b61389
track: mn-9a97cc
source: Erik request 2026-09-03 13:42 (mid-turn during the ControlPath fix)
base_commit: d83eef0bf0b3db678b8b9b552d0755dd5def776a
scope: '[P1][ARCHIVE][REMOTE] Federated archive: browse and restore sessions on the host that owns them'
inputs:
- Erik request 2026-09-03 13:42 (mid-turn during the ControlPath fix)
binding: sha256:cd52e3cd8ec1132154b130bb827d841ae16924e7ef9dae87c56ec44e5bd3c2fd
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

## Implementation receipt, 2026-09-07

- Archive mode now reads every configured remote host through `HolySSHTransportManager` as a `.control` / `.metadata` operation. It does not construct or invoke raw SSH.
- The remote helper accepts a typed JSON request on stdin, opens the owning host's `holy-archive.sqlite3` with SQLite `mode=ro`, enables `PRAGMA query_only`, rejects newer schemas, binds all values, and exposes no mutation operation.
- Local rows and remote rows merge into one recency-sorted list. Remote identities are namespaced by host while the raw provider session ID stays attached for exact restore.
- Search now federates both FTS and semantic similarity. The local query vector rides the typed request, and each remote host compares it with its own stored archive embeddings using the same weights and thresholds as local search.
- Query pages are cached per host and request under the local caches directory with directory mode `0700` and page mode `0600`. Cache writes use the Archive write pacer. Fresh live pages survive cache-write failures with an explicit degraded-cache notice. Offline hosts return cached pages marked stale instead of blanking the archive.
- List rows, search results, and detail show owning-host provenance. Remote tags, notes, title generation, annotation deletion, and raw command copy are disabled because the remote archive is read-only.
- Resume rebuilds the launch spec from the raw provider ID, runtime, working directory, owning host, SSH destination, and optional tmux socket, then uses the existing `HolyWorkspaceStore.createSession` remote launch path so the result returns to the local roster.

## Verification receipt

- Strict SwiftLint: 0 violations across the 12 owned Swift source and test files.
- `git diff --check`: passed.
- Fresh Debug arm64 Xcode `build-for-testing` with isolated DerivedData: passed.
- Scoped Xcode suite: 70 passed, 0 failed, 0 skipped. Covered Archive federation, Archive mode, presentation, restore command construction, managed SSH transport, and render smoke.
- The embedded remote query ran against a current-schema fixture archive, returned list, keyword, semantic-only, transcript, and annotation data, and left the database bytes unchanged.
- Build contract: `scripts/test-holy-ghostty-build-contract.sh` passed.
- Render smoke wrote 11 PNGs under `.dev/mn-b61389/archive-renders`. `archive-remote-stale.png` was inspected at original resolution and shows Source provenance, stale state, remote-only Resume wording, and disabled remote mutations without clipping.
- ZPC captured 8 error-resolution lessons and 6 architecture/completion decisions.

## Required live gate still open

This Mac Studio cannot execute the named cross-host acceptance: both the production and debug Holy databases currently report `0` rows in `remote_hosts`. No supported owning host is therefore available to query or resume from this checkout.

Keep `mn-b61389` in `in_progress` until a MacBook with Studio configured verifies all three runtime outcomes:

1. Archive lists Studio rows with visible provenance, including all 25 recovery-archived sessions from the 2026-09-03 transport outage.
2. One search returns matching rows from both the MacBook and Studio, including a semantic-only remote match when embeddings exist.
3. Resume on one Studio row launches on Studio with the archived runtime and cwd, then attaches into the MacBook's local roster.
