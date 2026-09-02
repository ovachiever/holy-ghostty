import AppKit
import Foundation
import SwiftUI

// The archive face wears the board cockpit's tokens (HolyMannaBoardPalette,
// HolyMannaBoardMetrics) and behaves like the agent-sessions TUI
// (agent_sessions/app.py, ui/widgets.py). Every rule below is transcribed
// from the TUI; the look comes from the cockpit so Holy's two faces read
// as one design.

/// Sizes the TUI decides in characters or fractions, in the cockpit's points.
enum HolyArchiveMetrics {
    /// The TUI gives details 45% of the width; within the cockpit's 220–600
    /// bounds this keeps a 2,000-character prompt readable at 12px mono.
    static let inspectorDefaultWidth: CGFloat = 440
    /// styles.py: parent list 60%, sub-agent pane 40% of the left column.
    static let childPaneFraction: CGFloat = 0.4
    static let projectCharacters = 12 // widgets.py project[:12]; the native column fits the whole name
    static let detailTitleCharacters = 50 // truncate(display_title, 50)
    static let promptCharacters = 2_000 // first prompt / parent last response cap
    static let childResponseCharacters = 1_000 // child last response cap
    static let childTypeCharacters = 18 // sub-agent child_type padded to 18
}

struct HolyArchiveListHead: Equatable, Sendable {
    let prompt: String
    let count: String
}

struct HolyArchiveRowText: Equatable, Sendable {
    let text: String
    /// True when no AI summary exists and the first prompt (or title) stands in.
    let isFallback: Bool
}

struct HolyArchiveColumnWidths: Equatable, Sendable {
    let date: CGFloat
    let harness: CGFloat
    let project: CGFloat
    let children: CGFloat
}

struct HolyArchiveChildColumnWidths: Equatable, Sendable {
    let type: CGFloat
}

enum HolyArchivePresentation {
    // MARK: Harness

    /// The TUI's provider colors (cyan, yellow, green, blue, magenta) mapped
    /// onto the cockpit's five hues; cursor takes the muted register because
    /// the cockpit's blue already belongs to Claude Code.
    static func colorClass(for harness: HolyArchiveHarness) -> String {
        switch harness {
        case .claudeCode: "active"
        case .codex: "decision"
        case .droid: "ready"
        case .opencode: "dream"
        case .cursor: "muted"
        }
    }

    static func shortLabel(for harness: HolyArchiveHarness) -> String {
        switch harness {
        case .claudeCode: "claude"
        case .codex: "codex"
        case .droid: "droid"
        case .cursor: "cursor"
        case .opencode: "opencode"
        }
    }

    // MARK: Rows

    private static func formatter(_ format: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }

    /// widgets.py: `MM-DD HH:MM`.
    static func dateStamp(_ date: Date?, timeZone: TimeZone = .current) -> String {
        guard let date else { return "??-?? ??:??" }
        return formatter("MM-dd HH:mm", timeZone: timeZone).string(from: date)
    }

    /// widgets.py detail panel: `%Y-%m-%d %H:%M:%S`, or Unknown.
    static func longDate(_ date: Date?, timeZone: TimeZone = .current) -> String {
        guard let date else { return "Unknown" }
        return formatter("yyyy-MM-dd HH:mm:ss", timeZone: timeZone).string(from: date)
    }

    /// widgets.py row: the AI summary in full color, else the first prompt,
    /// else the title, else "(no prompt)" dimmed. Newlines are flattened.
    static func rowText(for session: HolyArchiveSession) -> HolyArchiveRowText {
        if let summary = session.summary?.holyArchiveNilIfBlank {
            return .init(text: flatten(summary), isFallback: false)
        }
        if let prompt = HolyArchiveText.firstRealLine(in: session.firstPrompt) {
            return .init(text: flatten(prompt), isFallback: true)
        }
        if let title = session.title.holyArchiveNilIfBlank {
            return .init(text: flatten(title), isFallback: true)
        }
        return .init(text: "(no prompt)", isFallback: true)
    }

    static func flatten(_ value: String) -> String {
        value.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The TUI clips projects at 12 characters; here the column fits the
    /// whole name and the user narrows it by dragging (Erik, 2026-09-02:
    /// "never cut off project").
    static func projectLabel(_ session: HolyArchiveSession) -> String {
        session.projectName
    }

    static func childCountText(_ count: Int) -> String {
        count > 0 ? String(count) : "·"
    }

    // MARK: Heads

    /// app.py parent header: "All Sessions (500/78927 newest first)",
    /// "🧠 Claude Code (123 sessions)", or in search mode
    /// "Search: q (N sessions, M matches · by relevance)" — as a `$` prompt.
    static func listHead(
        query: String,
        filter: HolyArchiveHarness?,
        shown: Int,
        total: Int,
        sort: HolyArchiveSort,
        matchingChildren: Int
    ) -> HolyArchiveListHead {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return .init(
                prompt: "agent-sessions search \"\(trimmed)\"",
                count: "\(shown) sessions · \(matchingChildren) child matches · \(sort.label)"
            )
        }
        let countText = total > shown ? "\(shown)/\(total) newest first" : "\(total) newest first"
        if let filter {
            return .init(prompt: "agent-sessions list --harness \(filter.rawValue)", count: countText)
        }
        return .init(prompt: "agent-sessions list", count: countText)
    }

    static func childrenHead(searching: Bool, count: Int) -> HolyArchiveListHead {
        .init(
            prompt: searching ? "agent-sessions children --matching" : "agent-sessions children",
            count: String(count)
        )
    }

    // MARK: Details

    /// widgets.py: `PARENT SESSION` (+ sub-agent count) or `SUB-AGENT` + agent.
    static func typeLine(for session: HolyArchiveSession, childCount: Int) -> String {
        if session.isChild {
            return "sub-agent · \(session.childType ?? "unknown")"
        }
        return childCount > 0 ? "parent session · \(childCount) sub-agents" : "parent session"
    }

    /// widgets.py display title: child → child type; empty or "New Session"
    /// → project name; clipped at 50.
    static func detailTitle(for session: HolyArchiveSession) -> String {
        var title = session.title
        if session.isChild {
            title = session.childType ?? session.title
        } else if title.holyArchiveNilIfBlank == nil || title == "New Session" {
            title = session.projectName
        }
        return HolyMannaBoardPresentation.clip(title, HolyArchiveMetrics.detailTitleCharacters)
    }

    /// widgets.py excerpt boxes: the first N characters with a truncation note.
    static func excerpt(_ text: String, limit: Int, empty: String) -> String {
        guard let value = text.holyArchiveNilIfBlank else { return empty }
        guard value.count > limit else { return value }
        return String(value.prefix(limit)) + "\n... (truncated)"
    }

    static func responseLimit(for session: HolyArchiveSession) -> Int {
        session.isChild ? HolyArchiveMetrics.childResponseCharacters : HolyArchiveMetrics.promptCharacters
    }

    /// The footer's key legend, as the TUI prints it.
    static let keyLegend = "enter copy · r resume · t transcript · / search · f filter · s sort · i reindex · ? research · ^t tag · ^n note · esc back"
    static let transcriptLegend = "c copy all · / find · n next · esc back"

    // MARK: Columns

    static func columns(for sessions: [HolyArchiveSession], childCounts: [String: Int]) -> HolyArchiveColumnWidths {
        let projects = sessions.map { projectLabel($0).count }.max() ?? 0
        let harnesses = sessions.map { shortLabel(for: $0.harness).count }.max() ?? 0
        let children = sessions.map { childCountText(childCounts[$0.id] ?? 0).count }.max() ?? 0
        return .init(
            date: HolyMannaBoardMetrics.columnWidth(contentCharacters: "00-00 00:00".count, headerCharacters: "date".count),
            harness: HolyMannaBoardMetrics.columnWidth(contentCharacters: harnesses, headerCharacters: "harness".count),
            project: HolyMannaBoardMetrics.columnWidth(contentCharacters: projects, headerCharacters: "project".count),
            children: HolyMannaBoardMetrics.columnWidth(contentCharacters: children, headerCharacters: "sub".count)
        )
    }

    static func childColumns(for children: [HolyArchiveSession]) -> HolyArchiveChildColumnWidths {
        let types = min(
            children.map { ($0.childType ?? "sub-agent").count }.max() ?? 0,
            HolyArchiveMetrics.childTypeCharacters
        )
        return .init(type: HolyMannaBoardMetrics.columnWidth(contentCharacters: types, headerCharacters: "type".count))
    }
}
