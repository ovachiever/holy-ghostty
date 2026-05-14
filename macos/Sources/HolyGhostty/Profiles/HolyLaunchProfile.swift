import Foundation

enum HolyLaunchProfileSourceKind: String, Codable, CaseIterable {
    case localDefault
    case remoteHost
    case manual
}

struct HolyLaunchProfile: Codable, Equatable, Identifiable {
    static let localDefaultID = UUID(uuidString: "D527B433-13E4-4197-B0AE-55D28C1C7F7B")!

    let id: UUID
    var name: String
    var summary: String?
    var sourceKind: HolyLaunchProfileSourceKind
    var sourceRemoteHostID: UUID?
    var launchSpec: HolySessionLaunchSpec
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        summary: String? = nil,
        sourceKind: HolyLaunchProfileSourceKind = .manual,
        sourceRemoteHostID: UUID? = nil,
        launchSpec: HolySessionLaunchSpec,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.sourceKind = sourceKind
        self.sourceRemoteHostID = sourceRemoteHostID
        self.launchSpec = launchSpec
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var normalized: Self {
        var copy = self
        copy.name = name.holyProfileTrimmed.nilIfEmpty ?? "Launch Profile"
        copy.summary = summary?.holyProfileTrimmed.nilIfEmpty
        copy.launchSpec.transport = launchSpec.transport.normalized
        copy.launchSpec.tmux = launchSpec.tmux?.normalized
        return copy
    }

    var isRemote: Bool {
        launchSpec.transport.isRemote
    }

    static func localDefault(createdAt: Date = .now, updatedAt: Date = .now) -> Self {
        .init(
            id: localDefaultID,
            name: "Local Mac",
            summary: "Create a Holy-managed local tmux session.",
            sourceKind: .localDefault,
            sourceRemoteHostID: nil,
            launchSpec: .init(
                runtime: .shell,
                title: "Shell",
                objective: nil,
                transport: .local,
                tmux: .holyManagedDefault,
                workingDirectory: HolyLocalTmuxDefaults.workingDirectory,
                command: nil,
                initialInput: nil,
                waitAfterCommand: false,
                environment: [:],
                workspace: nil
            ),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func remoteDefault(for host: HolyRemoteHostRecord, createdAt: Date = .now) -> Self {
        let normalizedHost = host.normalized()
        return .init(
            name: normalizedHost.displayTitle,
            summary: "Create a Holy-managed tmux session over SSH.",
            sourceKind: .remoteHost,
            sourceRemoteHostID: normalizedHost.id,
            launchSpec: remoteLaunchSpec(for: normalizedHost),
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    func updated(from host: HolyRemoteHostRecord) -> Self {
        let normalizedHost = host.normalized()
        var copy = self
        copy.name = normalizedHost.displayTitle
        copy.summary = summary?.holyProfileTrimmed.nilIfEmpty ?? "Create a Holy-managed tmux session over SSH."
        copy.sourceKind = .remoteHost
        copy.sourceRemoteHostID = normalizedHost.id
        copy.launchSpec = Self.remoteLaunchSpec(for: normalizedHost)
        copy.updatedAt = .now
        return copy
    }

    func launchSpecForNewSession(fallbackTitle: String) -> HolySessionLaunchSpec {
        var spec = normalized.launchSpec
        let title = spec.title.holyProfileTrimmed
        if title.isEmpty || title == "Shell" {
            spec.title = fallbackTitle
        }

        if spec.transport.isRemote {
            spec.workspace = nil
        }

        return spec
    }

    private static func remoteLaunchSpec(for host: HolyRemoteHostRecord) -> HolySessionLaunchSpec {
        .init(
            runtime: .shell,
            title: "Shell",
            objective: nil,
            transport: .init(
                kind: .ssh,
                hostLabel: host.displayTitle,
                sshDestination: host.sshDestination
            ),
            tmux: .init(
                socketName: host.tmuxSocketName?.holyProfileTrimmed.nilIfEmpty ?? HolySessionTmuxSpec.defaultSocketName,
                sessionName: nil,
                createIfMissing: true
            ),
            workingDirectory: HolyLocalTmuxDefaults.workingDirectory,
            command: nil,
            initialInput: nil,
            waitAfterCommand: false,
            environment: [:],
            workspace: nil
        )
    }
}

struct HolyLaunchProfileState: Equatable {
    var profiles: [HolyLaunchProfile]
    var defaultProfileID: UUID?

    var defaultProfile: HolyLaunchProfile? {
        guard let defaultProfileID else { return profiles.first }
        return profiles.first(where: { $0.id == defaultProfileID }) ?? profiles.first
    }
}

private extension String {
    var holyProfileTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
