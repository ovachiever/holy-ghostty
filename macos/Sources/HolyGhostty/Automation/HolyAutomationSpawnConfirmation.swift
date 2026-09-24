import AppKit

/// The sheet a gated spawn URL must pass before a session exists. Cancel is
/// the first button, so it owns Return (and, by its title, Escape); creating
/// the session takes a deliberate click on the second button (mn-e9f9a9).
enum HolyAutomationSpawnConfirmation {
    static let cancelTitle = "Cancel"
    static let createTitle = "Create Session"

    /// The one response that means "go". It is the second button's, never
    /// the default's.
    static let createResponse: NSApplication.ModalResponse = .alertSecondButtonReturn

    struct SummaryLine: Equatable {
        let label: String
        let value: String
    }

    static func makeAlert(
        for request: HolyAutomationSpawnRequest,
        origin: HolyAutomationURLOrigin?
    ) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = request.carriesCommand
            ? "Run a command from a link?"
            : "Open a session from a link?"
        alert.informativeText = informativeText(for: request, origin: origin)

        let cancel = alert.addButton(withTitle: cancelTitle)
        cancel.keyEquivalent = "\r"
        let create = alert.addButton(withTitle: createTitle)
        create.keyEquivalent = ""
        create.hasDestructiveAction = request.carriesCommand
        return alert
    }

    static func summaryLines(
        for request: HolyAutomationSpawnRequest,
        origin: HolyAutomationURLOrigin?
    ) -> [SummaryLine] {
        let spec = request.launchSpec
        var lines: [SummaryLine] = [
            .init(label: "Requested by", value: origin?.displayText ?? "not reported by macOS"),
            .init(label: "Runtime", value: spec.runtime.displayName),
        ]

        switch spec.transport.kind {
        case .local:
            lines.append(.init(label: "Transport", value: "Local"))
        case .ssh:
            lines.append(.init(
                label: "Transport",
                value: "SSH to \(spec.transport.sshDestination ?? spec.transport.destinationDisplayName)"
            ))
        }

        if let tmux = spec.tmux {
            let socket = tmux.socketName ?? HolySessionTmuxSpec.defaultSocketName
            let session = tmux.sessionName ?? "chosen by Holy"
            let create = tmux.createIfMissing ? "create if missing" : "attach only"
            lines.append(.init(label: "tmux", value: "socket \(socket), session \(session), \(create)"))
        }

        lines.append(.init(label: "Working directory", value: spec.workingDirectory ?? "default"))
        lines.append(.init(label: "Title", value: spec.title))
        if let objective = spec.objective {
            lines.append(.init(label: "Objective", value: objective))
        }
        lines.append(.init(label: "Command", value: spec.command ?? "none"))
        lines.append(.init(label: "Initial input", value: spec.initialInput ?? "none"))
        lines.append(.init(label: "URL", value: request.url.absoluteString))
        return lines
    }

    static func informativeText(
        for request: HolyAutomationSpawnRequest,
        origin: HolyAutomationURLOrigin?
    ) -> String {
        let preface = request.carriesCommand
            ? "A link asked Holy to open a session and run the command below on this Mac"
                + (request.launchSpec.transport.isRemote ? " over SSH." : ".")
            : "A link asked Holy to open a session."
        let body = summaryLines(for: request, origin: origin)
            .map { "\($0.label): \($0.value)" }
            .joined(separator: "\n")
        return "\(preface) Nothing has run yet.\n\n\(body)"
    }
}

extension HolyAutomationURLOrigin {
    /// The sender macOS attached to an Apple Event, resolved to the running
    /// application when there is one. Nil when the event carries no sender.
    static func from(appleEvent event: NSAppleEventDescriptor?) -> HolyAutomationURLOrigin? {
        guard let event,
              let descriptor = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr)) else {
            return nil
        }
        let processIdentifier = descriptor.int32Value
        guard processIdentifier > 0 else { return nil }
        let application = NSRunningApplication(processIdentifier: processIdentifier)
        return HolyAutomationURLOrigin(
            processIdentifier: processIdentifier,
            applicationName: application?.localizedName,
            bundleIdentifier: application?.bundleIdentifier
        )
    }
}
