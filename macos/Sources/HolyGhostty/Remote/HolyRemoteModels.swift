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
        label: String = "Machine",
        sshDestination: String = "",
        tmuxSocketName: String? = nil,
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
        return socketName.map { "tmux -L \($0)" } ?? "Automatic: default tmux + holy"
    }

    func normalized() -> HolyRemoteHostRecord {
        let normalizedDestination = sshDestination.holyTrimmed.nilIfEmpty ?? ""
        let normalizedLabel = label.holyTrimmed.nilIfEmpty
            ?? normalizedDestination.nilIfEmpty
            ?? "Machine"

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
        if let projectTitle = projectTitleForDefaultSession {
            return projectTitle
        }

        if let title = normalizedTitle {
            return title
        }

        if let gitSummary {
            return gitSummary.repositoryName
        }

        if isLocalHost {
            return sessionName
        }

        return "\(hostLabel)/\(sessionName)"
    }

    private var normalizedTitle: String? {
        title?.holyTrimmed.nilIfEmpty
    }

    private var projectTitleForDefaultSession: String? {
        guard normalizedTitle.map(Self.isGeneratedDefaultTitle) ?? true else {
            return nil
        }

        if let gitSummary {
            return gitSummary.repositoryName
        }

        guard let workingDirectory = workingDirectory?.holyTrimmed.nilIfEmpty else {
            return nil
        }

        let directoryName = URL(fileURLWithPath: workingDirectory)
            .standardizedFileURL
            .lastPathComponent
            .holyTrimmed
        guard let directoryName = directoryName.nilIfEmpty,
              !Self.isGenericWorkspaceName(directoryName) else {
            return nil
        }

        return directoryName
    }

    private static func isGeneratedDefaultTitle(_ title: String) -> Bool {
        let normalized = title.holyTrimmed
        guard !normalized.isEmpty else { return true }

        if normalized.range(
            of: #"^Shell\s+\d+$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return true
        }

        return ["Shell", "Claude", "Codex", "OpenCode"].contains { defaultTitle in
            normalized.caseInsensitiveCompare(defaultTitle) == .orderedSame
        }
    }

    private static func isGenericWorkspaceName(_ name: String) -> Bool {
        switch name.holyTrimmed.lowercased() {
        case "custom-coding", "custom_coding", "projects", "repos", "repositories", "workspace", "workspaces":
            return true
        default:
            return false
        }
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

    var tmuxServerSummary: String {
        if let tmuxSocketName = tmuxSocketName?.holyTrimmed.nilIfEmpty {
            return "tmux -L \(tmuxSocketName)"
        }

        return "Default tmux server"
    }

    private var isLocalHost: Bool {
        let normalizedDestination = hostDestination.holyTrimmed.lowercased()
        return normalizedDestination == "localhost"
            || normalizedDestination == "127.0.0.1"
            || normalizedDestination == "::1"
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
