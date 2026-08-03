import Foundation

/// Builds the exact resume invocation for each provider runtime. The provider
/// session id is data: it is validated against a strict charset, carried as
/// one argv element, and rendered into tmux bootstrap shell source only
/// through per-element POSIX quoting. Nothing here ever emits `--continue`,
/// `--last`, or a picker.
enum HolyRestoreCommandBuilder {
    /// Provider session ids across claude/codex/opencode are UUIDs or short
    /// token ids: letters, digits, dash, underscore, dot. Anything else is
    /// treated as hostile, even though quoting alone would already contain it.
    static func isSafeProviderSessionID(_ id: String) -> Bool {
        guard (1 ... 128).contains(id.count) else { return false }
        return id.unicodeScalars.allSatisfy { scalar in
            switch scalar {
            case "a" ... "z", "A" ... "Z", "0" ... "9", "-", "_", ".":
                return true
            default:
                return false
            }
        }
    }

    /// The exact resume argv per runtime, or nil when no exact resume exists
    /// (shell runtime, or an id that fails validation).
    static func resumeArguments(
        runtime: HolySessionRuntime,
        providerSessionID: String
    ) -> [String]? {
        guard isSafeProviderSessionID(providerSessionID) else { return nil }

        switch runtime {
        case .shell:
            return nil
        case .claude:
            return ["claude", "--resume", providerSessionID]
        case .codex:
            return ["codex", "resume", providerSessionID]
        case .opencode:
            return ["opencode", "--session", providerSessionID]
        }
    }

    /// Renders an argv into shell source for the tmux bootstrap, quoting each
    /// element independently so the shell re-parses exactly the tokens we
    /// built and nothing more.
    static func shellCommand(fromArguments arguments: [String]) -> String {
        arguments.map(posixQuote).joined(separator: " ")
    }

    /// The launch-spec `command` string for a restored session, or nil when
    /// the runtime has no exact resume.
    static func renderedResumeCommand(
        runtime: HolySessionRuntime,
        providerSessionID: String
    ) -> String? {
        resumeArguments(runtime: runtime, providerSessionID: providerSessionID)
            .map(shellCommand(fromArguments:))
    }

    private static func posixQuote(_ value: String) -> String {
        if value.isEmpty {
            return "''"
        }

        let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }
}
