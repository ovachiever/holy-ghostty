import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Ghostty

/// Draws the archive faces offscreen from a hermetic fixture repository,
/// so the layout can be looked at without launching the app.
/// TEST_RUNNER_HOLY_ARCHIVE_RENDER_DIR chooses where the PNGs land.
struct HolyArchiveRenderSmokeTests {
    @Test @MainActor func everyFaceRendersOffscreen() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-archive-render-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let outputDirectory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOLY_ARCHIVE_RENDER_DIR"]
            ?? root.appendingPathComponent("png").path)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let defaults = UserDefaults.standard
        let inspectorKey = "holy.archive.inspectorWidth.v1"
        let columnsKey = "holy.archive.columns.v1"
        let previousInspectorWidth = defaults.object(forKey: inspectorKey)
        let previousColumns = defaults.object(forKey: columnsKey)
        defer {
            if let previousInspectorWidth {
                defaults.set(previousInspectorWidth, forKey: inspectorKey)
            } else {
                defaults.removeObject(forKey: inspectorKey)
            }
            if let previousColumns {
                defaults.set(previousColumns, forKey: columnsKey)
            } else {
                defaults.removeObject(forKey: columnsKey)
            }
        }
        defaults.set(600, forKey: inspectorKey)
        defaults.set("", forKey: columnsKey)

        let databaseURL = root.appendingPathComponent("holy.sqlite3")
        let repository = try HolyArchiveRepository(databaseURL: databaseURL)
        let base: TimeInterval = 1_788_390_000
        let rows: [(HolyArchiveSession, [HolyArchiveMessage])] = [
            (ArchiveFixtures.session(id: "aaaaaaaa-1", harness: .claudeCode, projectName: "aldebaran-group", firstPrompt: "Generate the Tiffany Heaven on Earth business astrology brief", summary: "Generated Erik Tiffany Heaven on Earth business astrology", activity: base), ArchiveFixtures.messages(sessionID: "aaaaaaaa-1")),
            (ArchiveFixtures.session(id: "bbbbbbbb-2", harness: .claudeCode, projectName: "holy-ghostty", firstPrompt: "Rebuild the Board to match the web cockpit", summary: "Built native Board and Archive modes in Holy", activity: base - 120), ArchiveFixtures.messages(sessionID: "bbbbbbbb-2")),
            (ArchiveFixtures.session(id: "cccccccc-3", harness: .codex, projectName: "vms.io", firstPrompt: "<local-command-stdout>Set effort level to medium</local-command-stdout>\nRedesign Rocks and fix summary authorization", summary: nil, activity: base - 300), ArchiveFixtures.messages(sessionID: "cccccccc-3")),
            (ArchiveFixtures.session(id: "dddddddd-4", harness: .droid, projectName: "agent-do", firstPrompt: "Build clickable Engine Room drilldown prototypes", summary: "Built clickable Engine Room drilldown prototypes", activity: base - 900), ArchiveFixtures.messages(sessionID: "dddddddd-4")),
            (ArchiveFixtures.session(id: "eeeeeeee-5", harness: .opencode, projectName: "the-point-revision", firstPrompt: "Review this change for security vulnerabilities.  Changed files (you may Read these and any other file in the repo)", summary: nil, activity: base - 1_800), ArchiveFixtures.messages(sessionID: "eeeeeeee-5")),
            (ArchiveFixtures.session(id: "ffffffff-6", harness: .cursor, projectName: "substack-writings", firstPrompt: "Draft the AI universe meaning essay", summary: "Drafted AI universe meaning essay for Substack", activity: base - 3_600), ArchiveFixtures.messages(sessionID: "ffffffff-6")),
            (ArchiveFixtures.session(id: "child-1", harness: .claudeCode, child: true, childType: "Explore", parentID: "bbbbbbbb-2", projectName: "holy-ghostty", firstPrompt: "Find every caller of HolyMannaBoardSheet", activity: base - 100), ArchiveFixtures.messages(sessionID: "child-1")),
            (ArchiveFixtures.session(id: "child-2", harness: .claudeCode, child: true, childType: "general-purpose", parentID: "bbbbbbbb-2", projectName: "holy-ghostty", firstPrompt: "Audit the render smoke test for hermeticity", activity: base - 90), ArchiveFixtures.messages(sessionID: "child-2")),
        ]
        for (session, messages) in rows {
            try repository.replace(session: session, messages: messages, chunks: HolyArchiveChunker.chunks(session: session, messages: messages))
        }
        _ = try repository.addAnnotation(sessionID: "bbbbbbbb-2", kind: .tag, value: "breakthrough")
        _ = try repository.addAnnotation(sessionID: "bbbbbbbb-2", kind: .note, value: "The web page is the reference; the ledger row is the unit.")

        // A home with no harness directories: nothing to index, nothing to migrate.
        let emptyHome = root.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyHome, withIntermediateDirectories: true)
        let store = HolyArchiveModeStore(
            registry: .init(homeDirectory: emptyHome),
            databaseURL: databaseURL,
            resumeHandler: { _ in false }
        )
        store.present()
        for _ in 0 ..< 400 where store.sessions.isEmpty {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(store.sessions.count == 6)
        store.selectParent("bbbbbbbb-2")
        #expect(store.children.count == 2)

        var written: [String] = []
        func render(_ name: String, width: CGFloat = 1480, height: CGFloat = 900) async throws {
            let view = HolyArchiveModeView(store: store, onDismiss: {})
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds: 150_000_000)
            hosting.layoutSubtreeIfNeeded()
            let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            let url = outputDirectory.appendingPathComponent("\(name).png")
            try png.write(to: url)
            #expect(png.count > 1_000, "\(name) rendered nothing")
            written.append(url.path)
            window.contentView = nil
        }

        for width: CGFloat in [900, 1_000, 1_280, 1_512, 1_728] {
            try await render("archive-width-\(Int(width))", width: width)
        }
        var dragged = HolyLedgerColumnOverrides(json: "")
        dragged.set("date", width: 420, availableWidth: 1_400)
        dragged.set("harness", width: 420, availableWidth: 1_400)
        dragged.set("project", width: 560, availableWidth: 1_400)
        dragged.set("sub", width: 280, availableWidth: 1_400)
        defaults.set(dragged.json, forKey: columnsKey)
        try await render("archive-grip-dragged-then-narrowed", width: 1_120)
        defaults.set("", forKey: columnsKey)
        try await render("archive-compact-fold", width: 840)
        store.selectChild("child-1")
        try await render("archive-child")
        store.selectParent("bbbbbbbb-2")
        store.showTranscript()
        for _ in 0 ..< 200 where store.transcript.isEmpty {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        store.showTranscriptFind()
        store.transcriptFindQuery = "search"
        store.recomputeFind()
        try await render("archive-transcript")
        store.closeTranscript()
        store.chatIsPresented = true
        try await render("archive-research")
        store.chatIsPresented = false
        store.dismiss()

        print("HOLY_ARCHIVE_RENDER wrote:\n" + written.joined(separator: "\n"))
        #expect(written.count == 10)
    }
}
