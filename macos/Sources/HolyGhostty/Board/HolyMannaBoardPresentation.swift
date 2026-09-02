import AppKit
import Foundation
import SwiftUI

// The manna serve web cockpit (agent-do/tools/agent-manna/serve/static:
// styles.css, app.js, index.js, view.js) is the ratified reference design.
// Every token and rendering rule in this file is transcribed from it so the
// native face and the page stay one design. When the two disagree, the page
// wins and this file changes.

extension Color {
    init(holyHex hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// styles.css `:root` colors. Holy's own obsidian coincides with the page's
/// three darks; everything else is the page's exact value.
enum HolyMannaBoardPalette {
    static let bg = HolyGhosttyTheme.bg // --bg
    static let surface = HolyGhosttyTheme.bgElevated // --surface
    static let raised = HolyGhosttyTheme.bgSurface // --raised
    static let zebra = Color(holyHex: 0x101216)
    static let line = Color(holyHex: 0x30343A)
    static let lineStrong = Color(holyHex: 0x474D55)
    static let text = Color(holyHex: 0xD8D9D2)
    static let muted = Color(holyHex: 0x8D939C)
    /// Measured 4.9:1 on --bg: the dpt contrast floor is 4.5:1.
    static let faint = Color(holyHex: 0x7C828B)
    static let green = Color(holyHex: 0x83D18C)
    static let amber = Color(holyHex: 0xE2B86B)
    static let red = Color(holyHex: 0xED7C83)
    static let blue = Color(holyHex: 0x79B8E8)
    static let violet = Color(holyHex: 0xB7A0E8)
    /// Selection only: orange never reads as a state (blue = in progress,
    /// amber = decision).
    static let select = Color(holyHex: 0xF0925A)

    /// styles.css `.c-*`: the color a state word is set in.
    static func wordColor(forClass cls: String) -> Color {
        switch cls {
        case "active", "working": blue
        case "ready", "done": green
        case "waiting", "failed": red
        case "decision", "needs-user": amber
        case "dream": violet
        case "muted", "present", "idle": muted
        default: faint
        }
    }

    /// styles.css `.s-*`: the color of a row's severity stripe.
    static func stripeColor(forClass cls: String) -> Color {
        switch cls {
        case "active", "working": blue
        case "ready": green
        case "waiting", "failed": red
        case "decision", "needs-user": amber
        case "dream": violet
        case "present", "idle": muted
        default: faint
        }
    }
}

/// styles.css `:root` sizes and view.js limits, in points. The page's px
/// are CSS px at 1x, which is what a SwiftUI point is.
enum HolyMannaBoardMetrics {
    // type scale: 12 13 16 — nothing under 12 (dpt floor)
    static let bodySize: CGFloat = 12 // --t-body / --t-meta / --t-small
    static let headingSize: CGFloat = 13 // --t-h
    static let bodyLineHeight: CGFloat = 1.45
    static let digestLineHeight: CGFloat = 1.35
    // spacing scale: 4 8 12 16 24 32
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 24
    static let s6: CGFloat = 32
    static let rowHeight: CGFloat = 26 // --row-h
    static let stripeColumnWidth: CGFloat = 10 // --col-stripe
    static let stripeWidth: CGFloat = 3 // .row::before width
    static let stripeHeight: CGFloat = 14 // .row::before height
    static let selectionEdgeWidth: CGFloat = 3 // .row.selected inset shadow
    static let columnHeaderHeight: CGFloat = 22 // .cols height
    static let columnGap: CGFloat = s3 // .row column-gap
    static let inspectorDefaultWidth: CGFloat = 300 // --inspector-w
    static let inspectorMinimumWidth: CGFloat = 220 // view.js INSPECTOR_MIN
    static let inspectorMaximumWidth: CGFloat = 600 // view.js INSPECTOR_MAX
    static let inspectorNarrowWidth: CGFloat = 260 // @media (max-width: 1100px)
    static let narrowBreakpoint: CGFloat = 1100
    static let compactBreakpoint: CGFloat = 860 // inspector hidden below this
    static let topbarHeight: CGFloat = 40 // --topbar-h
    static let stripHeight: CGFloat = 28 // --strip-h
    static let resizerWidth: CGFloat = 6 // .cockpit grid middle track
    static let grepFieldWidth: CGFloat = 400 // .grep input
    static let grepFieldHeight: CGFloat = 24
    static let metaLabelWidth: CGFloat = 76 // .inspector .meta grid
    static let debugLabelWidth: CGFloat = 160 // .kv grid
    static let chipRadius: CGFloat = 9 // .chip border-radius
    /// The list column holds a 72-character digest at 12px mono beside its
    /// fixed columns and the inspector; wider windows center the cockpit
    /// instead of stretching the digest across the screen.
    static let measure: CGFloat = 1440
    static let pillTracking: CGFloat = 0.06 * bodySize // letter-spacing .06em
    static let trackColumnMaxCharacters = 30 // COLS.board track max
    static let stateColumnMaxCharacters = 24 // COLS.board state max
    static let digestFloorCharacters = 24 // MIN_FLEX_CHARS
    static let commitSubjectCharacters = 56 // clip(c.subject, 56)
    static let promptQuoteCharacters = 90 // inbox peer row clip
    static let peerPromptCharacters = 100 // peer row clip
    static let dropNoteCharacters = 80 // inbox drop row clip
    static let timelineClipCharacters = 60
    static let toastSeconds: TimeInterval = 1.8 // app.js toast timer
    static let copiedFlashSeconds: TimeInterval = 1.6 // app.js [copied] flash
    /// The topbar sits under the transparent titlebar's traffic lights, like
    /// every other workspace face (HolyWorkspaceLayout.titlebarControlInset,
    /// private to the workspace view).
    static let titlebarInset: CGFloat = 42

    /// One monospace character's advance at the body size, measured from the
    /// live font once. The page fits every fixed column to characters ×
    /// advance because the font is monospace, so the measure is exact.
    static let charAdvance: CGFloat = {
        let font = NSFont.monospacedSystemFont(ofSize: bodySize, weight: .regular)
        return ("0" as NSString).size(withAttributes: [.font: font]).width
    }()

    /// app.js applyFit: content width, floored by the header label (+6), +4 slack.
    static func columnWidth(contentCharacters: Int, headerCharacters: Int, tracked: Bool = false) -> CGFloat {
        let content = CGFloat(contentCharacters) * (charAdvance + (tracked ? pillTracking : 0))
        let header = CGFloat(headerCharacters) * (charAdvance + pillTracking) + 6
        return ceil(max(content, header)) + 4
    }
}

enum HolyMannaBoardFilter: String, CaseIterable, Identifiable, Sendable {
    case live
    case done
    case dreams
    case recent
    case all

    var id: String { rawValue }
}

struct HolyMannaBoardSectionModel: Identifiable, Equatable, Sendable {
    let id: String
    let prompt: String
    let items: [HolyMannaBoardItem]
    let emptyText: String
    let showsAge: Bool
}

struct HolyMannaStateCell: Equatable, Sendable {
    /// Rendered in caps with tracking: "blocked", "needs you", "in progress".
    let word: String
    /// Rendered as-is after " · ": the short blocker ids.
    let keepCase: String?
    /// The `.c-*` / `.s-*` class the cell is colored by.
    let cls: String

    var plain: String { keepCase.map { "\(word) · \($0)" } ?? word }
}

struct HolyMannaInboxRowModel: Identifiable, Equatable, Sendable {
    let id: String
    let kind: String
    let cls: String
    let text: String
    let verb: String
    let ask: HolyMannaAsk
}

struct HolyMannaBoardColumnWidths: Equatable, Sendable {
    let id: CGFloat
    let track: CGFloat
    let state: CGFloat
    let priority: CGFloat
}

struct HolyMannaInboxColumnWidths: Equatable, Sendable {
    let kind: CGFloat
    let verb: CGFloat
}

struct HolyMannaPeerColumnWidths: Equatable, Sendable {
    let session: CGFloat
    let holding: CGFloat
    let state: CGFloat
    let age: CGFloat
}

struct HolyMannaClaimColumnWidths: Equatable, Sendable {
    let owner: CGFloat
    let state: CGFloat
    let age: CGFloat
}

struct HolyMannaDropColumnWidths: Equatable, Sendable {
    let from: CGFloat
    let age: CGFloat
}

/// index.html's table: every count column fits its widest cell, the
/// updated column its widest date, and the board name takes the rest.
struct HolyMannaEstateColumnWidths: Equatable, Sendable {
    let needsYou: CGFloat
    let working: CGFloat
    let here: CGFloat
    let active: CGFloat
    let ready: CGFloat
    let blocked: CGFloat
    let decision: CGFloat
    let dream: CGFloat
    let done: CGFloat
    let drift: CGFloat
    let updated: CGFloat
}

/// app.js rendering rules, as pure functions the view and the tests share.
enum HolyMannaBoardPresentation {
    // MARK: Labels

    static let stateLabels: [String: String] = [
        "active": "in progress",
        "ready": "ready",
        "waiting": "blocked",
        "decision": "decision",
        "dream": "dream",
        "done": "done",
        "track": "track",
    ]

    static func label(_ state: String?) -> String {
        guard let state, !state.isEmpty else { return "" }
        return stateLabels[state] ?? state.replacingOccurrences(of: "_", with: " ")
    }

    static let attentionLabels: [String: String] = [
        "needs-user": "needs you",
        "failed": "failed",
        "working": "working",
        "present": "present",
        "idle": "idle",
        "finished": "finished",
        "ended": "ended",
        "gone": "gone",
        "unseen": "unseen",
    ]

    static func attention(_ value: String?) -> String {
        guard let value else { return "" }
        return attentionLabels[value] ?? value
    }

    /// app.js clip: collapse whitespace, cut to n with an ellipsis.
    static func clip(_ text: String?, _ limit: Int) -> String {
        let collapsed = (text ?? "")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(max(0, limit - 1))) + "…"
    }

    private static let tagPrefix = #/^\s*(?:\[[^\]]{1,24}\]\s*)+/#
    private static let trackPrefix = #/^\s*track\s*:\s*/#.ignoresCase()
    private static let trailingParenthetical = #/\s*\([^)]*\)\s*$/#

    /// app.js shortTrack: drop leading [TAG]s, a "track:" prefix, and a
    /// trailing parenthetical.
    static func shortTrack(_ title: String?) -> String {
        var value = title ?? ""
        value = value.replacing(tagPrefix, with: "")
        value = value.replacing(trackPrefix, with: "")
        value = value.replacing(trailingParenthetical, with: "")
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func shortID(_ id: String) -> String {
        id.hasPrefix("mn-") ? String(id.dropFirst(3)) : id
    }

    // MARK: Rows

    /// app.js rowText: the digest, else the title.
    static func rowText(_ item: HolyMannaBoardItem) -> String {
        if let digest = item.digest?.trimmingCharacters(in: .whitespacesAndNewlines), !digest.isEmpty {
            return digest
        }
        return item.title
    }

    static func isFallbackText(_ item: HolyMannaBoardItem) -> Bool {
        (item.digest?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
    }

    /// The claimant's pulse overrides the state word: an in-progress item
    /// whose agent is waiting on a person reads "needs you".
    static func needsYou(_ item: HolyMannaBoardItem) -> Bool {
        item.effective == "active" && item.claimant?.attention == "needs-user"
    }

    static func stateCell(for item: HolyMannaBoardItem) -> HolyMannaStateCell {
        if item.effective == "waiting", !item.blockers.isEmpty {
            return .init(
                word: "blocked",
                keepCase: item.blockers.map { shortID($0.id) }.joined(separator: ", "),
                cls: "waiting"
            )
        }
        if needsYou(item) {
            return .init(word: "needs you", keepCase: nil, cls: "needs-user")
        }
        return .init(word: label(item.effective), keepCase: nil, cls: item.effective)
    }

    static func stripeClass(for item: HolyMannaBoardItem) -> String {
        needsYou(item) ? "needs-user" : item.effective
    }

    static func priorityText(_ item: HolyMannaBoardItem) -> String {
        item.order.map { "#\($0 + 1)" } ?? ""
    }

    // MARK: Filters

    /// app.js matches: grep over id, title, digest, track, claimant, description.
    static func matches(_ item: HolyMannaBoardItem, grep: String) -> Bool {
        let needle = grep.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        let hay = [item.id, item.title, item.digest, item.trackTitle, item.claimant?.label, item.description]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        return hay.contains(needle)
    }

    /// The track filter's untracked bucket.
    static let untrackedFilter = "(none)"

    static func trackMatches(_ item: HolyMannaBoardItem, track: String?) -> Bool {
        guard let track, !track.isEmpty else { return true }
        if track == untrackedFilter { return item.track == nil }
        return item.track == track
    }

    static func sections(
        state: HolyMannaStatePayload,
        filter: HolyMannaBoardFilter,
        track: String?,
        grep: String
    ) -> [HolyMannaBoardSectionModel] {
        let keep: ([HolyMannaBoardItem]) -> [HolyMannaBoardItem] = { rows in
            rows.filter { trackMatches($0, track: track) && matches($0, grep: grep) }
        }
        func section(_ id: String, _ rows: [HolyMannaBoardItem], _ empty: String, age: Bool = false) -> HolyMannaBoardSectionModel {
            .init(id: id, prompt: "manna \(id)", items: keep(rows), emptyText: empty, showsAge: age)
        }
        let byRecency: (HolyMannaBoardItem, HolyMannaBoardItem) -> Bool = {
            ($0.updatedAt ?? "") > ($1.updatedAt ?? "")
        }
        let waiting = state.waves.flatMap(\.items) + state.unlayered
        let live = [
            section("now", state.now, "nothing claimed"),
            section("next", state.next, "nothing is ready"),
            section("waiting", waiting, "nothing is blocked"),
        ]
        let dreams = section("dreams", state.dreams, "no dreams parked")
        let done = section(
            "done",
            state.all.filter { $0.effective == "done" }.sorted(by: byRecency),
            "nothing done yet"
        )
        switch filter {
        case .live: return live
        case .all: return live + [dreams, done]
        case .dreams: return [dreams]
        case .done: return [done]
        case .recent:
            return [section("recent", state.all.sorted(by: byRecency), "board is empty", age: true)]
        }
    }

    // MARK: Inbox

    static func kindLabel(_ kind: String) -> String {
        switch kind {
        case "failed": "peer"
        case "document": "doc"
        case "repair": "repairs"
        default: kind
        }
    }

    static func colorClass(for ask: HolyMannaAsk) -> String {
        switch ask.kind {
        case "peer": "needs-user"
        case "failed": "failed"
        case "decision", "landed": "decision"
        case "contention": "waiting"
        case "dream": "dream"
        case "ready": "ready"
        default: "muted"
        }
    }

    static func text(for ask: HolyMannaAsk) -> String {
        guard let detail = ask.detail, !detail.isEmpty else { return ask.title }
        return "\(ask.title) · \(detail)"
    }

    static func inboxRows(state: HolyMannaStatePayload, grep: String) -> [HolyMannaInboxRowModel] {
        let needle = grep.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return state.asks.compactMap { ask in
            let row = HolyMannaInboxRowModel(
                id: ask.id,
                kind: kindLabel(ask.kind),
                cls: colorClass(for: ask),
                text: text(for: ask),
                verb: ask.verb,
                ask: ask
            )
            guard needle.isEmpty || row.text.lowercased().contains(needle) else { return nil }
            return row
        }
    }

    // MARK: Coordination

    static func peerMatches(_ peer: HolyMannaPeer, grep: String) -> Bool {
        let needle = grep.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        return [peer.agentID, peer.alias, peer.goal, peer.pulse?.latestPrompt]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
            .contains(needle)
    }

    static func claimMatches(_ claim: HolyMannaCoordClaim, grep: String) -> Bool {
        let needle = grep.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        return "\(claim.path) \(claim.owner) \(claim.reason ?? "")".lowercased().contains(needle)
    }

    /// The peer row's focus cell: the goal, else the latest prompt quoted.
    static func peerFocusText(_ peer: HolyMannaPeer) -> String? {
        if let goal = peer.goal, !goal.isEmpty { return goal }
        if let prompt = peer.pulse?.latestPrompt, !prompt.isEmpty {
            return "“\(clip(prompt, HolyMannaBoardMetrics.peerPromptCharacters))”"
        }
        return nil
    }

    static func claimStateCell(_ claim: HolyMannaCoordClaim) -> HolyMannaStateCell {
        if claim.contended { return .init(word: "contended", keepCase: nil, cls: "waiting") }
        if claim.stale { return .init(word: "stale", keepCase: claim.ownerStatus ?? "gone", cls: "faint") }
        return .init(word: claim.strength ?? "claimed", keepCase: nil, cls: "ready")
    }

    static func claimStripeClass(_ claim: HolyMannaCoordClaim) -> String {
        claim.contended ? "waiting" : claim.stale ? "gone" : "ready"
    }

    // MARK: Time

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return isoFractional.date(from: value) ?? isoPlain.date(from: value)
    }

    /// index.js / app.js fmtDate: "Sep 2, 6:50 AM"; "—" for nothing; the raw
    /// text when it is not a date.
    static func formatDate(_ value: String?, timeZone: TimeZone = .current) -> String {
        guard let value, !value.isEmpty else { return "—" }
        guard let date = parseDate(value) else { return value }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }

    /// app.js ago: "now", "5m", "3h", "10d"; "never" for nothing.
    static func ago(_ value: String?, now: Date = .now) -> String {
        guard let value, !value.isEmpty else { return "never" }
        guard let date = parseDate(value) else { return value }
        let minutes = Int(floor(now.timeIntervalSince(date) / 60))
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        if minutes < 1440 { return "\(minutes / 60)h" }
        return "\(minutes / 1440)d"
    }

    /// app.js rel: the topbar's "updated 5s ago".
    static func updatedLabel(since: Date?, now: Date = .now) -> String {
        guard let since else { return "waiting for state" }
        let seconds = max(0, Int(floor(now.timeIntervalSince(since))))
        if seconds < 3 { return "updated now" }
        if seconds < 60 { return "updated \(seconds)s ago" }
        return "updated \(seconds / 60)m ago"
    }

    // MARK: Estate

    /// serve.py boards_index order: existing boards first, needs-you first,
    /// then working, then the freshest board; the name settles ties.
    static func estateRows(_ boards: [HolyMannaEstateBoard]) -> [HolyMannaEstateBoard] {
        boards.sorted { lhs, rhs in
            if lhs.exists != rhs.exists { return lhs.exists }
            if lhs.coord.needsYou != rhs.coord.needsYou { return lhs.coord.needsYou > rhs.coord.needsYou }
            if lhs.coord.working != rhs.coord.working { return lhs.coord.working > rhs.coord.working }
            let lhsUpdate = lhs.latestUpdate ?? ""
            let rhsUpdate = rhs.latestUpdate ?? ""
            if lhsUpdate != rhsUpdate { return lhsUpdate > rhsUpdate }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// index.js cell: nil is "not read yet" (…), zero is a dim dot, a count
    /// is the number.
    static func estateCellText(_ count: Int?) -> String {
        guard let count else { return "…" }
        return count == 0 ? "·" : String(count)
    }

    /// The estate contract's status_counts is a census of the board's
    /// effective states (active/ready/blocked/done); older boards may still
    /// carry the raw status names. An absent key on an existing board is a
    /// zero, never an unknown.
    static func estateStatusCount(_ board: HolyMannaEstateBoard, _ keys: String...) -> Int? {
        guard board.exists else { return nil }
        for key in keys {
            if let value = board.statusCounts[key] { return value }
        }
        return 0
    }

    // MARK: Columns

    static func boardColumns(for items: [HolyMannaBoardItem], showsAge: Bool, now: Date = .now) -> HolyMannaBoardColumnWidths {
        let ids = items.map(\.id.count).max() ?? 0
        let tracks = min(
            items.map { shortTrack($0.trackTitle).count }.max() ?? 0,
            HolyMannaBoardMetrics.trackColumnMaxCharacters
        )
        let states = min(
            items.map { stateCell(for: $0).plain.count }.max() ?? 0,
            HolyMannaBoardMetrics.stateColumnMaxCharacters
        )
        let priorities = items.map { showsAge ? ago($0.updatedAt, now: now).count : priorityText($0).count }.max() ?? 0
        return .init(
            id: HolyMannaBoardMetrics.columnWidth(contentCharacters: ids, headerCharacters: "id".count),
            track: HolyMannaBoardMetrics.columnWidth(contentCharacters: tracks, headerCharacters: "track".count),
            state: HolyMannaBoardMetrics.columnWidth(contentCharacters: states, headerCharacters: "state".count, tracked: true),
            priority: HolyMannaBoardMetrics.columnWidth(contentCharacters: priorities, headerCharacters: (showsAge ? "age" : "#").count)
        )
    }

    static func inboxColumns(for rows: [HolyMannaInboxRowModel]) -> HolyMannaInboxColumnWidths {
        let kinds = rows.map(\.kind.count).max() ?? 0
        let verbs = rows.map { row in
            row.ask.kind == "dream" ? "promote delete".count + 3 : row.verb.count
        }.max() ?? 0
        return .init(
            kind: HolyMannaBoardMetrics.columnWidth(contentCharacters: kinds, headerCharacters: "kind".count),
            verb: HolyMannaBoardMetrics.columnWidth(contentCharacters: verbs, headerCharacters: "verb".count, tracked: true)
        )
    }

    static func peerColumns(for peers: [HolyMannaPeer]) -> HolyMannaPeerColumnWidths {
        let sessions = peers.map { $0.displayName.count }.max() ?? 0
        let holdings = peers.map { $0.holding.map(\.id).joined(separator: " ").count }.max() ?? 0
        let states = peers.map { attention($0.attention).count }.max() ?? 0
        let ages = peers.map { ($0.age ?? "").count }.max() ?? 0
        return .init(
            session: HolyMannaBoardMetrics.columnWidth(contentCharacters: sessions, headerCharacters: "session".count),
            holding: HolyMannaBoardMetrics.columnWidth(contentCharacters: holdings, headerCharacters: "holding".count),
            state: HolyMannaBoardMetrics.columnWidth(contentCharacters: states, headerCharacters: "state".count, tracked: true),
            age: HolyMannaBoardMetrics.columnWidth(contentCharacters: ages, headerCharacters: "age".count)
        )
    }

    static func claimColumns(for claims: [HolyMannaCoordClaim], now: Date = .now) -> HolyMannaClaimColumnWidths {
        let owners = claims.map { ($0.ownerAlias ?? $0.owner).count }.max() ?? 0
        let states = claims.map { claimStateCell($0).plain.count }.max() ?? 0
        let ages = claims.map { ago($0.updatedAt, now: now).count }.max() ?? 0
        return .init(
            owner: HolyMannaBoardMetrics.columnWidth(contentCharacters: owners, headerCharacters: "owner".count),
            state: HolyMannaBoardMetrics.columnWidth(contentCharacters: states, headerCharacters: "state".count, tracked: true),
            age: HolyMannaBoardMetrics.columnWidth(contentCharacters: ages, headerCharacters: "age".count)
        )
    }

    static func dropFromText(_ drop: HolyMannaCoordDrop) -> String {
        "\(drop.owner ?? "unknown") → \(drop.recipient ?? "any")"
    }

    static func dropColumns(for drops: [HolyMannaCoordDrop], now: Date = .now) -> HolyMannaDropColumnWidths {
        let froms = drops.map { dropFromText($0).count }.max() ?? 0
        let ages = drops.map { ago($0.createdAt, now: now).count }.max() ?? 0
        return .init(
            from: HolyMannaBoardMetrics.columnWidth(contentCharacters: froms, headerCharacters: "from → for".count),
            age: HolyMannaBoardMetrics.columnWidth(contentCharacters: ages, headerCharacters: "age".count)
        )
    }

    static func estateColumns(for boards: [HolyMannaEstateBoard]) -> HolyMannaEstateColumnWidths {
        // Cells carry s2 of padding on each side inside their frame.
        let inset = 2 * HolyMannaBoardMetrics.s2
        func numeric(_ header: String, _ value: (HolyMannaEstateBoard) -> Int?) -> CGFloat {
            let widest = boards.map { estateCellText(value($0)).count }.max() ?? 0
            return HolyMannaBoardMetrics.columnWidth(contentCharacters: widest, headerCharacters: header.count) + inset
        }
        let dates = boards.map { formatDate($0.latestUpdate).count }.max() ?? 0
        return .init(
            needsYou: numeric("needs you") { $0.exists ? $0.coord.needsYou : nil },
            working: numeric("working") { $0.exists ? $0.coord.working : nil },
            here: numeric("here") { $0.exists ? $0.coord.here : nil },
            active: numeric("active") { estateStatusCount($0, "active", "in_progress") },
            ready: numeric("ready") { estateStatusCount($0, "ready", "open") },
            blocked: numeric("blocked") { estateStatusCount($0, "blocked") },
            decision: numeric("decision") { $0.exists ? $0.decisions : nil },
            dream: numeric("dream") { $0.exists ? $0.dreams : nil },
            done: numeric("done") { estateStatusCount($0, "done") },
            drift: numeric("drift") { $0.exists ? $0.driftCount : nil },
            updated: HolyMannaBoardMetrics.columnWidth(contentCharacters: dates, headerCharacters: "updated".count) + inset
        )
    }

    // MARK: Chrome

    /// The topbar's connection words: the mark is lit only while the board
    /// is being kept current and its last read succeeded.
    static func connectionLabel(isLive: Bool, isRefreshing: Bool, hasState: Bool, failed: Bool) -> String {
        if isRefreshing, !hasState { return "reading" }
        if failed { return "stale" }
        return isLive ? "live" : "paused"
    }
}
