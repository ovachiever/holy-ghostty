---
workflow: 2
manna: mn-7fbb07
track: mn-70875b
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[INBOX][BRIEF] Remote estates: the brief executes where the session lives'
inputs: []
binding: sha256:ea40a85201efef27c64cb99c2d16de473fa67a1d24643536fe4f2d2cbe812fcf
---

# Handoff: [INBOX][BRIEF] Remote estates: the brief executes where the session lives

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-7fbb07
```

## Scope

[INBOX][BRIEF] Remote estates: the brief executes where the session lives

## Inputs

- None declared.

## Work order

Erik 2026-08-11 15:34: on the MacBook, focused sessions live on the Studio over SSH — a locally-run brief reads the wrong (empty) estate. GENERAL DESIGN (public repo — no user-specific anything): the brief subprocess executes on the focused session,s host, resolved from the session,s existing transport descriptor (local → local subprocess; ssh → /usr/bin/ssh BatchMode wrapper, the same rail HolyRemoteTmuxDiscoveryService rides). The remote host resolves its own agent-do via its login shell and its own ANTHROPIC_API_KEY via its own env/creds — credentials are NEVER forwarded over SSH (each host owns its secrets). Path context (focused repo/board) is already host-local by construction since it derives from the remote session,s discovered cwd. Absent agent-do or ssh failure degrades honestly, naming the host. Suggestion rows for a remote estate spawn their shell ON that host via the automation URL,s existing host/transport params, so the typed command runs where the board lives. Requirement documented: agent-do installed on any host whose sessions you want briefed.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-7fbb07`.
4. Commit with `Manna: mn-7fbb07` and run `agent-do manna done mn-7fbb07` only after the work is verified.
