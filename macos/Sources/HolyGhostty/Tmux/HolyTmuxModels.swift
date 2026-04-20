import Foundation

enum HolySessionTransportKind: String, Codable, CaseIterable, Identifiable {
    case local
    case ssh

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .local:
            return "Local"
        case .ssh:
            return "SSH"
        }
    }
}

struct HolySessionTransportSpec: Codable, Equatable {
    var kind: HolySessionTransportKind = .local
    var hostLabel: String?
    var sshDestination: String?

    static let local = Self()

    var isRemote: Bool {
        kind == .ssh
    }

    var destinationDisplayName: String {
        if let hostLabel = hostLabel?.holyTrimmed.nilIfEmpty {
            return hostLabel
        }

        if let sshDestination = sshDestination?.holyTrimmed.nilIfEmpty {
            return sshDestination
        }

        return kind.displayName
    }

    var summaryText: String {
        switch kind {
        case .local:
            return "Local tmux session"
        case .ssh:
            return "SSH to \(destinationDisplayName)"
        }
    }

    var normalized: Self {
        .init(
            kind: kind,
            hostLabel: hostLabel?.holyTrimmed.nilIfEmpty,
            sshDestination: sshDestination?.holyTrimmed.nilIfEmpty
        )
    }
}

struct HolySessionTmuxSpec: Codable, Equatable {
    static let defaultSocketName = "holy"

    var socketName: String?
    var sessionName: String?
    var createIfMissing: Bool = true

    static let holyManagedDefault = Self(
        socketName: Self.defaultSocketName,
        sessionName: nil,
        createIfMissing: true
    )

    var normalized: Self {
        .init(
            socketName: socketName?.holyTrimmed.nilIfEmpty,
            sessionName: sessionName?.holyTrimmed.nilIfEmpty,
            createIfMissing: createIfMissing
        )
    }

    var serverLabel: String {
        if let socketName = socketName?.holyTrimmed.nilIfEmpty {
            return "Socket \(socketName)"
        }

        return "Default Server"
    }

    var sessionDisplayName: String {
        sessionName?.holyTrimmed.nilIfEmpty ?? "Automatic"
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
