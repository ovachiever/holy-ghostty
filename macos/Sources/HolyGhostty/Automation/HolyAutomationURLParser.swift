import Foundation

enum HolyAutomationURLParser {
    static let scheme = "holy-ghostty"

    static func launchSpec(from url: URL) -> HolySessionLaunchSpec? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == scheme else {
            return nil
        }

        let route = routeName(from: components)
        guard route == "spawn" else { return nil }

        let runtime = runtimeValue(from: queryValue(named: "runtime", in: components)) ?? .shell
        let host = trimmed(queryValue(named: "host", in: components))
        let transport = transportValue(
            from: queryValue(named: "transport", in: components),
            host: host
        )
        let tmuxSessionName = trimmed(queryValue(named: "tmuxSession", in: components))
        let tmuxSocketName = trimmed(queryValue(named: "tmuxSocket", in: components))
        let createIfMissing = boolValue(
            from: queryValue(named: "createIfMissing", in: components)
        )

        let resolvedTitle = trimmed(queryValue(named: "title", in: components))
            ?? derivedTitle(runtime: runtime, host: host, tmuxSessionName: tmuxSessionName)

        return HolySessionLaunchSpec(
            runtime: runtime,
            title: resolvedTitle,
            objective: trimmed(queryValue(named: "objective", in: components)),
            task: nil,
            budget: nil,
            transport: .init(
                kind: transport,
                hostLabel: host,
                sshDestination: host
            ),
            tmux: tmuxSpec(
                sessionName: tmuxSessionName,
                socketName: tmuxSocketName,
                createIfMissing: createIfMissing
            ),
            workingDirectory: trimmed(queryValue(named: "workingDirectory", in: components)),
            command: trimmed(
                queryValue(named: "command", in: components)
                    ?? queryValue(named: "bootstrapCommand", in: components)
            ),
            initialInput: trimmed(queryValue(named: "initialInput", in: components)),
            waitAfterCommand: false,
            environment: [:],
            workspace: nil
        )
    }

    private static func routeName(from components: URLComponents) -> String? {
        if let host = components.host?.lowercased(), !host.isEmpty {
            return host
        }

        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? nil : path.lowercased()
    }

    private static func queryValue(named name: String, in components: URLComponents) -> String? {
        guard let encodedValue = components.percentEncodedQueryItems?.first(where: { $0.name == name })?.value else {
            return nil
        }

        // Shell tools commonly produce application/x-www-form-urlencoded query strings.
        // URLComponents preserves "+" literally, so normalize it before percent-decoding.
        let formEncodedValue = encodedValue.replacingOccurrences(of: "+", with: " ")
        return formEncodedValue.removingPercentEncoding ?? formEncodedValue
    }

    private static func runtimeValue(from input: String?) -> HolySessionRuntime? {
        guard let normalized = trimmed(input)?.lowercased() else { return nil }

        return HolySessionRuntime.allCases.first {
            $0.rawValue == normalized || $0.displayName.lowercased() == normalized
        }
    }

    private static func transportValue(from input: String?, host: String?) -> HolySessionTransportKind {
        guard let normalized = trimmed(input)?.lowercased() else {
            return host == nil ? .local : .ssh
        }

        return HolySessionTransportKind.allCases.first {
            $0.rawValue == normalized || $0.displayName.lowercased() == normalized
        } ?? (host == nil ? .local : .ssh)
    }

    private static func boolValue(from input: String?) -> Bool? {
        guard let normalized = trimmed(input)?.lowercased() else { return nil }

        switch normalized {
        case "1", "true", "yes", "y", "on":
            return true
        case "0", "false", "no", "n", "off":
            return false
        default:
            return nil
        }
    }

    private static func tmuxSpec(
        sessionName: String?,
        socketName: String?,
        createIfMissing: Bool?
    ) -> HolySessionTmuxSpec? {
        guard sessionName != nil || socketName != nil || createIfMissing != nil else {
            return nil
        }

        return .init(
            socketName: socketName ?? HolySessionTmuxSpec.defaultSocketName,
            sessionName: sessionName,
            createIfMissing: createIfMissing ?? true
        )
    }

    private static func derivedTitle(
        runtime: HolySessionRuntime,
        host: String?,
        tmuxSessionName: String?
    ) -> String {
        if let host, let tmuxSessionName {
            return "\(host)/\(tmuxSessionName)"
        }

        if let tmuxSessionName {
            return tmuxSessionName
        }

        return runtime.displayName
    }

    private static func trimmed(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
