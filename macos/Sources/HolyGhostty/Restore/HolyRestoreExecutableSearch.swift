import Foundation

/// Where a provider executable was found — and therefore whether the restored
/// pane may invoke it by bare name.
///
/// The distinction is the whole point. Only the tmux server's own PATH is the
/// PATH the restored command actually runs under; every other layer proves the
/// binary exists somewhere the runtime may not look, so those hits must be
/// pinned into argv as an absolute path. A preflight pass can then never
/// precede a runtime "command not found".
enum HolyRestoreExecutableDiscovery: Equatable, Sendable {
    /// Found on the live tmux server's global PATH. That PATH *is* the
    /// runtime's PATH, so the bare name resolves in the pane.
    case tmuxServerPath(String)
    /// Found in a known tool directory (a version manager, a self-installer)
    /// that the runtime's PATH may not carry. argv must pin the path.
    case wellKnownDirectory(String)
    /// Found by a login-shell `command -v`, whose PATH is the app's, not the
    /// pane's — `.zshrc` never ran for either. argv must pin the path.
    case loginShell(String)
    /// Every layer missed.
    case missing

    /// The absolute path discovery settled on, or nil when nothing was found.
    var absolutePath: String? {
        switch self {
        case let .tmuxServerPath(path), let .wellKnownDirectory(path), let .loginShell(path):
            return path
        case .missing:
            return nil
        }
    }

    var isFound: Bool { absolutePath != nil }

    /// The argv[0] override the command builder must use, or nil when the bare
    /// name is safe. Nil for `.tmuxServerPath` (the runtime PATH already
    /// resolves it) and for `.missing` (there is nothing to pin).
    var pinnedArgvPath: String? {
        switch self {
        case .tmuxServerPath, .missing:
            return nil
        case let .wellKnownDirectory(path), let .loginShell(path):
            return path
        }
    }
}

/// The pure half of executable discovery: candidate construction, PATH
/// splitting, and nvm version ordering, all free of the filesystem so the
/// layering law can be tested exactly.
enum HolyRestoreExecutableSearch {
    /// Names come from `HolySessionRuntime` raw values, but this string lands
    /// inside a login-shell command line, so stay defensive.
    static func isSafeExecutableName(_ name: String) -> Bool {
        name.range(of: "^[a-z0-9-]{1,32}$", options: .regularExpression) != nil
    }

    /// The first directory of a colon-separated PATH that holds an executable
    /// `name`, rendered as an absolute path. Empty entries mean "the current
    /// directory" to a POSIX shell; restore refuses to honor that — a relative
    /// hit is never worth baking into a restored command.
    static func resolve(
        name: String,
        inSearchPath searchPath: String,
        isExecutable: (String) -> Bool
    ) -> String? {
        guard isSafeExecutableName(name) else { return nil }
        for directory in searchPath.split(separator: ":", omittingEmptySubsequences: true) {
            let directory = String(directory)
            guard directory.hasPrefix("/") else { continue }
            let candidate = directory.hasSuffix("/")
                ? "\(directory)\(name)"
                : "\(directory)/\(name)"
            if isExecutable(candidate) { return candidate }
        }
        return nil
    }

    /// Install locations of the managers that only initialize in `.zshrc`,
    /// which no login shell and no Dock launch ever sources — listed before
    /// the system directories, because a name still missing from the tmux
    /// server's PATH by this point is precisely the kind these managers own.
    /// Each entry names the real installer that produces it; extend only with
    /// a concrete sighting.
    static func wellKnownCandidates(
        name: String,
        home: String,
        nvmVersionDirectoryNames: [String]
    ) -> [String] {
        var candidates = nvmVersionDirectoriesNewestFirst(nvmVersionDirectoryNames).map {
            "\(home)/.nvm/versions/node/\($0)/bin/\(name)"  // nvm, newest version first
        }
        candidates += [
            "\(home)/.volta/bin/\(name)",       // volta shims
            "\(home)/.bun/bin/\(name)",         // bun global installs
            "\(home)/.opencode/bin/\(name)",    // opencode self-installer
            "\(home)/.pyenv/shims/\(name)",     // pyenv
            "\(home)/.local/bin/\(name)",       // pipx / uv / user installs
            "/opt/homebrew/bin/\(name)",        // homebrew (Apple Silicon)
            "/usr/local/bin/\(name)",           // homebrew (Intel) / manual
        ]
        return candidates
    }

    /// nvm keeps one bin directory per node version and chooses between them
    /// in `.zshrc`. Every version is searched, newest first: a tool installed
    /// under an older node stays invisible if only the newest is probed, which
    /// is exactly how `codex` under v22.16.0 hid behind an empty v24.19.0.
    /// Newest wins only among versions that actually carry the binary.
    static func nvmVersionDirectoriesNewestFirst(_ entries: [String]) -> [String] {
        entries
            .compactMap { entry -> (components: [Int], name: String)? in
                guard entry.hasPrefix("v") else { return nil }
                let numbers = entry.dropFirst().split(separator: ".").compactMap { Int($0) }
                guard !numbers.isEmpty else { return nil }
                return (numbers, entry)
            }
            .sorted { $1.components.lexicographicallyPrecedes($0.components) }
            .map(\.name)
    }
}
