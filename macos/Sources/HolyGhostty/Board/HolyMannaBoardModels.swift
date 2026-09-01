import Foundation

enum HolyMannaBoardSheet: String, CaseIterable, Identifiable, Sendable {
    case now
    case next
    case waves
    case asks
    case coordination
    case dreams
    case decisions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .now: "Now"
        case .next: "Next"
        case .waves: "Waiting in waves"
        case .asks: "Asks"
        case .coordination: "Coordination"
        case .dreams: "Dreams"
        case .decisions: "Decisions"
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
    }

    var allVisibleItems: [HolyMannaBoardItem] {
        var seen = Set<String>()
        return (now + next + waves.flatMap(\.items) + dreams + decisions + tracks.flatMap(\.items))
            .filter { seen.insert($0.id).inserted }
    }

    func item(id: String?) -> HolyMannaBoardItem? {
        guard let id else { return nil }
        return allVisibleItems.first { $0.id == id }
    }

    var asks: [HolyMannaAsk] {
        var result: [HolyMannaAsk] = []

        for peer in peers where peer.attention == "needs-user" || peer.attention == "failed" {
            let prompt = peer.pulse?.latestPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(.init(
                id: "peer:\(peer.agentID)",
                kind: peer.attention == "failed" ? "failed" : "peer",
                title: peer.displayName,
                detail: prompt?.isEmpty == false ? prompt : (peer.goal ?? "Waiting for a person"),
                verb: peer.attention == "failed" ? "fix" : "grant",
                target: .peer(peer.agentID),
                action: nil
            ))
        }

        for item in decisions {
            result.append(.init(
                id: "decision:\(item.id)",
                kind: "decision",
                title: item.titlePlain,
                detail: item.id,
                verb: "rule",
                target: .item(item.id),
                action: nil
            ))
        }

        for contention in coord.contention {
            result.append(.init(
                id: "contention:\(contention.paths.joined(separator: "|")):\(contention.owners.joined(separator: "|"))",
                kind: "contention",
                title: contention.paths.isEmpty ? "Overlapping work" : contention.paths.joined(separator: ", "),
                detail: contention.owners.isEmpty ? nil : contention.owners.joined(separator: " and "),
                verb: "split",
                target: .sheet(.coordination),
                action: nil
            ))
        }

        var needsSafeRepair = false
        var needsSync = false
        for finding in drift.findings {
            switch finding.kind {
            case "landed_open":
                guard let issueID = finding.issueID else { continue }
                result.append(.init(
                    id: "landed:\(issueID)",
                    kind: "landed",
                    title: item(id: issueID)?.titlePlain ?? issueID,
                    detail: finding.evidence.map { "Landed in \($0), still open" },
                    verb: "close",
                    target: .item(issueID),
                    action: .close(issueID)
                ))
            case "stale_dream":
                guard let issueID = finding.issueID else { continue }
                result.append(.init(
                    id: "dream:\(issueID)",
                    kind: "dream",
                    title: item(id: issueID)?.titlePlain ?? issueID,
                    detail: finding.evidence,
                    verb: "rule",
                    target: .item(issueID),
                    action: nil
                ))
            case "doc_reference", "prompt_pairing":
                result.append(.init(
                    id: "drift:\(finding.kind):\(finding.issueID ?? finding.evidence ?? finding.detail ?? "unidentified")",
                    kind: "document",
                    title: finding.detail ?? "A document names missing work",
                    detail: finding.evidence,
                    verb: "fix doc",
                    target: .sheet(.asks),
                    action: nil
                ))
            case "handoff_presentation":
                needsSync = true
            case "stale_claim", "blocker_desync":
                needsSafeRepair = true
            default:
                continue
            }
        }

        if needsSync {
            result.append(.init(
                id: "board:sync",
                kind: "handoffs",
                title: "Work-order presentation is behind the ledger",
                detail: "Regenerate filenames and the handoff index from canonical board state.",
                verb: "sync",
                target: .sheet(.asks),
                action: .sync
            ))
        }
        if needsSafeRepair {
            result.append(.init(
                id: "board:repair",
                kind: "repair",
                title: "Safe board repairs are ready",
                detail: "Release dead claims and remove blockers whose dependencies are complete.",
                verb: "apply",
                target: .sheet(.asks),
                action: .fix
            ))
        }

        if let first = next.first {
            result.append(.init(
                id: "ready:\(first.id)",
                kind: "ready",
                title: first.titlePlain,
                detail: first.order.map { "Priority #\($0 + 1)" },
                verb: "launch",
                target: .item(first.id),
                action: nil
            ))
        }

        let rank = ["grant", "fix", "rule", "split", "close", "apply", "sync", "fix doc", "launch"]
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
    let id: String
    let title: String
    let status: String
    let items: [HolyMannaBoardItem]
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

    enum CodingKeys: String, CodingKey {
        case path
        case note
        case owner
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
