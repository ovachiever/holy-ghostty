import Foundation

enum HolyArchiveHarness: String, Codable, CaseIterable, Identifiable, Sendable {
    case claudeCode = "claude-code"
    case codex
    case droid
    case cursor
    case opencode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .droid: "Droid"
        case .cursor: "Cursor"
        case .opencode: "OpenCode"
        }
    }

    var icon: String {
        switch self {
        case .claudeCode: "brain.head.profile"
        case .codex: "sparkles"
        case .droid: "cpu"
        case .cursor: "cursorarrow"
        case .opencode: "terminal"
        }
    }

    /// Cursor and OpenCode discover conversations through database queries
    /// and virtual paths. A startup quick pass must not sweep either store.
    var supportsFastDiscovery: Bool {
        switch self {
        case .cursor, .opencode: false
        default: true
        }
    }

    var runtime: HolySessionRuntime? {
        switch self {
        case .claudeCode: .claude
        case .codex: .codex
        case .opencode: .opencode
        case .droid, .cursor: nil
        }
    }
}

enum HolyArchiveMessageRole: String, Codable, Sendable {
    case user
    case assistant
    case tool
    case system
    case developer
    case unknown
}

struct HolyArchiveMessage: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let sessionID: String
    let role: HolyArchiveMessageRole
    let content: String
    let timestamp: Date?
    let sequence: Int

    var hasCode: Bool {
        content.contains("```") || content.contains("def ") || content.contains("function ")
    }

    var toolMentions: [String] {
        HolyArchiveText.agentDoToolMentions(in: content)
    }
}

struct HolyArchiveSession: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let harness: HolyArchiveHarness
    let rawPath: String
    let projectPath: String?
    let projectName: String
    var title: String
    var firstPrompt: String
    var lastPrompt: String
    var lastResponse: String
    let createdAt: Date
    var modifiedAt: Date?
    var isChild: Bool
    var childType: String?
    var parentID: String?
    var model: String?
    var toolCalls: [String]
    var tokensUsed: Int?
    var summary: String?
    var contentHash: String
    var extra: [String: String]
    var resumeCommand: String?
    var messageCount: Int
    var turnCount: Int
    let fileMTime: Date
    var indexedAt: Date
    var autoTags: [String]

    var activityAt: Date { modifiedAt ?? createdAt }
    var isParent: Bool { !isChild }

    var displayTitle: String {
        if let summary = summary?.holyArchiveNilIfBlank { return summary }
        if let first = HolyArchiveText.firstRealLine(in: firstPrompt) { return first }
        if let title = title.holyArchiveNilIfBlank { return title }
        return "Untitled session"
    }

    var citationLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm"
        return "[\(harness.rawValue)/\(projectName) @ \(formatter.string(from: activityAt)) · \(shortID)]"
    }

    var shortID: String { String(id.prefix(8)) }
}

enum HolyArchiveChunkType: String, Codable, CaseIterable, Sendable {
    case summary
    case turn
    case toolUsage = "tool_usage"
}

struct HolyArchiveChunk: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let sessionID: String
    let messageID: String?
    let index: Int
    let type: HolyArchiveChunkType
    let content: String
    let metadata: [String: String]
    var embedding: [Float]?
    var embeddingModel: String?
    let createdAt: Date
}

struct HolyArchiveAnnotation: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case tag
        case note
    }

    let id: Int64
    let sessionID: String
    let timestamp: Date
    let kind: Kind
    let value: String
    let source: String
}

struct HolyArchiveSearchQuery: Equatable, Sendable {
    var text: String
    var harness: HolyArchiveHarness?
    var rawHarness: String?
    var project: String?
    var after: Date?
    var before: Date?
    var tags: [String]

    var isFiltersOnly: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

enum HolyArchiveMatchSource: String, Codable, Sendable {
    case keyword
    case metadata
    case semantic
}

struct HolyArchiveSearchResult: Identifiable, Equatable, Sendable {
    let session: HolyArchiveSession
    let score: Double
    let keywordScore: Double?
    let semanticScore: Double?
    let matchSnippet: String?
    let matchSource: HolyArchiveMatchSource

    var id: String { session.id }
}

struct HolyArchiveSearchHistoryEntry: Identifiable, Hashable, Sendable {
    let id: Int64
    let query: String
    let resultCount: Int
    let topSessionIDs: [String]
    let searchTimeMilliseconds: Double
    let timestamp: Date
}

struct HolyArchiveProject: Identifiable, Hashable, Sendable {
    let path: String
    let name: String
    let totalSessions: Int
    let parentSessions: Int
    let childSessions: Int
    let firstSessionAt: Date?
    let lastSessionAt: Date?
    let harnesses: [HolyArchiveHarness]
    let totalMessages: Int
    let commonTags: [String]

    var id: String { path }
}

struct HolyArchiveIndexProgress: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable {
        case discovering
        case migrating
        case indexing
        case embedding
        case finishing
    }

    let phase: Phase
    let completed: Int
    let total: Int
    let detail: String
}

struct HolyArchiveIndexReceipt: Equatable, Sendable {
    var sessionsIndexed = 0
    var messagesIndexed = 0
    var chunksCreated = 0
    var projectsUpdated = 0
    var embeddingsCreated = 0
    var failures: [String] = []
    var elapsedMilliseconds: Double = 0
}

struct HolyArchiveResearchChat: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var backend: String
    var model: String
    var stateJSON: String
    var metadataJSON: String
}

struct HolyArchiveResearchMessage: Identifiable, Hashable, Sendable {
    let id: Int64
    let chatID: String
    let sequence: Int
    let role: HolyArchiveMessageRole
    let content: String
    let toolCallJSON: String?
    let toolOutputJSON: String?
    let citedSessionIDs: [String]
    let createdAt: Date
}

struct HolyArchiveResearchAnswer: Equatable, Sendable {
    let text: String
    let citedSessionIDs: [String]
    let recommendedSessionID: String?
}

struct HolyArchiveResolveCandidate: Identifiable, Equatable, Sendable {
    let session: HolyArchiveSession
    let distance: TimeInterval

    var id: String { session.id }
}

enum HolyArchiveResolveConfidence: String, Codable, Sendable {
    case none
    case exact
    case ambiguous
}

struct HolyArchiveResolveResult: Equatable, Sendable {
    let confidence: HolyArchiveResolveConfidence
    let candidates: [HolyArchiveSession]

    var matchedSession: HolyArchiveSession? {
        confidence == .exact ? candidates.first : nil
    }
}

protocol HolyArchiveProviding: Sendable {
    var harness: HolyArchiveHarness { get }
    var sessionsDirectory: URL { get }
    var isAvailable: Bool { get }
    func discoverSessionFiles() throws -> [URL]
    /// Nil means the provider cannot narrow discovery. An empty array means
    /// it narrowed correctly and found no files for the project.
    func discoverSessionFiles(forProjectPath projectPath: String) throws -> [URL]?
    func modificationDate(for url: URL) throws -> Date
    func parseSession(at url: URL) throws -> (HolyArchiveSession, [HolyArchiveMessage])?
    func resumeCommand(for session: HolyArchiveSession) -> String?
}

enum HolyArchiveFileTime {
    /// Foundation can preserve filesystem subsecond state that does not survive
    /// a SQLite REAL round trip even when both values expose the same Unix time.
    /// A microsecond remains well below the resolution relevant to archive files.
    static func matches(_ lhs: Date, _ rhs: Date) -> Bool {
        abs(lhs.timeIntervalSince1970 - rhs.timeIntervalSince1970) < 0.000_001
    }
}

extension HolyArchiveProviding {
    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: sessionsDirectory.path)
    }

    func discoverSessionFiles(forProjectPath projectPath: String) throws -> [URL]? { nil }

    func modificationDate(for url: URL) throws -> Date {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
        return values.contentModificationDate ?? .distantPast
    }
}

enum HolyArchiveDate {
    private static let fractionalISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainISO8601 = ISO8601DateFormatter()

    static func parse(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            var seconds = number.doubleValue
            if seconds > 10_000_000_000 { seconds /= 1_000 }
            return Date(timeIntervalSince1970: seconds)
        }
        guard let raw = value as? String else { return nil }
        if let seconds = Double(raw) {
            return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1_000 : seconds)
        }
        return fractionalISO8601.date(from: raw) ?? plainISO8601.date(from: raw)
    }

    static func format(_ date: Date?) -> String? {
        date.map { plainISO8601.string(from: $0) }
    }
}

enum HolyArchiveText {
    static let skipPrefixes = [
        "[Request interrupted",
        "<local-command-caveat>",
        "<local-command-stdout>",
        "<command-name>",
        "<command-message>",
        "<command-instruction>",
        "<system-reminder>",
        "<system-notification>",
        "[COMPACTION CONTEXT",
        "<ultrawork-mode>",
    ]

    static func isMetaMessage(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return skipPrefixes.contains { trimmed.hasPrefix($0) }
    }

    /// The first line of a prompt that is not harness chatter: what a row
    /// shows when no summary exists, and what a title falls back to.
    static func firstRealLine(in value: String) -> String? {
        for line in value.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || isMetaMessage(trimmed) { continue }
            return trimmed
        }
        return nil
    }

    static func firstRealPrompt(in messages: [HolyArchiveMessage]) -> String {
        let user = messages.filter { $0.role == .user }
        return user.first(where: {
            !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !isMetaMessage($0.content)
                && $0.content.count >= 20
        })?.content
            ?? user.first?.content
            ?? ""
    }

    static func lastRealPrompt(in messages: [HolyArchiveMessage]) -> String {
        messages.last(where: {
            $0.role == .user
                && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !isMetaMessage($0.content)
        })?.content ?? ""
    }

    static func lastRealResponse(in messages: [HolyArchiveMessage]) -> String {
        messages.last(where: {
            $0.role == .assistant
                && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !isMetaMessage($0.content)
        })?.content
            ?? messages.last(where: { $0.role == .assistant })?.content
            ?? ""
    }

    static func preview(_ value: String, limit: Int) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(max(0, limit - 3))) + "..."
    }

    static func agentDoToolMentions(in value: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"agent-do\s+([A-Za-z0-9_-]+)"#) else {
            return []
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        var seen = Set<String>()
        return regex.matches(in: value, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: value) else { return nil }
            let name = String(value[range])
            return seen.insert(name).inserted ? name : nil
        }
    }

    static func automatedSessionType(_ prompt: String) -> String? {
        let sample = String(prompt.prefix(500)).trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = sample.lowercased()
        let ordered: [(String, String)] = [
            ("<system-notification>", "system-notification"),
            ("<command-message>", "command-message"),
            ("<command-instruction>", "command-instruction"),
            ("<local-command-caveat>", "command-caveat"),
            ("<ultrawork-mode>", "ultrawork-mode"),
            ("[search-mode]", "search-mode"),
            ("[analyze-mode]", "analyze-mode"),
            ("[system directive", "system-directive"),
            ("[compaction context", "compaction-context"),
            ("[gas town]", "ci-dispatch"),
            ("gt boot", "ci-dispatch"),
            ("gt prime", "ci-dispatch"),
            ("gt hook", "ci-dispatch"),
            ("run `gt hook`", "ci-dispatch"),
            ("run `gt boot`", "ci-dispatch"),
            ("summarize the task tool output above", "subagent-continuation"),
        ]
        if let match = ordered.first(where: { lower.hasPrefix($0.0) }) { return match.1 }
        if lower.contains("polecat dispatched") {
            return "ci-dispatch"
        }
        return nil
    }
}

extension String {
    var holyArchiveNilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var holyArchiveFirstLine: String? {
        split(whereSeparator: \Character.isNewline).first.map(String.init)
    }
}
