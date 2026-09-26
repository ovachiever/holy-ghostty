import Foundation
import OSLog

/// The one decision point for every `holy-ghostty://` URL that reaches the
/// app, whichever door it came through: `application(_:open:)`, the Apple
/// Event handler, or a Command-click on a Manna link inside a terminal.
///
/// The board route only navigates, so it stays open. The spawn route runs a
/// sender-chosen command on this Mac or on a configured SSH host, and a URL
/// scheme is reachable from any web page, mail, PDF, or `open` call without
/// the user ever choosing Holy. So the spawn route is refused unless the user
/// opted in, refused again when the URL carries a command and commands were
/// not separately allowed, refused when any value is shaped like an
/// injection, and even then it only ever asks: a session exists only after
/// the confirmation sheet's non-default button is clicked (mn-e9f9a9). tmux
/// session and socket names are held to a strict allowlist on top of that,
/// as defense in depth behind the builder's quoting (mn-e6e3d0).
enum HolyAutomationURLGate {
    struct Policy: Equatable, Sendable {
        var allowSpawnURL: Bool
        var allowSpawnURLCommands: Bool

        /// What a fresh install ships with: every spawn URL refused and logged.
        static let shippedDefault = Policy(allowSpawnURL: false, allowSpawnURLCommands: false)

        enum DefaultsKey {
            static let allowSpawnURL = "holy.automation.allowSpawnURL"
            static let allowSpawnURLCommands = "holy.automation.allowSpawnURLCommands"
        }

        /// A missing key reads as `false`; nothing here can default to open.
        static func fromUserDefaults(_ defaults: UserDefaults = .standard) -> Policy {
            Policy(
                allowSpawnURL: defaults.bool(forKey: DefaultsKey.allowSpawnURL),
                allowSpawnURLCommands: defaults.bool(forKey: DefaultsKey.allowSpawnURLCommands)
            )
        }
    }

    enum Refusal: Equatable, Sendable {
        case spawnURLsDisabled
        case commandsDisabled(fields: [String])
        case malformed(String)

        var reason: String {
            switch self {
            case .spawnURLsDisabled:
                let domain = Bundle.main.bundleIdentifier ?? "org.holyghostty.app"
                return "spawn URLs are off by default; enable Allow Spawn URLs in the Holy menu"
                    + " or run: defaults write \(domain) \(Policy.DefaultsKey.allowSpawnURL) -bool true"
            case let .commandsDisabled(fields):
                let domain = Bundle.main.bundleIdentifier ?? "org.holyghostty.app"
                return "the URL carries \(fields.joined(separator: ", ")) but commands in spawn URLs are off;"
                    + " enable Allow Commands in Spawn URLs in the Holy menu"
                    + " or run: defaults write \(domain) \(Policy.DefaultsKey.allowSpawnURLCommands) -bool true"
            case let .malformed(problem):
                return "malformed spawn URL: \(problem)"
            }
        }
    }

    enum Decision: Equatable {
        case board(itemID: String)
        case confirmSpawn(HolyAutomationSpawnRequest)
        case refused(Refusal)
        case unsupported
    }

    /// Every query parameter the spawn route understands. Anything else is
    /// refused rather than ignored, so a sender cannot smuggle a field past a
    /// reviewer under a name this parser happens not to read.
    static let spawnParameterNames: Set<String> = [
        "runtime", "host", "transport", "tmuxSession", "tmuxSocket", "createIfMissing",
        "title", "objective", "workingDirectory", "command", "bootstrapCommand", "initialInput",
    ]

    /// Fields whose value is executed or typed into the pane: `command` and
    /// `bootstrapCommand` are spliced into the launch shell script, and
    /// `initialInput` is sent as keystrokes after attach.
    static let commandBearingParameterNames: [String] = ["command", "bootstrapCommand", "initialInput"]

    static func decide(_ url: URL, policy: Policy) -> Decision {
        if let id = HolyAutomationURLParser.boardItemID(from: url) {
            return .board(itemID: id)
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == HolyAutomationURLParser.scheme,
              HolyAutomationURLParser.routeName(from: components) == "spawn" else {
            return .unsupported
        }

        guard policy.allowSpawnURL else {
            return .refused(.spawnURLsDisabled)
        }

        if let problem = structuralProblem(in: components) {
            return .refused(.malformed(problem))
        }

        guard let items = HolyAutomationURLParser.decodedQueryItems(in: components) else {
            return .refused(.malformed("a query name or value is not valid percent-encoded UTF-8"))
        }

        var seen = Set<String>()
        for item in items {
            guard spawnParameterNames.contains(item.name) else {
                return .refused(.malformed("unknown query parameter \(printable(item.name))"))
            }
            guard seen.insert(item.name).inserted else {
                return .refused(.malformed("duplicate query parameter \(item.name)"))
            }
        }

        for item in items {
            if let value = item.value, let problem = valueProblem(value, field: item.name) {
                return .refused(.malformed(problem))
            }
        }

        let commandFields = commandBearingParameterNames.filter { name in
            items.contains { $0.name == name && !($0.value ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
        }
        if commandFields.contains("command"), commandFields.contains("bootstrapCommand") {
            return .refused(.malformed("both command and bootstrapCommand were given"))
        }
        if !commandFields.isEmpty, !policy.allowSpawnURLCommands {
            return .refused(.commandsDisabled(fields: commandFields))
        }

        if let problem = semanticProblem(in: items) {
            return .refused(.malformed(problem))
        }

        guard let launchSpec = HolyAutomationURLParser.launchSpec(from: url) else {
            return .refused(.malformed("the spawn request could not be parsed"))
        }

        return .confirmSpawn(HolyAutomationSpawnRequest(
            url: url,
            launchSpec: launchSpec,
            commandFields: commandFields
        ))
    }

    // MARK: - Validation

    /// The board route's shape rules, applied to spawn: no userinfo, no port,
    /// no fragment, and no path once the route rides in the host slot.
    private static func structuralProblem(in components: URLComponents) -> String? {
        if components.user != nil || components.password != nil {
            return "URL carries user information"
        }
        if components.port != nil {
            return "URL carries a port"
        }
        if components.fragment != nil {
            return "URL carries a fragment"
        }
        if let host = components.host, !host.isEmpty,
           !(components.path.isEmpty || components.path == "/") {
            return "URL carries an extra path after the route"
        }
        return nil
    }

    private static func valueProblem(_ value: String, field: String) -> String? {
        for scalar in value.unicodeScalars {
            if CharacterSet.controlCharacters.contains(scalar)
                || CharacterSet.newlines.contains(scalar)
                || CharacterSet.illegalCharacters.contains(scalar) {
                return "control character U+\(hex(scalar)) in \(field)"
            }
            if bidiControlScalars.contains(scalar) {
                return "bidirectional control character U+\(hex(scalar)) in \(field)"
            }
        }
        return nil
    }

    private static func semanticProblem(in items: [HolyAutomationURLParser.DecodedQueryItem]) -> String? {
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value?
                .trimmingCharacters(in: .whitespaces)
                .nilIfEmpty
        }

        if let runtime = value("runtime"), HolyAutomationURLParser.runtimeValue(from: runtime) == nil {
            return "unrecognized runtime \(printable(runtime))"
        }

        let host = value("host")
        if let host, !HolySSHTransportManager.isValidDestination(host) {
            return "host is not a valid SSH destination"
        }

        if let transport = value("transport") {
            guard let kind = HolyAutomationURLParser.transportKind(from: transport) else {
                return "unrecognized transport \(printable(transport))"
            }
            if kind == .ssh, host == nil {
                return "transport ssh without a host"
            }
        }

        if let createIfMissing = value("createIfMissing"),
           HolyAutomationURLParser.boolValue(from: createIfMissing) == nil {
            return "unrecognized createIfMissing \(printable(createIfMissing))"
        }

        if let workingDirectory = value("workingDirectory") {
            guard workingDirectory.hasPrefix("/") || workingDirectory.hasPrefix("~") else {
                return "workingDirectory is not an absolute or home-relative path"
            }
            // tmux splits its argv into commands at any argument ending in an
            // unescaped `;`, and `-c <dir>` is followed by the pane command.
            if workingDirectory.hasSuffix(";") {
                return "workingDirectory ends with ;, which tmux reads as a command separator"
            }
        }

        if let session = value("tmuxSession"), !isAllowedTmuxSessionName(session) {
            return "tmuxSession \(printable(session)) is not [A-Za-z0-9_-]+"
        }

        if let socket = value("tmuxSocket"), !isAllowedTmuxSocketName(socket) {
            return "tmuxSocket \(printable(socket)) is not [A-Za-z0-9._-]+ or is only dots"
        }

        return nil
    }

    // MARK: - tmux names (mn-e6e3d0)

    /// ASCII letters, digits, `_`, and `-`. A session name becomes a tmux
    /// target (`-t name`), where `:` separates session from window and `.`
    /// window from pane, `$ @ %` select by id, `= ~ ^` and glob characters
    /// change how the name is matched, and a trailing `;` splits tmux's argv
    /// into a second command. None of those can reach a target from a link.
    static func isAllowedTmuxSessionName(_ name: String) -> Bool {
        !name.isEmpty && name.unicodeScalars.allSatisfy { isTmuxNameScalar($0) }
    }

    /// ASCII letters, digits, `.`, `_`, and `-`, and not only dots. A socket
    /// name is a file name under tmux's socket directory (`-L name`), so `/`
    /// would escape it and `.` or `..` would name the directory itself.
    static func isAllowedTmuxSocketName(_ name: String) -> Bool {
        !name.isEmpty
            && name.unicodeScalars.allSatisfy { isTmuxNameScalar($0) || $0 == "." }
            && !name.unicodeScalars.allSatisfy { $0 == "." }
    }

    private static func isTmuxNameScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "A" ... "Z", "a" ... "z", "0" ... "9", "_", "-":
            return true
        default:
            return false
        }
    }

    /// Unicode bidirectional controls can reorder how a value renders, so a
    /// sheet could show a different command than the one that would run.
    private static let bidiControlScalars: Set<Unicode.Scalar> = [
        "\u{061C}", "\u{200E}", "\u{200F}",
        "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}",
        "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}",
    ]

    private static func hex(_ scalar: Unicode.Scalar) -> String {
        String(scalar.value, radix: 16, uppercase: true)
    }

    /// Names and values quoted into an audit line must not themselves carry
    /// the characters they are being refused for.
    static func printable(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            if CharacterSet.controlCharacters.contains(scalar)
                || CharacterSet.newlines.contains(scalar)
                || CharacterSet.illegalCharacters.contains(scalar)
                || bidiControlScalars.contains(scalar) {
                result += "\\u{\(hex(scalar))}"
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return "\"\(result)\""
    }
}

/// A spawn the gate would allow once the user confirms it.
struct HolyAutomationSpawnRequest: Equatable {
    let url: URL
    let launchSpec: HolySessionLaunchSpec
    /// Which command-bearing fields the URL carried (`command`,
    /// `bootstrapCommand`, `initialInput`), empty for a bare runtime open.
    let commandFields: [String]

    var carriesCommand: Bool { !commandFields.isEmpty }

    var auditDetail: String {
        var parts = ["runtime \(launchSpec.runtime.rawValue)", "transport \(launchSpec.transport.kind.rawValue)"]
        if let destination = launchSpec.transport.sshDestination {
            parts.append("host \(destination)")
        }
        if let workingDirectory = launchSpec.workingDirectory {
            parts.append("workingDirectory \(workingDirectory)")
        }
        parts.append(carriesCommand ? "with \(commandFields.joined(separator: ", "))" : "without a command")
        return parts.joined(separator: ", ")
    }
}

/// Where a URL came from, when macOS says. Only the Apple Event path carries a
/// sender; `application(_:open:)` may or may not have a current event.
struct HolyAutomationURLOrigin: Equatable, Sendable {
    let processIdentifier: pid_t
    let applicationName: String?
    let bundleIdentifier: String?

    var displayText: String {
        let name = applicationName ?? bundleIdentifier ?? "an unnamed process"
        return "\(name) (pid \(processIdentifier))"
    }
}

/// One line per verdict, always carrying the full URL, so an audit can
/// reconstruct exactly what was asked and what the app did about it.
struct HolyAutomationURLAuditEntry: Equatable, Sendable {
    enum Verdict: String, Sendable {
        case refused
        case unsupported
        case prompted
        case confirmed
        case cancelled
    }

    let verdict: Verdict
    let detail: String
    let url: URL

    var line: String {
        "holy-ghostty automation URL \(verdict.rawValue) (\(detail)): \(url.absoluteString)"
    }
}

enum HolyAutomationURLAudit {
    static let logger = Logger(subsystem: "org.holyghostty.app", category: "HolyAutomationURL")

    static func log(_ entry: HolyAutomationURLAuditEntry) {
        switch entry.verdict {
        case .refused, .unsupported:
            logger.warning("\(entry.line, privacy: .public)")
        case .prompted, .confirmed, .cancelled:
            logger.notice("\(entry.line, privacy: .public)")
        }
    }
}

/// Seams the app delegate consults on every automation URL. Production leaves
/// every field nil: policy from UserDefaults, audit to the unified log, the
/// confirmation sheet, and `createAutomatedHolySession`. Tests fill them to
/// prove what each door does without touching the live roster.
struct HolyAutomationURLHooks {
    var policy: (@MainActor () -> HolyAutomationURLGate.Policy)?
    var audit: (@MainActor (HolyAutomationURLAuditEntry) -> Void)?
    var confirm: (@MainActor (
        HolyAutomationSpawnRequest,
        HolyAutomationURLOrigin?,
        _ completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) -> Void)?
    var launch: (@MainActor (HolySessionLaunchSpec) -> HolySession?)?

    init() {}
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
