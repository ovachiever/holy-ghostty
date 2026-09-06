---
workflow: 2
manna: mn-bf6fe1
track: mn-9a97cc
source: 'MacBook holy-archive.sqlite3 sampled remotely 2026-09-05 21:45; rows: ''you-re-looking-at-a-screenshot'' (codex), ''/'', ''0.0.6'' (droid)'
base_commit: 8827922087e9abb78e3a5bff7bf6d164bcd13545
scope: '[P2][ARCHIVE][UX] Project names: real cwd basename or an honest fallback — never storage-dir slugs'
inputs:
- 'MacBook holy-archive.sqlite3 sampled remotely 2026-09-05 21:45; rows: ''you-re-looking-at-a-screenshot'' (codex), ''/'', ''0.0.6'' (droid)'
binding: sha256:053d4bf8651812f174afb5d6c47374e32919acbf774ce58d918daec44093f7e0
---

# Handoff: [P2][ARCHIVE][UX] Project names: real cwd basename or an honest fallback — never storage-dir slugs

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-bf6fe1
```

## Scope

[P2][ARCHIVE][UX] Project names: real cwd basename or an honest fallback — never storage-dir slugs

## Inputs

- MacBook holy-archive.sqlite3 sampled remotely 2026-09-05 21:45; rows: 'you-re-looking-at-a-screenshot' (codex), '/', '0.0.6' (droid)

## Work order

Erik 2026-09-05 (MacBook archive receipts via remote query): names are already basename(project_path), but fallback paths leak storage internals as 'projects': codex session with unrecorded cwd shows 'you-re-looking-at-a-screenshot' (the codex thread dir is a SLUG OF THE FIRST PROMPT under ~/Documents/Codex/<date>/ — never a project); droid rows show '/' (cwd was root) and '0.0.6' (~/.cache/opensession/0.0.6); umbrella dirs ('AI', 'Custom_Coding') appear when a session genuinely ran there — those stay, they are true. Rule: (1) project_path prefers the session's RECORDED cwd (codex turn_context cwd, claude jsonl cwd, droid session_start cwd) — the providers already parse these; the fallback to the store file's parent directory must never be treated as a project. (2) When no real cwd exists, display '(no project)' with the harness label and keep the row searchable; never render prompt-slugs, cache paths, or bare '/'. (3) Grouping/filtering keys on the same resolved value so one project never splits. Reindex applies the rule to existing rows (recompute display name at read or one migration pass). Receipts in this item's source.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-bf6fe1`.
4. Commit with `Manna: mn-bf6fe1` and run `agent-do manna done mn-bf6fe1` only after the work is verified.

## Implementation receipt

Implemented 2026-09-05 in the native Archive provider boundary.

- `HolyArchiveProjectIdentity` now owns path normalization and the display name together. Valid absolute cwd values keep their standardized path and folder basename. `/`, relative values, Codex prompt stores, and known harness cache roots resolve to `project_path = NULL` and `project_name = '(no project)'`.
- Claude and Droid no longer decode the archive directory name as a project fallback. Codex reads the first recorded `turn_context.cwd` when canonical `session_meta.cwd` is absent. Cursor and OpenCode no longer substitute the home directory when their project evidence is absent.
- The harness column remains independent, so an unknown project renders honestly beside its provider label and remains searchable through the stored project name.
- Full reindex reparses every provider file and upserts both project fields. A regression test starts with an existing wrong project row and proves full reindex replaces it with the canonical missing identity.

Verification:

- `HolyArchiveModeTests`, including recorded Codex cwd, Claude/Codex/Droid storage fallbacks, root/cache rejection, real umbrella preservation, and existing-row full reindex replacement: passed.
- `HolyArchivePresentationTests`: passed.
- Strict SwiftLint on all six owned source and test files: 0 violations.
- `xcodebuild build-for-testing`: passed.
- `HolyArchiveRenderSmokeTests`: passed across 840, 900, 1000, 1280, 1512, and 1728 point faces plus child, transcript, research, and persisted-width fixtures.
- `scripts/test-holy-ghostty-build-contract.sh`: passed.

Detailed receipt and render artifacts: `.dev/mn-bf6fe1-mn-6842ed/`.
