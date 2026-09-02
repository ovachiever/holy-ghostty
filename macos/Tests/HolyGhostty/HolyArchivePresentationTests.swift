import Foundation
import SQLite3
import Testing
@testable import Ghostty

/// The agent-sessions TUI's rendering rules (ui/widgets.py, app.py) as the
/// native archive transcribes them, plus the summary import from the TUI's
/// own SQLite index.
struct HolyArchivePresentationTests {
    typealias Present = HolyArchivePresentation

    @Test func rowTextPrefersSummaryThenRealPromptThenTitle() throws {
        let summarized = ArchiveFixtures.session(id: "s1", firstPrompt: "raw prompt", summary: "Built the ledger\nview")
        #expect(Present.rowText(for: summarized) == .init(text: "Built the ledger view", isFallback: false))

        let promptOnly = ArchiveFixtures.session(id: "s2", firstPrompt: "  fix the resizer  \nsecond line")
        #expect(Present.rowText(for: promptOnly) == .init(text: "fix the resizer", isFallback: true))

        // Harness chatter never becomes a row's text.
        let chatter = ArchiveFixtures.session(
            id: "s3",
            title: "Set effort",
            firstPrompt: "<local-command-stdout>Set effort level to medium</local-command-stdout>\nreal ask"
        )
        #expect(Present.rowText(for: chatter) == .init(text: "real ask", isFallback: true))
        #expect(chatter.displayTitle == "real ask")

        let titled = ArchiveFixtures.session(id: "s4", title: "Named", firstPrompt: "<system-reminder>x")
        #expect(Present.rowText(for: titled) == .init(text: "Named", isFallback: true))
        let empty = ArchiveFixtures.session(id: "s5", title: "", firstPrompt: "")
        #expect(Present.rowText(for: empty) == .init(text: "(no prompt)", isFallback: true))
    }

    @Test func datesAndLabelsMatchTheTUI() throws {
        let chicago = try #require(TimeZone(identifier: "America/Chicago"))
        let date = Date(timeIntervalSince1970: 1_788_374_921) // 2026-09-02 18:48:41 UTC
        #expect(Present.dateStamp(date, timeZone: chicago) == "09-02 13:48")
        #expect(Present.dateStamp(nil) == "??-?? ??:??")
        #expect(Present.longDate(date, timeZone: chicago) == "2026-09-02 13:48:41")
        #expect(Present.longDate(nil) == "Unknown")
        #expect(Present.shortLabel(for: .claudeCode) == "claude")
        #expect(Present.colorClass(for: .claudeCode) == "active")
        #expect(Present.colorClass(for: .codex) == "decision")
        #expect(Present.colorClass(for: .droid) == "ready")
        #expect(Present.childCountText(0) == "·")
        #expect(Present.childCountText(3) == "3")
        #expect(Present.projectLabel(ArchiveFixtures.session(id: "p", projectName: "versova-supply-intelligence")) == "versova-supp")
    }

    @Test func listHeadsFollowTheParentHeaderStrings() {
        let plain = Present.listHead(query: "", filter: nil, shown: 500, total: 2_461, sort: .relevance, matchingChildren: 0)
        #expect(plain == .init(prompt: "agent-sessions list", count: "500/2461 newest first"))
        let small = Present.listHead(query: "", filter: nil, shown: 12, total: 12, sort: .relevance, matchingChildren: 0)
        #expect(small.count == "12 newest first")
        let filtered = Present.listHead(query: "", filter: .codex, shown: 40, total: 40, sort: .relevance, matchingChildren: 0)
        #expect(filtered.prompt == "agent-sessions list --harness codex")
        let searched = Present.listHead(query: " resizer ", filter: nil, shown: 7, total: 7, sort: .newest, matchingChildren: 2)
        #expect(searched.prompt == "agent-sessions search \"resizer\"")
        #expect(searched.count == "7 sessions · 2 child matches · \(HolyArchiveSort.newest.label)")
        #expect(Present.childrenHead(searching: true, count: 2).prompt == "agent-sessions children --matching")
    }

    @Test func detailLinesFollowTheDetailPanel() {
        let parent = ArchiveFixtures.session(id: "p", projectName: "holy-ghostty", title: "New Session")
        #expect(Present.typeLine(for: parent, childCount: 3) == "parent session · 3 sub-agents")
        #expect(Present.typeLine(for: parent, childCount: 0) == "parent session")
        #expect(Present.detailTitle(for: parent) == "holy-ghostty")
        let child = ArchiveFixtures.session(id: "c", child: true, childType: "worker")
        #expect(Present.typeLine(for: child, childCount: 0) == "sub-agent · worker")
        #expect(Present.detailTitle(for: child) == "worker")
        #expect(Present.responseLimit(for: child) == 1_000)
        #expect(Present.responseLimit(for: parent) == 2_000)
        let long = String(repeating: "a", count: 2_010)
        #expect(Present.excerpt(long, limit: 2_000, empty: "(none)").hasSuffix("\n... (truncated)"))
        #expect(Present.excerpt("   ", limit: 10, empty: "(none)") == "(none)")
        #expect(Present.detailTitle(for: ArchiveFixtures.session(id: "t", title: String(repeating: "x", count: 60))).count == 50)
    }

    @Test func columnsFitTheirContentAndHeaders() {
        let sessions = [
            ArchiveFixtures.session(id: "a", projectName: "x"),
            ArchiveFixtures.session(id: "b", harness: .opencode, projectName: "a-long-project-name"),
        ]
        let widths = Present.columns(for: sessions, childCounts: ["a": 12])
        #expect(widths.project >= HolyMannaBoardMetrics.columnWidth(contentCharacters: 12, headerCharacters: 7))
        #expect(widths.harness >= HolyMannaBoardMetrics.columnWidth(contentCharacters: "opencode".count, headerCharacters: 7))
        #expect(widths.children >= HolyMannaBoardMetrics.columnWidth(contentCharacters: 2, headerCharacters: 3))
        let childWidths = Present.childColumns(for: [ArchiveFixtures.session(id: "c", child: true, childType: "a-very-long-child-type-name")])
        #expect(childWidths.type <= HolyMannaBoardMetrics.columnWidth(contentCharacters: HolyArchiveMetrics.childTypeCharacters, headerCharacters: 4))
    }

    @Test func summariesImportFromTheTUIsSQLiteIndex() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-archive-summaries-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // The TUI's index, as index/database.py creates it.
        let indexURL = root.appendingPathComponent("sessions.db")
        let index = try HolyDatabase.open(at: indexURL)
        try index.execute("CREATE TABLE summaries (session_id TEXT PRIMARY KEY, summary TEXT, model TEXT, content_hash TEXT, created_at INTEGER);")
        try index.execute("INSERT INTO summaries VALUES ('s1', 'Reviewed handoff order manifest', 'gpt-5.5', 'abc123def456', 1788374921);")
        try index.execute("INSERT INTO summaries VALUES ('s2', '', 'gpt-5.5', 'x', 1788374921);")
        try index.execute("INSERT INTO summaries VALUES ('s3', NULL, 'gpt-5.5', NULL, 1788374921);")

        let entries = try HolyArchiveLegacySummaryImporter.load(fromDatabase: indexURL)
        #expect(entries == [.init(sessionID: "s1", summary: "Reviewed handoff order manifest", contentHash: "abc123def456")])
        #expect(try HolyArchiveLegacySummaryImporter.load(fromDatabase: root.appendingPathComponent("missing.db")).isEmpty)

        // An index without the table (older agent-sessions) contributes nothing.
        let bareURL = root.appendingPathComponent("bare.db")
        let bare = try HolyDatabase.open(at: bareURL)
        try bare.execute("CREATE TABLE sessions (id TEXT PRIMARY KEY);")
        #expect(try HolyArchiveLegacySummaryImporter.load(fromDatabase: bareURL).isEmpty)

        // The summary lands on the session that lacked one.
        let repository = try HolyArchiveRepository(databaseURL: root.appendingPathComponent("holy.sqlite3"))
        try repository.replace(session: ArchiveFixtures.session(id: "s1"), messages: [], chunks: [])
        let imported = try HolyArchiveLegacySummaryImporter.migrate(repository: repository, from: [], databases: [indexURL])
        #expect(imported == 1)
        #expect(try repository.session(id: "s1")?.summary == "Reviewed handoff order manifest")
    }
}

enum ArchiveFixtures {
    static func session(
        id: String,
        harness: HolyArchiveHarness = .codex,
        child: Bool = false,
        childType: String? = nil,
        parentID: String? = nil,
        projectName: String = "holy-ghostty",
        title: String = "Built Archive Search",
        firstPrompt: String = "Build native archive search",
        lastResponse: String = "Implemented and tested archive search",
        summary: String? = nil,
        activity: TimeInterval = 1_700_000_000
    ) -> HolyArchiveSession {
        .init(
            id: id, harness: harness, rawPath: "/archive/\(id).jsonl", projectPath: "/project/\(projectName)",
            projectName: projectName, title: title,
            firstPrompt: firstPrompt, lastPrompt: "Verify the search",
            lastResponse: lastResponse, createdAt: Date(timeIntervalSince1970: activity - 60),
            modifiedAt: Date(timeIntervalSince1970: activity), isChild: child,
            childType: child ? (childType ?? "worker") : nil, parentID: parentID, model: "gpt-5.6",
            toolCalls: ["rg"], tokensUsed: 100, summary: summary, contentHash: "hash-\(id)",
            extra: [:], resumeCommand: "codex resume \(id)", messageCount: 2, turnCount: 1,
            fileMTime: Date(timeIntervalSince1970: activity),
            indexedAt: Date(timeIntervalSince1970: activity),
            autoTags: ["search"]
        )
    }

    static func messages(sessionID: String) -> [HolyArchiveMessage] {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        return [
            .init(id: "\(sessionID)-u", sessionID: sessionID, role: .user, content: "Build native archive search with find", timestamp: timestamp, sequence: 0),
            .init(id: "\(sessionID)-a", sessionID: sessionID, role: .assistant, content: "Implemented hybrid search; find is overlapping and case-insensitive.", timestamp: timestamp, sequence: 1),
            .init(id: "\(sessionID)-t", sessionID: sessionID, role: .tool, content: "(tool_result: 12 files)", timestamp: timestamp, sequence: 2),
        ]
    }
}
