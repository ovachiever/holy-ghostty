---
workflow: 2
manna: mn-fe97c2
track: mn-9a97cc
source: Erik, 2026-09-02 13:48, after reviewing mn-767817's first face
base_commit: c528bd74b39407bb647a4b36311ef2f0db7d5ea6
scope: 'Archive mode: cockpit-consistent face with agent-sessions behaviors'
inputs:
- Erik, 2026-09-02 13:48, after reviewing mn-767817's first face
binding: sha256:5643ad819d9cc4660ac09c7e3a074c68d8a30a012694ab372ce37d20d6c2a046
---

# Handoff: Archive mode: cockpit-consistent face with agent-sessions behaviors

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-fe97c2
```

## Scope

Archive mode: cockpit-consistent face with agent-sessions behaviors

## Inputs

- Erik, 2026-09-02 13:48, after reviewing mn-767817's first face

## Work order

Rebuild the native Archive presentation so it looks like the manna board cockpit (same tokens: 12px mono, 26px ledger rows, section heads, inspector, strip) and behaves like the agent-sessions TUI (newest-first list with AI summaries, harness filter chips, sub-agent pane, details with first prompt / last response / resume command, search, transcript with find, tag/note, research). Data fixes ride along: import agent-sessions summaries so rows read as titles, and skip <local-command-stdout> when choosing the first prompt. Erik's ask 2026-09-02: 'work and act like ../agent-sessions, look like the agent-do manna board and the rest of ghostty'. Keeps HolyArchiveRepository/Providers/Indexing/Search/Research as built under mn-767817.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-fe97c2`.
4. Commit with `Manna: mn-fe97c2` and run `agent-do manna done mn-fe97c2` only after the work is verified.

## Continuation (2026-09-02, first cut landed)

What landed:

- `HolyArchivePresentation.swift` (new): the TUI's rendering rules (row text = summary → first real prompt line → title → "(no prompt)"; `MM-DD HH:MM` stamps; parent/child type lines; detail title; 2,000/1,000-character excerpts; list/children heads as `$ agent-sessions …` prompts; harness → cockpit hue; column fitting) as pure functions.
- `HolyArchiveModeView.swift`: rebuilt on the board cockpit's tokens. Topbar `‹ terminal › archive` + sessions | research tabs + the search bar (which doubles as the tag/note input, as the TUI's does) + `N sessions | ● indexed | reindex ▾`. Sessions sheet: harness chips, DATE/HARNESS/PROJECT/SUMMARY/SUB ledger, `$ agent-sessions children` pane. Inspector: harness pill + type, title, meta table (harness/type/title/path/date/model/session id/tags/notes), search match, first prompt, last response, resume command block, `copy: [command] [id] [path]`, `act: [resume] [transcript] [name] [tag] [note]`. Transcript with find; research tab with model/effort and the send line. Strip: index progress or status on the left, the key legend on the right.
- Data: `<local-command-stdout>` joins the meta-prompt skip list and titles/rows take the first real line; the legacy summary importer now reads agent-sessions' SQLite `summaries` table (2,376 rows on Erik's machine) besides the JSON sidecars; the store takes a database URL and skips indexing when no provider directory exists.

Verification: `HolyArchiveModeTests` (23), `HolyArchivePresentationTests` (6), `HolyArchiveRenderSmokeTests` (1) green alongside the board suites (30). The render test draws sessions, child, transcript, and research faces from a hermetic fixture; set `TEST_RUNNER_HOLY_ARCHIVE_RENDER_DIR` to keep the PNGs.

Not built (reasons): the TUI's list is limited to the sessions Holy has indexed — the startup pass covers the last 48 hours, so "full reindex" from the reindex menu is what brings all 2,461 parents in; summaries appear once that pass and the import run. Open until Erik's production pass.

### Addendum (2026-09-02 15:35): embedding failures on Erik's first production pass

The installed app raised "Archive update completed with 946 failure(s): … OpenAI embeddings failed with HTTP 400: maximum input length is 8192 tokens". `HolyArchiveEmbeddingInputBounds` now clips inputs at 8,192 × 2 characters (the dense, code-heavy case) and the OpenAI provider halves every input and retries when the API still refuses one as too long; `HolyArchiveEmbeddingBoundsTests` (3) pin the bound, the verdict match, and the halving floor. Chunks that failed earlier stay unembedded until the next update or "generate missing embeddings" from the reindex menu.
