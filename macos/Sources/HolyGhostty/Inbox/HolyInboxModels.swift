import Foundation

/// Which pane the single right-hand region hosts. There is one right-hand
/// region, ever: the archive surface (mn-fe1b48) adds a case here instead of
/// a second panel.
enum HolyWorkspaceRightPanel: String, Codable, Equatable, Sendable {
    case inbox
}

/// One compact status chip on an inbox row ("review requested", "draft").
struct HolyInboxChip: Equatable, Hashable, Sendable {
    enum Emphasis: Equatable, Hashable, Sendable {
        case neutral
        case attention
        case warning
    }

    let label: String
    let emphasis: Emphasis

    init(_ label: String, emphasis: Emphasis = .neutral) {
        self.label = label
        self.emphasis = emphasis
    }
}

/// What clicking a row does. Sources declare intent; the panel executes it
/// (NSWorkspace for URLs, roster selection for sessions).
enum HolyInboxRowAction: Equatable, Sendable {
    case openURL(URL)
    case selectSession(UUID)
    case none
}

/// One admission-tested row: addressed to the human, actionable, and cleared
/// by its source when reality changes (the Row Law). Rows never linger after
/// Erik acted — a source that cannot self-clear does not get rows.
struct HolyInboxRow: Equatable, Sendable, Identifiable {
    /// Stable across polls so the panel can diff ("gh:org/repo#7", "alert:12").
    let id: String
    let title: String
    /// Compact metadata line under the title (repo, author, alert body).
    let subtitle: String?
    let updatedAt: Date?
    let chips: [HolyInboxChip]
    let action: HolyInboxRowAction
    /// True when the source offers an explicit acknowledge affordance
    /// (alert rows). GitHub rows are cleared by reality, never by hand.
    let acknowledgeable: Bool
    /// Digest rows expand into children (bot PRs collapsed per repo).
    let children: [HolyInboxRow]
    /// A degraded row reports a broken source ("GitHub inbox unavailable").
    /// It renders quietly and never counts toward the unread badge.
    let isDegraded: Bool

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        updatedAt: Date? = nil,
        chips: [HolyInboxChip] = [],
        action: HolyInboxRowAction = .none,
        acknowledgeable: Bool = false,
        children: [HolyInboxRow] = [],
        isDegraded: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.updatedAt = updatedAt
        self.chips = chips
        self.action = action
        self.acknowledgeable = acknowledgeable
        self.children = children
        self.isDegraded = isDegraded
    }
}

/// A titled group of rows from one source. `sourceID` must equal the owning
/// source's `sourceID` — the engine routes acknowledge calls through it.
struct HolyInboxSection: Equatable, Sendable, Identifiable {
    let id: String
    let sourceID: String
    let title: String
    let rows: [HolyInboxRow]
    /// Sections of secondary attention ("Yours, open", bot digests) start
    /// collapsed; the panel remembers the user's override per section id.
    let collapsedByDefault: Bool
    /// Only sections of first-person attention feed the unread badge
    /// (needs-your-review rows, unacknowledged alerts). The badge must not lie.
    let countsTowardBadge: Bool

    init(
        id: String,
        sourceID: String,
        title: String,
        rows: [HolyInboxRow],
        collapsedByDefault: Bool = false,
        countsTowardBadge: Bool = false
    ) {
        self.id = id
        self.sourceID = sourceID
        self.title = title
        self.rows = rows
        self.collapsedByDefault = collapsedByDefault
        self.countsTowardBadge = countsTowardBadge
    }
}

/// Everything one source knows right now. Rows absent from the snapshot leave
/// the pane — clearing is the source re-stating truth, not local dismissal.
struct HolyInboxSourceSnapshot: Equatable, Sendable {
    let sections: [HolyInboxSection]
    /// One optional footer line ("this session: 3 lessons"), never rows.
    let footnote: String?

    init(sections: [HolyInboxSection], footnote: String? = nil) {
        self.sections = sections
        self.footnote = footnote
    }

    static let empty = HolyInboxSourceSnapshot(sections: [])
}

/// Cross-source facts the engine passes into every refresh.
struct HolyInboxRefreshContext: Equatable, Sendable {
    /// "org/repo" of the focused session's repository, for
    /// focused-repo-first ordering. Nil when no session or no GitHub remote.
    let focusedRepoSlug: String?

    init(focusedRepoSlug: String? = nil) {
        self.focusedRepoSlug = focusedRepoSlug
    }
}

/// The lane contract: one row source per attention domain. GitHub PRs and DB
/// alerts ship in this lane; manna triage (lane 08) conforms to this protocol
/// and registers with the engine without touching inbox files.
///
/// Contract:
/// - `sourceID` is stable and unique; every section the source returns must
///   carry it in `HolyInboxSection.sourceID`.
/// - `refresh` re-derives current truth. The engine serializes calls; a
///   source never sees two concurrent refreshes. Errors degrade into a quiet
///   degraded row inside the snapshot — never a throw, never a crash.
/// - `acknowledge` performs a row's acknowledge affordance for rows returned
///   with `acknowledgeable == true`; sources whose rows clear only through
///   reality (GitHub) keep the default no-op.
protocol HolyInboxRowSource: AnyObject, Sendable {
    var sourceID: String { get }
    func refresh(context: HolyInboxRefreshContext) async -> HolyInboxSourceSnapshot
    func acknowledge(rowID: String) async
}

extension HolyInboxRowSource {
    func acknowledge(rowID: String) async {}
}
