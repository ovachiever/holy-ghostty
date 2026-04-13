# holy-ghostty/src/terminal/c Scope Guide

This file applies only to this local subtree.

## Scope
- Local path: `holy-ghostty/src/terminal/c/`.
- Nearest ancestor guide: `holy-ghostty/AGENTS.md`.

## Current Scope Signals
- Local manifests: none detected in this directory.
- Nearest owning manifest directory: `holy-ghostty/` with `Makefile`, `build.zig`.
- Allowed external helper reference here: `agent-do` only when the task truly needs automation beyond normal shell or editor work.

## Local Layout
- `allocator.zig` - checked-in root file
- `build_info.zig` - checked-in root file
- `cell.zig` - checked-in root file
- `color.zig` - checked-in root file
- `focus.zig` - checked-in root file
- `formatter.zig` - checked-in root file
- `grid_ref.zig` - checked-in root file
- `key_encode.zig` - checked-in root file
- `key_event.zig` - checked-in root file
- `kitty_graphics.zig` - checked-in root file

## Working Rules
- Keep instructions local to this subtree and tied to files that are actually checked in here.
- Keep unrelated non-engineering language out of this file.
- Prefer the nearest owning manifest and parent guide over assumptions carried in from sibling projects.
- If this scope contains only docs, templates, or generated assets, document that plainly and avoid inventing a runtime.

## Validation
- Validate through `holy-ghostty/` rather than treating this folder as a standalone package.
- `zig build`
- `zig build test`
