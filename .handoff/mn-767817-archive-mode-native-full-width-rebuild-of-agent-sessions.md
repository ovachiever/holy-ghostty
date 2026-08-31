---
workflow: 2
manna: mn-767817
track: mn-9a97cc
source: Erik ratified inline 2026-08-31 (One Ledger Two Faces); see track mn-9a97cc
base_commit: 0c6ba8bc635e3fcd76909c5e163e48fa53fa6e85
scope: 'Archive mode: native full-width rebuild of agent-sessions'
inputs:
- Erik ratified inline 2026-08-31 (One Ledger Two Faces); see track mn-9a97cc
binding: sha256:e34183f57a02878888344381be3af9b15bdefacf0e4cd1fc0260cf03a4184f26
---

# Handoff: Archive mode: native full-width rebuild of agent-sessions

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-767817
```

## Scope

Archive mode: native full-width rebuild of agent-sessions

## Inputs

- Erik ratified inline 2026-08-31 (One Ledger Two Faces); see track mn-9a97cc

## Work order

The workspace's third face: full-screen native archive — Erik's 2026-08-31 screenshot of the TUI is the ratified wireframe (session list top-left, detail right, researcher chat below, filter bar across). NOT a TUI overlay and NOT a WebView. Scope = complete feature parity with agent-sessions v0.9.0 per the ~200-behavior checklist sealed into this handoff (all five providers with their quirks; indexing pipeline incl. chunking, auto-tagging, titles; hybrid FTS+embedding search with the exact filter grammar, weights 0.3/0.7, cosine floor 0.35, match explanations, child-to-parent propagation, history; the eight-tool researcher with paging, spending caps, mid-turn rollback, citations carrying exact resume commands, auto-selected recommendation; annotations kept in Holy's own DB — Erik does not use agent-sessions' sidecars, no sync bridge). Storage: new tables in Holy's SQLite (FTS5 porter unicode61), embeddings as float32 blobs behind a pluggable embed provider (OpenAI/Voyage/Cohere, env keys, default text-embedding-3-small). Researcher/titles ride Holy's deep/fast routing roles (plan-first default chains, API models selectable). Fix the 13 known bugs listed in the checklist, do not port dead code. Resume = in-process spawn into the roster. Crash restore: RATIFIED — resolve in-process against this archive with agent-sessions' exact rules (48h window, 120s ambiguity, mtime staleness -> scoped reindex, exact-path match, children excluded); the external resolve CLI stays untouched on agent-sessions for other consumers. agent-sessions itself remains installed, untouched, working (legacy; still the index agent-do sessions reads).

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-767817`.
4. Commit with `Manna: mn-767817` and run `agent-do manna done mn-767817` only after the work is verified.

## Sealed input: feature-parity acceptance checklist

# agent-sessions → Holy native port: feature parity checklist

Generated 2026-08-29 from a read-only audit of /Users/erik/Custom-Coding/agent-sessions (v0.9.0, HEAD d52731c). Every line is a behavior the port must reproduce or explicitly decline.

I read every file listed plus the manna board, handoffs, and `.dev/session-prompts`. Full inventory below. Line receipts are `path:line`; all paths are under `/Users/erik/Custom-Coding/agent-sessions/`.

**Two headline facts before the list:** (a) `agent_sessions/__init__.py:3` declares `__version__ = "0.8.0"` while `pyproject.toml:8` declares `0.9.0` — `--version` under-reports. (b) Four designed features are on the board as **open, not built** (`.manna/issues.jsonl`) — they are in §11 as DESIGNED-NOT-BUILT, not as parity items.

---

# 1. PROVIDERS

## 1.0 Provider framework (contract every port must reproduce)
1. Registry is a decorator + insertion-ordered dict; **order matters for UI surfaces** — `providers/__init__.py:7-13`, import order pinned at `:48-55` (claude_code, codex, droid, cursor, opencode).
2. `get_provider(name)`, `get_all_providers()`, `get_available_providers()` (available = sessions dir exists) — `providers/__init__.py:16-31`; `is_available()` at `base.py:142-144`.
3. `discover_all_sessions()` merges all providers, sorts newest-first by `modified_time or created_time` — `providers/__init__.py:34-45`.
4. Abstract surface: `get_sessions_dir`, `discover_session_files`, `parse_session`, `get_resume_command` (abstract); overridable `discover_session_files_for_project` (returns **None = "cannot be narrowed"**, `[] = "narrowed, nothing here"`, `base.py:151-159`), `get_session_mtime` (default = file mtime, `base.py:166-177`), `load_sessions` (swallows per-file exceptions, `base.py:179-189`), `find_children` (`:196-202`), `get_task_invocations` (`:204-210`), `discover_sessions_fast` (id→mtime map keyed on `path.stem`, `:212-226`), `get_session_messages` (`:228-234`).
5. `fast_discovery: bool = True` class flag — providers with virtual paths/DB queries set False and are **skipped during startup quick sync** — `base.py:133-135`; consumed at `index/indexer.py:174-175`. Cursor `cursor.py:106` and OpenCode `opencode.py:121` set False.
6. Shared meta-message skip list `_SKIP_PREFIXES` (`base.py:10-20`): `[Request interrupted`, `<local-command-caveat>`, `<command-name>`, `<command-message>`, `<command-instruction>`, `<system-reminder>`, `<system-notification>`, `[COMPACTION CONTEXT`, `<ultrawork-mode>`.
7. `find_first_real_prompt` — first user message that isn't a skip-prefix **and is ≥20 chars**, else first message — `base.py:23-42`.
8. `find_last_real_response` — last non-empty, non-skip-prefix assistant message, else last — `base.py:45-64`.
9. `detect_automated_session(first_prompt)` → `(bool, type)`, shared by all providers, inspecting first 500 chars — `base.py:67-117`. Types: `system-notification`, `command-message`, `command-instruction`, `command-caveat`, `ultrawork-mode`, `search-mode`, `analyze-mode`, `system-directive`, `compaction-context`, `ci-dispatch` (`[GAS TOWN]`, `polecat dispatched`, `gt boot|gt prime|gt hook`, ``run `gt hook` ``), `subagent-continuation` ("summarize the task tool output above").
10. Unified `Session` dataclass fields: id, harness, raw_path, project_path, project_name, title, first_prompt, last_prompt, last_response, created_time, modified_time, is_child, child_type, parent_id, model, tool_calls[], tokens_used, summary, content_hash, extra{} — `models.py:9-47`. **`tokens_used` is never populated by any provider; no provider extracts cost.**

## 1.1 Claude Code (`providers/claude_code.py`)
- Identity: name `claude-code`, display `Claude Code`, icon `🧠`, color `cyan` — `:148-151`.
- Store: `~/.claude/projects/` (`:15`) **plus every `~/.claude-*/projects`** alternate config root (e.g. `claude-1m` via `CLAUDE_CONFIG_DIR`) — `_all_claude_sessions_dirs()` `:18-30`.
- Discovery: `*.jsonl` under each project dir of each root — `:156-173`.
- Scoped discovery: `encode_project_dir(cwd)` replaces every non-alphanumeric byte with `-` (lossy one-way; `decode_path` at `:34-36` is the inverse guess) — `:39-48`, `:175-183`.
- Parse (`:226-400`): reads JSONL line-by-line; skips `file-history-snapshot` and `progress` types (`:268-269`); from first `user` row takes `cwd`, `version`, `gitBranch`, `sessionId`; **`isSidechain` is the authoritative sub-agent flag** (`:281-283`, applied `:331-334`, child_type defaults to `"sidechain"`); model taken from first `assistant` row's `message.model` (`:286-289`); created_time from first message `timestamp` ISO (Z→+00:00).
- Content extraction handles string **and** list content blocks; drops `<system-reminder>`; renders `tool_result` blocks as `(tool_result: <first 50 chars>...)` for assistant only (`text_only=True` for user) — `:51-72`, used `:305-310`.
- Fallback sub-agent detection `detect_worker_session(first_prompt, project_dir)` — `:75-141`. Rules in order: automated-session types; `warmup`; `torus loop` → `torus-loop`; `autopilot` + ("no human review"|"no questions"); `@spirit.md`/`@wheel.md` → `torus-orchestrated`; path contains `merkabah-workers` → `merkabah-worker-N`; `torusv3-workers` → `torusv3-worker-N`; `# worker prompt` + (torusv3|one task); path `ophanim` or `@vision.md`+`@altar.json` or `# wings.md`+`one task` → `ophanim-worker`; prompt starts `# Worker Prompt` → `worker`; `subagent_type` regex → captured type else `task-subagent`.
- Title: first line of first prompt, 80 chars — `:341-344`.
- Returns None for sessions with zero messages — `:327-329`.
- Metadata cached in `MetadataCache` keyed on file path + mtime; cached fields truncated to 2000 chars each — `:360-377`; cache-hydrated Session at `:185-224` (extra = version, git_branch).
- **Resume command** `:402-423`: walk `raw_path.parts` for a `.claude-<suffix>` component; (1) if `~/.claude-<suffix>/.resume-cmd` exists, `"<file contents> --resume <id>"`; (2) else `"claude-<suffix> --resume <id>"`; (3) default `"claude --resume <id>"`. Note the stale comment at `:419-421` claiming `cmd_browse` uses `shell -ic` — it does not (`main.py:32-35`).
- `get_task_invocations` scans for `"name":"Task"` in assistant rows and extracts `subagent_type`, `timestamp`, `description` — `:425-469`.
- `find_children`: match child_type == subagent_type **and** created within 60s of the Task call; fallback = same project_path and modified within parent's 2h window — `:471-506`.
- `get_session_messages`: re-parses JSONL, message id = row `uuid` else `<session>_<n>`, **ISO-string timestamps** — `:508-545`.

## 1.2 Codex (`providers/codex.py`)
- Identity: `codex` / `Codex` / `✦` / `yellow` — `:262-265`.
- Store: `~/.codex/sessions/`, recursive `rglob("*.jsonl")` sorted — `:15`, `:270-275`.
- **Extra sidecar**: `~/.codex/session_index.jsonl` read once (`lru_cache`) for `thread_name` titles keyed by session id — `:16`, `:66-90`, applied `:344`.
- Parse (`_parse_codex_file` `:124-255`) understands four row types: `session_meta` (payload wins when `payload.id == path.stem`; otherwise first-seen, then **locked**, `:152-166`), `turn_context` → model (`:168-171`), `event_msg` with `user_message`/`agent_message` → primary messages (text from first non-empty of `text|content|message|delta`, `:37-43`, `:173-194`), `response_item` → `function_call` names collected into `tool_calls` set (`:202-205`) and `message` blocks → **fallback** transcript using `input_text` for user / `output_text` for assistant (`:206-226`).
- Fallback messages used only when no `event_msg` messages exist — `:237-238`.
- Timestamps: modified_time = max row timestamp; created_time from session_meta timestamp else first message epoch — `:146-148`, `:240-246`. Message timestamps stored as **epoch seconds** (`_parse_epoch_seconds`, `:29-34`).
- **Explicit sub-agent metadata** `_extract_subagent_context` `:93-121`: `source.subagent.thread_spawn` → `parent_thread_id`, `agent_nickname`, `agent_role`; falls back to top-level `agent_nickname`/`agent_role`; if child without parent, uses `forked_from_id` (**fork lineage**); child_type = agent_role → agent_nickname → `"subagent"`.
- `extra`: originator, cli_version, model_provider, agent_nickname, thread_name — `:364-370`.
- Session id comes from `session_meta.id`, **not the filename stem** — `:332` (this is why incremental indexing matches on file_path, §2.4).
- **Resume**: `codex resume <id>` — `:414-415`.
- `find_children`: strict `parent_id == parent.id` — `:417-428`.

## 1.3 Droid / FactoryAI (`providers/droid.py`)
- Identity: `droid` / `Droid` / `🤖` / `green` — `:55-58`.
- Store `~/.factory/sessions/<project>/*.jsonl` — `:15`, `:63-76`.
- Sidecar `<session>.settings.json` supplies `model` — `:118`, `:144-150`; path kept in `extra["settings_path"]`.
- Row types: `session_start` → title (`title` or `sessionTitle`, 80 chars) + `cwd`; `message` → role/content + first timestamp — `:161-190`.
- Sub-agent detection: title starts with `"# Task Tool Invocation"` (`SUBAGENT_TITLE_PREFIX` `:16`), type from `Subagent type: <x>` regex — `:166-170`; else `detect_automated_session` — `:210-215`.
- Session id = `path.stem` — `:249`.
- **Resume**: `droid --resume <id>` — `:268-269`.
- `get_task_invocations` (only matches compact `'"name":"Task"'`, no-space form) `:271-317`; `find_children` identical 60s/2h logic to Claude Code — `:319-355`.
- `get_session_messages` yields ISO-string timestamps — `:357-392`.

## 1.4 Cursor (`providers/cursor.py`)
- Identity: `cursor` / `Cursor` / `⌘` / `blue`, **`fast_discovery = False`** — `:102-106`.
- Store: `~/Library/Application Support/Cursor/`; DB `User/globalStorage/state.vscdb`; workspaces `User/workspaceStorage` — `:19-21`.
- **Connection strategy** `_get_db_connection()` `:27-52`: try `file:<db>?mode=ro` URI read-only, test with `SELECT 1`; on any sqlite error **copy the DB to a `tempfile.mkstemp(suffix=".vscdb")`** and connect to the copy; the temp path is cached in a module global and reused — `:24`, `:44-50`.
- Discovery: keys `LIKE 'backgroundComposerModalInputData:%'` in table `cursorDiskKV`, each turned into a **virtual path** `<CURSOR_DATA_DIR>/sessions/<id>.cursor` — `:111-141`.
- Parse `:187-337`: `composerData.richText` decoded from **Lexical rich-text JSON** (walks `root`, text nodes plus `@mention` names) — `:55-77`; project root guessed by regexing `"fsPath":"..."` out of the rich text then walking parents until `.git` or `package.json` — `:236-248`; `bcCachedDetails:<id>` supplies `model` and `lastResponse` (2000 chars) — `:254-267`.
- Cache key/mtime is the **global DB's mtime** (virtual files can't be stat'd) — `:193-202`, `:317`; `modified_time` for every Cursor session is the DB mtime — `:290`.
- Returns None if no first_prompt — `:274-275`. Automated-session detection promotes to child — `:277-283`.
- **Resume**: returns the pseudo-command string `"# Open Cursor and restore session <id>"` — `:339-341`. (Bug: `main.py:35` will `execvp("#", ...)`; see §11.)
- `find_children` always `[]` — `:343-345`. No `get_session_messages` override → **transcripts are empty for Cursor** (`base.py:228-234`); indexer synthesizes first_prompt/last_response pseudo-messages instead (`indexer.py:462-477`).

## 1.5 OpenCode (`providers/opencode.py`)
- Identity: `opencode` / `OpenCode` / `💻` / `magenta`, **`fast_discovery = False`** — `:117-121`.
- **Dual store** (module docstring `:1-8`): live SQLite `~/.local/share/opencode/opencode.db` **first**, pre-2026-migration file tree `~/.local/share/opencode/storage/{message,part,session}/` as archive fallback — `:22-31`.
- Read-only URI connect with `row_factory` — `:34-43`. **WAL-aware change stamp**: `max(db.mtime, db-wal.mtime)` because WAL writes don't touch the main file — `_db_stamp()` `:46-57`.
- `_db_session_mtimes()` caches `id → time_updated//1000` for all rows of `session`, invalidated on stamp change; on sqlite error returns the stale map rather than empty — `:130-147`.
- Discovery merges DB ids and legacy `storage/message/ses_*` dirs, both as **virtual paths** `storage/sessions/<id>.opencode` so file_path keys survive the migration — `:29-31`, `:149-167`.
- DB parse `:221-277`: `SELECT parent_id, directory, title, model, agent, time_created, time_updated FROM session`; ms→s divisions; model column is JSON `{"id","providerID"}` decoded by `_model_id` `:60-70`; transcript from `_db_transcript` `:489-544` which joins `part` rows (`type == "text"`) to `message` rows ordered by `time_created, id`, and picks up model/agent off assistant message JSON.
- Legacy parse `:279-384`: newest message-file mtime as the session mtime; per-message JSON with `time.created/.completed`, `path.root`/`path.cwd` for project, `modelID`/`agent`; content assembled from `storage/part/<message_id>/*.json` text parts (`_get_part_content` `:546-566`); session metadata (`parentID`, `title`, `directory`) located by scanning `storage/session/<hash>/<id>.json` (`_get_session_metadata` `:73-91`).
- Child detection: `is_child = bool(parent_id)`; child_type by prompt heuristic `_detect_child_type` `:94-110` → `prometheus` | `single-task` | `oh-my-opencode` | `file-analysis` | `worker`; otherwise automated-session detection — `:410-419`.
- Title: metadata title, else first non-`<tag>` line (scans lines 1-5) capped at 80 — `:421-437`.
- `get_session_mtime` override: DB map first, else newest legacy message file — `:586-599`. `discover_sessions_fast` merges both stores — `:601-619`.
- **Resume**: `opencode --session <id>` — `:568-569`. `find_children` by explicit `parent_id` — `:571-584`.

## 1.6 Per-provider display behavior
- Icon + color drive the filter bar chips (`app.py:422-426`), list-row icon (`ui/widgets.py:117-119,134`), detail-panel harness badge (`ui/widgets.py:429-432`), and `providers` CLI output (`main.py:52,66`).
- Sub-agent time-window heuristic differs by harness in the TUI: **OpenCode 24h, everything else 2h** — `app.py:589-592` and `:625-628`.

---

# 2. INDEXING

## 2.1 Schema (SQLite, `SCHEMA_VERSION = 4`, `index/database.py:9`)
DB path `~/.cache/agent-sessions/sessions.db` — `database.py:10`.

| Table | Purpose | Receipt |
|---|---|---|
| `schema_meta` | version ledger (MAX(version) read) | `:241-245`, `:186-199` |
| `index_meta` | key/value: `annotations_synced_at`, `resolve_reindex:<harness>:<path>` claims | `:247-250`, `indexer.py:558`, `resolve.py:94-96` |
| `sessions` | id, harness, project_path, project_name, timestamp, timestamp_end, is_child, parent_id (FK self, ON DELETE SET NULL), child_type, message_count, turn_count, first_prompt_preview, last_response_preview, file_path, file_mtime, indexed_at, auto_tags(JSON) | `:252-271`; 5 indexes `:273-277` |
| `messages` | id, session_id (FK CASCADE), role, content, timestamp, sequence, has_code, tool_mentions(JSON) | `:279-292` |
| `chunks` | id, session_id, message_id, chunk_index, chunk_type, content, metadata(JSON), embedding(BLOB), embedding_model, created_at | `:294-309` |
| `semantic_searches` | query, result_count, top_session_ids(JSON), search_time_ms, timestamp — **every search is logged** | `:311-318`, writer `:1176-1191` |
| `project_stats` | project_path PK, project_name, total/parent/child sessions, first/last_session_time, harness_counts(JSON), total_messages, common_tags(JSON), updated_at | `:320-332`, writer `:1123-1174` |
| `summaries` | session_id PK, summary, model, content_hash, created_at | `:334-341` |
| `annotations` | session_id, timestamp, type, value, source(default 'hook') | `:343-354` |
| `chats` | id, title, created_at, updated_at, backend, model, state_json, metadata | `:208-219` |
| `chat_messages` | chat_id FK CASCADE, sequence, role, content, tool_call_json, tool_output_json, cited_session_ids, created_at; UNIQUE(chat_id,sequence) | `:221-236` |
| `messages_fts` | FTS5 external-content over `messages.content`, tokenizer `porter unicode61 remove_diacritics 1` | `:359-364` |
| `sessions_fts` | FTS5 over `first_prompt_preview, project_name, auto_tags`, tokenizer `porter unicode61` | `:366-373` |
| 6 triggers | `messages_ai/ad/au`, `sessions_ai/ad/au` keep FTS in sync | `:376-411` |

**Migrations**: v0→full create (`:138-140`); v1→v2 adds `last_response_preview` + rebuilds both FTS indexes (`:173-184`); v2→v3 adds `annotations` + 2 indexes (`:157-171`); v3→v4 adds `chats`/`chat_messages` (`:153-155`). `_row_to_session` tolerates a v1 row missing `last_response_preview` (`:1433-1438`).

## 2.2 Chunking (`index/chunker.py`)
- `TARGET_TOKENS = 400`, token estimate = `len//4`, `SUMMARY_PREVIEW_CHARS = 200` — `:31-32`, `:41-43`.
- Three chunk types, always in this order — `chunk_session()` `:240-268`:
  1. **summary chunk** (index 0, `message_id=None`): "Project / Path / Title / First prompt (200 chars) / Tools used" + metadata {chunk_type, session_id, project_name, harness, tools} — `:56-110`.
  2. **turn chunks**: messages formatted `[role]: content`, packed until >400 est. tokens, never splitting a message; metadata carries `message_ids[]` and `token_count` — `:162-238`.
  3. **tool_usage chunks**: one per regex hit of `agent-do\s+(\S+)(?:\s+(.+?))?$` (MULTILINE, `:36-39`), content = `Tool: agent-do <t>` + `Command:` + `Context:` (±200 chars around the match); metadata carries `tool: agent-do-<t>` and `command` — `:112-160`.
- `extract_tool_mentions` de-dupes agent-do tool names for the summary chunk — `:45-54`.

## 2.3 Auto-tagging (`index/tagger.py`) — complete rule list
Tags are computed per session over title + first_prompt + last_prompt + last_response + all message content (`:145-168`), scored, sorted, **top 15 kept** (`:201-204`).
- **TOOL_PATTERNS, +2 each hit** (`:13-35`): `agent-do <x>` → `tool:agent-do-<x>`; `git (commit|push|pull|rebase|merge|branch|checkout)` → `tool:git`; `npm (install|run|test|build|start)` → `tool:npm`; `docker (build|run|compose|push|pull)` → `tool:docker`; `pytest` and `python -m pytest` → `tool:pytest`; `rg`/`ripgrep` → `tool:ripgrep`; `lsp_*` → `tool:lsp`; `ast_grep` → `tool:ast-grep`; plus `tool:grep`, `tool:find`, `tool:ls`, `tool:cat`, `tool:sed`, `tool:awk`, `tool:jq`, `tool:curl`, `tool:wget`, `tool:vim` (vim|vi), `tool:tmux`, `tool:vscode` (vscode|code).
- **ACTIVITY_PATTERNS, +1.5 once each** (`:38-49`): debugging, implementing, refactoring, testing, documenting, reviewing, optimizing, deploying, migrating, integrating — each with its own verb alternation list.
- **TECH_PATTERNS, +1 per occurrence** (`:52-127`): frontend (react, vue, angular, svelte, nextjs, nuxt, astro); languages (python, javascript|js, typescript|ts, ruby, java, go|golang, rust, cpp, csharp, php); databases (postgres, mysql, sqlite, mongodb, redis, firebase, dynamodb); ORMs (prisma, drizzle, typeorm, sqlalchemy, sequelize); testing (jest, vitest, mocha, rspec, unittest); build (webpack, vite, esbuild, rollup, pnpm, yarn); cloud (cloudflare, aws, azure, gcp, vercel, netlify, heroku, docker, kubernetes|k8s); frameworks (express, fastapi, django, rails, flask, hono, fastify, graphql, rest); other (git, ai|llm|gpt, api, auth, caching, search, indexing).
- **+0.5 each**: `project:<lowercased project_name>`, `harness:<lowercased harness>` — `:191-199`.

## 2.4 Index pipelines (`index/indexer.py`)
- **`full_reindex(progress_callback, metadata_only=False)`** `:50-126`: enumerate every available provider's files, parse, index, collect per-project aggregates, then `_apply_parent_links`, `_update_all_project_stats`, `_sync_annotations`; stats = sessions_indexed, messages_indexed, chunks_created, projects/annotations, time_ms.
- **`incremental_update(max_age_hours=None)`** `:128-243`: loads `(file_mtime, indexed_at)` keyed **both** by session id and by `file_path` (`:156-162`) — the file_path key is what stops Codex re-indexing every launch; skips `not fast_discovery` providers when `age_cutoff` is set (startup quick sync, `:174-175`); **backlog rule**: if a provider has more files on disk than DB rows, the age cutoff is ignored so a newly added provider backfills once (`:178-197`); change test is `file_mtime > indexed_at` (`:199-201`).
- **`index_paths(provider, paths)`** `:245-322`: scoped pass — never enumerates the store, never loads all rows; freshness read via `get_session_rows_by_file_paths`; **deliberately skips annotation sync** (`:254-256`).
- **`_index_session`** `:324-450`: previews truncated to **200 chars (first_prompt) / 500 chars (last_response)** with `"..."` suffix (`:345-355`); `turn_count` = count of user messages (`:343`); `timestamp` = created_time else now; `timestamp_end` = modified_time; **parent_id only written if the parent row already exists** (FK safety, `:360-365`); on non-metadata-only passes it deletes then re-inserts messages and chunks (`:387-389`); per-message `has_code` = content contains ` ``` ` or `def ` or `function ` (`:401`); `tool_mentions` = JSON list of `agent-do (\w+)` captures (`:403-407`); embeddings generated inline when available (`:423-424`); `embedding_model` stamped `text-embedding-3-small` (`:436`).
- **`_get_session_messages`** `:452-478`: delegates to provider; if empty, synthesizes a 2-message pseudo-transcript from first_prompt/last_response (this is how Cursor gets any indexed content).
- **`_apply_parent_links`** `:488-495` backfills `parent_id` after all rows exist so ordering never matters.
- **`_update_all_project_stats`** `:497-545`: per project_path — total/parent/child counts, min/max created timestamps, harness_counts dict, total_messages, and **`common_tags` = top 10 auto_tags by frequency**, updated_at.
- **`_sync_annotations`** `:547-578`: globs annotation files, skips any whose mtime ≤ `index_meta.annotations_synced_at`, upserts changed ones, stamps the marker only when something changed.

## 2.5 Titles / summaries (`cache.py`)
- Model `gpt-5.5` (`SUMMARY_MODEL` `:18`), client timeout **60 s** (`:147`), input bounded to `MAX_TRANSCRIPT_CHARS = 80_000` head+tail with a `[... transcript truncated ...]` marker (`:19`, `:167-173`).
- Prompt asks for a **6-8 word past-tense title, no trailing punctuation**, with four few-shot examples; output stripped of quotes/period and **capped at 80 chars** — `:175-199`.
- Errors are stashed on the function object as `generate_summary_sync._last_error` and surfaced as a toast in the TUI — `:196`, `:204`, consumed `app.py:767-770`.
- Written to the `summaries` table with model/content_hash/created_at — `app.py:756-762`.
- **Legacy JSON cache migration**: on every load the app imports summaries from `~/.factory/session-summaries.json` and `~/.cache/agent-sessions/summaries.json` into the DB for sessions lacking one — `app.py:452-501`.
- `SummaryCache` (singleton, `cache.py:78-127`) and `MetadataCache` (singleton, `:22-75`) are both mtime/hash-invalidated JSON sidecars; `compute_content_hash` = md5 of `first_prompt[:500] + "|" + last_response[:500]`, first 12 hex chars — `:130-133`.

## 2.6 Embeddings (`index/embeddings.py`)
- Model `text-embedding-3-small`, 1536 dims, `BATCH_SIZE = 100` — `:19-21`.
- Optional-import gate `HAS_OPENAI = importlib.util.find_spec("openai") is not None` — `:14`; `available` also requires `OPENAI_API_KEY` — `:32-52`.
- Client timeout **30 s** with an explicit rationale comment (SDK default 600 s would look like a hang) — `:45-48`.
- Storage format: raw `struct.pack('<n>f')` float32 BLOB — `:58-65`.
- Per-text truncation to `8000 tokens × 3 chars` — `:71-75`; batch builder caps a batch at **250 000 estimated tokens** and then sub-batches by count — `:97-127`.
- `embed_query` / `embed_query_blob` — `:130-149`. Failures log and return `None`s (degrade, never raise).
- Backfill CLI: `--generate-embeddings` (see §6.5).

## 2.7 Sidecar / on-disk paths (complete)
| Path | Written by |
|---|---|
| `~/.cache/agent-sessions/sessions.db` | `database.py:10` |
| `~/.cache/agent-sessions/summaries.json` | `cache.py:16` |
| `~/.cache/agent-sessions/metadata.json` | `cache.py:17` |
| `~/.local/share/agent-sessions/annotations/<session_id>.json` | `annotations.py:14` |
| `~/.factory/session-summaries.json` (legacy read-only) | `app.py:467` |
| `~/.codex/session_index.jsonl` (read-only) | `codex.py:16` |
| `~/.claude-<x>/.resume-cmd` (read-only) | `claude_code.py:414` |
| temp `*.vscdb` copy | `cursor.py:45` |

---

# 3. SEARCH

## 3.1 Query language (`index/search.py`)
- `#tag:<name>` extracted first, repeatable, removed from the text — `:135-136`.
- `harness:` `project:` `after:` `before:` parsed by `_MODIFIER_RE` `:52-55`, which supports **quoted values** (`"..."`/`'...'`) and requires a non-space boundary before the key; values unquoted by `_strip_quotes` `:95-99`.
- Date values via `search.py:72-107`: relative `\d+[dhwm]` (h/d/w/m where m = 30 days), ISO, then `%Y-%m-%d`, `%Y/%m/%d`, `%m-%d`, `%m/%d` (year defaulted to current).
- **Natural-language cleanup**: five regex shapes (`_NATURAL_QUERY_PATTERNS` `:57-92`) extract the `topic` from phrasings like "find me the sessions where we worked on X", "which sessions did we fix X", "sessions where we built X", "worked on X", "find the sessions about X"; residual cleanup strips leading "please/find/show/list/get/pull up/look up/look for/search for (me)" and "(the) sessions about/on/for/with" — `:102-129`.
- Filters-only query (no text left) → returns **all matching sessions by recency with score 1.0** — `:266-277`.

## 3.2 FTS path
- `_build_fts_query` (`database.py:1537-1564`): tokenize `[a-zA-Z0-9]+`, lowercase, strip a 46-word stop list, **AND-join quoted terms**; if stop-word removal leaves <2 terms while the raw query had ≥2, the raw tokens are restored (preserves "ctrl+A"); empty → `'""'`.
- `search_messages_fts` (`:1566-1628`): `MIN(rank)` grouped per session (comment at `:1591-1592` explains `rank` is used instead of `bm25()` because bm25 breaks with GROUP BY on SQLite ≥3.51); a **second query fetches `snippet(messages_fts, 0, '', '', '...', 24)`** per session for the "why this matched" text.
- `search_sessions_fts` (`:1630-1666`): metadata index, `snippet(sessions_fts, -1, ...)` across all three columns.
- Both accept harness/project/after/before/tag filters, compiled by the shared `_build_session_filter_clauses` (`:658-700`) — project matches `project_name` **or** `project_path` substring case-insensitively; after/before compare `COALESCE(timestamp_end, timestamp)`; each tag becomes an `id IN (SELECT ... annotations WHERE type='tag' AND value=?)` subquery.

## 3.3 Semantic path
- Loads **all** chunk embeddings once into a pre-normalized numpy matrix with parallel session-id and chunk-id lists — `search.py:194-222`; `invalidate_cache()` at `:505-509`.
- Cosine via `matrix @ query_vec / (norms * qnorm)`; **absolute threshold `MIN_COSINE = 0.35`** — `:394`, `:402-415`; best chunk per session retained; the winning chunk's content becomes the snippet with source `"semantic"` — `:420-435`.
- Candidate pre-filtering is applied inside the loop when metadata filters produced a candidate set — `:410-411`.

## 3.4 Ranking / fusion
- Each side is min-max normalized into **[0.5, 1.0]** (`FLOOR = 0.5`) — `_normalize_scores` `:478-492`.
- Default weights **fts 0.3 / semantic 0.7**, overridable per call — `:177-187`, `:279-289`.
- Both present → weighted sum, snippet from whichever score is higher; one present → `score × 0.5` — `_combine_scores` `:437-476`.
- Global drop threshold `score >= 0.2` — `:290`; then candidate-set filter, then sort desc, then limit.
- Result carries `session_id, score, fts_score, semantic_score, match_snippet, match_source` where source ∈ `keyword` | `metadata` | `semantic` — `:13-20`, `:350-363`.
- Escape hatches: `search_fts_only()` `:304-316`, `search_semantic_only()` `:318-329`; `has_embeddings` / `embeddings_available` properties `:511-517`.

## 3.5 Search history
- Every `search()` call (including zero-result and filters-only paths) logs query, result count, top-10 session ids, elapsed ms into `semantic_searches` — `:261-262`, `:274-276`, `:298-300`. Surfaced by `--search-history` (§6.9).

## 3.6 Child→parent propagation & display
- TUI maps a matching child's score and snippet onto its **explicit parent** (`parent_id`, not a heuristic) taking the max — `app.py:1588-1612`; matched children are listed in the bottom pane (§4.6).
- Legacy in-file scanner (`search.py:110-250`: `search_session_file`, `search_sessions`, `SearchEngine`, `parse_search_query`) still exists and is unit-tested but is **dead in the app path** — `app.py:24` imports `search_sessions` and never calls it.

---

# 4. TUI

## 4.1 Layout / widget tree
`compose()` `app.py:307-325`: `Header(show_clock=True)` → Horizontal[ Vertical#left-container( Static#filter-bar, Input#search-input, Vertical#parent-container(Static#parent-header, ListView#parent-list), Vertical#subagent-container(Static#subagent-header, ListView#subagent-list, ChatPanel#chat-panel) ), Vertical#detail-container( Vertical#loading-container(LoadingIndicator, Static#loading-status), SessionDetailPanel#detail-panel ) ] → `Footer()`.
Geometry: left 55% / detail 45%, parent 60% / subagent 40% of the left column — `ui/styles.py:8-28`. Chat fullscreen uses `layer: chat-overlay; dock: top; 100%×100%` — `app.py:78-86`.

## 4.2 Full BINDINGS table (`app.py:177-208`)
| Key | Action | Label / notes |
|---|---|---|
| `q` | quit | Quit |
| `enter` | copy_command | copies resume command via `pbcopy` only (`:1726-1736`) |
| `r` | resume_session | exits app with `(cmd, project_path)` |
| `tab` | switch_pane | **priority=True**; parent ↔ sub-agent only |
| `shift+tab` | focus_detail | **priority=True**; toggles left pane ↔ detail |
| `escape` | back_to_list | layered "back" (§4.9) |
| `/` (`slash`) | activate_search | search box, or in-transcript find |
| `f` | cycle_filter | provider filter cycle |
| `s` | cycle_search_sort | relevance → newest → oldest |
| `i` | reindex | incremental reindex |
| `?` | toggle_chat | open/refocus chat |
| `z` | toggle_chat_fullscreen | |
| `ctrl+r` | toggle_chat_history | "Recent" |
| `ctrl+h` | toggle_chat_history | hidden duplicate (`show=False`) |
| `ctrl+y` | copy_chat | "Copy All" |
| `ctrl+n` | new_chat | **declared twice** — `new_chat` at `:199` then `add_note` at `:199`/`:199`; Textual resolves the later `ctrl+n → add_note`, and `check_action` gates which is live (test pins `active_bindings["ctrl+n"].action == "new_chat"` when chat is focused, `tests/test_chat_tui.py:186`) |
| `t` | show_all_messages | Transcript |
| `y` | copy_transcript | |
| `a` | select_all_transcript | "select all & copy", reports line count |
| `c` | copy_visible_message | message nearest scroll position |
| `ctrl+t` | add_tag | |
| `ctrl+n` | add_note | |
| `j`/`k`/`down`/`up` | cursor_down/up | hidden |
| `home`/`end` | cursor_home/end | hidden, priority |
| `pageup`/`pagedown` | cursor_page_up/down | hidden, priority; page = `height - 2` |

**Dynamic binding visibility** `check_action()` `:210-248`: chat actions (`toggle_chat_fullscreen`, `toggle_chat_history`, `copy_chat`, `new_chat`) only when chat is open **and** focused; transcript copy actions only when a chat item has focus or the detail panel is in transcript mode; browser actions (`copy_command`, `resume_session`, `switch_pane`, `focus_detail`, `activate_search`, `cycle_filter`, `cycle_search_sort`, `reindex`, `show_all_messages`, `add_tag`, `add_note`) are **suppressed while chat has focus**; `cycle_search_sort` requires `_search_mode`.

**Widget-scoped bindings**
- `TranscriptArea` (`ui/widgets.py:68-76`): `c`/`y` copy all, `a` select-all, `escape` back, `/` find, `n` next match, `shift+n` prev match. Its `_on_key` **lets every printable key bubble to app bindings while read-only** (`:78-81`).
- `TranscriptFindBar` (`ui/widgets.py:87-91`): `escape` close, `down` next, `up` prev.
- `ChatTranscriptArea` (`ui/chat_widgets.py:152-160`): `ctrl+c`/`super+c` copy selection, `escape`, `z`, `ctrl+r`, `ctrl+h`, `ctrl+y`, `ctrl+n`.
- `ChatInput` and `ChatPanel` intercept `z`, `ctrl+r`/`ctrl+h`, `ctrl+y`, `ctrl+n` before Input insertion and re-post them as messages — `chat_widgets.py:251-272`, `:463-484`.

## 4.3 Filter bar
- Hidden entirely when ≤1 provider is available — `app.py:406-408`.
- Renders `Filter: [●All] [○🧠Claude Code] [○✦Codex] …  | N sessions`, filled bullet = active, provider color applied — `:412-432`.
- `f` cycles `None → each available provider → None`, re-filters, rebuilds the list, rewrites the parent header (`"🧠 Claude Code (123 sessions)"` or `"All Sessions (500/78927 newest first)"` when >500), resets selection to index 0 and focuses the parent list — `:643-687`.
- **There is no date filter, tag filter, or has-note filter in the bar** — those exist only as query syntax (§3.1).

## 4.4 Session list row anatomy (`ui/widgets.py:112-148`)
`MM-DD HH:MM` (cyan) + `" │ "` + `<icon> ` + `project_name[:12]` left-padded to 12 (green) + `" │ "` + optional `(<child_count>) ` in bold yellow + description.
- `prefix_width = 36` constant (`:139`), plus the child-count string length; description width = `max(20, terminal_width - prefix)`; truncation adds `...` (`truncate()` `:52-56`).
- Description prefers the AI summary (**bold white**), falls back to first_prompt → title → `(no prompt)` (**dim white**) — `:121-129`; newlines flattened.
- Rows rebuild on resize (`on_resize` `:107-110`) and on summary arrival (`refresh_text()` `:150-153`, called from `app.py:1314-1320`).
- List is capped at **500 rows** for performance (`MAX_DISPLAY`, `app.py:538`, also `:1652`) and mounted in one batch (`:546-551`).

## 4.5 Sub-agent list (`ui/widgets.py:156-193`)
`★ ` (yellow) or two spaces + `child_type` padded to 18 (cyan bold) + `" │ "` + first_prompt (white), prefix 27, floor 20. Container dims to `opacity: 0.5` when empty (`styles.py:102-104`, toggled `app.py:1329-1335`).

## 4.6 Search-results mode
- Parent header becomes `Search: <query> (N sessions, M matches · by relevance)` — `app.py:1643-1646`.
- Bottom pane retitles to `Matching Sub-agents (n)` and lists only children that themselves matched — `_update_search_results_list` `:1359-1379`.
- `s` cycles sort and re-renders with the label `by relevance` / `newest first` / `oldest first` — `:1622-1665`.
- Search runs in a worker thread with `limit=50` — `:1574-1578`.

## 4.7 Detail panel (`ui/widgets.py:412-552`)
Sections, in order: `━━━ Session Details ━━━`; **Harness** (icon + display name); **Type** `PARENT SESSION` (+ `Sub-agents: n`) or `SUB-AGENT` + `Agent: <child_type>`; **Title** (child→child_type, "New Session"/empty→project_name, truncated 50); **Path**; **Date** (`%Y-%m-%d %H:%M:%S` or `Unknown`); **Model**; **Session ID**; **Annotations box** (tags as `[name]` cyan badges on one line, then one line per note prefixed with `ts[:16]` T→space) — `:467-489`; **Search Match box** showing `Source: keyword|metadata|semantic` and the snippet — `:491-501`; **First Prompt box** (2000 chars, `... (truncated)`); **Last Response box** (2000 chars parent / **1000 child**) — `:522`; **Resume Command** rendered as `bold white on blue`; footer hint "Press Enter to copy | r to resume | Tab switch panes".
- Annotations are read live from the DB on every render (`SessionDatabase().get_annotations`, `:468-469`).

## 4.8 Transcript viewer
- `t` → toast "Loading transcript…", then a threaded loader — `app.py:774-820`.
- **DB-first with a quality gate**: uses indexed messages only if >50% have non-empty content, else re-parses via the provider (comment explains the Claude Code nested-content case) — `:784-801`.
- Streams into the panel in batches of 10 with a 10 ms yield — `:810-817`; header written first (`show_full_transcript_start` `ui/widgets.py:554-579`) with Session/Path/Messages counts and `(no messages found)` when zero; footer `━━━ End of Transcript ━━━` + `c copy all | / find | Escape back` (`:581-596`).
- Rendering: each message boxed as `┌─ [i] User ───…` green / `Assistant` magenta with `│ ` gutters and a 40-char rule — `build_message_text` `:598-626`. **Tool calls are not specially rendered** in the transcript; they arrive already flattened by providers as `(tool_result: …)`.
- Body is a read-only, soft-wrapped, no-line-number `TextArea` so the terminal's native selection/copy works — `:571-577`; content is set in one shot at the end (`:586-588`) and `_transcript_ready` flips true.
- Late batches after the user exits are **dropped**, not mounted — `write_message` `:290-300`.
- **Find-in-transcript**: `/` opens a docked bottom find bar (only when `_transcript_ready`, else warns "Transcript still loading…") — `app.py:1474-1491`, `ui/widgets.py:325-339`; live match recompute on every keystroke (`app.py:1667-1671`); matches are case-insensitive, **overlapping**, Unicode-casefold with a length-change fallback to `.lower()` — `find_all_matches` `ui/widgets.py:26-49`; selection applied via `offset_to_line_col` + `scroll_cursor_visible(center=True)` (`:381-393`); border title shows `Find`, `Find — no matches`, or `Find — match k/n` (`:395-406`); `n`/`Shift+N`/`Enter`/`↓`/`↑` cycle with wraparound (`app.py:1498-1510`, `:1673-1678`); `Escape` closes the bar and collapses selection (`:341-355`).

## 4.9 Escape / back stack (`app.py:1428-1472`), in strict priority order
1. find bar open → close find; 2. chat fullscreen → windowed; 3. chat open → close chat; 4. search input focused in annotation mode → cancel annotation and restore placeholder; 5. search input focused → cancel search; 6. transcript mode → **restore the exact pre-transcript detail view** (search-match variant included, `_restore_session_detail` `:822-841`) and refocus the list; 7. search mode → clear search; 8. detail focused → back to last left pane; 9. otherwise → quit.

## 4.10 Annotations UI
- `Ctrl+T` / `Ctrl+N` reuse the search input with placeholder "Enter tag name (e.g. breakthrough)…" / "Enter note text…" and set `_annotation_mode` — `app.py:1268-1291`.
- On submit: `save_annotation(session_id, mode, value, source="manual")` writes the JSON sidecar, then `db.upsert_annotations(...)` syncs to SQLite immediately, toast `Tag saved: …` / `Note saved: …`, placeholder restored, detail panel re-rendered — `:1686-1722`.
- Empty input → "Empty input, cancelled" warning — `:1690-1696`.
- Sidecar format: `{"session_id": ..., "annotations": [{ts, type, value, source}]}`; loader accepts both that shape and a bare list — `annotations.py:23-68`; timestamps are ISO-8601 UTC.
- The `#tag:name` / `#note text` **Claude Code UserPromptSubmit hook is documented but not shipped in this repo** (README:170); only the sidecar format and `source: "hook"` default exist (`database.py:349`).

## 4.11 Clipboard (`app.py:1031-1087`)
Chain: `pbcopy` → verify with `pbpaste` (byte-compare) → if `$TMUX` set, also `tmux load-buffer -w -` → if still not copied, Textual's OSC-52 `copy_to_clipboard`. Toast on success, `Failed to copy to clipboard` (error severity) otherwise. Note `action_copy_command` (Enter) **does not use this chain** — it calls `pbcopy` directly and falls back to a toast showing the command (`:1726-1736`).

## 4.12 Loading / progress / degraded states
- Startup overlay: `LoadingIndicator` + status text progressing "Syncing sessions…" → "Checking for new sessions…" → "Indexed N new sessions, loading…" / "Loading sessions…" — `app.py:321-323`, `:344-363`.
- Empty state renders "No sessions found!" plus every checked provider's icon, display name, and directory — `:378-385`.
- Toast durations: default **8 s**, errors **10 s**, overridable — `toast_timeout` `:156-160`, `notify` override `:168-175`.
- No-API-key path: one warning toast "OPENAI_API_KEY not set - summaries disabled" (3 s) and summaries silently disabled — `:716-719`; `HAS_OPENAI` gate at `:691-692`.
- Summary failures show the first error only, truncated to 200 chars — `:765-770`.
- Indexing failures toast `Indexing failed: <e>` at error severity — `:1310-1312`.
- **Focus rule**: background completions never steal focus if chat is open or an `Input` is focused — `_focus_after_background_load` `:391-400`.

## 4.13 Resume flow
`action_resume_session` `:1738-1745` → `app.exit(result=(cmd, project_path))` → `main.cmd_browse` `:25-35`: if the path is a directory, `os.chdir` + print `[cd <path>]`, print `[Resuming session...]\n<cmd>`, then `os.execvp(parts[0], parts)` after a **naïve `cmd.split()`** (no shlex; see §11).

## 4.14 Mouse
- List rows highlight on hover (`ParentSessionItem:hover`, `styles.py:90-92`).
- Detail panel supports **drag-to-scroll at the viewport edges**: `EDGE_ZONE = 5` lines, `SCROLL_INTERVAL = 0.03 s`, `SCROLL_BASE = 4` lines/tick with speed increasing toward the edge — `ui/widgets.py:199-267` (disabled in transcript mode).
- Chat: left-click a message jumps to its first cited session; **right-click (button 3) copies** the message — `chat_widgets.py:76-83`; left-click a tool-call widget expands/collapses it, right-click copies name+args+output — `:130-136`; clickable `Copy` / `New` / `Recent` / `Clear` labels in the chat control row — `:378-396`.

---

# 5. RESEARCH / CHAT AGENT

## 5.1 Model & backend
- Defaults `backend="openai"`, `model="gpt-5.6"`, `reasoning_effort="xhigh"` — `chat/persistence.py:10-12`; `reasoning_effort()` currently **always returns the default**, ignoring per-chat metadata (`:75-76`), though `set_reasoning_effort` exists (`:78-92`).
- Env override `AGENT_SESSIONS_CHAT_MODEL` wins over the chat's stored model — `chat/backend.py:86`.
- Uses the OpenAI **Responses API** with `instructions=system`, `tools`, `tool_choice="auto"|"none"`, `reasoning={"effort":…, "summary":"auto"}`, `previous_response_id` (server-side conversation state), `store=True`, `parallel_tool_calls=True`, **`truncation="auto"`** (the fix for `context_length_exceeded`) — `backend.py:85-96`. State persisted is just `{"response_id": …}` (`:116`).
- Missing key raises `RuntimeError("OPENAI_API_KEY is not set")` — `:65-66`. `AnthropicBackend` is a declared-but-unimplemented stub — `:121-125`.

## 5.2 System prompt (`chat/prompts.py:7-36`)
Injects today's date and `$USER`. Seven numbered rules: resolve scope first via `list_projects`/`list_tags`; prefer `find_sessions` for metadata questions and `search_sessions` for content; always use the provided **citation label**, never invent IDs; assess completion by reading messages with `last_n`/`around_query` and continuing paged results via `next_start`; surface count discrepancies; say "ended mid-task" rather than over-claiming; **for every cited session emit its exact `resume_command` verbatim in a fenced code block**, and say so when it is null.

## 5.3 Tools (all 8, `chat/tools.py:54-145`) — strict JSON schemas, all properties required, nullable via type unions (`_nullable` `:42-51`)
1. **`today()`** → `{date, timestamp}` — `:219-224`.
2. **`list_projects(after, before, harness)`** → `{projects:[{project_path, project_name, total_sessions, parent_sessions, child_sessions, first_session_at, last_session_at, harnesses[]}], count}`; aggregates live from `sessions`, not `project_stats` — `:226-235`, SQL `database.py:820-866`.
3. **`list_tags(prefix)`** → `{tags:[{tag,count}], count}` from annotation tags ordered by count — `:237-244`, `database.py:1307-1320`.
4. **`find_sessions(harness, project, after, before, tags, start)`** → paged `{sessions, count, total, next_start}` of session briefs — `:246-263`.
5. **`search_sessions(query, harness, project, after, before, tags, start)`** → same brief shape plus `score`, `match_source`, `match_snippet`; runs the full HybridSearch — `:265-299`.
6. **`get_session(session_id)`** → `{session: brief + child_ids[] + annotations[]}` — `:301-309`.
7. **`get_messages(session_id, role, last_n, around_query, start)`** → paged `{session_id, messages:[{id,sequence,role,timestamp,content,truncated:false}], count, total, next_start}`; **content is never truncated** — `:311-328`, `chat/rendering.py:27-45`. `around_query` returns ±4 messages around every LIKE hit, de-duplicated (`database.py:941-985`); `last_n` returns the tail in ascending order (`:987-1007`).
8. **`get_chunks(session_id, chunk_type∈{summary,turn,tool_usage}, start)`** → paged chunk payloads with metadata — `:330-345`.
- **Session brief** (`_session_brief` `:347-375`): session_id, short_id (8 chars), **citation_label** `[<harness>/<project> @ MM-DD HH:MM · 8charid]` (`:395-398`), **resume_command** obtained from the real provider (never hand-assembled; `None` on failure) with a per-harness provider cache (`:377-393`), harness, project_name/path, started_at/ended_at (ISO to minutes), is_child, parent_id, child_type, message_count, turn_count, first_prompt_preview, last_response_preview, summary, and the union of auto_tags + annotation tags sorted.
- **Timestamp tolerance**: `format_timestamp` accepts epoch ints **and** ISO strings (Codex/OpenCode vs Claude Code/Droid) and passes unparseable strings through instead of erroring the tool call — `rendering.py:9-24`.
- **Paging**: `PAGE_CHAR_BUDGET = 200_000` chars per page, measured per item; **always returns at least one item** so an oversized entry can't stall the cursor; `next_start` is null on the last page — `tools.py:152-172`.
- Dispatch is by `_tool_<name>` lookup; unknown tool → `{"error": "Unknown tool: x"}`; any exception → `{"error": "<Type>: <msg>"}` (never raises into the loop) — `:210-217`.
- `collect_session_ids` walks arbitrary nested tool output collecting `session_id` values, de-duplicated in order — `:412-433`.

## 5.4 Turn loop, budgets, rollback (`chat/agent.py`)
- Unbounded tool rounds by design (pinned by `tests/test_chat_agent.py:145`).
- **Per-payload guard** `OUTPUT_GUARD_CHARS = 400_000`: a single oversized tool output is elided head+tail with an explicit `[... N characters elided … refetch with narrower arguments or the start cursor ...]` marker; **the full output is still persisted to the DB** — `:30`, `:44-57`, `:199`.
- **Per-turn budget** `TURN_TOOL_OUTPUT_BUDGET_CHARS = 500_000`: once the sum of guarded outputs crosses it, `allow_tools` flips false (`tool_choice="none"`) and a `developer` message `BUDGET_EXHAUSTED_NOTE` instructs the model to answer from gathered evidence and name what's unverified — `:35-41`, `:209-211`.
- **Turn rollback**: `turn_start_state` is captured before the first model call; on any mid-flight exception the chat's persisted `state_json` is rolled back to it, a readable error message (`Chat turn failed mid-flight: <Type>: <msg>` + tool-call count + rollback notice) is appended as an assistant message, and the turn returns normally with the retrieval work preserved — `:110-152`.
- Every step is persisted: user message, one assistant row per tool call (`name({args})` + raw `tool_call_json`), one `tool` row per output (`tool_output_json` + cited ids), final assistant text with cited ids — `:106`, `:173-198`, `:155-159`.
- Chat title auto-derived from the first user message (whitespace-collapsed, 57 chars + `...`, else "New chat") — `persistence.py:151-156`, applied `agent.py:102-104`.
- **`pick_recommended_session(text, cited_ids)`** `:60-83`: returns the cited session mentioned earliest in the answer text, matching either the full id or the 8-char short id; sessions that appear only in tool byproducts are never picked.

## 5.5 Chat UI (`ui/chat_widgets.py` + `app.py`)
- Panel replaces the sub-agent pane when open (header + list hidden) — `app.py:860-886`; closing restores them and the dimmed state.
- Structure: header (`Chat` / `Chat (new)` + status), hidden-by-default history `ListView#chat-history` (height 8, bordered), `ChatTranscriptArea#chat-scroll` (read-only selectable TextArea), control row (spacer, Copy, New, Recent, Clear), `ChatInput#chat-input` — `chat_widgets.py:234-249`; CSS `app.py:88-152`.
- Transcript rendering is plain text `You\n…` / `Assistant\n…` joined by blank lines, plus `refs: <8-char ids>` when cited — `:361-376`; auto-scrolls to end after refresh (`:358-366`).
- `ChatMessageWidget` / `ToolCallWidget` classes exist with citation-click, expand/collapse and copy support (`:25-137`) but `add_tool_event` / `add_tool_call` are **no-ops** (`:339-343`) — tool calls are not currently displayed in the panel.
- Running state disables the input and shows `thinking...` — `:293-295`; re-entrancy guarded by `_chat_running` (`app.py:1089-1096`).
- Turn runs on a worker thread; `_apply_chat_turn` appends the answer (or `(no response)`), refreshes the recent-chats list, and **auto-selects the recommended session in the parent list without stealing focus**, toasting `Selected <8char> · Esc then r to resume` (6 s) — `app.py:1108-1135`; child recommendations resolve to their parent (`:1128-1133`).
- Failures render as `Chat failed: <Type>: <msg>` in the panel — `:1137-1139`.
- History: `Ctrl+R`/`Ctrl+H` toggles the list (reloaded from DB each toggle); selecting a row loads that chat's messages and hides the list — `:984-990`, `:1145-1157`.
- `Ctrl+N` new chat clears id, input, and messages; `Ctrl+Y` copies the whole visible transcript; `z` fullscreen; `Escape` collapses fullscreen then closes; `?` re-focuses instead of closing — `:940-1016`.
- Clicking a citation opens that session in the browser: clears search, closes chat, selects the parent row, and for a child also selects it in the sub-agent list — `_show_session_from_chat` `:1163-1191`.
- `ChatInput` paste handler flattens multi-line pastes into one space-joined line — `chat_widgets.py:452-461`.
- **No streaming**: the answer appears when the turn completes (no token streaming anywhere in the chat path).
- **No delete-chat in the UI**: `db.delete_chat` exists (`database.py:1428-1431`) but nothing calls it; the `Clear` button clears the *input*, not the chat (`app.py:973-982`).

---

# 6. CLI (`agent_sessions/main.py`, entry points `agent-sessions` and `ais`, `pyproject.toml:44-46`)

1. **`browse` (default when no subcommand)** — `--harness/-H`, `--project/-p` — `:424-426`, `:473-480`; on exit performs chdir + execvp (§4.13).
2. **`providers [--status/-s]`** — plain list with ✓/✗ + icon + display name + name; with `--status` also prints path, status, and **parses every session** to print "N parent, M child" — `:38-66`.
3. **`search <query> [--harness] [--project] [--limit N=10]`** — prints "Found N sessions:" then per result: `<icon> <project> - <first_prompt_preview[:50]>`, `ID:`, `Score: %.2f`, and `Match (<source>): <snippet>` when present; "No matches found for: q" otherwise — `:69-104`.
4. **`cache clear|info`** — clear unlinks `summaries.json` and `metadata.json` and lists what it removed; info prints each path, entry count, and KB size, or "not found" — `:107-148`.
5. **`--reindex`** — full reindex with a 40-char `█/░` progress bar, then prints sessions/messages/chunks/projects indexed — `:151-178`. (Note: it prints `projects_updated`, a key `full_reindex` never sets — always 0, `:178`.)
6. **`--generate-embeddings`** — refuses with "❌ OpenAI API key not configured." when unavailable; otherwise backfills **chunks whose embedding IS NULL** in batches of 100 with a progress bar — `:181-249`.
7. **`--stats`** — total/parent/child session counts, message count, chunk count with/without embeddings, DB size in MB, and counts per harness from a **hardcoded list** `["claude-code","codex","droid","cursor","opencode"]` — `:252-293`.
8. **`--projects`** — top 20 rows of `project_stats` by session count: Project / Sessions / Messages / Last Activity — `:296-338`.
9. **`--search-history`** — last 20 rows of `semantic_searches`: Query(50) / Results / Time (ms) / Timestamp — `:341-382`.
10. **`--version` / `-v`** — prints `agent-sessions <__version__>` — `:446-449`.
11. **`resolve` / `resolve-batch`** — registered from `resolve.py` (§7) — `:440-442`, `:467-472`.
- **Dispatch precedence** `:451-480`: global flags beat subcommands (`--reindex` > `--generate-embeddings` > `--stats` > `--projects` > `--search-history` > providers/search/cache/resolve/resolve-batch/browse > default browse).
- **Exit codes**: everything except resolve returns None → exit 0 even on failure; `resolve`/`resolve-batch` `raise SystemExit(cmd_*)` returning 0 or 1 (§7).
- **JSON output** exists only for `resolve` and `resolve-batch`; all other commands are human-formatted text.

---

# 7. RESOLVE / CRASH-RESTORE (`agent_sessions/resolve.py`)

- `resolve --cwd --harness{claude|claude-code|codex|opencode} --near <unix s> [--window 172800] [--limit 5] [--no-reindex] [--json]` — `:403-438`.
- Name mapping both ways: `claude→claude-code`, identity for codex/opencode; output carries both `harness` and `runtime` — `:36-47`, `:369-400`.
- Matching: `is_child = 0`, exact `project_path == realpath(expanduser(cwd))`, `|COALESCE(timestamp_end,timestamp) - near| <= window`, sorted best-first — `_candidates` `:54-78`, realpath `:197`.
- `confidence`: `none` (no rows) | `exact` (sole candidate, or runner-up **>120 s** farther) | `ambiguous` (≤120 s gap) — `AMBIGUITY_SECONDS = 120`, `:358-366`.
- Output object keys: `matched, id, harness, runtime, project_path, resume_command, confidence, candidates[{id, timestamp_end, preview≤120}]` — `:226-232`, `:369-400`; `PREVIEW_CHARS = 120` `:28`.
- `resume_command` always from the provider's `get_resume_command` on a reconstructed `Session` — `:157-177`.
- Staleness rule: reindex when there are no rows, or the best row's `file_path` is missing / its on-disk mtime ≠ indexed `file_mtime` — `_is_stale` `:81-91`; suppressed by `--no-reindex`.
- Scoped refresh `reindex_provider` `:98-154`: asks the provider `discover_session_files_for_project(cwd)`; **None ⇒ unscopeable ⇒ whole-provider `incremental_update`** behind a claim; otherwise a per-cwd claim then `index_paths`. A cwd with no files on disk burns no claim (`:144`).
- Reindex claim window `REINDEX_MIN_INTERVAL_SECONDS = 120` implemented as a single conditional upsert into `index_meta` — exactly one winner per scope per interval — `:33`, `database.py:801-818`.
- `resolve-batch` reads `{"requests":[…]}` or a bare list on stdin, validates each request naming the exact problem, unions the scopes so each harness is refreshed **once**, then answers each request; per-request results carry `cwd, harness, runtime, candidates[]` and an `error` string when that request failed; candidate payloads **include `resume_command`** so the caller needs no second round trip; batch limit default 10 — `:26`, `:235-355`, `:460-488`.
- Exit codes: 0 whenever resolution ran (including `matched:false` and per-request errors); 1 only for unreadable stdin / usage / internal failure. JSON on stdout, diagnostics on stderr — `:441-457`, `:501-526`.

---

# 8. CONFIG

- **Env vars (complete list, `grep environ`)**:
  - `OPENAI_API_KEY` — gates summaries (`cache.py:141`, `app.py:716`), embeddings (`embeddings.py:37`), chat (`backend.py:65`).
  - `AGENT_SESSIONS_CHAT_MODEL` — overrides the chat model (`backend.py:86`).
  - `TMUX` — enables the `tmux load-buffer -w` clipboard leg (`app.py:1064`).
  - `USER` — interpolated into the chat system prompt (`prompts.py:9`).
  - **There is no config file of any kind** — no dotfile, no TOML, no `~/.config/agent-sessions`. Every path is a hardcoded constant.
- **Paths**: see §2.7. Cache root `~/.cache/agent-sessions/`, user-data root `~/.local/share/agent-sessions/`.
- **Optional dependency handling**: `openai` is an extra (`pyproject.toml:35-37`, floor `>=2.14.0`), detected without importing via `importlib.util.find_spec("openai")` in two places (`cache.py:13`, `embeddings.py:14`) and imported lazily inside functions (`cache.py:146`, `embeddings.py:43`, `backend.py:67`). Hard runtime deps are only `numpy>=1.26`, `textual>=0.40`, `rich>=13` (`pyproject.toml:28-32`); Python ≥3.10.
- Defaults worth pinning for a port: fts/semantic weights 0.3/0.7; cosine floor 0.35; combined-score floor 0.2; normalization floor 0.5; TUI search limit 50; list cap 500; chunk target 400 tokens; embedding batch 100 / 250k tokens; page budget 200k chars; per-payload guard 400k; per-turn budget 500k; toast 8 s / 10 s; startup incremental window 48 h; reindex claim 120 s; resolve window 172 800 s (48 h); resolve limit 5, batch limit 10; ambiguity 120 s; preview 120 chars.

---

# 9. PERFORMANCE / SAFETY BEHAVIORS

1. `SessionDatabase` is a **process-wide singleton with thread-local connections**, tracked in a list for bulk close; `reset_instance()` for tests — `database.py:85-128`, `:103-109`.
2. Connections: `check_same_thread=False`, `isolation_level=None` (autocommit), `timeout=30`, `PRAGMA foreign_keys=ON`, `journal_mode=WAL`, `busy_timeout=30000` — `:115-124`.
3. Schema creation is double-checked-locked behind `_schema_lock` and a `_initialized` flag; every public method calls `_ensure_schema()` — `:130-151`.
4. Foreign DBs are opened **read-only via URI** (`cursor.py:36`, `opencode.py:39`); Cursor falls back to a temp copy when locked (`cursor.py:42-50`); OpenCode's change stamp accounts for the `-wal` sidecar (`opencode.py:46-57`).
5. `get_session_rows_by_file_paths` chunks the `IN (...)` list at 500 params — `database.py:790-798`.
6. `get_all_sessions()` uses `limit=100000` with an explicit comment about children crowding out parents — `:868-874`.
7. Truncation rules, all of them: metadata cache fields 2000 chars (all providers); `first_prompt_preview` 200 / `last_response_preview` 500 (`indexer.py:345-355`); detail-panel prompt 2000, response 2000/1000 (`widgets.py:508`, `:522`); title 80 chars (`cache.py:199`); summary transcript 80k head+tail (`cache.py:19`); embedding input 24 000 chars (`embeddings.py:74-75`); tool page 200k; tool payload guard 400k; turn budget 500k; resolve preview 120; citation short id 8; chat title 57+`...`; list description ≥20 chars.
8. Threading in the TUI: four `@work(thread=True)` workers — background load (`app.py:348`), summary generation (`:707`), transcript load (`:780`), chat turn (`:1098`), search (`:1574`); reindex is `@work(exclusive=True, thread=True)` (`:1297`). All UI mutation goes through `call_from_thread`.
9. Bounded API timeouts everywhere: embeddings 30 s, summaries 60 s (chat relies on the SDK default plus `truncation="auto"`).
10. Failure philosophy: providers swallow per-file errors (`base.py:186-188`), indexer logs and continues per session (`indexer.py:107-109`, `:228-230`, `:448-450`), tool dispatch returns `{"error": …}` rather than raising, resolve-batch prints refresh failures to stderr and still answers from the existing index (`resolve.py:286-290`).

---

# 10. TESTS (one line each; 16 files)

1. `tests/test_providers.py` — provider identity/dirs/resume commands for Droid, Claude Code, Codex; fixture parsing incl. Codex parent vs child (`source.subagent.thread_spawn`); registry order and lookup; OpenCode DB-vs-legacy discovery, DB parse, child + model fallback, metadata-cache reuse, **DB timestamps in seconds**, legacy parse, `get_session_mtime` prefers DB, `discover_sessions_fast` merges stores, no-DB-still-reads-legacy.
2. `tests/test_indexer.py` — incremental backfill of an old session when a provider has a backlog; no re-index of unchanged sessions with **internal ids ≠ file stems**; embedding client uses a bounded timeout.
3. `tests/test_search.py` — legacy `parse_search_query` modifiers, relative/ISO/invalid date parsing, `SearchEngine` harness/project/date filters, `SearchResult` shape.
4. `tests/test_hybrid_search.py` — natural-language topic extraction; topic (not instruction words) drives the query; documented metadata filters applied; date + tag filters; `get_chunks_without_embeddings`; semantic result carries the best chunk snippet; `--generate-embeddings` backfills.
5. `tests/test_transcript_find.py` — `find_all_matches` (empty/none/single/multiple/**overlapping**/case-insensitive/Unicode casefold/across newline/at end) and `offset_to_line_col` edge cases.
6. `tests/test_transcript_find_pilot.py` — live-pilot find-bar lifecycle; find blocked until transcript ready; "no matches" status; **search match explanation renders in the detail panel**; **child match propagates to the parent result**.
7. `tests/test_chat_tui.py` — chat replaces the sub-agent panel; `z` fullscreen + Escape collapse; history toggle/selection; `Ctrl+N` new chat + exact control-row/header composition + binding identity; copy uses visible chat text (with tmux); transcript copy keys route to chat when a chat item has focus; **turn auto-selects the recommended session**; background load doesn't steal chat focus; `?` refocuses instead of closing; Escape restores the session detail after a transcript; late transcript writes are dropped.
8. `tests/test_chat_agent.py` — tool dispatch + state persistence; **no artificial tool-round cap**; system prompt mandates exact resume commands; `pick_recommended_session` (earliest mention / full id in a resume command / none without a text mention); oversized output elided; turn budget forces a final answer; backend failure rolls state back to turn start and returns a graceful partial turn.
9. `tests/test_chat_tools.py` — find/get scope; list_projects & chunk shapes; briefs include the exact resume command; **tools expose no limit knobs**; ISO/None timestamp formatting; get_messages with string timestamps; pagination for chunks, messages, find_sessions, search_sessions; at-least-one-item rule; `start` cursor present in the schemas.
10. `tests/test_chat_persistence.py` — chat/message round-trip; defaults gpt-5.6 + xhigh; **v3→v4 migration**; thread-local connections.
11. `tests/test_chat_backend.py` — request carries `truncation="auto"`; `allow_tools` maps to `tool_choice`.
12. `tests/test_resolve.py` (1229 lines) — runtime↔harness mapping both directions, provider-sourced resume commands (Claude + Codex), symlink normalization, children excluded, window edges, 119/120/121 s confidence boundaries, sort + limit, 120-char preview, all four staleness triggers, `--no-reindex`, exact contract keys, CLI stdout/exit codes, unknown-harness rejection, tie-break toward the newer session, `main` dispatch, Claude project-dir encoding, scoped discovery incl. alternate config roots, unscopeable stores, scoped index passes (only given files / skip current / reindex on mtime move), lookup by file_path, and the reindex-claim window semantics (granted once, again after the interval, independent per key, per-cwd isolation, no claim burned on an empty cwd).
13. `tests/test_resolve_batch.py` — order preservation, verbatim cwd echo, exact contract keys, both names present, **every candidate carries a resume command**, best-first, cap at 10, window, children excluded, preview cap, empty cwd, two panes see identical candidates, one refresh per harness, per-harness passes, `--no-reindex`, per-request error degradation, malformed request isolation, empty batch, symlinks, CLI stdin/exit-code behavior, bare-list acceptance, defaults, `main` dispatch.
14. `tests/test_toasts_and_summaries.py` — toast defaults ≥5 s / errors ≥10 s, explicit override honored, summary transcript bounded head+tail with both markers present and a client timeout set.
15. `tests/fixtures/` — `claude_code_session.jsonl`, `codex_parent_session.jsonl`, `codex_child_session.jsonl`, `droid_session.jsonl` (no Cursor or OpenCode fixtures on disk; OpenCode tests build a SQLite DB inline).
16. CI runs `pytest tests/ -v` on Python 3.10/3.11/3.12 — `.github/workflows/ci.yml`.

---

# 11. ANYTHING ELSE

## 11.1 Bugs / rough edges a port should decide about
1. **`ctrl+n` is bound twice** (`app.py:199` `new_chat` and `:199` `add_note`); behavior depends on `check_action` gating, not on the table.
2. **`cmd.split()` instead of `shlex.split`** in `main.cmd_browse` (`main.py:32-35`) — a quoted resume prefix from `~/.claude-*/.resume-cmd` breaks.
3. **Cursor's pseudo-command is exec'd**: `get_resume_command` returns `"# Open Cursor and restore session <id>"` (`cursor.py:341`) and `main.py:35` runs `execvp("#", …)` → `FileNotFoundError`.
4. **Stale comment** at `claude_code.py:419-421` claiming `cmd_browse` uses an interactive shell (`shell -ic`); it does not.
5. **Version drift**: `__init__.py:3` = 0.8.0 vs `pyproject.toml:8` = 0.9.0.
6. `--reindex` prints `Projects updated: 0` always (`main.py:178` reads a key `full_reindex` never sets).
7. `reasoning_effort()` ignores stored per-chat metadata (`persistence.py:75-76`).
8. `cmd_projects` / `cmd_search_history` call `conn.close()` on a **thread-local shared connection** (`main.py:314`, `:359`) — fine for one-shot CLI, hostile in a long-lived process.
9. `AnthropicBackend` raises `NotImplementedError` — the only `NotImplemented` in the codebase (`backend.py:125`).
10. `agent_sessions/search.py`'s `SearchEngine`/`search_sessions` path is dead in the app (imported at `app.py:24`, never called) but still tested.
11. `action_copy_command` (Enter) bypasses the tmux/OSC-52 clipboard chain and uses bare `pbcopy` (`app.py:1733`) — macOS-only, unlike every other copy path.
12. `ChatPanel.add_tool_event` / `add_tool_call` are no-ops (`chat_widgets.py:339-343`), so `ToolCallWidget`'s expand/copy behavior is currently unreachable.
13. No UI path deletes a chat, though `delete_chat` exists.

## 11.2 Hidden / undocumented features (not in the README)
1. `ctrl+h` as an undocumented alias for chat history (`app.py:191`).
2. `a` = select-all-and-copy transcript with a line count in the toast (`app.py:196`, `:1217-1229`).
3. `j`/`k` vim navigation plus Home/End/PgUp/PgDn in every pane (`app.py:200-207`).
4. Drag-to-scroll at the detail panel's edges (`ui/widgets.py:222-267`).
5. Right-click-to-copy on chat messages and tool calls (`chat_widgets.py:78-81`, `:132-135`).
6. Clickable `Copy`/`New`/`Recent`/`Clear` chat controls (`chat_widgets.py:378-396`).
7. Alternate Claude config roots (`~/.claude-*/projects`) and the `.resume-cmd` prefix file (`claude_code.py:18-30`, `:414-417`).
8. Codex `session_index.jsonl` thread names as titles (`codex.py:66-90`).
9. Legacy `~/.factory/session-summaries.json` migration on every launch (`app.py:466-469`).
10. `HybridSearch.search_fts_only` / `search_semantic_only` and per-call weight overrides — reachable only from code.
11. The `metadata_only=True` mode of `full_reindex` (`indexer.py:53`, `:331-334`) — no CLI flag exposes it.
12. `tool_mentions` and `has_code` columns are populated but never read by any query.

## 11.3 DESIGNED-NOT-BUILT (open on the board — `.manna/issues.jsonl`; work orders sealed in `.handoff/`)
1. **`mn-b7efa6` Resume handoff mode** — `--on-resume '<template>'` flag on `browse` + `AGENT_SESSIONS_ON_RESUME` env var (flag wins). Placeholders `{cmd}`, `{cwd}`, `{id}`, `{harness}`, `{runtime}` (claude-code→claude, codex→codex, opencode→opencode, else `shell`), and URL-encoded twins `{cmd_q}`/`{cwd_q}` (`urllib.parse.quote(safe='')`). When set: substitute → `shlex.split` → `subprocess.run(argv)`, **never `shell=True`**, print one confirmation line, exit 0, no chdir, no execvp. Requires widening the TUI exit tuple to `(cmd, project_path, session_id, harness)`. Host example: `open "holy-ghostty://spawn?runtime={runtime}&workingDirectory={cwd_q}&command={cmd_q}"`. — `.handoff/01-…md`, `.dev/session-prompts/01-RESUME-BRIDGE.md`.
2. **`mn-b7ff4b` Resume exec fixes** — `shlex.split`; `#`-prefixed pseudo-commands print and exit 0 in both normal and handoff paths; delete the stale `shell -ic` comment. — `.handoff/02-…md`.
3. **`mn-1cca0f` holy-ghostty read-only provider** — name `holy-ghostty`, `fast_discovery=False`, reads `~/Library/Application Support/<bundle-id>/HolyGhostty/holy-ghostty.sqlite3` (WAL, `mode=ro`, temp-copy fallback, Cursor-style virtual paths + DB-mtime cache key) through Holy's shipped compat views `agent_sessions_sessions_v1`, `agent_sessions_resume_targets_v1`, `..._events_v1`, `..._annotations_v1`. **No messages view exists — index metadata/preview only, never fake transcripts.** Resume: `preferred_command` (tmux-attach hint for `resume_kind='active_session'`, fresh relaunch for archived). Also adds `"holy-ghostty"` to the hardcoded `--stats` harness list at `main.py:290`. — `.handoff/03-…md`, `.dev/session-prompts/03-HOLY-PROVIDER.md`.
4. **`mn-a7eb85` Compact narrow-pane mode** — auto-compact below ~56 columns plus an explicit `--compact` browse flag; single-column stacked layout instead of 55/45; row prefix shrinks to short date + icon (project moves to a section header/detail); trimmed footer; chat stays functional; wide mode must not regress. Rationale: the fixed 36-col prefix makes the TUI unusable under ~60 columns, and Holy Ghostty's panel is ~420-500 pt. — `.handoff/04-…md`, `.dev/session-prompts/04-COMPACT-MODE.md`.
5. **Parent track `mn-2b847f`** "Holy Ghostty panel integration (agent-sessions side)" remains open; `mn-7dfdb0` (resolve) and `mn-73001f` (resolve-batch) are the two done children.
6. `.dev/session-prompts/02-HOLY-PANEL.md`, `06-CRASH-RESTORE.md`, `07-INBOX-V1.md`, `08-INBOX-MANNA.md` are work orders for the **holy-ghostty repo**, not this one — they consume the `resolve` contract but add nothing to agent-sessions' own surface.