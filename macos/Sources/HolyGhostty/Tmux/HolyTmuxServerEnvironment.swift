import Foundation

/// Reads the global environment of a live tmux server — the environment every
/// new session on that server inherits.
///
/// Restore needs this because a restored pane does not run under the app's
/// PATH. It runs under the tmux server's, and that server was usually started
/// from an interactive shell that sourced `.zshrc` (nvm, volta, bun). Asking
/// the server directly is the only way the preflight check and the runtime can
/// share one truth about what is invocable.
enum HolyTmuxServerEnvironment {
    /// `show-environment` against a live server is a local socket round-trip
    /// that answers in milliseconds. Bounded by the same probe budget the
    /// lifecycle service uses for `has-session`: past that the socket is
    /// wedged, and preflight must not hang the sheet behind it.
    static var probeTimeout: TimeInterval { HolyTmuxLifecycleService.defaultProbeTimeout }

    /// The `PATH` the named tmux server hands to new sessions, or nil when the
    /// server is not running, has no PATH in its global environment, or could
    /// not be read at all. Absence is never an error here: the caller simply
    /// falls through to the next discovery layer.
    static func globalPath(
        socketName: String?,
        timeout: TimeInterval = probeTimeout
    ) async -> String? {
        let command = showEnvironmentCommand(socketName: socketName, variable: "PATH")
        let result = await HolyRestoreProcessRunner.run(
            executablePath: command.executablePath,
            arguments: command.arguments,
            timeout: timeout,
            environment: HolyTmuxLifecycleService.scrubbedTmuxEnvironment(
                ProcessInfo.processInfo.environment
            )
        )
        guard case let .success(output) = result, output.exitCode == 0 else { return nil }
        return parseGlobalValue(fromShowEnvironmentOutput: output.stdout, variable: "PATH")
    }

    struct Command: Equatable, Sendable {
        let executablePath: String
        let arguments: [String]
    }

    /// `tmux -L <socket> show-environment -g <variable>`, wrapped in a login
    /// shell so `tmux` itself resolves, and with the inherited tmux client
    /// variables unset so the query can never be redirected at whatever server
    /// happens to own the app's own pane.
    static func showEnvironmentCommand(socketName: String?, variable: String) -> Command {
        var tmuxArguments = ["tmux"]
        if let socketName = socketName?.holyServerEnvironmentTrimmed.nilIfEmpty {
            tmuxArguments += ["-L", socketName]
        }
        tmuxArguments += ["show-environment", "-g", variable]
        let script = "unset TMUX TMUX_PANE TMUX_TMPDIR; "
            + tmuxArguments.map(posixQuote).joined(separator: " ")
        return .init(executablePath: "/bin/zsh", arguments: ["-lc", script])
    }

    /// tmux answers `show-environment -g NAME` with either `NAME=<value>` or a
    /// bare `-NAME`, the latter meaning the variable is explicitly unset. Only
    /// the assignment form carries a value, and an empty value is no value.
    static func parseGlobalValue(
        fromShowEnvironmentOutput output: String,
        variable: String
    ) -> String? {
        let prefix = "\(variable)="
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(prefix) else { continue }
            let value = String(trimmed.dropFirst(prefix.count))
            return value.isEmpty ? nil : value
        }
        return nil
    }

    private static func posixQuote(_ value: String) -> String {
        if value.isEmpty { return "''" }
        return "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}

private extension String {
    var holyServerEnvironmentTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
