import AppKit
import SwiftUI

@MainActor
final class HolyWorkspaceWindowController: NSWindowController, NSWindowDelegate {
    let workspaceStore: HolyWorkspaceStore

    init(ghostty: Ghostty.App, initialConfig: Ghostty.SurfaceConfiguration? = nil) {
        self.workspaceStore = HolyWorkspaceStore(
            ghostty: ghostty,
            seedDefaultSession: initialConfig == nil
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1580, height: 980),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.minSize = NSSize(width: 920, height: 620)
        window.title = "Holy Ghostty"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("HolyGhosttyWorkspaceWindow")

        let hostingController = NSHostingController(
            rootView: HolyWorkspaceRootView(store: workspaceStore)
                .environmentObject(ghostty)
        )
        window.contentViewController = hostingController

        super.init(window: window)
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
            workspaceStore.selectedSessionID = session.id
            showAndActivate()
        }
        return session
    }

    func duplicateSelectedSession() {
        guard let selected = workspaceStore.selectedSession else { return }
        workspaceStore.duplicate(selected)
    }

    func closeSelectedSession() {
        guard let selected = workspaceStore.selectedSession else { return }
        workspaceStore.close(selected)
    }

    func focus(surfaceView: Ghostty.SurfaceView) {
        workspaceStore.selectedSessionID = surfaceView.id
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
