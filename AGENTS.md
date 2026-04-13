# holy-ghostty Engineering Guide

This file is the current as-is operating guide for agents working in this project.

## Scope
- Applies to `holy-ghostty/`.
- Deeper `AGENTS.md` files refine only their local subtree.

## Source Of Truth
1. Running code and checked-in files in this project
2. Local manifests and lockfiles
3. Local README, deployment files, and nearest scoped `AGENTS.md` files
4. Historic notes only when they still match the code

## Current Repo Signals
- Root manifests: `Makefile`, `build.zig`.
- Inferred stack signals: Zig.
- Allowed external helper reference here: `agent-do` when browser, mobile, desktop, or GUI automation is actually required.
- Local scoped guides exist under `holy-ghostty/example/`, `holy-ghostty/macos/`, `holy-ghostty/src/inspector/`, `holy-ghostty/src/terminal/c/`, `holy-ghostty/test/fuzz-libghostty/`.

## Top-Level Layout
- `src/` - main source tree
- `pkg/` - package exports
- `scripts/` - automation scripts
- `test/` - test suite
- `macos/` - macOS or native code
- `example/` - checked-in subtree
- `flatpak/` - checked-in subtree
- `images/` - checked-in subtree
- `include/` - checked-in subtree
- `nix/` - checked-in subtree
- `po/` - checked-in subtree
- `snap/` - checked-in subtree
- `vendor/` - checked-in subtree
- `zig-out/` - checked-in subtree

## Working Rules
- Keep this file factual and current-state. Do not turn it into a roadmap or target architecture document.
- Keep unrelated non-engineering language out of this file.
- Use the nearest scoped `AGENTS.md` before changing a deeper package, app, or subsystem.
- Prefer small, local changes and validate through the manifest that owns the touched code.

## Validation
- `zig build`
- `zig build test`
