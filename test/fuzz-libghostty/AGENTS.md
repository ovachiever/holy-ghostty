# holy-ghostty/test/fuzz-libghostty Scope Guide

This file applies only to this local subtree.

## Scope
- Local path: `holy-ghostty/test/fuzz-libghostty/`.
- Nearest ancestor guide: `holy-ghostty/AGENTS.md`.

## Current Scope Signals
- Local manifests: `build.zig`.
- Nearest owning manifest directory: `holy-ghostty/test/fuzz-libghostty/` with `build.zig`.
- Allowed external helper reference here: `agent-do` only when the task truly needs automation beyond normal shell or editor work.

## Local Layout
- `src/` - main source tree
- `corpus/` - checked-in subtree
- `build.zig` - checked-in root file
- `build.zig.zon` - checked-in root file
- `README.md` - checked-in root file
- `replay-crashes.nu` - checked-in root file

## Working Rules
- Keep instructions local to this subtree and tied to files that are actually checked in here.
- Keep unrelated non-engineering language out of this file.
- Prefer the nearest owning manifest and parent guide over assumptions carried in from sibling projects.
- If this scope contains only docs, templates, or generated assets, document that plainly and avoid inventing a runtime.

## Validation
- `zig build`
- `zig build test`
