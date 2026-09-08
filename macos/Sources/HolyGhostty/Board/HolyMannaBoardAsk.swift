import CryptoKit
import Foundation

enum HolyMannaAskError: LocalizedError, Equatable {
    case timedOut
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .timedOut: "The board answer timed out after 60 seconds. Press Enter to try again."
        case let .unavailable(message): message
        }
    }
}

struct HolyMannaBoardQuestion: Sendable {
    // Verbatim serve/digest.py ASK_SYSTEM. Board text is data, never authority.
    static let system = "You answer questions about a software project board using only the rows you are given. "
        + "Read every row before answering, including rows marked done: a done item that covers the question "
        + "means the board covers it and the work is finished; say which state each cited item is in. "
        + "Cite the item id (mn-xxxxxx) inline for every item you mention, and never cite an id that is not in the rows. "
        + "If nothing on the board covers the question, say so plainly. "
        + "Two short paragraphs at most; no headings, no bullet lists, no preamble."

    let question: String
    let rows: String
    let allowedIDs: Set<String>
    let contentHash: String
    let context: HolyMannaBoardContext
    let model: String

    init(question: String, state: HolyMannaStatePayload, context: HolyMannaBoardContext, model: String) throws {
        self.question = question.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        self.context = context
        self.model = model
        let items = state.allVisibleItems.filter { $0.kind != "track" }.sorted { $0.id < $1.id }
        allowedIDs = Set(items.map(\.id))
        rows = try Self.rows(for: items)
        contentHash = Self.hash(rows)
    }

    static func contentHash(_ state: HolyMannaStatePayload) -> String? {
        (try? rows(for: state.allVisibleItems.filter { $0.kind != "track" }.sorted { $0.id < $1.id })).map(hash)
    }

    private static func rows(for items: [HolyMannaBoardItem]) throws -> String {
        // JSON keeps arbitrary descriptions from forging row boundaries. Include done
        // and every field that can change the meaning of a board answer.
        let rows = items.map { item -> [String: Any] in
            ["id": item.id, "state": item.effective, "status": item.status,
             "title": item.title, "digest": item.digest ?? "", "summary": item.summary ?? "",
             "description": item.description ?? "", "kind": item.kind,
             "track": item.track ?? "", "track_title": item.trackTitle ?? "",
             "claimant": item.claimedBy ?? item.claimant?.label ?? "",
             "blockers": item.blockedBy.sorted().joined(separator: ","),
             "handoff": item.prompt ?? "", "handoff_digest": item.handoffDigest ?? "",
             "created_at": item.createdAt ?? "", "updated_at": item.updatedAt ?? "",
             "claimed_at": item.claimedAt ?? "", "order": item.order ?? -1,
             "decision": item.decision, "dependents": item.dependents.sorted(),
             "commits": item.commits.map { ["sha": $0.sha, "at": $0.at, "subject": $0.subject] }]
        }
        let data = try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys])
        guard let text = String(bytes: data, encoding: .utf8) else {
            throw HolyMannaAskError.unavailable("The board rows could not be encoded. No question was sent.")
        }
        return text
    }

    static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    var cacheKey: String {
        Self.hash([context.remoteHost ?? "local", context.boardRoot ?? "", model, question, contentHash]
            .joined(separator: "\u{0}"))
    }
}

struct HolyMannaBoardAnswer: Equatable, Sendable {
    let text: String
    let citedIDs: [String]
    let model: String
    let contentHash: String
    var wasCached = false

    static func validated(_ text: String, for request: HolyMannaBoardQuestion) -> Self {
        guard let regex = try? NSRegularExpression(pattern: #"\bmn-[0-9a-f]{6,}\b"#) else {
            preconditionFailure("Invalid built-in Manna ID pattern")
        }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var cited: [String] = []
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            let id = String(text[range])
            if request.allowedIDs.contains(id), !cited.contains(id) { cited.append(id) }
        }
        var sanitized = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: sanitized) else { continue }
            if !request.allowedIDs.contains(String(sanitized[range])) {
                sanitized.replaceSubrange(range, with: "[unknown board item omitted]")
            }
        }
        return .init(text: sanitized, citedIDs: cited, model: request.model, contentHash: request.contentHash)
    }
}

protocol HolyMannaBoardAsking: Sendable {
    func answer(_ request: HolyMannaBoardQuestion) async throws -> HolyMannaBoardAnswer
}

actor HolyMannaBoardAskService: HolyMannaBoardAsking {
    static let shared = HolyMannaBoardAskService()
    typealias Completion = @Sendable (HolyMannaBoardQuestion) async throws -> String
    private let completion: Completion
    private var cache: [String: HolyMannaBoardAnswer] = [:]

    init(completion: @escaping Completion = { request in
        try await HolyIntelligenceRouter.shared.complete(
            role: .deep,
            prompt: "QUESTION: \(request.question)\n\nBOARD ROWS:\n\(request.rows)",
            workingDirectory: nil,
            model: request.model,
            systemPrompt: HolyMannaBoardQuestion.system
        ).text
    }) {
        self.completion = completion
    }

    func answer(_ request: HolyMannaBoardQuestion) async throws -> HolyMannaBoardAnswer {
        guard !request.question.isEmpty else { throw HolyMannaAskError.unavailable("Type a board question first.") }
        if var cached = cache[request.cacheKey] {
            cached.wasCached = true
            return cached
        }
        guard request.rows.utf8.count + request.question.utf8.count <= 200_000 else {
            throw HolyMannaAskError.unavailable("This board is too large to ask in one request. No rows were silently omitted.")
        }
        let text = try await completion(request).trimmingCharacters(in: .whitespacesAndNewlines)
        try Task.checkCancellation()
        guard !text.isEmpty else { throw HolyMannaAskError.unavailable("The deep role returned an empty answer.") }
        let answer = HolyMannaBoardAnswer.validated(text, for: request)
        if cache.count >= 64 { cache.removeAll(keepingCapacity: true) }
        cache[request.cacheKey] = answer
        return answer
    }
}
