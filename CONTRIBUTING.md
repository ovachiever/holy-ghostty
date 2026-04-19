# Contributing to Holy Ghostty

Holy Ghostty is a product fork of [Ghostty](https://github.com/ghostty-org/ghostty). The terminal core remains upstream Ghostty; the Holy layer adds a native macOS control surface for agentic coding sessions.

## What Lives Where

- **`src/`**: upstream Ghostty Zig core. Do not modify unless the macOS host genuinely needs a new structured signal from the terminal layer.
- **`macos/Sources/HolyGhostty/`**: all Holy-specific Swift/SwiftUI code. This is where most contributions will land.
- **`macos/Sources/`** (outside HolyGhostty): existing Ghostty macOS host code. Modify carefully; Holy Ghostty is layered into this host.
- **`docs/holy-ghostty/`**: Holy Ghostty documentation.

## Getting Started

```bash
# Prerequisites: macOS 15+, Xcode 26+ with Metal Toolchain, Zig 0.15.2 (not 0.16)
xcodebuild -downloadComponent MetalToolchain  # one-time setup

# Build the Zig core, then the macOS app
zig build -Demit-xcframework
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug SYMROOT=build build

# Install locally
scripts/install-holy-ghostty.sh Debug

# Launch
open -a "Holy Ghostty"
```

If you only need the Zig core (no macOS app bundle):

```bash
zig build -Demit-macos-app=false
```

**Zig version matters.** Zig is pre-1.0. Minor versions (0.15 to 0.16) carry breaking API changes. Use exactly **Zig 0.15.2**. Install from https://ziglang.org/download/.

See [HACKING.md](HACKING.md) for upstream Zig build details and extra dependency requirements.

## Pull Requests

1. Fork the repository and create a feature branch
2. Keep changes focused on a single concern
3. Test the macOS app manually (build, install, launch, exercise the affected flow)
4. Write a clear commit message that explains the purpose of the change

## Code Conventions

- Swift/SwiftUI code follows the existing patterns in `macos/Sources/HolyGhostty/`
- The design system lives in `HolyGhosttyDesignSystem.swift`; use shared colors and spacing tokens
- Domain types live in `HolyModels.swift`; keep the model layer flat and value-oriented
- The workspace store (`HolyWorkspaceStore.swift`) is the central orchestrator; coordinate with it rather than building parallel state

## Reporting Issues

Open a GitHub issue with:

- What you expected
- What actually happened
- Steps to reproduce
- macOS version and whether you built Debug or Release

## Security

If you discover a security vulnerability, see [SECURITY.md](SECURITY.md).

## Upstream Ghostty

This project depends on Ghostty's terminal core. For upstream Ghostty contributing guidelines and development setup, see [HACKING.md](HACKING.md) and the [upstream repository](https://github.com/ghostty-org/ghostty).

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
