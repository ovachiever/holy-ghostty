---
workflow: 2
manna: mn-4be59b
track: mn-9a97cc
source: null
base_commit: 065ff58584b5ce1b3b1515a589998982f0185148
scope: '[P1][TERMINAL] mn- ids render blue at rest in every pane — no hover underline'
inputs: []
binding: sha256:f512c7a3be78db7cb9c9b13f4e6907e0193bfd81925cf3bb22948a16edaac516
---

# Handoff: [P1][TERMINAL] Manna IDs render blue at rest in every pane

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-4be59b
```

## Scope

Detected `mn-[a-f0-9]{6,}` identifiers render in terminal ANSI blue at rest in every pane. Command-hover changes the pointer and shows the URL caption without an underline. Command-click retains the existing Board item route.

**Installed visual acceptance FAILED at `51b4a81f5`.** Erik reported flickering IDs during streaming output and permanently white IDs in animated agent panes. Those observations supersede any inference of visual success from the initial green builds. The item remains open for the repaired build's executed and visual acceptance.

## Inputs

- The claimed input binding was verified as `sha256:0e5fa10a56a2c9d7a7543458b82c96672c25e4fe9f35030c351fe95a1ec6b874` by canonical Manna claim/state/lint. The tracked handoff existed and had a valid content seal.
- Canonical Manna's 2026-09-11 description explicitly supersedes the old purple/underline body. That blue/no-underline revision governs this implementation.
- Existing link detection and routing from `mn-5a26f9`, including the soft-wrap correction `7baec439e`, remain the click path.
- The repair continuation verified the existing owner `codex-01a0904d96e87981` and canonical seal `sha256:ba6797fdcb33d4c335e126c40c494bd4df6df637b0bcafa5048e4874a231ca0b` before editing. The claim was retained, not stolen or replaced.

## Work order

Paint visible identifiers with palette entry 4, using the actual terminal font and cell geometry. Erase the original glyphs with opaque rectangles in the surface background color before painting blue glyphs. Painting is persistent per physical row: unchanged rows gain or retain paint while other rows animate or receive appended output. Replace changed run sets atomically, without publishing nil during transient instability or read failures. Immediately clear only when scroll, resize, cell-size, configuration, or palette/background changes invalidate the positions or colors. Keep all core/Zig sources and the imported core payload unchanged.

Focused coverage must include plain and soft-wrapped runs, scroll invalidation, and rejection of identifiers embedded in longer words. Required acceptance remains: Erik sees blue identifiers at rest in any pane, hover has no underline, and Command-click lands on the correct Board item.

### Initial implementation receipt, superseded by failed installed acceptance

Implementation commit: `2f5f7ca5dfd165b2746dff651c23a2199a64a44f`, `feat(terminal): paint Manna IDs blue at rest`, with exact trailer `Manna: mn-4be59b`.

- `HolyMannaLink.swift` maps regex matches through core-provided cell-prefix selections. Non-rectangular reads preserve hard newlines and unwrap soft wraps; Unicode width is never guessed from Swift string length. A changed read rejects the complete frame.
- `HolyMannaLinkOverlay.swift` polls only presented, visible panes at 100ms intervals and paints after two identical samples. It rechecks the viewport after mapping, uses `ghostty_surface_quicklook_font`, and paints glyphs at fixed cell advances. No pointer movement or terminal input is used to scan.
- Geometry uses the padded baseline from `ghostty_surface_read_text` and a cell edge from read-only `ghostty_surface_ime_point`. Every IME cell bottom is congruent to a row edge, so the first-row baseline identifies the grid origin without duplicating padding/font configuration. Fixtures cover `window-padding-y=34,2`, cursor-row changes, and fractional point sizes.
- ANSI blue comes from `ghostty_config_get(..., "palette", ...)`, entry 4. Surface palette/background events and configuration reloads refresh the painter.
- `SurfaceView_AppKit.swift` invalidates on scroll, scrollbar updates, keyboard input, mouse-down, cell-size changes, resizing, and configuration/color changes. Selection suppresses painting so the overlay does not obscure selection highlighting.
- `SurfaceView.swift` mounts the noninteractive overlay below the existing chrome. The existing absence of a hover underline and the Board click handler are preserved.
- `HolyMannaBoardLinkTests.swift` adds ten regression functions for geometry, wrapped and hard lines, omitted trailing cells, Unicode prefixes, invalidation, changed reads, lookalikes, and configured ANSI blue.

### Initial build-only verification receipts, 2026-09-11

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

### Repair receipt, 2026-09-11

Implementation commit: `5d4473ba6`, `fix(terminal): preserve Manna ID paint across row updates`, with exact trailer `Manna: mn-4be59b`.

Final core-coordinate correction: `b93858177`, `fix(terminal): derive Manna paint geometry from core points`, with the same trailer. The final validation below includes both commits.

The failed build's whole-viewport equality gate and transient `frame = nil` publication have been removed. `RowPaintState` samples physical rows independently. A row unchanged across two samples can gain paint while any other row changes; accepted rows survive transient changes or failed reads. The painter publishes one complete replacement only when the resulting runs differ, including a valid empty frame when IDs have actually disappeared. Selection temporarily hides the retained frame without discarding its row state.

Cell mapping now starts at the candidate's own physical row, so animation above it cannot invalidate its prefix reads. Read ranges extend across rows only while the identifier can continue, and check the neighboring cells for word boundaries. Core selections still determine Unicode cell positions and soft wraps. Single-row reads use rectangular selection to prevent a wide spacer at the right edge from pulling text out of the next row.

Scrollbar changes clear paint only when `offset` or `len` changes. Growth in `total` at a fixed viewport retains paint. Repeated size notifications with unchanged dimensions and ordinary keyboard, mouse-down, or general binding actions no longer discard paint. Wheel scrolling, changed size/cell metrics, and config/palette/background changes retain immediate invalidation.

IME check: `src/apprt/embedded.zig:1905` forwards `imePoint()` directly. `src/Surface.zig:2089` computes the cursor cell bottom and `src/Surface.zig:2129` returns cell height divided by the core content scale, independent of focus or preedit text height. The text baseline also uses core point coordinates. The old `abs(imeHeight - cellSize.height) < 0.01` compared that value with a separate AppKit backing conversion and was not needed to derive the grid origin. It has been removed. Final review also removed the mixed coordinate sources: cell width comes from adjacent core selection origins, cell height from core IME height, and a one-column grid uses its cursor midpoint to recover width. AppKit backing conversion no longer determines paint geometry. Cursor-row/asymmetric-padding/fractional-size geometry fixtures remain, with a new core-point metric regression covering one-column and wider grids. Installed focus/IME behavior still requires Erik's check.

Required regression coverage is in the production painter's published frame, not only its helper return values:

- `animatedRowCannotBlockOrClearAStableIDRow` varies a row above and below a stable ID, verifies the ID gains paint, and rejects extra nil or repaint publications.
- `streamingAppendsBelowAnIDNeverUnpaintIt` varies output rows and scrollbar totals at fixed offset and verifies no frame publication or paint loss.
- `scrollAndResizeInvalidateImmediatelyEvenWhenTextRepeats` verifies the frame clears synchronously before the next sample after a scroll, resize, or explicit geometry invalidation.
- `transientReadsKeepPaintAndChangedRunsSwapAtomically` covers failed reads, ID replacement, and legitimate ID removal without an intermediate nil frame.
- Existing geometry, plain/wrapped text, omitted cells, Unicode mapping, and lookalike tests are retained. Additional fixtures cover a prefix split after `m` or `mn` and the leading word boundary across a wrap.

### Repair validation receipts

All commands below exited 0. **`HolyMannaBoardLinkTests` compiled; zero tests executed in this lane.** Release and hosted-test outputs used separate existing lane-owned build roots. No app launches, installs, screenshots, live sessions, pushes, or PRs occurred.

```bash
scripts/build-holy-ghostty-core.sh verify

xcodebuild -quiet -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .dev/mn-4be59b/TestDerivedData \
  SYMROOT=/Users/erik/Custom-Coding/holy-ghostty/.dev/mn-4be59b/test-products \
  -resultBundlePath .dev/mn-4be59b/row-persistence/validation/build-for-testing-core-geometry.xcresult \
  -only-testing:GhosttyTests/HolyMannaBoardLinkTests \
  -jobs 4 build-for-testing CODE_SIGNING_ALLOWED=NO

xcodebuild -quiet -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -configuration ReleaseLocal -destination 'platform=macOS' \
  -derivedDataPath .dev/mn-4be59b/ReleaseDerivedData \
  SYMROOT=/Users/erik/Custom-Coding/holy-ghostty/.dev/mn-4be59b/release-products \
  -jobs 4 build

codesign --verify --deep --strict --verbose=2 \
  '.dev/mn-4be59b/release-products/ReleaseLocal/Holy Ghostty.app'

swiftlint lint --strict --config macos/.swiftlint.yml \
  'macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift' \
  macos/Sources/HolyGhostty/Automation/HolyMannaLink.swift \
  macos/Sources/HolyGhostty/Automation/HolyMannaLinkOverlay.swift \
  macos/Tests/HolyGhostty/HolyMannaBoardLinkTests.swift

git diff --check
agent-do coord guard check --staged
```

Results: imported ReleaseFast core unchanged and verified at input fingerprint `9d9f76225c12968b5518f7477263b66f6635faff03ff9b9840852de3a38a02be`; focused Debug build-for-testing succeeded with 0 errors, 497 warnings, and 0 warnings attributed to the four changed Swift files; ReleaseLocal build succeeded; code signature valid on disk and satisfies its designated requirement; strict SwiftLint found 0 violations; whitespace and staged ownership checks passed. Both builds passed on the first repair attempt. These are build receipts, not runtime or visual acceptance.

Final evidence: `.dev/mn-4be59b/row-persistence/validation/` contains `core-verify.log`, `build-for-testing-core-geometry.log`, `build-for-testing-core-geometry.xcresult`, `build-results-core-geometry.json`, `release-build-core-geometry.log`, `codesign-core-geometry.log`, `swiftlint-core-geometry.log`, and `source-hashes.txt`. The first repair build and earlier `.dev/mn-4be59b/validation/` evidence remain intact. Portable handoff and validation copies are under iCloud Transfer's `mn-4be59b-5d4473ba6` folder, with a dated repair note in the Obsidian vault.

Repair lessons logged: 3 (new) | Decisions logged: 1 (new).
Lesson IDs: `les-32f912`, `les-a6d5be`, `les-8ed98e`. Decision: `dec-1f25dd`. The earlier `dec-da3fb1` was retracted with the installed failure receipt because its whole-viewport settling requirement was wrong.

### Required coordinated acceptance after the repair

1. Coordinator `session-17a022e17710` executes `GhosttyTests/HolyMannaBoardLinkTests` from the repair commit in the coordinated app-hosted acceptance window and returns the xcresult and actual passed/failed/skipped counts through Coord. Compilation is not an execution receipt.
2. Erik re-checks visually after the next coordinated install: stable ID rows remain continuously blue while a different row animates above or below them and while output streams below them. Scroll must immediately invalidate old positions. Repeat in single, split, and quad panes, including soft wraps, Unicode prefixes, resize, font-size changes, and focus/IME movement. Check alignment with asymmetric top padding and compare the color with terminal ANSI blue output.
3. Verify Command-hover shows the pointer and URL caption with no underline; Command-click selects the correct Board item.

Manna remains `in_progress` under `codex-01a0904d96e87981`. Do not call `manna done` until the required execution and live/visual receipts are recorded. This lane did not install, push, or create a pull request.

Initial implementation logged 5 lessons and 1 decision: `les-f335d1`, `les-330a0d`, `les-46abb4`, `les-350ae9`, `les-baa040`, and the now-retracted `dec-da3fb1`. The repair's new counts are listed separately above.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-4be59b`.
4. Commit with `Manna: mn-4be59b` and run `agent-do manna done mn-4be59b` only after the work is verified.
