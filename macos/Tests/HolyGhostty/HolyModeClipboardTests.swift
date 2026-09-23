import AppKit
import SwiftUI
import Testing
@testable import Ghostty

/// App-hosted. Build in a no-launch lane; execute only at coordinated acceptance.
/// Real surfaces run /bin/cat, never a shell, tmux, or a provider session. Clipboard
/// contents stay in memory and are restored, including non-text representations.
@MainActor
@Suite(.serialized)
struct HolyModeClipboardTests {
    @Test(arguments: HolyWorkspaceWindow.Mode.allCases)
    func presentationResignsTerminalAndRejectsLateFocus(mode: HolyWorkspaceWindow.Mode) async throws {
        let fixture = try ClipboardFixture()
        defer { fixture.close() }
        #expect(fixture.window.makeFirstResponder(fixture.surface))
        fixture.present(mode)
        #expect(fixture.window.modeOwnsKeyboard)
        #expect(fixture.window.firstResponder !== fixture.surface)
        #expect(!fixture.surface.focused)

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 30))
        fixture.window.contentView?.addSubview(field)
        #expect(fixture.window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        #expect(fixture.window.firstResponder === editor)
        #expect(!fixture.window.makeFirstResponder(fixture.surface))
        Ghostty.moveFocus(to: fixture.surface)
        try await Task.sleep(for: .milliseconds(100))
        #expect(fixture.window.firstResponder === editor)
        fixture.surface.focusDidChange(true)
        #expect(!fixture.surface.focused)

        // SwiftUI removes the terminal from the view tree under a mode. Its
        // exclusion must survive window == nil and stale direct event delivery.
        fixture.surface.removeFromSuperview()
        #expect(fixture.surface.window == nil)
        #expect(fixture.surface.holyModeOwnsKeyboard)
        #expect(!fixture.surface.becomeFirstResponder())
        for (key, code): (String, UInt16) in [("v", 9), ("c", 8), ("a", 0)] {
            #expect(!fixture.surface.performKeyEquivalent(with: try fixture.key(key, code: code)))
        }
        #expect(fixture.surface.keyDownCount == 0)
        #expect(fixture.window.firstResponder === editor)
    }

    @Test(arguments: ClipboardDestination.allCases)
    func commandPasteInsertsIntoActualModeField(destination: ClipboardDestination) async throws {
        let fixture = try ClipboardFixture()
        defer { fixture.close() }
        #expect(fixture.window.makeFirstResponder(fixture.surface))
        let hosting: NSView
        if destination == .board {
            fixture.present(.board)
            hosting = NSHostingView(rootView: HolyMannaBoardView(
                store: fixture.board, onDismiss: {}, onFocusPeer: { _ in false }
            ))
        } else {
            fixture.present(.archive)
            if destination == .tag { fixture.archive.annotationMode = .tag }
            if destination == .note { fixture.archive.annotationMode = .note }
            if destination == .research { fixture.archive.chatIsPresented = true }
            hosting = NSHostingView(rootView: HolyArchiveModeView(store: fixture.archive, onDismiss: {}))
        }
        try await fixture.mount(hosting)
        let field = try #require(descendants(hosting).compactMap { $0 as? NSTextField }
            .first { $0.placeholderString == destination.placeholder })
        #expect(fixture.window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        #expect(fixture.window.firstResponder === editor)
        editor.selectAll(nil)
        fixture.clipboard("clipboard-\(destination.rawValue)")
        // Use AppKit's event/menu/responder dispatch, including the production
        // window's performKeyEquivalent, rather than calling the editor's paste.
        NSApp.sendEvent(try fixture.key("v", code: 9))
        #expect(editor.string == "clipboard-\(destination.rawValue)")
        #expect(fixture.window.firstResponder === editor)
        #expect(fixture.surface.keyDownCount == 0)
        try await Task.sleep(for: .milliseconds(100))
        #expect(!fixture.surface.cachedActiveContents.get().contains("clipboard-"))
        switch destination {
        case .board: #expect(fixture.board.grep == editor.string)
        case .search: #expect(fixture.archive.query == editor.string)
        case .tag, .note: #expect(fixture.archive.annotationDraft == editor.string)
        case .research: #expect(fixture.archive.researchDraft == editor.string)
        }
    }

    @Test(arguments: HolyWorkspaceWindow.Mode.allCases)
    func dismissRestoresTerminalTypingAndPaste(mode: HolyWorkspaceWindow.Mode) async throws {
        let fixture = try ClipboardFixture()
        defer { fixture.close() }
        #expect(fixture.window.makeFirstResponder(fixture.surface))
        fixture.present(mode)
        fixture.dismiss(mode)
        try await eventually { fixture.window.firstResponder === fixture.surface }
        #expect(!fixture.window.modeOwnsKeyboard)
        #expect(fixture.surface.focused)
        NSApp.sendEvent(try fixture.key("x", code: 7, flags: []))
        fixture.clipboard("restored-paste")
        NSApp.sendEvent(try fixture.key("v", code: 9))
        try await eventually { fixture.surface.cachedActiveContents.get().contains("xrestored-paste") }
        #expect(fixture.surface.keyDownCount > 0)
    }

    @Test func switchingModesNeverRestoresTerminalBetweenThem() async throws {
        let fixture = try ClipboardFixture()
        defer { fixture.close() }
        #expect(fixture.window.makeFirstResponder(fixture.surface))
        fixture.present(.board)
        fixture.dismiss(.board)
        fixture.present(.archive)
        try await Task.sleep(for: .milliseconds(150))
        #expect(fixture.window.modeOwnsKeyboard)
        #expect(fixture.window.firstResponder !== fixture.surface)
        #expect(!fixture.window.makeFirstResponder(fixture.surface))
        // Duplicate dismissals must not disturb an editor in the other mode.
        fixture.dismiss(.board)
        #expect(fixture.window.modeOwnsKeyboard)
    }

    @Test(arguments: HolyWorkspaceWindow.Mode.allCases)
    func selectedModeTextCopiesExcerptThroughPasteboard(mode: HolyWorkspaceWindow.Mode) async throws {
        let fixture = try ClipboardFixture()
        defer { fixture.close() }
        fixture.present(mode)
        let hosting: NSView
        if mode == .archive {
            let message = HolyArchiveMessage(
                id: "fixture-message", sessionID: "fixture-session", role: .assistant,
                content: "before clipboard excerpt after", timestamp: nil, sequence: 0
            )
            hosting = NSHostingView(rootView: HolyArchiveTranscriptMessageView(index: 1, message: message, find: ""))
        } else {
            try await eventually { fixture.board.selectedItem != nil }
            hosting = NSHostingView(rootView: HolyMannaBoardView(
                store: fixture.board, onDismiss: {}, onFocusPeer: { _ in false }
            ))
        }
        try await fixture.mount(hosting)
        let text = try selectableEditor(containing: "clipboard excerpt", in: hosting, window: fixture.window)
        text.setSelectedRange((text.string as NSString).range(of: "clipboard excerpt"))
        fixture.clipboard("unchanged sentinel")
        NSApp.sendEvent(try fixture.key("c", code: 8))
        #expect(NSPasteboard.general.string(forType: .string) == "clipboard excerpt")
        #expect(fixture.surface.keyDownCount == 0)

        let destination = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        fixture.window.contentView?.addSubview(destination)
        #expect(fixture.window.makeFirstResponder(destination))
        NSApp.sendEvent(try fixture.key("v", code: 9))
        #expect(destination.string == "clipboard excerpt")
    }

    @Test func unhandledBoardCopyUsesSelectedIDAndTitleOnlyInBoard() async throws {
        let fixture = try ClipboardFixture()
        defer { fixture.close() }
        fixture.present(.board)
        try await eventually { fixture.board.selectedItem != nil }
        #expect(fixture.board.selectedRowCopyText == "mn-123456 Clipboard fixture")
        #expect(fixture.window.makeFirstResponder(nil))
        NSApp.sendEvent(try fixture.key("c", code: 8))
        #expect(NSPasteboard.general.string(forType: .string) == fixture.board.selectedRowCopyText)

        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        text.string = "read-only text"
        text.isEditable = false
        fixture.window.contentView?.addSubview(text)
        #expect(fixture.window.makeFirstResponder(text))
        text.setSelectedRange(NSRange(location: 0, length: 0))
        fixture.clipboard("empty selection sentinel")
        NSApp.sendEvent(try fixture.key("c", code: 8))
        #expect(NSPasteboard.general.string(forType: .string) == fixture.board.selectedRowCopyText)

        // An empty selection in an editable field must retain normal Copy
        // semantics rather than replacing the clipboard with a ledger row.
        text.isEditable = true
        fixture.clipboard("editor sentinel")
        NSApp.sendEvent(try fixture.key("c", code: 8))
        #expect(NSPasteboard.general.string(forType: .string) == "editor sentinel")

        fixture.dismiss(.board)
        fixture.present(.archive)
        fixture.clipboard("archive sentinel")
        let copy = NSMenuItem(title: "Copy", action: #selector(HolyWorkspaceWindow.copy(_:)), keyEquivalent: "c")
        #expect(!fixture.window.validateMenuItem(copy))
        fixture.window.copy(nil)
        #expect(NSPasteboard.general.string(forType: .string) == "archive sentinel")
    }

    @Test func archiveEditingKeepsLettersAndCommandClipboardKeys() throws {
        let fixture = try ClipboardFixture()
        defer { fixture.close() }
        fixture.present(.archive)
        fixture.archive.chatIsPresented = true
        #expect(!fixture.archive.handleKeyEquivalent(try fixture.key("z", code: 6, flags: []), textInputActive: true))
        #expect(!fixture.archive.chatIsFullscreen)
        for (key, code): (String, UInt16) in [("c", 8), ("v", 9), ("a", 0)] {
            #expect(!fixture.archive.handleKeyEquivalent(try fixture.key(key, code: code), textInputActive: true))
        }
        #expect(fixture.archive.handleKeyEquivalent(try fixture.key("z", code: 6, flags: []), textInputActive: false))
        #expect(fixture.archive.chatIsFullscreen)
    }

    @Test func archiveTranscriptAndResumeCopyVerbsRemainAvailable() async throws {
        let fixture = try ClipboardFixture()
        defer { fixture.close() }
        try fixture.seedArchive()
        fixture.present(.archive)
        try await eventually { fixture.archive.sessions.count == 1 }
        fixture.archive.selectParent("fixture-session")
        #expect(fixture.archive.handleKeyEquivalent(try fixture.key("\r", code: 36, flags: []), textInputActive: false))
        #expect(NSPasteboard.general.string(forType: .string) == "codex resume fixture-session")
        fixture.archive.showTranscript()
        try await eventually { fixture.archive.transcript.count == 1 }
        for key in ["y", "a"] {
            #expect(fixture.archive.handleKeyEquivalent(try fixture.key(key, code: 0, flags: []), textInputActive: false))
            #expect(NSPasteboard.general.string(forType: .string) == "[Assistant]\nbefore clipboard excerpt after")
        }
        #expect(fixture.archive.handleKeyEquivalent(try fixture.key("c", code: 8, flags: []), textInputActive: false))
        #expect(NSPasteboard.general.string(forType: .string) == "before clipboard excerpt after")
    }
}

enum ClipboardDestination: String, CaseIterable {
    case board, search, tag, note, research

    var placeholder: String {
        switch self {
        case .board: "ask AI · grep · ⌘K"
        case .search: "search · / · harness: project: after: before: #tag:"
        case .tag: HolyArchiveAnnotationMode.tag.placeholder
        case .note: HolyArchiveAnnotationMode.note.placeholder
        case .research: "ask the archive researcher"
        }
    }
}

@MainActor
private final class ClipboardFixture {
    let config: TemporaryConfig
    let ghostty: Ghostty.App
    let surface: ClipboardSurface
    let window: HolyWorkspaceWindow
    let board: HolyMannaBoardModeStore
    let archive: HolyArchiveModeStore
    private let directory: URL
    private let savedClipboard: [[NSPasteboard.PasteboardType: Data]]

    init() throws {
        savedClipboard = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
        config = try TemporaryConfig("command = /bin/cat\nshell-integration = none\n")
        ghostty = Ghostty.App(configPath: config.temporaryFile.path)
        surface = ClipboardSurface(try #require(ghostty.app))
        _ = try #require(surface.surface)
        directory = config.temporaryFile.deletingPathExtension().appendingPathExtension("clipboard-fixture")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let window = HolyWorkspaceWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1480, height: 900),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        self.window = window
        window.isReleasedWhenClosed = false
        let client = HolyMannaBoardClient(identityStore: .init(fileURL: directory.appendingPathComponent("actor.json"))) { _, _ in
            .init(stdout: clipboardBoardJSON, stderr: "", exitCode: 0)
        }
        board = HolyMannaBoardModeStore(
            client: client, prewarmer: ClipboardPrewarmer(),
            presentationChanged: { [weak window] in window?.setMode(.board, presented: $0) }
        )
        archive = HolyArchiveModeStore(
            registry: .init(providers: []), databaseURL: directory.appendingPathComponent("archive.sqlite3"),
            resumeHandler: { _ in false },
            presentationChanged: { [weak window] in window?.setMode(.archive, presented: $0) }
        )
        window.terminalResponder = { [weak surface] in surface }
        window.boardCopyText = { [weak board] in board?.selectedRowCopyText }
        window.contentView?.addSubview(surface)
        window.makeKeyAndOrderFront(nil)
    }

    func present(_ mode: HolyWorkspaceWindow.Mode) {
        switch mode {
        case .board: board.present(context: .init(boardRoot: directory.path, remoteHost: nil))
        case .archive: archive.present()
        }
    }

    func dismiss(_ mode: HolyWorkspaceWindow.Mode) {
        switch mode {
        case .board: board.dismiss()
        case .archive: archive.dismiss()
        }
    }

    func mount(_ view: NSView) async throws {
        view.frame = window.contentView!.bounds
        window.contentView?.addSubview(view)
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        view.layoutSubtreeIfNeeded()
    }

    func clipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func seedArchive() throws {
        let repository = try HolyArchiveRepository(databaseURL: directory.appendingPathComponent("archive.sqlite3"))
        let date = Date(timeIntervalSince1970: 1_790_116_200)
        let session = HolyArchiveSession(
            id: "fixture-session", harness: .codex, rawPath: "/fixture", projectPath: "/fixture", projectName: "fixture",
            title: "Clipboard fixture", firstPrompt: "fixture", lastPrompt: "fixture", lastResponse: "fixture",
            createdAt: date, modifiedAt: date, isChild: false, childType: nil, parentID: nil, model: nil,
            toolCalls: [], tokensUsed: nil, summary: nil, contentHash: "fixture", extra: [:],
            resumeCommand: "codex resume fixture-session", messageCount: 1, turnCount: 1,
            fileMTime: date, indexedAt: date, autoTags: []
        )
        let message = HolyArchiveMessage(
            id: "fixture-message", sessionID: session.id, role: .assistant,
            content: "before clipboard excerpt after", timestamp: date, sequence: 0
        )
        try repository.replace(session: session, messages: [message], chunks: [])
    }

    func key(_ characters: String, code: UInt16, flags: NSEvent.ModifierFlags = .command) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: code
        ))
    }

    func close() {
        window.terminalResponder = nil
        board.dismiss()
        archive.dismiss()
        window.contentView = nil
        window.close()
        NSPasteboard.general.clearContents()
        let items = savedClipboard.map { representations in
            let item = NSPasteboardItem()
            for (type, data) in representations { item.setData(data, forType: type) }
            return item
        }
        NSPasteboard.general.writeObjects(items)
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class ClipboardSurface: Ghostty.SurfaceView {
    var keyDownCount = 0

    override func keyDown(with event: NSEvent) {
        keyDownCount += 1
        super.keyDown(with: event)
    }
}

@MainActor private func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(descendants)
}

@MainActor private func selectableEditor(containing value: String, in view: NSView, window: NSWindow) throws -> NSTextView {
    let views = descendants(view)
    if let text = views.compactMap({ $0 as? NSTextView }).first(where: { $0.isSelectable && $0.string.contains(value) }) {
        #expect(window.makeFirstResponder(text))
        return text
    }
    // AppKit may back selectable SwiftUI Text with a label and the window's
    // shared field editor rather than a permanently mounted NSTextView.
    let field = try #require(views.compactMap { $0 as? NSTextField }
        .first { $0.isSelectable && $0.stringValue.contains(value) })
    #expect(window.makeFirstResponder(field))
    field.selectText(nil)
    return try #require(field.currentEditor() as? NSTextView)
}

@MainActor private func eventually(_ predicate: () -> Bool) async throws {
    for _ in 0..<200 {
        if predicate() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    try #require(predicate(), "Clipboard responder operation did not settle")
}

private struct ClipboardPrewarmer: HolyMannaBoardPrewarming {
    func enqueueFocused(_ payload: HolyMannaStatePayload, context: HolyMannaBoardContext,
                        allowGeneration: Bool, usageGuardReason: String?, sink: @escaping HolyMannaWarmSink) async {}
    func enqueueEstate(_ payload: HolyMannaEstatePayload, baseContext: HolyMannaBoardContext,
                       focusedRoot: String?, allowGeneration: Bool, usageGuardReason: String?, sink: @escaping HolyMannaWarmSink) async {}
    func waitUntilIdle() async {}
}

private let clipboardBoardJSON = """
{
  "success": true, "generated_at": "2026-09-22T23:00:00Z", "name": "clipboard-fixture", "root": "/fixture",
  "total": 1, "counts": {}, "status_counts": {},
  "now": [{"id": "mn-123456", "title": "[P1] Clipboard fixture", "title_plain": "Clipboard fixture",
    "description": "before clipboard excerpt after", "status": "in_progress", "effective": "active",
    "kind": "item", "decision": false, "blocked_by": [], "blockers": [], "dependents": [], "commits": []}],
  "next": [], "waves": [], "dreams": [], "decisions": [], "tracks": [], "peers": [], "attention": {},
  "coord": {"claims": [], "contention": [], "needs": [], "drops": []},
  "drift": {"present": false, "count": 0, "kinds": {}, "findings": []},
  "git": {"dirty_paths": 0, "is_repo": true}, "board": {"order_count": 0}
}
"""
