import Foundation
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
        let hasTmuxSubstrate = realizedLaunchSpec.tmux?.normalized.sessionName?.holyTrimmed.nilIfEmpty != nil
        let launchesViaCommand = !hasTmuxSubstrate || realizedLaunchSpec.transport.isRemote
        let launchCommand = launchesViaCommand
            ? command(for: realizedLaunchSpec)
            : shellInput(for: realizedLaunchSpec)

        var config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = realizedLaunchSpec.transport.isRemote ? nil : realizedLaunchSpec.workingDirectory
        config.command = launchesViaCommand ? launchCommand : nil
        config.initialInput = !launchesViaCommand
            ? combinedInitialInput(
                primaryCommand: launchCommand,
                trailingInput: realizedLaunchSpec.initialInput
            )
            : realizedLaunchSpec.initialInput
        config.waitAfterCommand = false
        config.environmentVariables = realizedLaunchSpec.environment
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
        launchScript(for: launchSpec, interactiveShellInput: false)
    }

    static func shellInput(for launchSpec: HolySessionLaunchSpec) -> String? {
        launchScript(for: launchSpec, interactiveShellInput: true)
    }

    private static func launchScript(
        for launchSpec: HolySessionLaunchSpec,
        interactiveShellInput: Bool
    ) -> String? {
        guard let tmux = launchSpec.tmux?.normalized,
              let sessionName = tmux.sessionName?.holyTrimmed.nilIfEmpty else {
            return launchSpec.command?.holyTrimmed.nilIfEmpty
        }

        let tmuxPrefix = tmuxPrefixArguments(for: tmux)
        let bootstrapCommand = bootstrapCommand(for: launchSpec)
        let metadataCommands = metadataCommands(for: launchSpec, tmux: tmux, sessionName: sessionName)

        if launchSpec.transport.isRemote,
           !tmux.createIfMissing,
           let destination = launchSpec.transport.sshDestination?.holyTrimmed.nilIfEmpty {
            return shellCommand(["ssh", "-t", destination] + tmuxPrefix + ["attach", "-t", sessionName])
        }

        var lines: [String] = []
        if tmux.createIfMissing {
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
                let metadataScript = metadataCommands.joined(separator: "; ")
                lines.append("if \(ensureSessionCommand); then \(metadataScript); else exit 1; fi")
            }
        } else {
            lines.append("\(shellCommand(tmuxPrefix + ["has-session", "-t", sessionName])) >/dev/null")
        }

        lines.append("exec \(shellCommand(tmuxPrefix + ["attach", "-t", sessionName]))")
        let localScript = lines.joined(separator: "; ")

        if launchSpec.transport.isRemote {
            guard let destination = launchSpec.transport.sshDestination?.holyTrimmed.nilIfEmpty else {
                return interactiveShellInput ? localScript : shellCommand(["zsh", "-lc", localScript])
            }

            if interactiveShellInput {
                return shellCommand(["ssh", "-t", destination, localScript])
            }

            let remoteCommand = shellCommand(["zsh", "-lc", localScript])
            return shellCommand(["ssh", "-t", destination, remoteCommand])
        }

        if interactiveShellInput {
            return localScript
        }

        return shellCommand(["zsh", "-lc", localScript])
    }

    private static func bootstrapCommand(for launchSpec: HolySessionLaunchSpec) -> String {
        let shellScript: String
        if let command = launchSpec.command?.holyTrimmed.nilIfEmpty {
            shellScript = "\(command); exec ${SHELL:-/bin/zsh} -l"
        } else {
            shellScript = "exec ${SHELL:-/bin/zsh} -l"
        }

        return "sh -lc \(posixQuote(shellScript))"
    }

    private static func combinedInitialInput(
        primaryCommand: String?,
        trailingInput: String?
    ) -> String? {
        let trimmedCommand = primaryCommand?.holyTrimmed.nilIfEmpty
        let trimmedTrailingInput = trailingInput?.nilIfEmpty

        switch (trimmedCommand, trimmedTrailingInput) {
        case let (command?, trailingInput?):
            return "\(command)\n\(trailingInput)"
        case let (command?, nil):
            return "\(command)\n"
        case let (nil, trailingInput?):
            return trailingInput
        case (nil, nil):
            return nil
        }
    }

    private static func tmuxPrefixArguments(for tmux: HolySessionTmuxSpec) -> [String] {
        var arguments = ["tmux"]
        if let socketName = tmux.socketName?.holyTrimmed.nilIfEmpty {
            arguments += ["-L", socketName]
        }
        return arguments
    }

    private static func metadataCommands(
        for launchSpec: HolySessionLaunchSpec,
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
            shellCommand(tmuxPrefixArguments(for: tmux) + ["set-option", "-q", "-t", sessionName, key, value])
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
              sessionName.hasPrefix("holy-shell-shell-") else {
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

private extension String {
    var holyTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
