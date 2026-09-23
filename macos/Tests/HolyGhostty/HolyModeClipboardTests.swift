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
        defer { fixture.tearDown() }
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
        defer { fixture.tearDown() }
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
        // Establish the field/editor/binding path independently of the host's
        // activation and key-equivalent dispatch. A key failure must not erase
        // this control result or get repaired by a direct-paste fallback.
        let directText = "direct-clipboard-\(destination.rawValue)"
        editor.selectAll(nil)
        fixture.clipboard(directText)
        editor.paste(nil)
        let directPasteSucceeded = editor.string == directText
        print("Clipboard direct paste control: destination=\(destination.rawValue), succeeded=\(directPasteSucceeded), firstResponderIsEditor=\(fixture.window.firstResponder === editor)")
        #expect(directPasteSucceeded, "Direct paste: failed for \(destination.rawValue)")
        fixture.expectDraft(directText, at: destination)
        editor.selectAll(nil)
        editor.insertText("", replacementRange: editor.selectedRange())
        #expect(editor.string.isEmpty)
        fixture.expectDraft("", at: destination)

        fixture.clipboard("clipboard-\(destination.rawValue)")
        // Use AppKit's event/menu/responder dispatch, including the production
        // window and the host's real menu. Do not install a test-only paste menu.
        let pasteItem = try #require(menuItem(for: #selector(NSText.paste(_:)), in: NSApp.mainMenu))
        #expect(pasteItem.keyEquivalent == "v")
        #expect(pasteItem.keyEquivalentModifierMask == .command)
        try await fixture.sendKey("v", code: 9)
        let pasteTargetsEditor = NSApp.target(forAction: #selector(NSText.paste(_:)), to: nil, from: pasteItem) as? NSTextView === editor
        #expect(editor.string == "clipboard-\(destination.rawValue)",
                "Command-V: directPasteSucceeded=\(directPasteSucceeded), active=\(NSApp.isActive), keyWindow=\(fixture.window.isKeyWindow), firstResponderIsEditor=\(fixture.window.firstResponder === editor), pasteTargetsEditor=\(pasteTargetsEditor)")
        #expect(fixture.window.firstResponder === editor)
        #expect(fixture.surface.keyDownCount == 0)
        #expect(fixture.surface.handledKeyEquivalentCount == 0)
        try await Task.sleep(for: .milliseconds(100))
        #expect(!fixture.surface.cachedActiveContents.get().contains("clipboard-"))
        fixture.expectDraft("clipboard-\(destination.rawValue)", at: destination)
    }

    @Test(arguments: HolyWorkspaceWindow.Mode.allCases)
    func dismissRestoresTerminalTypingAndPaste(mode: HolyWorkspaceWindow.Mode) async throws {
        let fixture = try ClipboardFixture()
        defer { fixture.tearDown() }
        #expect(fixture.window.makeFirstResponder(fixture.surface))
        fixture.present(mode)
        fixture.dismiss(mode)
        try await eventually { fixture.window.firstResponder === fixture.surface }
        #expect(!fixture.window.modeOwnsKeyboard)
        #expect(fixture.surface.focused)
        try await fixture.sendKey("x", code: 7, flags: [])
        fixture.clipboard("restored-paste")
        try await fixture.sendKey("v", code: 9)
        try await eventually { fixture.surface.cachedActiveContents.get().contains("xrestored-paste") }
        #expect(fixture.surface.keyDownCount > 0)
    }

    @Test func switchingModesNeverRestoresTerminalBetweenThem() async throws {
        let fixture = try ClipboardFixture()
        defer { fixture.tearDown() }
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

    @Test func fixtureTeardownDrainsSurfaceAndKeepsHostReusable() async throws {
        weak var retiredSurface: ClipboardSurface?
        weak var retiredUserdata: Ghostty.SurfaceUserdata?
        let retainedWindow = try autoreleasepool {
            let fixture = try ClipboardFixture()
            defer { fixture.tearDown() }
            fixture.present(.board)
            retiredSurface = fixture.surface
            retiredUserdata = fixture.surface.callbackUserdata
            return fixture.window
        }
        // The weak userdata disappears only after the queued C-surface free.
        // Reaching the next fixture also proves teardown did not quit the host.
        try await eventually { retiredSurface == nil && retiredUserdata == nil }
        #expect(!retainedWindow.isVisible)
        #expect(!retainedWindow.modeOwnsKeyboard)
        #expect(NSApp.windows.contains { $0 === retainedWindow })

        let next = try ClipboardFixture()
        defer { next.tearDown() }
        #expect(next.window === retainedWindow)
        #expect(next.window.makeFirstResponder(next.surface))
        #expect(next.surface.surface != nil)
    }

    @Test(arguments: HolyWorkspaceWindow.Mode.allCases)
    func selectedModeTextCopiesExcerptThroughPasteboard(mode: HolyWorkspaceWindow.Mode) async throws {
        let fixture = try ClipboardFixture()
        defer { fixture.tearDown() }
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
        try await fixture.sendKey("c", code: 8)
        #expect(NSPasteboard.general.string(forType: .string) == "clipboard excerpt")
        #expect(fixture.surface.keyDownCount == 0)

        let destination = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        fixture.window.contentView?.addSubview(destination)
        #expect(fixture.window.makeFirstResponder(destination))
        try await fixture.sendKey("v", code: 9)
        #expect(destination.string == "clipboard excerpt")
    }

    @Test func unhandledBoardCopyUsesSelectedIDAndTitleOnlyInBoard() async throws {
        let fixture = try ClipboardFixture()
        defer { fixture.tearDown() }
        fixture.present(.board)
        try await eventually { fixture.board.selectedItem != nil }
        #expect(fixture.board.selectedRowCopyText == "mn-123456 Clipboard fixture")
        #expect(fixture.window.makeFirstResponder(nil))
        try await fixture.sendKey("c", code: 8)
        #expect(NSPasteboard.general.string(forType: .string) == fixture.board.selectedRowCopyText)

        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        text.string = "read-only text"
        text.isEditable = false
        fixture.window.contentView?.addSubview(text)
        #expect(fixture.window.makeFirstResponder(text))
        text.setSelectedRange(NSRange(location: 0, length: 0))
        fixture.clipboard("empty selection sentinel")
        try await fixture.sendKey("c", code: 8)
        #expect(NSPasteboard.general.string(forType: .string) == fixture.board.selectedRowCopyText)

        // An empty selection in an editable field must retain normal Copy
        // semantics rather than replacing the clipboard with a ledger row.
        text.isEditable = true
        fixture.clipboard("editor sentinel")
        try await fixture.sendKey("c", code: 8)
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
        defer { fixture.tearDown() }
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
        defer { fixture.tearDown() }
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
private final class ClipboardTestHost {
    static let shared = Result { try ClipboardTestHost() }

    let config: TemporaryConfig
    let ghostty: Ghostty.App
    let window: HolyWorkspaceWindow

    private init() throws {
        // The focused-run receipt reports CVDisplayLink's zero active displays,
        // followed by error.OutOfMemory. Clipboard tests need real terminal IO,
        // not display-synchronized rendering. This is a supported core setting.
        config = try TemporaryConfig("""
        command = direct:/bin/cat
        shell-integration = none
        window-vsync = false
        """)
        ghostty = Ghostty.App(configPath: config.temporaryFile.path)
        _ = try #require(ghostty.app)
        window = HolyWorkspaceWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1480, height: 900),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isExcludedFromWindowsMenu = true
        window.tabbingMode = .disallowed
    }
}

@MainActor
private final class ClipboardFixture {
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
        let host = try ClipboardTestHost.shared.get()
        surface = ClipboardSurface(try #require(host.ghostty.app))
        _ = try #require(surface.surface, "Clipboard surface creation failed with window-vsync=false; inspect the core initialization error")
        directory = host.config.temporaryFile.deletingLastPathComponent()
            .appendingPathComponent("clipboard-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let window = host.window
        self.window = window
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 1480, height: 900))
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
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
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

    func expectDraft(_ expected: String, at destination: ClipboardDestination) {
        switch destination {
        case .board: #expect(board.grep == expected)
        case .search: #expect(archive.query == expected)
        case .tag, .note: #expect(archive.annotationDraft == expected)
        case .research: #expect(archive.researchDraft == expected)
        }
    }

    func sendKey(_ characters: String, code: UInt16, flags: NSEvent.ModifierFlags = .command) async throws {
        // NSApplication.sendEvent does not model keyboard input into an inactive
        // app. Fail at that host prerequisite instead of blaming an empty field.
        // Keep the production event/menu path once the host owns keyboard focus.
        for _ in 0..<200 {
            if NSApp.isActive, NSApp.keyWindow === window, NSApp.mainWindow === window { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(NSApp.isActive && NSApp.keyWindow === window && NSApp.mainWindow === window,
                     "Clipboard keyboard host unavailable: active=\(NSApp.isActive), keyWindow=\(window.isKeyWindow), mainWindow=\(window.isMainWindow). Direct paste control is independent; execute keyboard acceptance in an active GUI host.")
        NSApp.sendEvent(try key(characters, code: code, flags: flags))
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

    func tearDown() {
        window.terminalResponder = nil
        window.boardCopyText = nil
        board.dismiss()
        archive.dismiss()
        _ = window.makeFirstResponder(nil)
        window.contentView = nil
        // Reuse a retained, empty window instead of closing the test host's last
        // window and invoking Holy's normal auto-quit policy. Keep its core app
        // alive too: Surface.deinit queues ghostty_surface_free on the main actor.
        window.orderOut(nil)
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
    var handledKeyEquivalentCount = 0

    override func keyDown(with event: NSEvent) {
        keyDownCount += 1
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let handled = super.performKeyEquivalent(with: event)
        if handled { handledKeyEquivalentCount += 1 }
        return handled
    }
}

@MainActor private func menuItem(for action: Selector, in menu: NSMenu?) -> NSMenuItem? {
    for item in menu?.items ?? [] {
        if item.action == action { return item }
        if let found = menuItem(for: action, in: item.submenu) { return found }
    }
    return nil
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
