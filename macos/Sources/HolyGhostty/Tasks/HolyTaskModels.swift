import Foundation

enum HolyTaskSourceKind: String, Codable, CaseIterable, Identifiable {
    case manual
    case githubIssue
    case linearIssue
    case jiraIssue
    case genericURL

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual:
            return "Manual"
        case .githubIssue:
            return "GitHub"
        case .linearIssue:
            return "Linear"
        case .jiraIssue:
            return "Jira"
        case .genericURL:
            return "External"
        }
    }

    static func inferred(from canonicalURL: String?) -> HolyTaskSourceKind {
        guard let canonicalURL,
              let url = URL(string: canonicalURL),
              let host = url.host?.lowercased() else {
            return .manual
        }

        if host.contains("github.com") {
            return .githubIssue
        }

        if host.contains("linear.app") {
            return .linearIssue
        }

        if host.contains("atlassian.net") || host.contains("jira") {
            return .jiraIssue
        }

        return .genericURL
    }

    static func inferredExternalID(from canonicalURL: String?, sourceKind: HolyTaskSourceKind) -> String? {
        guard let canonicalURL,
              let url = URL(string: canonicalURL) else {
            return nil
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }

        switch sourceKind {
        case .githubIssue:
            guard pathComponents.count >= 4,
                  pathComponents[2].lowercased() == "issues" else {
                return nil
            }
            return "\(pathComponents[0])/\(pathComponents[1])#\(pathComponents[3])"
        case .linearIssue:
            return pathComponents.last
        case .jiraIssue:
            return pathComponents.last
        case .genericURL, .manual:
            return nil
        }
    }
}

enum HolyExternalTaskStatus: String, Codable, CaseIterable {
    case inbox
    case claimed
    case active
    case waitingInput
    case done
    case failed
    case archived

    var displayName: String {
        switch self {
        case .inbox:
            return "Inbox"
        case .claimed:
            return "Claimed"
        case .active:
            return "Active"
        case .waitingInput:
            return "Needs Input"
        case .done:
            return "Done"
        case .failed:
            return "Failed"
        case .archived:
            return "Archived"
        }
    }
}

struct HolyExternalTaskReference: Codable, Equatable, Identifiable {
    let id: UUID
    var sourceKind: HolyTaskSourceKind
    var sourceLabel: String
    var externalID: String?
    var canonicalURL: String?
    var title: String
    var summary: String?

    init(
        id: UUID,
        sourceKind: HolyTaskSourceKind,
        sourceLabel: String,
        externalID: String?,
        canonicalURL: String?,
        title: String,
        summary: String?
    ) {
        self.id = id
        self.sourceKind = sourceKind
        self.sourceLabel = sourceLabel
        self.externalID = externalID
        self.canonicalURL = canonicalURL
        self.title = title
        self.summary = summary
    }

    var sourceSummary: String {
        if let externalID, !externalID.isEmpty {
            return "\(sourceLabel) · \(externalID)"
        }

        return sourceLabel
    }
}

struct HolyExternalTaskRecord: Codable, Equatable, Identifiable {
    let id: UUID
    var sourceKind: HolyTaskSourceKind
    var sourceLabel: String
    var externalID: String?
    var canonicalURL: String?
    var title: String
    var summary: String
    var preferredRuntime: HolySessionRuntime
    var preferredWorkingDirectory: String?
    var preferredRepositoryRoot: String?
    var preferredCommand: String?
    var preferredInitialInput: String?
    var status: HolyExternalTaskStatus
    var linkedSessionID: UUID?
    var linkedSessionTitle: String?
    var linkedSessionPhase: HolySessionPhase?
    var createdAt: Date
    var updatedAt: Date
    var lastImportedAt: Date?

    init(
        id: UUID = UUID(),
        sourceKind: HolyTaskSourceKind = .manual,
        sourceLabel: String = HolyTaskSourceKind.manual.displayName,
        externalID: String? = nil,
        canonicalURL: String? = nil,
        title: String = "Untitled Task",
        summary: String = "",
        preferredRuntime: HolySessionRuntime = .codex,
        preferredWorkingDirectory: String? = nil,
        preferredRepositoryRoot: String? = nil,
        preferredCommand: String? = nil,
        preferredInitialInput: String? = nil,
        status: HolyExternalTaskStatus = .inbox,
        linkedSessionID: UUID? = nil,
        linkedSessionTitle: String? = nil,
        linkedSessionPhase: HolySessionPhase? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastImportedAt: Date? = nil
    ) {
        self.id = id
        self.sourceKind = sourceKind
        self.sourceLabel = sourceLabel
        self.externalID = externalID
        self.canonicalURL = canonicalURL
        self.title = title
        self.summary = summary
        self.preferredRuntime = preferredRuntime
        self.preferredWorkingDirectory = preferredWorkingDirectory
        self.preferredRepositoryRoot = preferredRepositoryRoot
        self.preferredCommand = preferredCommand
        self.preferredInitialInput = preferredInitialInput
        self.status = status
        self.linkedSessionID = linkedSessionID
        self.linkedSessionTitle = linkedSessionTitle
        self.linkedSessionPhase = linkedSessionPhase
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastImportedAt = lastImportedAt
    }

    var reference: HolyExternalTaskReference {
        .init(
            id: id,
            sourceKind: sourceKind,
            sourceLabel: sourceLabel,
            externalID: externalID,
            canonicalURL: canonicalURL,
            title: title,
            summary: summary.nilIfBlank
        )
    }

    var sourceSummary: String {
        reference.sourceSummary
    }

    var linkedSessionSummary: String {
        if let linkedSessionTitle, let linkedSessionPhase {
            return "\(linkedSessionTitle) · \(linkedSessionPhase.displayName)"
        }

        if let linkedSessionTitle {
            return linkedSessionTitle
        }

        return "No linked session"
    }

    func normalized() -> HolyExternalTaskRecord {
        let normalizedURL = canonicalURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        let inferredSourceKind = HolyTaskSourceKind.inferred(from: normalizedURL)
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? "Untitled Task"
        let normalizedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)

        return .init(
            id: id,
            sourceKind: normalizedURL == nil ? .manual : inferredSourceKind,
            sourceLabel: normalizedURL == nil ? HolyTaskSourceKind.manual.displayName : inferredSourceKind.displayName,
            externalID: normalizedURL == nil ? nil : HolyTaskSourceKind.inferredExternalID(from: normalizedURL, sourceKind: inferredSourceKind),
            canonicalURL: normalizedURL,
            title: normalizedTitle,
            summary: normalizedSummary,
            preferredRuntime: preferredRuntime,
            preferredWorkingDirectory: preferredWorkingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            preferredRepositoryRoot: preferredRepositoryRoot?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            preferredCommand: preferredCommand?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            preferredInitialInput: preferredInitialInput?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            status: status,
            linkedSessionID: linkedSessionID,
            linkedSessionTitle: linkedSessionTitle,
            linkedSessionPhase: linkedSessionPhase,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastImportedAt: lastImportedAt
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
