---
workflow: 2
manna: mn-56f896
track: mn-eb7a80
source: null
base_commit: bda6d543abafdbfe0f663fc6605de4d83bc5fbce
scope: '[P0][META] Preserve notes, Today pins, titles, and identity across lifecycle'
inputs: []
binding: sha256:c85684fec1fe3884f735640462c5761ce006f9c7980c3a443cbee621bea3f712
---

# Handoff: [P0][META] Preserve notes, Today pins, titles, and identity across lifecycle

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-56f896
```

## Scope

[P0][META] Preserve notes, Today pins, titles, and identity across lifecycle

## Inputs

- None declared.

## Work order

User-visible bug: session notes disappeared after Clear plus Attach All; Today pin must survive the same transition. Commit 00e4194e8 is partial implementation evidence, not acceptance.

Scope:
- Bind user-authored metadata to stable logical/session and remote tmux identity, not disposable roster rows.
- Preserve note, explicit title, Today pin, roster order, and source Holy UUID across Clear, Attach All, restart, archive, readoption, relaunch, and recovery.
- Define the Today pin date/expiration rule explicitly.
- Prevent duplicate records and stale rows from overwriting newer user edits.

Done when:
- Transition-matrix tests cover local and SSH sessions across every lifecycle path.
- Studio and MacBook installed builds preserve edits through Clear plus Attach All.
- Conflicts fail visibly; no silent metadata loss.
- Current drag-to-reorder issue mn-211310 can then be re-evaluated.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-56f896`.
4. Commit with `Manna: mn-56f896` and run `agent-do manna done mn-56f896` only after the work is verified.

## Report: 2026-09-29, Gate 3 scope boundary

Claimed by `codex-01a0ef08871d7243` after verifying the canonical handoff seal `sha256:b6d91465b8e90b73a7e5c8242424d4a74171f94c7f130a1dcf5ae8e3919d20d2`. No implementation change or test execution is claimed for this child. Source edits stopped before extending contracts outside the gate's enumerated Remote, Session, Workspace, AgentState, and Supervisor paths.

### Current source evidence

1. `macos/Sources/HolyGhostty/Domain/HolyModels.swift:1616` owns the durable `HolySessionLaunchSpec`. It has note and Today-pin edit timestamps but no explicit-title timestamp. `Session/HolySession.swift:559` renames only the local record, without publishing a versioned title edit. A timestamp-free title cannot participate in the same newer-edit rule as notes and pins.
2. `macos/Sources/HolyGhostty/Tmux/HolyTmuxSessionMetadata.swift:113` owns the cross-host snapshot and `:120` owns the merge result. The snapshot carries only note/pin. The merge result has keep-local/apply-remote/publish-local, with no conflict result; equal timestamps with different values fall through to keep-local at `:158`. The child requires conflicts to fail visibly, which cannot be implemented truthfully solely by treating that result as success in Workspace.
3. `Supervisor/HolySessionSupervisor.swift:798` copies the reconciled launch spec, then unconditionally replaces note and pin with archived values at `:802-803` without replacing the reconciled timestamps. A newer synchronized value can therefore be replaced by an old value carrying the newer timestamp. This local defect must be fixed together with the canonical merge contract and regression coverage, not hidden by a second merge rule.
4. Relaunch creates a fresh record in `HolySessionSupervisor.createSession`, whereas readoption preserves `sourceSessionID`. The transition matrix must pin which identity survives every path. Clear archives in roster order, but discovery readoption currently appends in discovery order; restore that order from durable archive lineage rather than introducing a parallel order store.
5. Current Today pins are a persistent manual flag. There is no midnight expiration in `HolySession.isFocused` or `setFocused`. Preserve that behavior unless explicitly changed, and document/test it as "pinned until unpinned" instead of claiming an unimplemented date rule.

### Concrete continuation scope requested

Extend this gate to the two canonical contracts `Domain/HolyModels.swift` and `Tmux/HolyTmuxSessionMetadata.swift`, with their focused tests. Add backward-compatible optional title edit provenance to the existing serialized launch spec and tmux metadata payload; add an explicit conflict outcome to the existing merge law and expose it through Session/Workspace. Preserve the archived UUID/order in the existing lifecycle paths and merge note/pin values with their own timestamps. Test old JSON decoding and a local/SSH matrix spanning Clear, Attach All, restart, archive/readoption, relaunch, and recovery. No new dependency, parallel metadata store, or direct database repair is proposed.

The gate handoff's allowed source list does not include Domain or this Tmux contract. The user's global start sequence also requires stopping for architectural or schema-affecting changes. Accordingly these two files remain untouched. Persistence/ and Database/ belong to the concurrent `mn-ca1805` lane and remain untouched; any later need there requires a separate ownership handoff under the gate's explicit stop-and-report rule. `Restore/`, `Archive/`, `Board/`, and `Tmux/HolyTmuxCommandBuilder.swift` remain outside this lane.

Required next: authorize the two-file scope extension, finish this child, then continue in the gate's order with `mn-a0406e`, `mn-cf5fb6`, and `mn-ede22a`. Those later children have not been claimed or implemented. All affected children and the parent gate remain not-done. Runtime acceptance still requires the coordinated `mn-f92871-executed-live-acceptance` pass under the user's no-launch boundary.
