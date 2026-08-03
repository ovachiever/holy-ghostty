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

/// Everything one board answered on one refresh tick. `degradedDetail` is set
/// when either command failed: a whole-board failure carries no issues, a
/// reconcile-only failure still carries the `list` half, and both still owe
/// the human one honest degraded row.
struct HolyMannaBoardReading: Equatable, Sendable {
    /// Absolute path of the directory containing `.manna`.
    let root: String
    let issues: [HolyMannaIssueSummary]
    let findings: [HolyMannaReconcileFinding]
    let degradedDetail: String?

    init(
        root: String,
        issues: [HolyMannaIssueSummary] = [],
        findings: [HolyMannaReconcileFinding] = [],
        degradedDetail: String? = nil
    ) {
        self.root = root
        self.issues = issues
        self.findings = findings
        self.degradedDetail = degradedDetail
    }

    var displayName: String {
        URL(fileURLWithPath: root).lastPathComponent
    }
}

/// The admission law for manna rows, kept out of the source so it is a pure
/// function of board data (same shape as HolyGitHubInboxSectioner).
///
/// Most manna traffic is agent-to-agent and never belongs here. Exactly three
/// board states are a decision only the human can make, and each clears when
/// the board moves — never by dismissal:
///
///   1. **Dreams awaiting triage.** The grammar says a dream is converted or
///      closed with a written reason; until then it waits on Erik. Converting
///      moves its type off `dream`; closing sets it done. Either way the row
///      leaves on the next tick.
///   2. **Unblocked but unclaimed.** `done` never auto-unblocks dependents, so
///      work whose blockers are all resolved sits invisibly blocked with
///      nobody on it. Reconcile calls this `blocker_desync`. A claim or a
///      blocker-state change clears it.
///   3. **Stale claims.** A claim held by a session that is provably gone
///      (`dead_claim`). A reclaim or an abandon clears it.
///
/// Open backlogs, in_progress work, and tracks stay out: the inbox is not a
/// board mirror. So does the rest of reconcile's drift (`landed_open`,
/// `dangling_track`, `doc_reference`, `prompt_pairing`, `skipped`) — that is
/// agent bookkeeping, addressed to the swarm and not to Erik.
enum HolyMannaInboxSectioner {
    static let sourceID = "manna"

    static func sections(
        boards: [HolyMannaBoardReading],
        focusedBoardRoot: String? = nil
    ) -> [HolyInboxSection] {
        var dreams: [HolyInboxRow] = []
        var unblocked: [HolyInboxRow] = []
        var staleClaims: [HolyInboxRow] = []
        var degraded: [HolyInboxRow] = []

        for board in boards {
            let byID = Dictionary(board.issues.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let staleDreamIDs = Set(findingIssueIDs(board.findings, kind: .staleDream))

            // 1. Dreams awaiting triage.
            for issue in board.issues where issue.type == .dream && issue.status != .done {
                var chips = [HolyInboxChip("dream", emphasis: .attention)]
                if staleDreamIDs.contains(issue.id) {
                    chips.append(HolyInboxChip("stale", emphasis: .warning))
                }
                dreams.append(row(board: board, issue: issue, chips: chips, evidence: nil))
            }

            // 2. Unblocked but unclaimed. A dream is never claimable and a
            //    track is a grouping, so neither can be this row.
            for finding in deduplicated(board.findings, kind: .blockerDesync) {
                guard let id = finding.issueID,
                      let issue = byID[id],
                      issue.type == .item,
                      issue.claimedBy == nil else {
                    continue
                }
                unblocked.append(row(
                    board: board,
                    issue: issue,
                    chips: [HolyInboxChip("unblocked", emphasis: .attention)],
                    evidence: finding.evidence
                ))
            }

            // 3. Stale claims.
            for finding in deduplicated(board.findings, kind: .deadClaim) {
                guard let id = finding.issueID,
                      let issue = byID[id],
                      issue.claimedBy != nil,
                      issue.status != .done else {
                    continue
                }
                staleClaims.append(row(
                    board: board,
                    issue: issue,
                    chips: [HolyInboxChip("stale claim", emphasis: .warning)],
                    evidence: finding.evidence ?? finding.detail
                ))
            }

            if let detail = board.degradedDetail {
                degraded.append(HolyInboxRow(
                    id: "manna:\(board.root):degraded",
                    title: "manna unavailable — \(board.displayName)",
                    subtitle: detail,
                    isDegraded: true
                ))
            }
        }

        var sections: [HolyInboxSection] = []

        func append(
            id: String,
            title: String,
            rows: [HolyInboxRow],
            collapsedByDefault: Bool = false,
            countsTowardBadge: Bool = false
        ) {
            guard !rows.isEmpty else { return }
            sections.append(HolyInboxSection(
                id: id,
                sourceID: sourceID,
                title: title,
                rows: sorted(rows, focusedBoardRoot: focusedBoardRoot),
                collapsedByDefault: collapsedByDefault,
                countsTowardBadge: countsTowardBadge
            ))
        }

        append(
            id: "manna.dreams",
            title: "Dreams awaiting triage",
            rows: dreams,
            countsTowardBadge: true
        )
        append(
            id: "manna.unblocked",
            title: "Unblocked, nobody on it",
            rows: unblocked,
            countsTowardBadge: true
        )
        // Drift cleanup is real work but it is not first-person attention;
        // it stays collapsed and out of the badge so the badge cannot lie.
        append(
            id: "manna.staleclaims",
            title: "Stale claims",
            rows: staleClaims,
            collapsedByDefault: true
        )
        append(id: "manna.degraded", title: "manna", rows: degraded)

        return sections
    }

    // MARK: Rows

    private static func row(
        board: HolyMannaBoardReading,
        issue: HolyMannaIssueSummary,
        chips: [HolyInboxChip],
        evidence: String?
    ) -> HolyInboxRow {
        let subtitle = [board.displayName, issue.id, evidence]
            .compactMap { $0 }
            .joined(separator: " · ")

        return HolyInboxRow(
            id: rowID(boardRoot: board.root, issueID: issue.id),
            title: issue.title,
            subtitle: subtitle,
            updatedAt: issue.updatedDate,
            chips: chips,
            action: spawnURL(boardRoot: board.root, issueID: issue.id)
                .map(HolyInboxRowAction.openURL) ?? .none
        )
    }

    static func rowID(boardRoot: String, issueID: String) -> String {
        "manna:\(boardRoot):\(issueID)"
    }

    /// Clicking a row opens a shell in the board's repo showing the issue.
    ///
    /// `initial_input` is piped to the child's stdin, so whatever goes here
    /// RUNS — which is exactly why it is `manna show` and never `claim`,
    /// `abandon`, or `reconcile --fix`. A glance must never move the board.
    static func spawnURL(boardRoot: String, issueID: String) -> URL? {
        var components = URLComponents()
        components.scheme = HolyAutomationURLParser.scheme
        components.host = "spawn"
        components.queryItems = [
            URLQueryItem(name: "runtime", value: "shell"),
            URLQueryItem(name: "workingDirectory", value: boardRoot),
            URLQueryItem(name: "title", value: "manna · \(URL(fileURLWithPath: boardRoot).lastPathComponent)"),
            URLQueryItem(name: "initialInput", value: "agent-do manna show \(issueID)"),
        ]
        // URLComponents leaves "+" literal in a query value and the automation
        // parser reads it back as a space (form-encoding convention), so a
        // path like "a+b" would arrive mangled. Encode it here.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    // MARK: Findings

    private static func findingIssueIDs(
        _ findings: [HolyMannaReconcileFinding],
        kind: HolyMannaFindingKind
    ) -> [String] {
        findings.filter { $0.kind == kind }.compactMap(\.issueID)
    }

    /// Reconcile can report the same issue twice under one kind (blocked with
    /// an empty `blocked_by` and blocked with everything resolved are separate
    /// findings). One issue is one row.
    private static func deduplicated(
        _ findings: [HolyMannaReconcileFinding],
        kind: HolyMannaFindingKind
    ) -> [HolyMannaReconcileFinding] {
        var seen: Set<String> = []
        return findings.filter { finding in
            guard finding.kind == kind, let id = finding.issueID else { return false }
            return seen.insert(id).inserted
        }
    }

    // MARK: Ordering

    /// Focused board first, then newest activity first, then id for a stable
    /// order across ticks. Focus reorders, never filters — what waits on Erik
    /// on another board still waits on Erik.
    private static func sorted(
        _ rows: [HolyInboxRow],
        focusedBoardRoot: String?
    ) -> [HolyInboxRow] {
        let focusedPrefix = focusedBoardRoot.map { "manna:\($0):" }
        return rows.sorted { lhs, rhs in
            if let focusedPrefix {
                let lhsFocused = lhs.id.hasPrefix(focusedPrefix)
                let rhsFocused = rhs.id.hasPrefix(focusedPrefix)
                if lhsFocused != rhsFocused { return lhsFocused }
            }
            let lhsDate = lhs.updatedAt ?? .distantPast
            let rhsDate = rhs.updatedAt ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.id < rhs.id
        }
    }
}
