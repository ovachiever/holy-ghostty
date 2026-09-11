---
workflow: 2
manna: mn-4be59b
track: mn-9a97cc
source: null
base_commit: 065ff58584b5ce1b3b1515a589998982f0185148
scope: '[P1][TERMINAL] mn- ids render blue at rest in every pane — no hover underline'
inputs: []
binding: sha256:ba6797fdcb33d4c335e126c40c494bd4df6df637b0bcafa5048e4874a231ca0b
---

# Handoff: [P1][TERMINAL] Manna IDs render blue at rest in every pane

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-4be59b
```

## Scope

Detected `mn-[a-f0-9]{6,}` identifiers render in terminal ANSI blue at rest in every pane. Command-hover changes the pointer and shows the URL caption without an underline. Command-click retains the existing Board item route.

## Inputs

- The claimed input binding was verified as `sha256:0e5fa10a56a2c9d7a7543458b82c96672c25e4fe9f35030c351fe95a1ec6b874` by canonical Manna claim/state/lint. The tracked handoff existed and had a valid content seal.
- Canonical Manna's 2026-09-11 description explicitly supersedes the old purple/underline body. That blue/no-underline revision governs this implementation.
- Existing link detection and routing from `mn-5a26f9`, including the soft-wrap correction `7baec439e`, remain the click path.

## Work order

Paint visible identifiers with palette entry 4, using the actual terminal font and cell geometry. Erase the original glyphs with opaque rectangles in the surface background color before painting blue glyphs. Refresh after output/scroll settles, invalidate changed geometry/content, and emit no overlay when no identifiers are visible. Keep all core/Zig sources and the imported core payload unchanged.

Focused coverage must include plain and soft-wrapped runs, scroll invalidation, and rejection of identifiers embedded in longer words. Required acceptance remains: Erik sees blue identifiers at rest in any pane, hover has no underline, and Command-click lands on the correct Board item.

### Implementation receipt

Implementation commit: `2f5f7ca5dfd165b2746dff651c23a2199a64a44f`, `feat(terminal): paint Manna IDs blue at rest`, with exact trailer `Manna: mn-4be59b`.

- `HolyMannaLink.swift` maps regex matches through core-provided cell-prefix selections. Non-rectangular reads preserve hard newlines and unwrap soft wraps; Unicode width is never guessed from Swift string length. A changed read rejects the complete frame.
- `HolyMannaLinkOverlay.swift` polls only presented, visible panes at 100ms intervals and paints after two identical samples. It rechecks the viewport after mapping, uses `ghostty_surface_quicklook_font`, and paints glyphs at fixed cell advances. No pointer movement or terminal input is used to scan.
- Geometry uses the padded baseline from `ghostty_surface_read_text` and a cell edge from read-only `ghostty_surface_ime_point`. Every IME cell bottom is congruent to a row edge, so the first-row baseline identifies the grid origin without duplicating padding/font configuration. Fixtures cover `window-padding-y=34,2`, cursor-row changes, and fractional point sizes.
- ANSI blue comes from `ghostty_config_get(..., "palette", ...)`, entry 4. Surface palette/background events and configuration reloads refresh the painter.
- `SurfaceView_AppKit.swift` invalidates on scroll, scrollbar updates, keyboard input, mouse-down, cell-size changes, resizing, and configuration/color changes. Selection suppresses painting so the overlay does not obscure selection highlighting.
- `SurfaceView.swift` mounts the noninteractive overlay below the existing chrome. The existing absence of a hover underline and the Board click handler are preserved.
- `HolyMannaBoardLinkTests.swift` adds ten regression functions for geometry, wrapped and hard lines, omitted trailing cells, Unicode prefixes, invalidation, changed reads, lookalikes, and configured ANSI blue.

### Verification receipts, 2026-09-11

All final commands below exited 0. No app, app-hosted test process, installed bundle, screenshot workflow, or live session was launched by this lane. **Zero tests executed.**

```bash
scripts/build-holy-ghostty-core.sh verify

xcodebuild -quiet -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -configuration ReleaseLocal -destination 'platform=macOS' \
  -derivedDataPath .dev/mn-4be59b/ReleaseDerivedData \
  SYMROOT=/Users/erik/Custom-Coding/holy-ghostty/.dev/mn-4be59b/release-products \
  -jobs 4 build

codesign --verify --deep --strict --verbose=2 \
  '.dev/mn-4be59b/release-products/ReleaseLocal/Holy Ghostty.app'

xcodebuild -quiet -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .dev/mn-4be59b/TestDerivedData \
  SYMROOT=/Users/erik/Custom-Coding/holy-ghostty/.dev/mn-4be59b/test-products \
  -resultBundlePath .dev/mn-4be59b/validation/build-for-testing-final.xcresult \
  -only-testing:GhosttyTests/HolyMannaBoardLinkTests \
  -jobs 4 build-for-testing CODE_SIGNING_ALLOWED=NO

swiftlint lint --strict --config macos/.swiftlint.yml \
  'macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift' \
  'macos/Sources/Ghostty/Surface View/SurfaceView.swift' \
  macos/Sources/HolyGhostty/Automation/HolyMannaLink.swift \
  macos/Sources/HolyGhostty/Automation/HolyMannaLinkOverlay.swift \
  macos/Tests/HolyGhostty/HolyMannaBoardLinkTests.swift

# Repeated on the final test-only fixture edit:
swiftlint lint --strict --config macos/.swiftlint.yml \
  macos/Tests/HolyGhostty/HolyMannaBoardLinkTests.swift
git diff --check
```

Results:

- Imported core verified: ReleaseFast, Zig 0.15.2, input fingerprint `9d9f76225c12968b5518f7477263b66f6635faff03ff9b9840852de3a38a02be`. No local core rebuild.
- ReleaseLocal app build: exit 0. Code signature valid on disk and satisfies its designated requirement.
- Final focused Debug build-for-testing: `succeeded`, 0 errors, 497 warnings, 0 warnings attributed to the five changed Swift files. The suite compiled; it did not execute.
- Focused strict SwiftLint: 0 violations. Diff whitespace check and Coord guard: clean.
- Manna lint confirms the content binding. Its item-specific filename finding is a rename held by the live claim; the handoff was not manually renamed.

Evidence is under `.dev/mn-4be59b/validation/`: `release-build-final.log`, `build-for-testing-final-fixtures.log`, `build-for-testing-final.xcresult`, `build-results-final.json`, `swiftlint.log`, `swiftlint-final-test.log`, and `source-hashes.txt`.

Earlier failures are retained in `build-for-testing-attempt-1.log` (actor isolation), `build-for-testing-attempt-2.log` (ReleaseLocal lacks test access), `release-build.log` (partial test bundle in a reused output root), and `build-for-testing-attempt-3.log` / `.xcresult` (missing direct AppKit import in a test). The final commands above verify their corrections. Release and hosted-test outputs now have separate roots.

### Required coordinated acceptance

1. Execute `GhosttyTests/HolyMannaBoardLinkTests` from the implementation commit in the coordinated app-hosted acceptance window. Record actual passed/failed/skipped counts. Compilation is not an execution receipt.
2. Verify blue identifiers at rest in single, split, and quad panes, including plain text, soft wraps, Unicode prefixes, output updates, scrollback, resize, and font-size changes. Check alignment with asymmetric top padding and compare the color with terminal ANSI blue output.
3. Verify Command-hover shows the pointer and URL caption with no underline; Command-click selects the correct Board item.

Manna remains `in_progress` under `codex-01a0904d96e87981`. Do not call `manna done` until the required execution and live/visual receipts are recorded. This lane did not install, push, or create a pull request.

Lessons logged: 5 (new) | Decisions logged: 1 (new).
Lesson IDs: `les-f335d1`, `les-330a0d`, `les-46abb4`, `les-350ae9`, `les-baa040`. Decision: `dec-da3fb1`.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-4be59b`.
4. Commit with `Manna: mn-4be59b` and run `agent-do manna done mn-4be59b` only after the work is verified.
