import Foundation
import Darwin
import GhosttyKit

enum HolyTmuxCommandBuilder {
    static func realizedLaunchSpec(_ launchSpec: HolySessionLaunchSpec) -> HolySessionLaunchSpec {
        var copy = launchSpec
        copy.transport = copy.transport.normalized
        if shouldDisableImplicitTmux(for: copy) {
            copy.tmux = nil
        }

        var tmux = copy.tmux?.normalized
        if tmux?.sessionName == nil, tmux != nil {
            tmux?.sessionName = suggestedSessionName(for: copy)
        }
        copy.tmux = tmux
        return copy
    }

    static func surfaceConfiguration(for launchSpec: HolySessionLaunchSpec) -> Ghostty.SurfaceConfiguration {
        let realizedLaunchSpec = realizedLaunchSpec(launchSpec)
        let launchCommand = command(for: realizedLaunchSpec)

        var config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = realizedLaunchSpec.transport.isRemote ? nil : realizedLaunchSpec.workingDirectory
        config.command = launchCommand
        config.initialInput = realizedLaunchSpec.initialInput
        config.waitAfterCommand = false
        config.environmentVariables = sanitizedEnvironment(realizedLaunchSpec.environment)
        return config
    }

    static func suggestedSessionName(for launchSpec: HolySessionLaunchSpec) -> String {
        let base = sanitizedSessionComponent(launchSpec.resolvedTitle)
        let runtime = sanitizedSessionComponent(launchSpec.runtime.displayName)
        let prefix = [base, runtime]
            .compactMap { value -> String? in
                guard !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: "-")

        let stem = prefix.isEmpty ? "session" : prefix
        let suffix = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .prefix(8)

        return "holy-\(stem)-\(suffix)"
    }

    static func command(for launchSpec: HolySessionLaunchSpec) -> String? {
        launchScript(for: launchSpec)
    }

    private static func launchScript(for launchSpec: HolySessionLaunchSpec) -> String? {
        guard let tmux = launchSpec.tmux?.normalized,
              let sessionName = tmux.sessionName?.holyTrimmed.nilIfEmpty else {
            return launchSpec.command?.holyTrimmed.nilIfEmpty
        }

        let usesManagedServer = tmux.createIfMissing && tmux.socketName == HolySessionTmuxSpec.defaultSocketName
        let tmuxPrefix = tmuxPrefixArguments(for: tmux, useCleanConfig: usesManagedServer)
        let bootstrapCommand = bootstrapCommand(for: launchSpec)
        let metadataCommands = metadataCommands(
            for: launchSpec,
            tmuxPrefix: tmuxPrefix,
            tmux: tmux,
            sessionName: sessionName
        )
        let ownershipStampCommand = HolyAgentStateBridge
            .tmuxOwnershipStampArguments(forTarget: sessionName)
            .map { shellCommand(tmuxPrefix + $0) }

        var lines: [String] = []
        if tmux.createIfMissing {
            if usesManagedServer {
                lines.append(contentsOf: managedServerConfigurationCommands(tmuxPrefix: tmuxPrefix))
            }

            var createArguments = tmuxPrefix + ["new-session", "-d", "-s", sessionName]
            if let workingDirectory = launchSpec.workingDirectory?.holyTrimmed.nilIfEmpty {
                createArguments += ["-c", workingDirectory]
            }
            createArguments.append(bootstrapCommand)

            let hasSessionArguments = tmuxPrefix + ["has-session", "-t", sessionName]
            let ensureSessionCommand = "\(shellCommand(hasSessionArguments)) 2>/dev/null || \(shellCommand(createArguments))"

            if metadataCommands.isEmpty {
                lines.append(ensureSessionCommand)
            } else {
                let metadataScript = (metadataCommands + [ownershipStampCommand].compactMap(\.self))
                    .joined(separator: "; ")
                lines.append("if \(ensureSessionCommand); then \(metadataScript); else exit 1; fi")
            }
        } else {
            lines.append("\(shellCommand(tmuxPrefix + ["has-session", "-t", sessionName])) >/dev/null")
            if let ownershipStampCommand {
                lines.append(ownershipStampCommand)
            }
        }

        lines.append("exec \(shellCommand(tmuxPrefix + ["attach", "-t", sessionName]))")
        let localScript = lines.joined(separator: "; ")

        if launchSpec.transport.isRemote {
            guard let destination = launchSpec.transport.sshDestination?.holyTrimmed.nilIfEmpty else {
                return shellCommand(["zsh", "-lc", localScript])
            }

            return shellCommand(["zsh", "-lc", remoteLaunchWrapper(destination: destination, localScript: localScript)])
        }

        return shellCommand(["zsh", "-lc", localScript])
    }

    private static func bootstrapCommand(for launchSpec: HolySessionLaunchSpec) -> String {
        let shellScript: String
        if let command = launchSpec.command?.holyTrimmed.nilIfEmpty {
            if launchSpec.runtime == .claude {
                shellScript = "\(command); \(clearClaudeOwnedModelLabelCommand); exec ${SHELL:-/bin/zsh} -l"
            } else {
                shellScript = "\(command); exec ${SHELL:-/bin/zsh} -l"
            }
        } else {
            shellScript = "exec ${SHELL:-/bin/zsh} -l"
        }

        return "sh -lc \(posixQuote(shellScript))"
    }

    private static let clearClaudeOwnedModelLabelCommand = """
    if [ -n "${TMUX_PANE:-}" ] && command -v tmux >/dev/null 2>&1; then tmux if-shell -F -t "$TMUX_PANE" '#{==:#{@holy_model_source},claude}' "set-option -pu -t '$TMUX_PANE' @holy_model_label ; set-option -pu -t '$TMUX_PANE' @holy_model_source" 2>/dev/null || true; fi
    """

    private static func remoteLaunchWrapper(destination: String, localScript: String) -> String {
        let sshCommand = shellCommand([
            "ssh", "-tt",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=4",
            "-o", "TCPKeepAlive=no",
            "-o", "ConnectTimeout=8",
            destination,
            shellCommand(["zsh", "-lc", localScript]),
        ])
        let failureMessage = "Holy Ghostty could not reach \(destination). Reattach after SSH is reachable."

        return [
            terminalInputFlushCommand,
            sshCommand,
            "holy_status=$?",
            "if [ \"$holy_status\" -ne 0 ]; then",
            "  \(terminalModeResetCommand)",
            "  printf '\n%s\n' \(posixQuote(failureMessage))",
            "  printf 'SSH exited with status %s.\n' \"$holy_status\"",
            "  sleep 2",
            "  exit \"$holy_status\"",
            "fi",
            "exit 0",
        ].joined(separator: "; ")
    }

    private static let terminalInputFlushCommand = "python3 -c 'import sys, termios; termios.tcflush(sys.stdin.fileno(), termios.TCIFLUSH)' 2>/dev/null || true"

    private static let terminalModeResetCommand = [
        "printf '\\033[?1000l\\033[?1002l\\033[?1003l\\033[?1006l\\033[?1015l\\033[?2004l\\033[?25h'",
        "stty sane 2>/dev/null || true",
        terminalInputFlushCommand,
    ].joined(separator: "; ")

    private static func sanitizedEnvironment(_ environment: [String: String]) -> [String: String] {
        var sanitized = environment
        for key in inheritedDirenvStateKeys {
            sanitized[key] = ""
        }
        return sanitized
    }

    private static let inheritedDirenvStateKeys = [
        "DIRENV_DIR",
        "DIRENV_DIFF",
        "DIRENV_FILE",
        "DIRENV_LAYOUT",
        "DIRENV_WATCHES",
    ]

    private static func tmuxPrefixArguments(
        for tmux: HolySessionTmuxSpec,
        useCleanConfig: Bool = false
    ) -> [String] {
        var arguments = ["tmux"]
        if let socketName = tmux.socketName?.holyTrimmed.nilIfEmpty {
            arguments += ["-L", socketName]
        }
        if useCleanConfig {
            if let configPath = managedTmuxConfigPath() {
                arguments += ["-f", configPath]
            }
        }
        return arguments
    }

    private static func managedServerConfigurationCommands(tmuxPrefix: [String]) -> [String] {
        let optionCommands = [
            ["set-option", "-gq", "destroy-unattached", "off"],
            ["set-option", "-gq", "prefix", "`"],
            ["set-option", "-gq", "mouse", "on"],
            ["set-option", "-gq", "history-limit", managedTmuxHistoryLimit],
            ["set-option", "-sq", "escape-time", "0"],
            ["set-option", "-gq", "default-terminal", "tmux-256color"],
            ["set-option", "-gq", "terminal-overrides", managedTmuxTerminalOverrides],
            ["set-option", "-gq", "terminal-features", managedTmuxTerminalFeatures],
            ["set-option", "-gq", "allow-passthrough", "on"],
            ["set-option", "-gq", "set-clipboard", "on"],
            ["set-option", "-gq", "status-right-length", managedTmuxStatusRightLength],
            ["set-option", "-gq", "status-right", managedTmuxStatusRight],
            ["set-window-option", "-gq", "aggressive-resize", "on"],
        ]

        return optionCommands.map { command in
            "\(shellCommand(tmuxPrefix + command)) 2>/dev/null || true"
        }
    }

    private static func managedTmuxConfigPath() -> String? {
        let fileManager = FileManager.default
        guard let supportRoot = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let holyDirectory = supportRoot.appendingPathComponent("Holy Ghostty", isDirectory: true)
        do {
            try fileManager.createDirectory(at: holyDirectory, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let configURL = holyDirectory.appendingPathComponent("managed-tmux.conf")
        do {
            try managedTmuxConfigBody.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }

        return configURL.path
    }

    private static let managedTmuxHistoryLimit = "50000"
    private static let managedTmuxTerminalOverrides = "linux*:AX@,xterm-256color:RGB,xterm-ghostty:RGB"
    private static let managedTmuxTerminalFeatures = "xterm*:clipboard:ccolour:cstyle:focus:title,screen*:title,rxvt*:ignorefkeys,xterm-ghostty:clipboard:ccolour:cstyle:focus:title"
    fileprivate static let managedTmuxStatusRightLength = "96"
    fileprivate static let managedTmuxStatusRight = "#{?#{&&:#{==:#{@holy_model_source},claude},#{==:#{@holy_claude_model_enabled},off}},,#{?@holy_model_label,#{@holy_model_label} · ,}}\"#{=21:pane_title}\" %H:%M %d-%b-%y"
    private static let managedTmuxConfigBody = """
    # Holy Ghostty managed tmux server config.
    # This file is regenerated by the app and applies only to Holy's `tmux -L holy` server.
    set -g destroy-unattached off
    set -g mouse on
    set -g history-limit \(managedTmuxHistoryLimit)
    set -s escape-time 0
    set -g default-terminal "tmux-256color"
    set -g terminal-overrides "\(managedTmuxTerminalOverrides)"
    set -g terminal-features "\(managedTmuxTerminalFeatures)"
    set -g allow-passthrough on
    set -g set-clipboard on
    set -g status-right-length \(managedTmuxStatusRightLength)
    set -g status-right '\(managedTmuxStatusRight)'
    setw -g aggressive-resize on

    # Prefix: backtick instead of C-b. Press `` to type a literal backtick.
    unbind C-b
    set -g prefix `
    bind ` send-prefix

    # `<prefix> a` copies the entire pane history (full scrollback) to the
    # macOS clipboard — the "select everything" the terminal's own select-all
    # can't do while tmux owns the screen.
    bind a run-shell 'tmux capture-pane -pJ -S - -t "#{pane_id}" | pbcopy'
    """

    private static func metadataCommands(
        for launchSpec: HolySessionLaunchSpec,
        tmuxPrefix: [String],
        tmux: HolySessionTmuxSpec,
        sessionName: String
    ) -> [String] {
        guard tmux.createIfMissing else { return [] }

        let metadata: [(String, String)] = [
            ("@holy_title", launchSpec.resolvedTitle),
            ("@holy_runtime", launchSpec.runtime.rawValue),
            ("@holy_transport", launchSpec.transport.kind.rawValue),
            ("@holy_transport_target", launchSpec.transport.destinationDisplayName),
            ("@holy_session_name", sessionName),
            ("@holy_working_directory", launchSpec.workingDirectory?.holyTrimmed.nilIfEmpty ?? ""),
            ("@holy_objective", launchSpec.objective?.holyTrimmed.nilIfEmpty ?? ""),
            ("@holy_command", launchSpec.command?.holyTrimmed.nilIfEmpty ?? ""),
            ("@holy_task_title", launchSpec.task.map { $0.title.holyTrimmed.nilIfEmpty ?? "" } ?? ""),
            ("@holy_task_source", launchSpec.task?.sourceSummary ?? ""),
        ]

        return metadata.map { key, value in
            shellCommand(tmuxPrefix + ["set-option", "-q", "-t", sessionName, key, value])
        }
    }

    private static func shellCommand(_ arguments: [String]) -> String {
        arguments.map(posixQuote).joined(separator: " ")
    }

    private static func posixQuote(_ value: String) -> String {
        if value.isEmpty {
            return "''"
        }

        let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }

    private static func sanitizedSessionComponent(_ value: String) -> String {
        let filtered = value
            .lowercased()
            .map { character -> Character in
                if character.isLetter || character.isNumber {
                    return character
                }

                return "-"
            }

        let collapsed = String(filtered)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")

        return String(collapsed.prefix(24))
    }

    private static func shouldDisableImplicitTmux(for launchSpec: HolySessionLaunchSpec) -> Bool {
        guard let tmux = launchSpec.tmux?.normalized,
              let sessionName = tmux.sessionName?.holyTrimmed.nilIfEmpty,
              HolyDiscoveredTmuxSession.isGeneratedHolyShellSessionName(sessionName) else {
            return false
        }

        guard launchSpec.runtime == .shell,
              launchSpec.transport.kind == .local,
              launchSpec.workspace == nil,
              launchSpec.task == nil,
              launchSpec.budget == nil,
              launchSpec.command?.holyTrimmed.nilIfEmpty == nil,
              launchSpec.initialInput?.holyTrimmed.nilIfEmpty == nil,
              launchSpec.objective?.holyTrimmed.nilIfEmpty == nil else {
            return false
        }

        guard launchSpec.resolvedTitle == "Shell" else {
            return false
        }

        return tmux.socketName?.holyTrimmed.nilIfEmpty == HolySessionTmuxSpec.defaultSocketName
    }
}

struct HolyTmuxModelLabelUpdateCommand: Sendable, Equatable {
    let executableURL: URL
    let arguments: [String]

    static func command(
        for launchSpec: HolySessionLaunchSpec,
        label: String?
    ) -> Self? {
        // Model metadata is advisory, but it still must target stored identity.
        // Never realize an incomplete spec here: doing so can invent a session
        // name and publish authoritative-looking state to the wrong target.
        guard let tmux = launchSpec.tmux?.normalized,
              let socketName = tmux.socketName?.holyTrimmed.nilIfEmpty,
              let sessionName = tmux.sessionName?.holyTrimmed.nilIfEmpty else {
            return nil
        }

        let tmuxArguments = ["tmux", "-L", socketName]
        // `set-option -p` expects a pane target. The leading `=` disables
        // tmux's dangerous prefix matching; the trailing `:` resolves the
        // active pane only within that exact session.
        let exactPaneTarget = "=\(sessionName):"

        var commandScripts: [String] = []
        if socketName == HolySessionTmuxSpec.defaultSocketName {
            commandScripts.append(shellCommand(tmuxArguments + [
                "set-option", "-gq", "status-right-length",
                HolyTmuxCommandBuilder.managedTmuxStatusRightLength,
            ]))
            commandScripts.append(shellCommand(tmuxArguments + [
                "set-option", "-gq", "status-right",
                HolyTmuxCommandBuilder.managedTmuxStatusRight,
            ]))
        }

        if let label = sanitizedLabel(label) {
            commandScripts.append(shellCommand(tmuxArguments + [
                "set-option", "-p", "-t", exactPaneTarget,
                "@holy_model_label", label,
            ]))
            commandScripts.append(shellCommand(tmuxArguments + [
                "set-option", "-p", "-t", exactPaneTarget,
                "@holy_model_source", "app",
            ]))
        } else {
            let sourceCommand = shellCommand(tmuxArguments + [
                "show-options", "-pqv", "-t", exactPaneTarget,
                "@holy_model_source",
            ])
            let clearLabelCommand = shellCommand(tmuxArguments + [
                "set-option", "-pu", "-t", exactPaneTarget,
                "@holy_model_label",
            ])
            let clearSourceCommand = shellCommand(tmuxArguments + [
                "set-option", "-pu", "-t", exactPaneTarget,
                "@holy_model_source",
            ])
            commandScripts.append(
                "if [ \"$(\(sourceCommand))\" != 'claude' ]; then "
                    + "\(clearLabelCommand); \(clearSourceCommand); fi"
            )
        }

        let tmuxScript = commandScripts.joined(separator: "; ")
        if launchSpec.transport.isRemote {
            guard let destination = launchSpec.transport.sshDestination?.holyTrimmed.nilIfEmpty else {
                return nil
            }

            return .init(
                executableURL: URL(fileURLWithPath: "/usr/bin/ssh"),
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "-o", "ConnectionAttempts=1",
                    "-o", "ServerAliveInterval=5",
                    "-o", "ServerAliveCountMax=1",
                    destination,
                    "zsh -lc \(posixQuote(tmuxScript))",
                ]
            )
        }

        return .init(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: [
                "-lc",
                "unset TMUX TMUX_PANE TMUX_TMPDIR; \(tmuxScript)",
            ]
        )
    }

    @discardableResult
    func run(timeout: TimeInterval = 10) -> Bool {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            guard !process.isRunning else {
                process.terminate()
                let terminationDeadline = Date().addingTimeInterval(0.5)
                while process.isRunning, Date() < terminationDeadline {
                    Thread.sleep(forTimeInterval: 0.025)
                }
                if process.isRunning {
                    _ = Darwin.kill(process.processIdentifier, SIGKILL)
                }
                return false
            }
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func sanitizedLabel(_ label: String?) -> String? {
        guard let label = label?.holyTrimmed.nilIfEmpty else { return nil }

        let scalars = label.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
                && scalar != "#"
        }
        let clean = String(String.UnicodeScalarView(scalars)).holyTrimmed
        return clean.isEmpty ? nil : String(clean.prefix(64))
    }

    private static func shellCommand(_ arguments: [String]) -> String {
        arguments.map(posixQuote).joined(separator: " ")
    }

    private static func posixQuote(_ value: String) -> String {
        if value.isEmpty { return "''" }
        return "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}

private extension String {
    var holyTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

#if DEBUG
extension HolyTmuxCommandBuilder {
    static func remoteLaunchWrapperForTesting(destination: String, localScript: String) -> String {
        remoteLaunchWrapper(destination: destination, localScript: localScript)
    }

    static var managedTmuxStatusRightForTesting: String {
        managedTmuxStatusRight
    }
}
#endif
