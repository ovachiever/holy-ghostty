import Foundation

// MARK: - Pinned payloads

/// Issue status as `agent-do manna list --json` reports it. Not
/// `RawRepresentable`: a manna release that adds a status must degrade to
/// `.unknown` (a value no admission rule matches) rather than blank the pane.
enum HolyMannaIssueStatus: Sendable, Equatable {
    case open
    case inProgress
    case blocked
    case done
    case unknown

    init(rawValue: String) {
        switch rawValue {
        case "open": self = .open
        case "in_progress": self = .inProgress
        case "blocked": self = .blocked
        case "done": self = .done
        default: self = .unknown
        }
    }
}

/// Manna grammar: a board row is a track (grouping), an item (work unit,
/// the wire default) or a dream (raw intake awaiting a human decision).
enum HolyMannaIssueType: Sendable, Equatable {
    case track
    case item
    case dream
    case unknown

    init(rawValue: String) {
        switch rawValue {
        case "track": self = .track
        case "item": self = .item
        case "dream": self = .dream
        default: self = .unknown
        }
    }
}

/// One row of `agent-do manna list --json`. Field names pinned from live
/// invocations on 2026-08-03 against `/Users/erik/Custom-Coding/holy-ghostty`
/// and `/Users/erik/Custom-Coding`: id, title, status, claimed_by?, type?
/// (omitted when the default `item`), track?, updated, gate? (dreams only).
/// Do not edit them from memory; re-run the CLI.
struct HolyMannaIssueSummary: Equatable, Sendable {
    let id: String
    let title: String
    let status: HolyMannaIssueStatus
    let claimedBy: String?
    let type: HolyMannaIssueType
    let track: String?
    /// Display string — "2026-07-21 (13d ago)" — never ISO8601.
    let updated: String
    /// Present only on dreams: the row is visible but not workable.
    let gate: String?

    /// Only the leading calendar day of `updated` is real data; the "(13d
    /// ago)" tail is prose. An unparseable value is no date, never a guess.
    static func updatedDate(from raw: String) -> Date? {
        let head = raw.prefix(10)
        guard head.count == 10 else { return nil }
        let parts = head.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1...12).contains(month),
              (1...31).contains(day) else {
            return nil
        }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day

        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: components),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else {
            return nil
        }
        return date
    }

    var updatedDate: Date? {
        Self.updatedDate(from: updated)
    }
}

extension HolyMannaIssueSummary: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case status
        case claimedBy = "claimed_by"
        case type
        case track
        case updated
        case gate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        status = HolyMannaIssueStatus(rawValue: try container.decode(String.self, forKey: .status))
        claimedBy = try container.decodeIfPresent(String.self, forKey: .claimedBy)
        type = HolyMannaIssueType(
            rawValue: try container.decodeIfPresent(String.self, forKey: .type) ?? "item"
        )
        track = try container.decodeIfPresent(String.self, forKey: .track)
        updated = try container.decode(String.self, forKey: .updated)
        gate = try container.decodeIfPresent(String.self, forKey: .gate)
    }
}

struct HolyMannaListPayload: Decodable, Equatable, Sendable {
    let success: Bool
    let issues: [HolyMannaIssueSummary]

    /// Fail-closed. The CLI answers errors in YAML even under `--json`
    /// ("success: false\nerror: …", verified live 2026-08-03), and a
    /// `success:false` JSON body is not a board either: both parse to nil so
    /// the source degrades instead of inventing an empty board.
    static func parse(_ data: Data) -> HolyMannaListPayload? {
        guard let payload = try? JSONDecoder().decode(HolyMannaListPayload.self, from: data),
              payload.success else {
            return nil
        }
        return payload
    }
}

/// Drift kinds pinned from manna's `FindingKind` enum (agent-do
/// tools/agent-manna/src/reconcile.rs, 2026-08-03).
enum HolyMannaFindingKind: Sendable, Equatable {
    case landedOpen
    case deadClaim
    case blockerDesync
    case staleDream
    case danglingTrack
    case docReference
    case promptPairing
    case skipped
    case unknown

    init(rawValue: String) {
        switch rawValue {
        case "landed_open": self = .landedOpen
        case "dead_claim": self = .deadClaim
        case "blocker_desync": self = .blockerDesync
        case "stale_dream": self = .staleDream
        case "dangling_track": self = .danglingTrack
        case "doc_reference": self = .docReference
        case "prompt_pairing": self = .promptPairing
        case "skipped": self = .skipped
        default: self = .unknown
        }
    }
}

/// One `agent-do manna reconcile --json` finding: kind, issue_id?, detail,
/// evidence?, proposed_fix?.
struct HolyMannaReconcileFinding: Equatable, Sendable {
    let kind: HolyMannaFindingKind
    let issueID: String?
    let detail: String
    let evidence: String?
    let proposedFix: String?
}

extension HolyMannaReconcileFinding: Decodable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case issueID = "issue_id"
        case detail
        case evidence
        case proposedFix = "proposed_fix"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = HolyMannaFindingKind(rawValue: try container.decode(String.self, forKey: .kind))
        issueID = try container.decodeIfPresent(String.self, forKey: .issueID)
        detail = try container.decode(String.self, forKey: .detail)
        evidence = try container.decodeIfPresent(String.self, forKey: .evidence)
        proposedFix = try container.decodeIfPresent(String.self, forKey: .proposedFix)
    }
}

struct HolyMannaReconcilePayload: Decodable, Equatable, Sendable {
    let success: Bool
    let findings: [HolyMannaReconcileFinding]

    static func parse(_ data: Data) -> HolyMannaReconcilePayload? {
        guard let payload = try? JSONDecoder().decode(HolyMannaReconcilePayload.self, from: data),
              payload.success else {
            return nil
        }
        return payload
    }
}

// MARK: - Source

/// Production bridge to the local manna boards. Manna is git-backed JSONL on
/// disk, so there is no polling problem: both commands run on the inbox's own
/// refresh tick, read-only, once per board.
final class HolyMannaInboxSource: HolyInboxRowSource {
    /// Both commands read `./.manna` from the child's working directory —
    /// manna exposes no board flag (`manna-core list --help`,
    /// `manna-core reconcile --help`, 2026-08-03) — so the board root is
    /// passed as the process cwd, never as an argument.
    static let listArguments = ["manna", "list", "--json"]
    /// `reconcile` without `--fix`: the inbox reads drift, it never repairs it.
    static let reconcileArguments = ["manna", "reconcile", "--json"]

    let sourceID = HolyMannaInboxSectioner.sourceID

    func refresh(context: HolyInboxRefreshContext) async -> HolyInboxSourceSnapshot {
        .empty
    }
}

/// The admission law for manna rows, kept out of the source so it is a pure
/// function of board data (same shape as HolyGitHubInboxSectioner).
enum HolyMannaInboxSectioner {
    static let sourceID = "manna"
}
