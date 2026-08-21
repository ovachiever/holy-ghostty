---
workflow: 2
manna: mn-2b3a11
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P1][SYNC] Always-on cross-host note/pin sync via tmux user options'
inputs: []
binding: sha256:882735f324be5c3ac005f29176bcd9c9ea4cbe5e5390632004e172874ea5d915
---

# Handoff: [P1][SYNC] Always-on cross-host note/pin sync via tmux user options

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-2b3a11
```

## Scope

[P1][SYNC] Always-on cross-host note/pin sync via tmux user options

## Inputs

- None declared.

## Work order

Ship the continuous version of the one-time import proven 2026-07-20 (8 notes MacBook→Studio, matched by tmux session name, fill-blank merge, zero conflicts). Erik: 'I want this all the time.'

ARCHITECTURE — the shared tmux server IS the sync bus. No new daemon, no new transport: mirror user-authored metadata as session-scoped user options on the session's OWN tmux server, exactly like @holy_title and @holy_working_directory already do (precedent: title edits ALREADY flow cross-host through this channel — this issue extends the same pattern to notes and Today pins).

Options: @holy_note_v1 (base64-encoded UTF-8; cap 4KB pre-encoding — raw newlines/quotes are unsafe in option values), @holy_note_updated_at_v1 (ms epoch), @holy_today_pin_v1 + @holy_today_pin_updated_at_v1.

WRITE PATH: setNote/setFocus stamp updated_at locally and publish through the existing delivery machinery (HolyTmuxModelLabelUpdateCommand pattern — bounded retry/backoff already built; fail-closed on incomplete tmux identity per house rule). Works identically for local and SSH sessions — the option lands on whichever server hosts the session.

READ PATH: discovery already reads user options (HolyRemoteTmuxDiscoveryService format strings, local + remote); extend to the new options and apply through applyDiscoveredLaunchMetadata.

MERGE SEMANTICS (the contract): remote value wins iff its updated_at is STRICTLY newer than the local edit stamp; an older or timestamp-less remote value never clobbers a local note; local note + absent option → publish local (self-heal + legacy migration on first pass); no flicker loops (applying a remote value must not restamp updated_at). Deletion is a real state: empty-note with newer stamp clears, absent option does not.

BONUS DELIVERY: this substantially advances mn-56f896 — after Clear + Attach All, readoption re-reads the options from tmux, so notes/pins survive roster-row recreation on BOTH hosts.

NON-GOALS v1: roster order, resume descriptors, sessions that do not share a tmux server, archived rows.

ACCEPTANCE (installed-app, both machines, verified with Erik): note edited on host A appears on host B after B's next discovery pass; edit ping-pong resolves newer-wins with no oscillation; Clear+Attach All preserves notes/pins on both hosts; a note deleted on one host clears on the other; multiline + emoji notes roundtrip byte-exact; full suite green; real-tmux-PTY integration test for the option roundtrip (suite precedent exists).

Prior art to read first: today's import script pattern (join key + non-clobber), mn-15ba3d (the eventual full sync contract — this issue is its proven v1 slice), the @holy_title delivery/read path end to end.

IMPLEMENTATION EVIDENCE 2026-07-20 — commit 45772ea65 implements the v1 contract. TDD red→green covered merge ordering, tombstone-vs-absence, byte-exact multiline/emoji base64, field-selective retry coalescing, exact-identity failure, and a real tmux PTY write→option→production-discovery roundtrip (13/13 focused). Full macOS suite: 425 executed, 424 passed, 0 failed, 1 benchmark placeholder skipped. Canonical signed ReleaseLocal is installed and running on the Studio with verified ReleaseFast core. KEEP IN PROGRESS: MacBook SSH timed out during deployment; MacBook install plus Erik’s two-machine note/pin, ping-pong, deletion, and Clear + Attach All acceptance remain required. No branch was pushed.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-2b3a11`.
4. Commit with `Manna: mn-2b3a11` and run `agent-do manna done mn-2b3a11` only after the work is verified.
