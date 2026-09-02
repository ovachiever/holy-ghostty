import Foundation

enum HolyMannaBoardSheet: String, CaseIterable, Identifiable, Sendable {
    /// The web's "inbox" tab: asks only — who/what · the ask · the verb.
    case asks
    case board
    case coordination
    /// Toggled from the strip, never a tab.
    case debug

    var id: String { rawValue }

    /// The three tabs beside the crumb, in the web's order.
    static let tabs: [HolyMannaBoardSheet] = [.asks, .board, .coordination]

    var title: String {
        switch self {
        case .asks: "inbox"
        case .board: "board"
        case .coordination: "coordination"
        case .debug: "debug"
        }
    }
}

struct HolyMannaBoardContext: Equatable, Sendable {
    var boardRoot: String?
    var remoteHost: String?

    @MainActor
    static func focused(session: HolySession?) -> Self {
        guard let session else { return .init(boardRoot: nil, remoteHost: nil) }
        let transport = session.record.launchSpec.transport.normalized
        return .init(
            boardRoot: session.ownership.repositoryRoot ?? session.workingDirectory,
            remoteHost: transport.isRemote ? transport.sshDestination : nil
        )
    }

    func selecting(boardRoot: String) -> Self {
        .init(boardRoot: boardRoot, remoteHost: remoteHost)
    }
}

struct HolyMannaStatePayload: Decodable, Equatable, Sendable {
    let success: Bool
    let generatedAt: String
    let name: String
    let root: String
    let total: Int
    let counts: [String: Int]
    let statusCounts: [String: Int]
    let now: [HolyMannaBoardItem]
    let next: [HolyMannaBoardItem]
    let waves: [HolyMannaWave]
    let dreams: [HolyMannaBoardItem]
    let decisions: [HolyMannaBoardItem]
    let tracks: [HolyMannaTrack]
    let peers: [HolyMannaPeer]
    let attention: [String: Int]
    let coord: HolyMannaCoordination
    let drift: HolyMannaDrift
    let git: HolyMannaGitSummary
    let board: HolyMannaBoardMetadata
    /// Every row on the board, done and tracks included: the done and recent
    /// filters read it. Older cores omit it.
    let all: [HolyMannaBoardItem]
    /// Blocked rows the wave layering could not place.
    let unlayered: [HolyMannaBoardItem]

    enum CodingKeys: String, CodingKey {
        case success
        case generatedAt = "generated_at"
        case name
        case root
        case total
        case counts
        case statusCounts = "status_counts"
        case now
        case next
        case waves
        case dreams
        case decisions
        case tracks
        case peers
        case attention
        case coord
        case drift
        case git
        case board
        case all
        case unlayered
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        generatedAt = try container.decode(String.self, forKey: .generatedAt)
        name = try container.decode(String.self, forKey: .name)
        root = try container.decode(String.self, forKey: .root)
        total = try container.decode(Int.self, forKey: .total)
        counts = try container.decode([String: Int].self, forKey: .counts)
        statusCounts = try container.decode([String: Int].self, forKey: .statusCounts)
        now = try container.decode([HolyMannaBoardItem].self, forKey: .now)
        next = try container.decode([HolyMannaBoardItem].self, forKey: .next)
        waves = try container.decode([HolyMannaWave].self, forKey: .waves)
        dreams = try container.decode([HolyMannaBoardItem].self, forKey: .dreams)
        decisions = try container.decode([HolyMannaBoardItem].self, forKey: .decisions)
        tracks = try container.decode([HolyMannaTrack].self, forKey: .tracks)
        peers = try container.decode([HolyMannaPeer].self, forKey: .peers)
        attention = try container.decode([String: Int].self, forKey: .attention)
        coord = try container.decode(HolyMannaCoordination.self, forKey: .coord)
        drift = try container.decode(HolyMannaDrift.self, forKey: .drift)
        git = try container.decode(HolyMannaGitSummary.self, forKey: .git)
        board = try container.decode(HolyMannaBoardMetadata.self, forKey: .board)
        all = try container.decodeIfPresent([HolyMannaBoardItem].self, forKey: .all) ?? []
        unlayered = try container.decodeIfPresent([HolyMannaBoardItem].self, forKey: .unlayered) ?? []
    }

    var allVisibleItems: [HolyMannaBoardItem] {
        var seen = Set<String>()
        return (now + next + waves.flatMap(\.items) + unlayered + dreams + decisions + tracks.flatMap(\.items) + all)
            .filter { seen.insert($0.id).inserted }
    }

    func item(id: String?) -> HolyMannaBoardItem? {
        guard let id else { return nil }
        return allVisibleItems.first { $0.id == id }
    }

    func peer(id: String?) -> HolyMannaPeer? {
        guard let id else { return nil }
        return peers.first { $0.agentID == id }
    }

    /// The coordination tab's badge: sessions waiting on a person or failed.
    var attentionCount: Int {
        attention["needs-user", default: 0] + attention["failed", default: 0]
    }

    /// app.js inboxRows: every row is who/what · the ask · the verb you
    /// perform, ranked by verb. Title carries the who/what, detail the ask.
    var asks: [HolyMannaAsk] {
        var result: [HolyMannaAsk] = []

        for peer in peers where peer.attention == "needs-user" || peer.attention == "failed" {
            let prompt = peer.pulse?.latestPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
            let failed = peer.attention == "failed"
            let detail: String? = if failed {
                peer.goal ?? "failed"
            } else if let prompt, !prompt.isEmpty {
                "“\(HolyMannaBoardPresentation.clip(prompt, HolyMannaBoardMetrics.promptQuoteCharacters))”"
            } else {
                peer.goal ?? "waiting on you"
            }
            result.append(.init(
                id: "peer:\(peer.agentID)",
                kind: failed ? "failed" : "peer",
                title: peer.displayName,
                detail: detail,
                verb: failed ? "fix" : "grant",
                target: .peer(peer.agentID),
                action: nil
            ))
        }

        for item in decisions {
            result.append(.init(
                id: "decision:\(item.id)",
                kind: "decision",
                title: HolyMannaBoardPresentation.rowText(item),
                detail: nil,
                verb: "rule",
                target: .item(item.id),
                action: nil
            ))
        }

        for contention in coord.contention {
            result.append(.init(
                id: "contention:\(contention.paths.joined(separator: "|")):\(contention.owners.joined(separator: "|"))",
                kind: "contention",
                title: contention.paths.isEmpty ? "overlapping work" : contention.paths.joined(separator: ", "),
                detail: contention.owners.isEmpty ? nil : contention.owners.joined(separator: " and "),
                verb: "split",
                target: .sheet(.coordination),
                action: nil
            ))
        }

        var handoffsBehind = 0
        var safeRepairs = 0
        for finding in drift.findings {
            switch finding.kind {
            case "landed_open":
                guard let issueID = finding.issueID else { continue }
                result.append(.init(
                    id: "landed:\(issueID)",
                    kind: "landed",
                    title: item(id: issueID).map(HolyMannaBoardPresentation.rowText) ?? issueID,
                    detail: "landed in \(finding.evidence ?? "a commit"), still open",
                    verb: "close",
                    target: .item(issueID),
                    action: .close(issueID)
                ))
            case "stale_dream":
                guard let issueID = finding.issueID else { continue }
                let since = finding.evidence.map { $0.replacingOccurrences(of: "created_at ", with: "") }
                result.append(.init(
                    id: "dream:\(issueID)",
                    kind: "dream",
                    title: item(id: issueID).map(HolyMannaBoardPresentation.rowText) ?? issueID,
                    detail: "parked since \(since ?? "a while")",
                    verb: "rule",
                    target: .item(issueID),
                    action: nil
                ))
            case "doc_reference", "prompt_pairing":
                result.append(.init(
                    id: "drift:\(finding.kind):\(finding.issueID ?? finding.evidence ?? finding.detail ?? "unidentified")",
                    kind: "document",
                    title: finding.detail ?? "a document names a missing item",
                    detail: finding.evidence,
                    verb: "fix doc",
                    target: .sheet(.debug),
                    action: nil
                ))
            case "handoff_presentation":
                handoffsBehind += 1
            case "stale_claim", "blocker_desync":
                safeRepairs += 1
            default:
                continue
            }
        }

        if handoffsBehind > 0 {
            result.append(.init(
                id: "board:sync",
                kind: "handoffs",
                title: "\(handoffsBehind) work-order filename\(handoffsBehind == 1 ? "" : "s") behind their priority",
                detail: nil,
                verb: "sync",
                target: .sheet(.debug),
                action: .sync
            ))
        }
        if safeRepairs > 0 {
            result.append(.init(
                id: "board:repair",
                kind: "repair",
                title: "\(safeRepairs) safe repair\(safeRepairs == 1 ? "" : "s") (dead claims, resolved blockers)",
                detail: nil,
                verb: "apply",
                target: .sheet(.debug),
                action: .fix
            ))
        }

        for drop in coord.drops {
            result.append(.init(
                id: "drop:\(drop.id)",
                kind: "drop",
                title: drop.paths.isEmpty ? "note" : drop.paths.joined(separator: ", "),
                detail: "\(HolyMannaBoardPresentation.clip(drop.note, HolyMannaBoardMetrics.dropNoteCharacters)) · from \(drop.owner ?? "unknown")",
                verb: "read",
                target: .sheet(.coordination),
                action: nil
            ))
        }

        if let first = next.first {
            result.append(.init(
                id: "ready:\(first.id)",
                kind: "ready",
                title: HolyMannaBoardPresentation.rowText(first),
                detail: "priority #\((first.order ?? 0) + 1)",
                verb: "launch",
                target: .item(first.id),
                action: nil
            ))
        }

        let rank = HolyMannaAsk.verbRank
        return result.sorted { lhs, rhs in
            (rank.firstIndex(of: lhs.verb) ?? rank.count) < (rank.firstIndex(of: rhs.verb) ?? rank.count)
        }
    }
}

struct HolyMannaBoardItem: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let titlePlain: String
    let description: String?
    let status: String
    let effective: String
    let kind: String
    let order: Int?
    let decision: Bool
    let blockedBy: [String]
    let blockers: [HolyMannaBlocker]
    let dependents: [String]
    let claimant: HolyMannaClaimant?
    let commits: [HolyMannaCommit]
    let claimedBy: String?
    let claimedAt: String?
    let createdAt: String?
    let updatedAt: String?
    let track: String?
    let trackTitle: String?
    let prompt: String?
    let handoffDigest: String?
    let handoffExists: Bool?
    let source: String?
    /// A one-line digest attached by the serve daemon; the CLI's own state
    /// carries none today, and the title stands in (dimmed) when absent.
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case titlePlain = "title_plain"
        case description
        case status
        case effective
        case kind
        case order
        case decision
        case blockedBy = "blocked_by"
        case blockers
        case dependents
        case claimant
        case commits
        case claimedBy = "claimed_by"
        case claimedAt = "claimed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case track
        case trackTitle = "track_title"
        case prompt
        case handoffDigest = "handoff_digest"
        case handoffExists = "handoff_exists"
        case source
        case digest
    }
}

struct HolyMannaBlocker: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let status: String
    let title: String
}

struct HolyMannaCommit: Decodable, Equatable, Identifiable, Sendable {
    let sha: String
    let at: String
    let subject: String

    var id: String { "\(sha):\(at)" }
}

struct HolyMannaClaimant: Decodable, Equatable, Sendable {
    let label: String
    let liveness: String
    let attention: String
    let runtime: String?
    let age: String?
    let goal: String?
    let pulse: HolyMannaPulse?
}

struct HolyMannaPulse: Decodable, Equatable, Sendable {
    let status: String?
    let activity: String?
    let latestPrompt: String?
    let updatedAt: String?
    let turns: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case activity
        case latestPrompt = "latest_prompt"
        case updatedAt = "updated_at"
        case turns
    }
}

struct HolyMannaWave: Decodable, Equatable, Identifiable, Sendable {
    let wave: Int
    let items: [HolyMannaBoardItem]

    var id: Int { wave }
}

struct HolyMannaTrack: Decodable, Equatable, Identifiable, Sendable {
    // The core emits a synthetic "(no track)" bucket for untracked items with
    // id: null and status: null; both must stay optional or the whole state
    // payload fails to decode on any board that has untracked items.
    let trackID: String?
    let title: String
    let status: String?
    let items: [HolyMannaBoardItem]

    var id: String { trackID ?? "(no track)" }

    enum CodingKeys: String, CodingKey {
        case trackID = "id"
        case title
        case status
        case items
    }
}

struct HolyMannaPeer: Decodable, Equatable, Identifiable, Sendable {
    let agentID: String
    let alias: String?
    let runtime: String?
    let status: String
    let attention: String
    let age: String?
    let ageSeconds: Int?
    let goal: String?
    let mode: String?
    let phase: String?
    let role: String?
    let paths: [String]
    let holding: [HolyMannaHeldIssue]
    let pulse: HolyMannaPulse?

    enum CodingKeys: String, CodingKey {
        case agentID = "agent_id"
        case alias
        case runtime
        case status
        case attention
        case age
        case ageSeconds = "age_seconds"
        case goal
        case mode
        case phase
        case role
        case paths
        case holding
        case pulse
    }

    var id: String { agentID }
    var displayName: String { alias ?? agentID }
}

struct HolyMannaHeldIssue: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
}

struct HolyMannaCoordination: Decodable, Equatable, Sendable {
    let claims: [HolyMannaCoordClaim]
    let contention: [HolyMannaCoordContention]
    let needs: [HolyMannaCoordNeed]
    let drops: [HolyMannaCoordDrop]

    enum CodingKeys: String, CodingKey {
        case claims
        case contention
        case needs
        case drops
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        claims = try container.decodeIfPresent([HolyMannaCoordClaim].self, forKey: .claims) ?? []
        contention = try container.decodeIfPresent([HolyMannaCoordContention].self, forKey: .contention) ?? []
        needs = try container.decodeIfPresent([HolyMannaCoordNeed].self, forKey: .needs) ?? []
        drops = try container.decodeIfPresent([HolyMannaCoordDrop].self, forKey: .drops) ?? []
    }
}

struct HolyMannaCoordClaim: Decodable, Equatable, Identifiable, Sendable {
    let path: String
    let owner: String
    let ownerAlias: String?
    let ownerStatus: String?
    let reason: String?
    let strength: String?
    let updatedAt: String?
    let stale: Bool
    let contended: Bool

    enum CodingKeys: String, CodingKey {
        case path
        case owner
        case ownerAlias = "owner_alias"
        case ownerStatus = "owner_status"
        case reason
        case strength
        case updatedAt = "updated_at"
        case stale
        case contended
    }

    var id: String { "\(path):\(owner)" }
}

struct HolyMannaCoordContention: Decodable, Equatable, Identifiable, Sendable {
    let paths: [String]
    let owners: [String]

    enum CodingKeys: String, CodingKey {
        case paths
        case path
        case owners
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        paths = try container.decodeIfPresent([String].self, forKey: .paths)
            ?? container.decodeIfPresent(String.self, forKey: .path).map { [$0] }
            ?? []
        owners = try container.decodeIfPresent([String].self, forKey: .owners) ?? []
    }

    var id: String { "\(paths.joined(separator: "|")):\(owners.joined(separator: "|"))" }
}

struct HolyMannaCoordNeed: Decodable, Equatable, Identifiable, Sendable {
    let key: String
    let why: String?
    let owner: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case key
        case why
        case owner
        case updatedAt = "updated_at"
    }

    var id: String { key }
}

struct HolyMannaCoordDrop: Decodable, Equatable, Identifiable, Sendable {
    let paths: [String]
    let note: String?
    let owner: String?
    let recipient: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case path
        case note
        case owner
        case recipient = "for"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let values = try? container.decode([String].self, forKey: .path) {
            paths = values
        } else if let value = try? container.decode(String.self, forKey: .path) {
            paths = [value]
        } else {
            paths = []
        }
        note = try container.decodeIfPresent(String.self, forKey: .note)
        owner = try container.decodeIfPresent(String.self, forKey: .owner)
        recipient = try container.decodeIfPresent(String.self, forKey: .recipient)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }

    var id: String { "\(owner ?? "unknown"):\(paths.joined(separator: "|")):\(note ?? "")" }
}

struct HolyMannaDrift: Decodable, Equatable, Sendable {
    let present: Bool
    let source: String?
    let count: Int
    let generatedAt: String?
    let kinds: [String: Int]
    let findings: [HolyMannaDriftFinding]

    enum CodingKeys: String, CodingKey {
        case present
        case source
        case count
        case generatedAt = "generated_at"
        case kinds
        case findings
    }
}

struct HolyMannaDriftFinding: Decodable, Equatable, Sendable {
    let kind: String
    let issueID: String?
    let detail: String?
    let evidence: String?
    let proposedFix: String?

    enum CodingKeys: String, CodingKey {
        case kind
        case issueID = "issue_id"
        case detail
        case evidence
        case proposedFix = "proposed_fix"
    }
}

struct HolyMannaGitSummary: Decodable, Equatable, Sendable {
    let branch: String?
    let head: String?
    let dirtyPaths: Int
    let isRepo: Bool

    enum CodingKeys: String, CodingKey {
        case branch
        case head
        case dirtyPaths = "dirty_paths"
        case isRepo = "is_repo"
    }
}

struct HolyMannaBoardMetadata: Decodable, Equatable, Sendable {
    let boardID: String?
    let workflow: String?
    let path: String?
    let handoffDir: String?
    let orderCount: Int?
    let issuesModifiedAt: String?

    enum CodingKeys: String, CodingKey {
        case boardID = "board_id"
        case workflow
        case path
        case handoffDir = "handoff_dir"
        case orderCount = "order_count"
        case issuesModifiedAt = "issues_modified_at"
    }
}

struct HolyMannaEstatePayload: Decodable, Equatable, Sendable {
    let generatedAt: String
    let boards: [HolyMannaEstateBoard]
    let count: Int
    let registry: String
    let totals: HolyMannaEstateTotals
    let building: Int

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case boards
        case count
        case registry
        case totals
        case building
    }
}

struct HolyMannaEstateBoard: Decodable, Equatable, Identifiable, Sendable {
    let name: String
    let root: String
    let exists: Bool
    let total: Int
    let statusCounts: [String: Int]
    let dreams: Int
    let decisions: Int
    let driftCount: Int
    let driftGeneratedAt: String?
    let latestUpdate: String?
    let coord: HolyMannaEstateCoord
    let slug: String
    let url: String

    enum CodingKeys: String, CodingKey {
        case name
        case root
        case exists
        case total
        case statusCounts = "status_counts"
        case dreams
        case decisions
        case driftCount = "drift_count"
        case driftGeneratedAt = "drift_generated_at"
        case latestUpdate = "latest_update"
        case coord
        case slug
        case url
    }

    var id: String { root }
    var needsYou: Int { coord.needsYou }
    var activeCount: Int { statusCounts["active", default: 0] }
}

struct HolyMannaEstateCoord: Decodable, Equatable, Sendable {
    let attention: [String: Int]
    let needsYou: Int
    let working: Int
    let here: Int
    let gone: Int

    enum CodingKeys: String, CodingKey {
        case attention
        case needsYou = "needs_you"
        case working
        case here
        case gone
    }
}

struct HolyMannaEstateTotals: Decodable, Equatable, Sendable {
    let needsYou: Int
    let working: Int
    let here: Int

    enum CodingKeys: String, CodingKey {
        case needsYou = "needs_you"
        case working
        case here
    }
}

struct HolyMannaAsk: Equatable, Identifiable, Sendable {
    enum Target: Equatable, Sendable {
        case item(String)
        case peer(String)
        case sheet(HolyMannaBoardSheet)
    }

    let id: String
    let kind: String
    let title: String
    let detail: String?
    let verb: String
    let target: Target
    let action: HolyMannaMutation?

    /// app.js VERB_RANK: the inbox's order of urgency.
    static let verbRank = ["grant", "fix", "rule", "split", "close", "apply", "sync", "fix doc", "read", "launch"]

    /// The item a rule ask is about, when it is one.
    var itemID: String? {
        if case let .item(id) = target { return id }
        return nil
    }
}

enum HolyMannaMutation: Equatable, Identifiable, Sendable {
    case claim(String)
    case done(String)
    case abandon(String)
    case close(String)
    case promote(String)
    case delete(String)
    case unblock(issueID: String, blockerID: String)
    case sync
    case fix

    var id: String {
        switch self {
        case let .claim(id): "claim:\(id)"
        case let .done(id): "done:\(id)"
        case let .abandon(id): "abandon:\(id)"
        case let .close(id): "close:\(id)"
        case let .promote(id): "promote:\(id)"
        case let .delete(id): "delete:\(id)"
        case let .unblock(issueID, blockerID): "unblock:\(issueID):\(blockerID)"
        case .sync: "sync"
        case .fix: "fix"
        }
    }

    /// The word the action row prints inside brackets.
    var verb: String {
        switch self {
        case .claim: "claim"
        case .done: "done"
        case .abandon: "abandon"
        case .close: "close"
        case .promote: "promote"
        case .delete: "delete"
        case let .unblock(_, blockerID): "unblock \(HolyMannaBoardPresentation.shortID(blockerID))"
        case .sync: "sync"
        case .fix: "apply"
        }
    }

    var label: String {
        switch self {
        case .claim: "Claim"
        case .done: "Mark done"
        case .abandon: "Release claim"
        case .close: "Close landed item"
        case .promote: "Promote to item"
        case .delete: "Delete dream"
        case .unblock: "Remove blocker"
        case .sync: "Sync handoffs"
        case .fix: "Apply safe repairs"
        }
    }

    var confirmationTitle: String {
        switch self {
        case .claim: "Claim this item?"
        case .done: "Mark this item done?"
        case .abandon: "Release this claim?"
        case .close: "Claim and close this landed item?"
        case .promote: "Promote this dream to an item?"
        case .delete: "Delete this dream permanently?"
        case .unblock: "Remove this blocker?"
        case .sync: "Regenerate handoff presentation?"
        case .fix: "Apply Manna's safe repairs?"
        }
    }

    var confirmationDetail: String {
        let command = commands.map { "agent-do \($0.joined(separator: " "))" }.joined(separator: "\nthen ")
        return "Holy will run the real Manna CLI under its own durable actor identity:\n\(command)"
    }

    var isDestructive: Bool {
        if case .delete = self { return true }
        return false
    }

    var commands: [[String]] {
        switch self {
        case let .claim(id): [["manna", "claim", id]]
        case let .done(id): [["manna", "done", id]]
        case let .abandon(id): [["manna", "abandon", id]]
        case let .close(id): [["manna", "claim", id], ["manna", "done", id]]
        case let .promote(id): [["manna", "update", id, "--type", "item"]]
        case let .delete(id): [["manna", "delete", id]]
        case let .unblock(issueID, blockerID): [["manna", "unblock", issueID, blockerID]]
        case .sync: [["manna", "sync"]]
        case .fix: [["manna", "reconcile", "--fix", "--json"]]
        }
    }
}
