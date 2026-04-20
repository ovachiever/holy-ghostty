import Foundation

struct HolyRemoteHostRecord: Codable, Equatable, Identifiable {
    let id: UUID
    var label: String
    var sshDestination: String
    var tmuxSocketName: String?
    var createdAt: Date
    var updatedAt: Date
    var lastDiscoveredAt: Date?

    init(
        id: UUID = UUID(),
        label: String = "Remote Host",
        sshDestination: String = "",
        tmuxSocketName: String? = HolySessionTmuxSpec.defaultSocketName,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastDiscoveredAt: Date? = nil
    ) {
        self.id = id
        self.label = label
        self.sshDestination = sshDestination
        self.tmuxSocketName = tmuxSocketName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastDiscoveredAt = lastDiscoveredAt
    }

    var displayTitle: String {
        label.holyTrimmed.nilIfEmpty
            ?? sshDestination.holyTrimmed.nilIfEmpty
            ?? "Remote Host"
    }

    var subtitle: String {
        sshDestination.holyTrimmed.nilIfEmpty ?? "No SSH destination"
    }

    var tmuxSummary: String {
        let socketName = tmuxSocketName?.holyTrimmed.nilIfEmpty
        return socketName.map { "tmux -L \($0)" } ?? "Default tmux server"
    }

    func normalized() -> HolyRemoteHostRecord {
        let normalizedDestination = sshDestination.holyTrimmed.nilIfEmpty ?? ""
        let normalizedLabel = label.holyTrimmed.nilIfEmpty
            ?? normalizedDestination.nilIfEmpty
            ?? "Remote Host"

        return .init(
            id: id,
            label: normalizedLabel,
            sshDestination: normalizedDestination,
            tmuxSocketName: tmuxSocketName?.holyTrimmed.nilIfEmpty,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastDiscoveredAt: lastDiscoveredAt
        )
    }
}

struct HolyDiscoveredTmuxSession: Equatable, Identifiable {
    let hostID: UUID
    let hostLabel: String
    let hostDestination: String
    let tmuxSocketName: String?
    let sessionName: String
    let title: String?
    let runtimeRawValue: String?
    let objective: String?
    let workingDirectory: String?
    let bootstrapCommand: String?
    let taskTitle: String?
    let taskSource: String?
    let gitSummary: HolyRemoteGitSummary?
    let attachedClientCount: Int
    let windowCount: Int
    let discoveredAt: Date

    var id: String {
        [
            hostID.uuidString,
            tmuxSocketName?.holyTrimmed.nilIfEmpty ?? "default",
            sessionName,
        ]
        .joined(separator: ":")
    }

    var runtime: HolySessionRuntime? {
        runtimeRawValue.flatMap(HolySessionRuntime.init(rawValue:))
    }

    var isHolyManaged: Bool {
        [
            title,
            runtimeRawValue,
            objective,
            workingDirectory,
            bootstrapCommand,
            taskTitle,
            taskSource,
        ]
        .contains { ($0?.holyTrimmed.nilIfEmpty) != nil }
    }

    var displayTitle: String {
        title?.holyTrimmed.nilIfEmpty ?? "\(hostLabel)/\(sessionName)"
    }

    var subtitle: String {
        if let objective = objective?.holyTrimmed.nilIfEmpty {
            return objective
        }

        if let runtime {
            return runtime.displayName
        }

        return sessionName
    }

    var statusSummary: String {
        let attachmentSummary = attachedClientCount == 1
            ? "1 client"
            : "\(attachedClientCount) clients"
        let windowSummary = windowCount == 1
            ? "1 window"
            : "\(windowCount) windows"
        var segments = [attachmentSummary, windowSummary]

        if let gitSummary {
            segments.append(gitSummary.changeSummaryText)
        }

        if isHolyManaged {
            segments.append("Holy metadata")
        }

        return segments.joined(separator: " · ")
    }
}

struct HolyRemoteGitSummary: Equatable {
    let repositoryRoot: String
    let branch: String
    let isDetachedHead: Bool
    let aheadCount: Int
    let behindCount: Int
    let stagedCount: Int
    let unstagedCount: Int
    let untrackedCount: Int
    let conflictedCount: Int

    var repositoryName: String {
        URL(fileURLWithPath: repositoryRoot).lastPathComponent
    }

    var branchDisplayName: String {
        if isDetachedHead {
            return "Detached HEAD"
        }

        return branch.holyTrimmed.nilIfEmpty ?? "Unknown Branch"
    }

    var changeCount: Int {
        stagedCount + unstagedCount + untrackedCount + conflictedCount
    }

    var changeSummaryText: String {
        if conflictedCount > 0 {
            return conflictedCount == 1 ? "1 conflict" : "\(conflictedCount) conflicts"
        }

        if changeCount == 0 {
            return "Clean"
        }

        return changeCount == 1 ? "1 change" : "\(changeCount) changes"
    }

    var syncStatusText: String {
        switch (aheadCount, behindCount) {
        case (0, 0):
            return "Current"
        case let (ahead, 0):
            return "Ahead \(ahead)"
        case let (0, behind):
            return "Behind \(behind)"
        case let (ahead, behind):
            return "Ahead \(ahead), Behind \(behind)"
        }
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
