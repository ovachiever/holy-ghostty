import AppKit
import OSLog
import SwiftUI
import GhosttyKit

private enum HolyWorkspaceKeyCode {
    static let tab: UInt16 = 48
}

@MainActor
private final class HolyWorkspaceWindow: NSWindow {
    weak var holyWorkspaceController: HolyWorkspaceWindowController?

    /// mn-7afa94: ⌘P "has never worked" while its handler exists and is
    /// wired. Log every ⌘-key that reaches this override so a single press
    /// answers whether the event arrives at all and who consumed it.
    static let keyDebugLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mitchellh.ghostty",
        category: "HolyKeyDebug"
    )

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let handled = holyWorkspaceController?.handleWorkspaceKeyEquivalent(event) == true
        if event.modifierFlags.contains(.command) {
            Self.keyDebugLogger.error(
                "performKeyEquivalent key=\(event.charactersIgnoringModifiers ?? "?", privacy: .public) flags=\(event.modifierFlags.rawValue) handledByWorkspace=\(handled) controllerWired=\(self.holyWorkspaceController != nil)"
            )
        }
        if handled {
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
        Self.retain(self)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(ghosttyDidNewSplit(_:)),
            name: Ghostty.Notification.ghosttyNewSplit,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(holySystemDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        if let initialConfig {
            _ = createSession(from: initialConfig)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func holySystemDidWake(_ notification: Notification) {
        Task { @MainActor [weak self] in
            // Tailscale and Wi-Fi need a moment after wake before SSH works.
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            self?.workspaceStore.convergeOnSystemWake()
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

    func closeWorkspaceWindow() {
        close()
    }

    @discardableResult
    func closeSelectedSessionIfAvailable() -> Bool {
        guard let selected = workspaceStore.selectedSession else { return false }
        workspaceStore.close(selected)
        return true
    }

    func splitPaneRight(
        cloning baseConfig: Ghostty.SurfaceConfiguration? = nil,
        from sourceSessionID: UUID? = nil
    ) {
        workspaceStore.splitPaneRight(cloning: baseConfig, from: sourceSessionID)
    }

    func splitPaneDown(
        cloning baseConfig: Ghostty.SurfaceConfiguration? = nil,
        from sourceSessionID: UUID? = nil
    ) {
        workspaceStore.splitPaneDown(cloning: baseConfig, from: sourceSessionID)
    }

    func toggleCommandPalette() {
        workspaceStore.commandPaletteIsShowing.toggle()
    }

    @IBAction func toggleGhosttyFullScreen(_ sender: Any?) {
        window?.toggleFullScreen(sender)
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
        if handleSessionCycleKey(event) {
            return true
        }

        guard event.type == .keyDown,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

        let relevantFlags = event.modifierFlags.intersection([.command, .option, .control, .shift])

        if relevantFlags == .command,
           let slot = Int(key),
           (1...HolyPaneLayout.maxSlotCount).contains(slot) {
            workspaceStore.assignCurrentSessionToSlot(slot)
            return true
        }

        if key == "w", relevantFlags == .command {
            return closeSelectedSessionIfAvailable()
        }

        if key == "q", relevantFlags == .option {
            return killSelectedTmuxSessionIfAvailable()
        }

        // P for Panel — sits beside ⌘⇧P (palette) as the workspace P-family.
        if key == "p", relevantFlags == .command {
            workspaceStore.toggleInboxPanel()
            return true
        }

        return false
    }

    /// First-responder target of the View ▸ Inbox Panel menu item. The menu
    /// carries the same ⌘P equivalent for discoverability; the key itself is
    /// consumed by `handleWorkspaceKeyEquivalent` before menu dispatch, so
    /// both paths land on the same toggle.
    @objc func toggleInboxPanel(_ sender: Any?) {
        workspaceStore.toggleInboxPanel()
    }

    /// First-responder target of View ▸ Restore Sessions…. The durable
    /// entry to the crash-restore sheet: unlike the cold-boot banner it
    /// survives dismissal and relaunches, so a missed banner never strands
    /// the user. Enabled whenever any cold-boot archive exists, fresh or
    /// older (`validateMenuItem`).
    @objc func presentCrashRestore(_ sender: Any?) {
        workspaceStore.presentRestore()
    }

    func handleSessionCycleKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.keyCode == HolyWorkspaceKeyCode.tab else {
            return false
        }

        let relevantFlags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if relevantFlags.isEmpty {
            return workspaceStore.cycleSelectedSession(.next)
        }

        if relevantFlags == .shift {
            return workspaceStore.cycleSelectedSession(.previous)
        }

        return false
    }

    func focus(surfaceView: Ghostty.SurfaceView) {
        workspaceStore.selectSession(surfaceView.id)
        showAndActivate()
    }

    func noteSurfaceFocused(_ surfaceView: Ghostty.SurfaceView) {
        workspaceStore.selectSession(surfaceView.id)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let selected = workspaceStore.selectedSession else { return }
        Ghostty.moveFocus(to: selected.surfaceView)
    }

    func windowWillClose(_ notification: Notification) {
        Self.release(self)
    }

    func findSurface(id: UUID) -> Ghostty.SurfaceView? {
        workspaceStore.sessions.first(where: { $0.id == id })?.surfaceView
    }

    var allSurfaceViews: [Ghostty.SurfaceView] {
        workspaceStore.sessions.map(\.surfaceView)
    }

    @objc private func ghosttyDidNewSplit(_ notification: Notification) {
        guard let surfaceView = notification.object as? Ghostty.SurfaceView,
              let sourceSession = workspaceStore.sessions.first(where: { $0.surfaceView === surfaceView }) else {
            return
        }

        guard let directionAny = notification.userInfo?["direction"],
              let direction = directionAny as? ghostty_action_split_direction_e else {
            return
        }

        let config = notification.userInfo?[Ghostty.Notification.NewSurfaceConfigKey] as? Ghostty.SurfaceConfiguration
        switch direction {
        case GHOSTTY_SPLIT_DIRECTION_RIGHT, GHOSTTY_SPLIT_DIRECTION_LEFT:
            splitPaneRight(cloning: config, from: sourceSession.id)
        case GHOSTTY_SPLIT_DIRECTION_DOWN, GHOSTTY_SPLIT_DIRECTION_UP:
            splitPaneDown(cloning: config, from: sourceSession.id)
        default:
            return
        }
    }

    /// NSWindow.windowController is an ASSIGN property and nothing else held
    /// these controllers, so every instance deallocated moments after launch
    /// — silently killing the workspace key family (⌘P, ⌘W, ⌘1-9), both
    /// View-menu entries, and every `.preferred` lookup. Found via the
    /// mn-7afa94 instrumentation: `controllerWired=false` on every ⌘-key.
    /// The registry holds them for their window's lifetime.
    private static var strongRegistry: [HolyWorkspaceWindowController] = []

    static func retain(_ controller: HolyWorkspaceWindowController) {
        strongRegistry.append(controller)
    }

    static func release(_ controller: HolyWorkspaceWindowController) {
        strongRegistry.removeAll { $0 === controller }
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

// MARK: NSMenuItemValidation

extension HolyWorkspaceWindowController: NSMenuItemValidation {
    /// Menu auto-enablement would light every item whose action a responder
    /// implements; Restore Sessions… must instead track whether there is
    /// anything to restore. Every other item keeps the default behavior.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(presentCrashRestore(_:)) {
            return !workspaceStore.crashRestoreBatch.isEmpty
        }
        return true
    }
}
