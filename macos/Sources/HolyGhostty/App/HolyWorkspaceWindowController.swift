import AppKit
import SwiftUI

@MainActor
private final class HolyWorkspaceWindow: NSWindow {
    weak var holyWorkspaceController: HolyWorkspaceWindowController?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if holyWorkspaceController?.handleWorkspaceKeyEquivalent(event) == true {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func performClose(_ sender: Any?) {
        if holyWorkspaceController?.closeSelectedSessionIfAvailable() == true {
            return
        }

        super.performClose(sender)
    }
}

@MainActor
final class HolyWorkspaceWindowController: NSWindowController, NSWindowDelegate {
    let workspaceStore: HolyWorkspaceStore

    init(
        ghostty: Ghostty.App,
        initialConfig: Ghostty.SurfaceConfiguration? = nil,
        seedDefaultSession: Bool? = nil
    ) {
        let resolvedSeedDefaultSession = seedDefaultSession ?? (initialConfig == nil)
        self.workspaceStore = HolyWorkspaceStore(
            ghostty: ghostty,
            seedDefaultSession: resolvedSeedDefaultSession
        )

        let window = HolyWorkspaceWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1580, height: 980),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.minSize = NSSize(width: 920, height: 620)
        window.title = "Holy Ghostty"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovable = true
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary, .managed]
        window.setFrameAutosaveName("HolyGhosttyWorkspaceWindow")

        let hostingController = NSHostingController(
            rootView: HolyWorkspaceRootView(store: workspaceStore)
                .environmentObject(ghostty)
        )
        window.contentViewController = hostingController

        super.init(window: window)
        window.holyWorkspaceController = self
        window.delegate = self

        if let initialConfig {
            _ = createSession(from: initialConfig)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showAndActivate() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if let selected = workspaceStore.selectedSession {
            Ghostty.moveFocus(to: selected.surfaceView)
        }
    }

    @discardableResult
    func createSession(from baseConfig: Ghostty.SurfaceConfiguration? = nil) -> HolySession? {
        let session = workspaceStore.createSession(from: baseConfig)
        if let session {
            workspaceStore.selectSession(session.id)
            showAndActivate()
        }
        return session
    }

    @discardableResult
    func createSession(
        with launchSpec: HolySessionLaunchSpec,
        origin: HolySessionEventOrigin = .directLaunch
    ) -> HolySession? {
        let session = workspaceStore.createSession(with: launchSpec, origin: origin)
        if let session {
            workspaceStore.selectSession(session.id)
            showAndActivate()
        }
        return session
    }

    func duplicateSelectedSession() {
        guard let selected = workspaceStore.selectedSession else { return }
        workspaceStore.duplicate(selected)
    }

    func closeSelectedSession() {
        closeSelectedSessionIfAvailable()
    }

    @discardableResult
    func closeSelectedSessionIfAvailable() -> Bool {
        guard let selected = workspaceStore.selectedSession else { return false }
        workspaceStore.close(selected)
        return true
    }

    @discardableResult
    func killSelectedTmuxSessionIfAvailable() -> Bool {
        guard let selected = workspaceStore.selectedSession,
              workspaceStore.canKillTmuxSession(selected) else {
            return false
        }

        workspaceStore.killTmuxSession(selected)
        return true
    }

    func handleWorkspaceKeyEquivalent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

        let relevantFlags = event.modifierFlags.intersection([.command, .option, .control, .shift])

        if key == "w", relevantFlags == .command {
            return closeSelectedSessionIfAvailable()
        }

        if key == "q", relevantFlags == .option {
            return killSelectedTmuxSessionIfAvailable()
        }

        return false
    }

    func focus(surfaceView: Ghostty.SurfaceView) {
        workspaceStore.selectSession(surfaceView.id)
        showAndActivate()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let selected = workspaceStore.selectedSession else { return }
        Ghostty.moveFocus(to: selected.surfaceView)
    }

    func findSurface(id: UUID) -> Ghostty.SurfaceView? {
        workspaceStore.sessions.first(where: { $0.id == id })?.surfaceView
    }

    var allSurfaceViews: [Ghostty.SurfaceView] {
        workspaceStore.sessions.map(\.surfaceView)
    }

    static var all: [HolyWorkspaceWindowController] {
        NSApp.windows.compactMap { $0.windowController as? HolyWorkspaceWindowController }
    }

    static var preferred: HolyWorkspaceWindowController? {
        all.first(where: { $0.window?.isMainWindow ?? false })
        ?? all.first(where: { $0.window?.isKeyWindow ?? false })
        ?? all.last
    }
}
