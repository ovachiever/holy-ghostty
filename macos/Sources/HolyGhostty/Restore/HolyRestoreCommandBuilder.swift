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
    /// (shell runtime, or an id that fails validation). `executablePath`
    /// replaces argv[0] with a resolved absolute path: the command executes
    /// under a login-shell PATH that misses .zshrc-initialized managers
    /// (nvm, ~/.opencode/bin), so a bare name may not resolve in the pane.
    /// Overrides every Holy-driven Codex launch carries, because nobody is at
    /// the pane to answer a prompt. Codex checks for updates on startup and
    /// shows "Update available · 0.156.1 → 0.157.0 … enter continue · esc skip",
    /// which waits for a keypress; on 2026-09-26 every crash-restored Codex
    /// session sat on it and none resumed. The key is Codex's top-level
    /// `check_for_update_on_startup` (config_toml.rs: "Defaults to `true`");
    /// the TUI's `get_upgrade_version_for_popup` returns nothing when it is
    /// false (tui/src/updates.rs). Verified on Codex 0.157.1: `codex -c
    /// check_for_update_on_startup=false doctor` reports "startup update check
    /// false", and without the override "true" (same with `--config`). The long
    /// form is used because `-c` is Claude's `--continue` and the builder's
    /// forbidden-flag rule keeps `-c` out of every resume command; `--config`
    /// is a global option and precedes the subcommand. User-started sessions (templates, the New
    /// Session sheet) keep Codex's default so Erik still sees updates.
    static let codexUnattendedLaunchOverrides: [String] = ["--config", "check_for_update_on_startup=false"]

    static func resumeArguments(
        runtime: HolySessionRuntime,
        providerSessionID: String,
        executablePath: String? = nil
    ) -> [String]? {
        guard isSafeProviderSessionID(providerSessionID) else { return nil }

        switch runtime {
        case .shell:
            return nil
        case .claude:
            return [executablePath ?? "claude", "--resume", providerSessionID]
        case .codex:
            return [executablePath ?? "codex"] + codexUnattendedLaunchOverrides + ["resume", providerSessionID]
        case .opencode:
            return [executablePath ?? "opencode", "--session", providerSessionID]
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
        providerSessionID: String,
        executablePath: String? = nil
    ) -> String? {
        resumeArguments(
            runtime: runtime,
            providerSessionID: providerSessionID,
            executablePath: executablePath
        )
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
