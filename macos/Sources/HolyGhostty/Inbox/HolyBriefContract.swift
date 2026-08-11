import Foundation

// MARK: - The brief holy contract, version 1

/// Models for `agent-do brief holy --json`, pinned from the live capture at
/// .dev/brief-holy-capture-2026-08-11.json (12,164 bytes, the same morning
/// the engine went live). Top-level shape is STRICT — a missing key or a
/// contract other than 1 parses to nil so the panel degrades honestly
/// (mn-b2e2e9 lesson: silent contract drift cost three diagnosis rounds).
/// Thread sub-objects observed only as null (pr, manna, last_commit) decode
/// leniently: their arrival must enrich rows, never blank the pane.
struct HolyBriefPayload: Equatable, Sendable {
    static let supportedContract = 1

    let contract: Int
    let generatedAt: Date?
    let paragraph: HolyBriefParagraph
    let threads: [HolyBriefThread]
    let threadsTotal: Int
    let suggestions: [HolyBriefSuggestion]
    let suggestionsTotal: Int
    let delta: HolyBriefDelta
    let sources: [String: HolyBriefSourceStatus]
    let annotations: [HolyBriefAnnotation]
    let receipts: [String: HolyBriefReceipt]
    let ranking: HolyBriefRanking
    let readState: HolyBriefReadState
    let caller: HolyBriefCaller?

    /// Fail-closed: anything outside contract 1's shape is nil, and the
    /// caller renders a degraded annotation with the full parse story.
    static func parse(_ data: Data) -> HolyBriefPayload? {
        guard let payload = try? JSONDecoder().decode(HolyBriefPayload.self, from: data),
              payload.contract == supportedContract else {
            return nil
        }
        return payload
    }
}

struct HolyBriefParagraph: Equatable, Sendable, Decodable {
    /// "model" (voiced, receipt-guarded) or "deterministic" (counts).
    let mode: String
    let model: String?
    let text: String
    let receipts: [String]
}

struct HolyBriefRank: Equatable, Sendable, Decodable {
    let score: Double
    let reasons: [String]
}

/// The session leg of a thread, when one is live.
struct HolyBriefThreadSession: Equatable, Sendable, Decodable {
    let agentID: String?
    let goal: String?
    let phase: String?
    let status: String?
    let lastSeen: String?

    private enum CodingKeys: String, CodingKey {
        case agentID = "agent_id"
        case goal
        case phase
        case status
        case lastSeen = "last_seen"
    }
}

/// One joined thread. `kind` observed: "session"; the engine may add kinds —
/// unknown kinds still render as generic threads (title + rank carry them).
struct HolyBriefThread: Equatable, Sendable {
    let id: String
    let kind: String
    let title: String
    let needsMe: Bool
    let claimable: Bool
    let pinned: Bool
    let snoozed: Bool
    let updatedAt: Date?
    let rank: HolyBriefRank
    let receipts: [String]
    let why: [String]
    let session: HolyBriefThreadSession?
    /// Observed only as null so far; decoded as raw presence indicators.
    let hasPR: Bool
    let hasManna: Bool
    let hasLastCommit: Bool
}

extension HolyBriefThread: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, kind, title, pinned, snoozed, rank, receipts, why, session
        case needsMe = "needs_me"
        case claimable
        case updatedAt = "updated_at"
        case pr, manna
        case lastCommit = "last_commit"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(String.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        needsMe = try container.decode(Bool.self, forKey: .needsMe)
        claimable = (try? container.decode(Bool.self, forKey: .claimable)) ?? false
        pinned = (try? container.decode(Bool.self, forKey: .pinned)) ?? false
        snoozed = (try? container.decode(Bool.self, forKey: .snoozed)) ?? false
        let rawDate = try? container.decode(String.self, forKey: .updatedAt)
        updatedAt = rawDate.flatMap { ISO8601DateFormatter().date(from: $0) }
        rank = try container.decode(HolyBriefRank.self, forKey: .rank)
        receipts = (try? container.decode([String].self, forKey: .receipts)) ?? []
        why = (try? container.decode([String].self, forKey: .why)) ?? []
        session = try? container.decodeIfPresent(HolyBriefThreadSession.self, forKey: .session)
        // Sub-objects whose live shape is unobserved (null in the capture):
        // presence is signal enough for rendering; shapes pin when they land.
        hasPR = container.contains(.pr) && !((try? container.decodeNil(forKey: .pr)) ?? true)
        hasManna = container.contains(.manna) && !((try? container.decodeNil(forKey: .manna)) ?? true)
        hasLastCommit = container.contains(.lastCommit) && !((try? container.decodeNil(forKey: .lastCommit)) ?? true)
    }
}

/// A loaded verb: the exact command travels as DATA. The panel types it into
/// a shell and stops — the human presses Enter (Second Chair covenant).
struct HolyBriefSuggestion: Equatable, Sendable, Decodable {
    let id: String
    let kind: String
    let label: String
    let command: String
    let argv: [String]
    let issueID: String?
    let receipts: [String]

    private enum CodingKeys: String, CodingKey {
        case id, kind, label, command, argv, receipts
        case issueID = "issue_id"
    }
}

struct HolyBriefDelta: Equatable, Sendable, Decodable {
    let mode: String
    let count: Int
    let since: String?
    let threadIDs: [String]

    private enum CodingKeys: String, CodingKey {
        case mode, count, since
        case threadIDs = "thread_ids"
    }
}

struct HolyBriefSourceStatus: Equatable, Sendable, Decodable {
    let status: String
    let origin: String?
    let fetchedAt: String?
    let reason: String?

    private enum CodingKeys: String, CodingKey {
        case status, origin, reason
        case fetchedAt = "fetched_at"
    }
}

struct HolyBriefAnnotation: Equatable, Sendable, Decodable {
    let kind: String
    let source: String?
    let status: String?
    let reason: String
}

struct HolyBriefReceipt: Equatable, Sendable, Decodable {
    let kind: String
    let ref: String
    let detail: String?
}

struct HolyBriefRanking: Equatable, Sendable, Decodable {
    let mode: String
    let journalObservations: Int?

    private enum CodingKeys: String, CodingKey {
        case mode
        case journalObservations = "journal_observations"
    }
}

/// The engine's echo of the context it was called with. Observed 2026-08-11:
/// focused_repo echoes the PATH when a path was passed — treat as a display
/// hint, never as a slug for URL building unless it contains "org/repo".
struct HolyBriefCaller: Equatable, Sendable, Decodable {
    let focusedRepo: String?
    let focusedBoard: String?

    private enum CodingKeys: String, CodingKey {
        case focusedRepo = "focused_repo"
        case focusedBoard = "focused_board"
    }
}

struct HolyBriefReadState: Equatable, Sendable, Decodable {
    let lastBriefAt: String?
    let pins: Int?
    let snoozes: Int?

    private enum CodingKeys: String, CodingKey {
        case lastBriefAt = "last_brief_at"
        case pins, snoozes
    }
}

extension HolyBriefPayload: Decodable {
    private enum CodingKeys: String, CodingKey {
        case contract, paragraph, threads, suggestions, delta, sources
        case annotations, receipts, ranking, caller
        case generatedAt = "generated_at"
        case threadsTotal = "threads_total"
        case suggestionsTotal = "suggestions_total"
        case readState = "read_state"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contract = try container.decode(Int.self, forKey: .contract)
        let rawGenerated = try? container.decode(String.self, forKey: .generatedAt)
        generatedAt = rawGenerated.flatMap { ISO8601DateFormatter().date(from: $0) }
        paragraph = try container.decode(HolyBriefParagraph.self, forKey: .paragraph)
        threads = try container.decode([HolyBriefThread].self, forKey: .threads)
        threadsTotal = try container.decode(Int.self, forKey: .threadsTotal)
        suggestions = try container.decode([HolyBriefSuggestion].self, forKey: .suggestions)
        suggestionsTotal = try container.decode(Int.self, forKey: .suggestionsTotal)
        delta = try container.decode(HolyBriefDelta.self, forKey: .delta)
        sources = try container.decode([String: HolyBriefSourceStatus].self, forKey: .sources)
        annotations = (try? container.decode([HolyBriefAnnotation].self, forKey: .annotations)) ?? []
        receipts = (try? container.decode([String: HolyBriefReceipt].self, forKey: .receipts)) ?? [:]
        ranking = try container.decode(HolyBriefRanking.self, forKey: .ranking)
        readState = try container.decode(HolyBriefReadState.self, forKey: .readState)
        caller = try? container.decodeIfPresent(HolyBriefCaller.self, forKey: .caller)
    }
}
