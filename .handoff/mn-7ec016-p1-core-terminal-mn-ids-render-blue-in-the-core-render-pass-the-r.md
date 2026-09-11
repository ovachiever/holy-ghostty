---
workflow: 2
manna: mn-7ec016
track: mn-9a97cc
source: null
base_commit: b5c7f1763fe1e7d71eabb501c219f4e97681b8f1
scope: '[P1][CORE][TERMINAL] mn- ids render blue in the core render pass — the renderer is the only painter'
inputs: []
binding: sha256:5ef6f4f370dd5e19ac9e1ebdc437700c7fb8f88b0cd51673aec032b198fd6135
---

# Handoff: [P1][CORE][TERMINAL] mn- ids render blue in the core render pass — the renderer is the only painter

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-7ec016
```

## Scope

[P1][CORE][TERMINAL] mn- ids render blue in the core render pass — the renderer is the only painter

## Inputs

- None declared.

## Work order

Current amendment from Erik, 2026-09-11: use a unique RGB color, default `#FFB86C` (soft amber, manna gold), configurable through runtime-changeable `holy-manna-highlight-color` using Ghostty's existing `Color` type. This supersedes all prior ANSI palette-color instructions, including palette 12. `CellStyle.foreground` carries `terminal.color.RGB`. Keep the existing `holy-manna-highlight` gate, selection/search precedence, and mouse behavior. Add default, valid-hex and invalid-value diagnostic config tests, and update RGB style expectations. Stability acceptance already passed according to Erik; matching and invalidation must remain unchanged. Local validation is formatting and AST checks only. The coordinator owns the push and CI/artifact/install cycle.

Historical architecture work order, retained for provenance (its palette-color requirement is superseded above):

Erik ruling 2026-09-11 (supersedes the overlay approach of mn-4be59b, reverted b5c7f1763/6d6c2d2b1/9699989dd): ONE GRID, ONE PAINTER — text-anchored styling lives in the terminal renderer, never in an AppKit overlay shadowing it over a polling API; the overlay was structurally one frame behind (flicker on stream, stuck-white on animated viewports, blink on scroll — one disease, three views). Implementation, in-core: src/renderer/link.zig already regex-matches the viewport per frame into a cell map with per-rule highlight modes (URL hover-underline rides it, and URLs never flicker — that is the proof of home). Add a built-in Holy rule: pattern mn-[a-f0-9]{6,} with word boundaries (reject ids embedded in longer tokens), highlight always (not hover-gated), style = foreground palette color 4 (ANSI blue, follows the user theme), no underline. Gate behind config key holy-manna-highlight default true. The macOS cmd-click/hover hit-testing (mn-5a26f9) is event-side and stays untouched. CONSTRAINT (house law, scroll-regression postmortem): the engine builds via CI ReleaseFast artifact ONLY — local Zig linking is broken on macOS 26; Zig source edits + core-side unit tests land in the repo, the artifact rides CI, and the install that carries it follows the CI cycle. Tests: core-side matcher boundaries (short hex, uppercase, embedded), cell-map runs for wrapped ids, config gate off = no styling. Acceptance: Erik sees blue mn- ids at rest that are rock-steady during streaming, spinners, and scrolling — by construction, since the same pass draws text and color.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-7ec016`.
4. Commit with `Manna: mn-7ec016` and run `agent-do manna done mn-7ec016` only after the work is verified.

## Implementation and verification: 2026-09-11

Initial local implementation snapshot (see the CI follow-up below for newer evidence): implementation committed locally; no local core compilation or execution. Keep this item `in_progress` until required acceptance is verified.

- Claim owner: `codex-01a090df1edb76b2`. Claim succeeded before other workspace work. No claim was stolen.
- The original handoff was tracked and verified against canonical `agent-do manna state --json` and `.manna/issues.jsonl`. Its normalized binding was exactly `sha256:25bd308d1640c3472576fd6b3825672bd97284250068870d8b56fc22ef3f85ac`; its raw file SHA-256 was `6f1b67f97e360e128e952094dbb90de028426bd2a704264bc6c7d58d9828faed`.
- Implementation commit: `85b2ae0b82fcfdb9b94069c1bf68e0fbe3fa5d53`, `feat(terminal): render Manna IDs blue in the core pass`, with exact trailer `Manna: mn-7ec016`.
- Coord focus and individual path claims preceded edits. Other workers' release-document changes were preserved and excluded from the commit. No local engine linking or shared Xcode build occurred.

Changes:

1. `src/renderer/link.zig` adds the renderer-only `\\bmn-[a-f0-9]{6,}\\b` rule, always active when enabled, with foreground palette index 4 and no added underline. The styled cell map merges existing URL and OSC8 hover decoration without changing input actions.
2. `src/renderer/generic.zig` resolves that foreground from the current terminal palette when generating glyph cells. Selection and search colors retain precedence. Mouse conditions use the same snapshot as the text. Comparing old and new style maps invalidates cached rows for newly completed, removed, or moved matches, including unchanged prefixes on wrapped rows.
3. `src/config/Config.zig` adds default-on `holy-manna-highlight`, including config parsing coverage. Turning it off clears cached styling on the next render update.
4. `src/renderer.zig` explicitly includes the link tests. The focused inventory is 10 link tests plus 1 config test (8 new tests), including 16 matcher-boundary cases, multirow runs, config-off behavior, URL/OSC8 coexistence, streaming completion/invalidation, animation, and scrolling.
5. `.github/workflows/build-holy-macos.yml` executes the focused Zig tests before the canonical ReleaseFast artifact build. The test command disables macOS app and XCFramework emission and requests the test summary. No workflow was dispatched from this lane.

Local verification receipts are in `.dev/mn-7ec016/`; `verification.json` records source SHA-256 values and the exact distinction between source checks and compiled/executed tests.

| Command/check | Actual result |
| --- | --- |
| `.dev/toolchains/zig-aarch64-macos-0.15.2/zig version` | `0.15.2`. PATH and the Homebrew `zig@0.15` path both resolved to 0.16.0, so the existing pinned toolchain was used. |
| `.dev/toolchains/zig-aarch64-macos-0.15.2/zig fmt --check src/renderer.zig src/renderer/link.zig src/renderer/generic.zig src/config/Config.zig` | Exit 0 for all four files. `zig-fmt.log`. |
| `zig ast-check` using that pinned executable, individually on the same four files | All four exit 0. Source syntax checks only, without type checking or linking. `zig-ast-check.log`. |
| `TMPDIR="$PWD/.dev/mn-7ec016/tmp" scripts/test-holy-ghostty-build-contract.sh` | Executed, exit 0: `Holy build contract tests passed.` This is the canonical isolated shell-fixture suite, not a core or app build. `build-contract.log`. |
| Ruby YAML parse and test-before-build step-order assertion on the changed workflow | Exit 0. Existing Ruby ffi extension warning was nonfatal. `workflow-yaml.log`. |
| `git diff --cached --check` | Exit 0. |
| `git diff --cached -- <the five implementation paths> \| gitleaks stdin --redact --no-banner` | Exit 0, no leaks. `gitleaks.log`, `gitleaks.json`. |

Compiled core tests: **0**. Executed core tests: **0**. Compiled app-hosted tests: **0**. Executed app-hosted tests: **0**. The engine build was not attempted locally, as required by this work order. Formatting, syntax, and shell-fixture receipts do not establish core build success or visual acceptance.

## Required continuation and acceptance

1. The coordinator publishes this revision and reruns the canonical **Build Holy macOS core** CI workflow. This lane must not push or open a PR.
2. On the CI runner, execute the checked-in focused command and retain its real test counts/results:

   ```sh
   zig build test -Dtest-filter=renderer.link -Dtest-filter=holy-manna-highlight -Demit-macos-app=false -Demit-xcframework=false --summary all
   ```

   Then `scripts/build-holy-ghostty-core.sh build` and `scripts/build-holy-ghostty-core.sh verify` must succeed. Preserve the commit-addressed ReleaseFast artifact and its provenance. A failed test blocks artifact production.
3. Coordinate with the live acceptance/install owner through Coord. Once the no-launch boundary is lifted for that pass, import the matching artifact through the canonical core tool and use the canonical installer. Do not substitute an older engine, bypass its fingerprint checks, or link the engine locally.
4. Stability acceptance at rest and during streaming, spinners, and scrolling has already passed according to Erik. Preserve matching and invalidation. The coordinator's next cycle validates the unique configurable RGB color, default `#FFB86C`; it must not substitute an ANSI palette entry. No AppKit painter is added; the macOS event-side implementation is unchanged.
5. Attach CI test results, artifact/import/install receipts, and the human visual result to this handoff, reseal, and only then run `agent-do manna done mn-7ec016`.

No app launches, installs, screenshots, provider/tmux session spawning, pushes, or PRs occurred in this implementation lane. Lessons logged: 3 (new) | Decisions logged: 0 (new). `agent-do zpc harvest --since last` completed with no format issues or consolidation gaps.

## CI follow-up: run 34616487885

Erik reported that the engine compiled in CI and the first actual core test execution failed `renderCellMap Manna foreground coexists with URL and OSC8 underline`: expected 28 cells, found 29. The fixture expectations were wrong; this correction changes tests only. These CI facts are supplied by Erik, not a new execution from this lane.

- Recounted `https://example.com/mn-abcdef`: 29 ASCII cells, prefix length 20, slash at x=19, and the nine-character ID at x=20 through x=28.
- Corrected the hovered URL count to 29, asserted underline-only at x=19, and asserted blue plus underline at x=20 and x=28 with no styled cell at x=29. Moved the seeded OSC8 underline to x=20 so it overlaps the ID as intended.
- Rechecked sibling assertions: `https://example.com` is 19 cells; the unhovered ID remains 9 cells. Those expectations stay unchanged.
- `.dev/toolchains/zig-aarch64-macos-0.15.2/zig fmt --check src/renderer/link.zig`: exit 0.
- `.dev/toolchains/zig-aarch64-macos-0.15.2/zig ast-check src/renderer/link.zig`: exit 0. This checks source syntax, not types or linking.
- `git diff --check`: exit 0. Logs are in `.dev/mn-7ec016/ci-34616487885-fix/`.
- No compilation or test execution occurred locally. The coordinator owns the re-push and CI rerun. No push, app launch, or install occurred in this correction lane. Keep Manna `in_progress` until the rerun and required visual acceptance pass.
- Correction-turn lessons logged: 1 (new) | Decisions logged: 0 (new).

## RGB color update: 2026-09-11

This revision changes color plumbing only. `CellStyle.foreground` is now optional `terminal.color.RGB`; the renderer consumes the resolved RGB directly. `holy-manna-highlight-color` uses the same `Config.Color` parser as foreground/background and defaults to `#FFB86C`. The existing config reload path rebuilds the link configuration and marks the renderer dirty.

- Updated all styled-cell test expectations to RGB while retaining the corrected URL cell count and boundaries.
- Added three config tests: the default, valid mixed-case hex overrides with and without `#`, and an invalid hex value that records a diagnostic and retains the previous value.
- Added one color-change test using the existing `updateCellMap` path: unchanged ID cells receive the new RGB value and their cached row becomes dirty. Matching and invalidation implementations are byte-for-byte unchanged from `87023ecc7`; their combined source SHA-256 is `0fc4ef6ebed727124f90fde40f229e9679b6e1fb84c5ac0b59b058ec942b80fd`.
- The existing CI filters already select all four new tests (`renderer.link` and `holy-manna-highlight`); no workflow change is required.
- `.dev/toolchains/zig-aarch64-macos-0.15.2/zig fmt --check src/renderer/link.zig src/renderer/generic.zig src/config/Config.zig`: exit 0.
- `zig ast-check` with that same pinned executable on each of those three files: all exit 0. `git diff --check`: exit 0. Logs are in `.dev/mn-7ec016/rgb-color/`.
- These are source checks, not type checking, compilation, or executed tests. No local core/test compilation, test execution, app launch, install, or push occurred. The coordinator owns the remaining CI and color acceptance cycle; the already-passed stability acceptance is preserved.
- Color-update lessons logged: 1 (new) | Decisions logged: 0 (new).
