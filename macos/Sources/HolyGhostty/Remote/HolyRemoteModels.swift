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

    var connectionRuntime: HolySessionRuntime {
        runtime ?? .shell
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

    var shouldHideFromDiscovery: Bool {
        if isGeneratedHolyShellSessionName && !hasMeaningfulDiscoveryIdentity {
            return true
        }

        if isSymbolOnlyShellSession {
            return true
        }

        return isHolyManagedShellSession && isGenericWorkspaceSession && !hasMeaningfulDiscoveryIdentity
    }

    private var isGeneratedHolyShellSessionName: Bool {
        let normalized = sessionName.holyTrimmed.lowercased()
        return normalized.hasPrefix("holy-shell-") && normalized.contains("-shell-")
    }

    private var isHolyManagedShellSession: Bool {
        isHolyManaged && connectionRuntime == .shell
    }

    private var isSymbolOnlyShellSession: Bool {
        guard connectionRuntime == .shell else { return false }

        let candidate = normalizedTitle ?? sessionName
        let trimmed = candidate.holyTrimmed
        guard !trimmed.isEmpty, trimmed.count <= 2 else { return false }

        return !trimmed.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }

    private var isGenericWorkspaceSession: Bool {
        if Self.isGenericWorkspaceName(sessionName) {
            return true
        }

        if let title = normalizedTitle,
           Self.isGenericWorkspaceName(title) {
            return true
        }

        if let workingDirectory = workingDirectory?.holyTrimmed.nilIfEmpty,
           Self.isGenericWorkspaceName(URL(fileURLWithPath: workingDirectory).lastPathComponent) {
            return true
        }

        return false
    }

    private var hasMeaningfulDiscoveryIdentity: Bool {
        if usableExplicitTitle != nil {
            return true
        }

        if (objective?.holyTrimmed.nilIfEmpty) != nil
            || (bootstrapCommand?.holyTrimmed.nilIfEmpty) != nil
            || (taskTitle?.holyTrimmed.nilIfEmpty) != nil
            || (taskSource?.holyTrimmed.nilIfEmpty) != nil {
            return true
        }

        if gitSummary != nil || projectTitleForDefaultSession != nil {
            return true
        }

        return false
    }

    var displayTitle: String {
        if let projectTitle = projectTitleForDefaultSession {
            return projectTitle
        }

        if let title = usableExplicitTitle {
            return title
        }

        if let gitSummary {
            return Self.displayName(fromPathComponent: gitSummary.repositoryName) ?? gitSummary.repositoryName
        }

        if isLocalHost {
            return sessionName
        }

        return "\(hostLabel)/\(sessionName)"
    }

    private var normalizedTitle: String? {
        title?.holyTrimmed.nilIfEmpty
    }

    private var usableExplicitTitle: String? {
        guard let title = normalizedTitle,
              !Self.isGeneratedDefaultTitle(title),
              !Self.isInternalHolyTmuxTitle(title),
              !Self.isLocalMachineTitle(title),
              !Self.isGenericWorkspaceName(title),
              !Self.isLiveAgentStatusTitle(title) else {
            return nil
        }

        return Self.displayName(fromPathComponent: title) ?? title
    }

    private var projectTitleForDefaultSession: String? {
        guard usableExplicitTitle == nil else {
            return nil
        }

        if let gitSummary {
            return Self.displayName(fromPathComponent: gitSummary.repositoryName) ?? gitSummary.repositoryName
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

        return Self.displayName(fromPathComponent: directoryName) ?? directoryName
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

    private static func isInternalHolyTmuxTitle(_ title: String) -> Bool {
        let isInternalComponent: (String) -> Bool = { component in
            component.range(
                of: #"^holy-[a-z0-9-]+-[0-9A-Fa-f]{8}$"#,
                options: .regularExpression
            ) != nil
        }

        if isInternalComponent(title) {
            return true
        }

        return title
            .components(separatedBy: CharacterSet(charactersIn: "/: "))
            .contains(where: isInternalComponent)
    }

    private static func isLocalMachineTitle(_ title: String) -> Bool {
        let key = normalizedComparisonKey(title)
        guard !key.isEmpty else { return true }

        let genericKeys: Set<String> = [
            "local",
            "local mac",
            "mac",
            "machine",
            "this mac",
            "localhost",
        ]
        if genericKeys.contains(key) || key.hasSuffix(" local") {
            return true
        }

        return localMachineTitleCandidates()
            .map(normalizedComparisonKey)
            .contains(key)
    }

    private static func isGenericWorkspaceName(_ name: String) -> Bool {
        switch normalizedComparisonKey(name) {
        case "custom coding", "projects", "repos", "repositories", "workspace", "workspaces":
            return true
        default:
            return false
        }
    }

    private static func isLiveAgentStatusTitle(_ title: String) -> Bool {
        guard let first = title.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return false
        }

        return "✱✳✻✽✢⏺●○◐◓◑◒•·⠂⠄⠆⠇⠋⠐⠴⠼⠿".contains(first)
    }

    private static func localMachineTitleCandidates() -> [String] {
        let processInfo = ProcessInfo.processInfo
        return [
            Host.current().localizedName,
            processInfo.hostName,
            processInfo.environment["HOSTNAME"],
        ].compactMap { value in
            guard let trimmed = value?.holyTrimmed.nilIfEmpty else {
                return nil
            }
            return trimmed
        }
    }

    private static func normalizedComparisonKey(_ value: String) -> String {
        let scalars = value
            .lowercased()
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }

        return String(scalars)
            .split(separator: " ")
            .joined(separator: " ")
    }

    private static func displayName(fromPathComponent component: String) -> String? {
        let normalized = component
            .holyTrimmed
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let words = normalized
            .split(separator: " ")
            .map(String.init)
        guard !words.isEmpty else { return nil }

        return words.map { word in
            if word.contains(".") || word == word.uppercased() {
                return word
            }

            return word.prefix(1).uppercased() + String(word.dropFirst())
        }
        .joined(separator: " ")
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

    var connectionRosterSummary: String {
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
