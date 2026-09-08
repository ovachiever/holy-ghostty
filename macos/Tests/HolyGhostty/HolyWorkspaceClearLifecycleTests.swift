import AppKit
import GhosttyKit
import Testing
@testable import Ghostty

/// App-hosted: compile during a no-launch lane, execute only in the coordinated
/// synthetic acceptance run. No default/holy tmux server or live roster is used.
@MainActor
@Suite(.serialized)
struct HolyWorkspaceClearLifecycleTests {
    @Test func queuedMouseShapeAfterViewReleaseDoesNotDereferenceFreedView() async throws {
        let config = try TemporaryConfig("command = /bin/sleep 60\nshell-integration = none\n")
        let ghostty = Ghostty.App(configPath: config.temporaryFile.path)
        let app = try #require(ghostty.app)

        // Keep only the C-surface owner. This deterministically opens the same
        // lifetime gap as Clear, without relying on main-queue scheduling luck.
        weak var callbackUserdata: Ghostty.SurfaceUserdata?
        var model: Ghostty.Surface? = try autoreleasepool {
            let view = Ghostty.SurfaceView(app)
            let surface = try #require(view.surface)
            let userdata = ghostty_surface_userdata(surface)
            callbackUserdata = view.callbackUserdata
            #expect(Ghostty.App.surfaceUserdata(from: userdata) === view)
            return view.surfaceModel
        }
        let surface = try #require(model?.unsafeCValue)
        #expect(Ghostty.App.surfaceUserdata(from: ghostty_surface_userdata(surface)) == nil)

        var target = ghostty_target_s()
        target.tag = GHOSTTY_TARGET_SURFACE
        target.target.surface = surface
        var action = ghostty_action_s()
        action.tag = GHOSTTY_ACTION_MOUSE_SHAPE
        action.action.mouse_shape = GHOSTTY_MOUSE_SHAPE_DEFAULT
        let handled = Ghostty.App.action(app, target: target, action: action)
        #expect(handled)
        Ghostty.App.closeSurface(ghostty_surface_userdata(surface), processAlive: false)
        #expect(Ghostty.App.surfaceUserdata(from: nil) == nil)

        model = nil
        // Let the real deferred destructor finish while its app is still alive.
        for _ in 0..<100 where callbackUserdata != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(callbackUserdata == nil)
        withExtendedLifetime(ghostty) {}
    }

    @Test(arguments: [false, true])
    func clearPopulatedStorePreservesKeyWorkspaceAndEmptyPane(quitAfterLastWindow: Bool) async throws {
        let config = try TemporaryConfig("""
        command = /bin/sleep 60
        shell-integration = none
        quit-after-last-window-closed = \(quitAfterLastWindow)
        """)
        let ghostty = Ghostty.App(configPath: config.temporaryFile.path)
        _ = try #require(ghostty.app)
        var savedSnapshot: HolyWorkspaceSnapshot?
        let supervisor = HolySessionSupervisor(
            ghostty: ghostty,
            seedDefaultSession: false,
            saveWorkspace: { snapshot, _, _, _ in savedSnapshot = snapshot }
        )
        let store = HolyWorkspaceStore(sessionSupervisor: supervisor)
        let archiveURL = config.temporaryFile.deletingPathExtension().appendingPathExtension("sqlite3")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: archiveURL.path + suffix)
            }
        }
        let controller = HolyWorkspaceWindowController(
            ghostty: ghostty,
            seedDefaultSession: false,
            workspaceStore: store,
            archiveDatabaseURL: archiveURL
        )
        let window = try #require(controller.window)
        defer { window.close() }
        window.makeKeyAndOrderFront(nil)
        var spec = HolySessionLaunchSpec.interactiveShell(title: "Synthetic Clear regression")
        spec.command = "/bin/sleep 60"
        spec.workingDirectory = config.temporaryFile.deletingLastPathComponent().path
        for _ in 0..<3 {
            let created = autoreleasepool { store.createSession(with: spec) != nil }
            #expect(created)
        }
        let originalIDs = Set(store.sessions.map(\.id))
        #expect(originalIDs.count == 3)

        store.detachAllSessions()
        for _ in 0..<10 { await Task.yield() }
        #expect(store.sessions.isEmpty)
        #expect(store.selectedSession == nil)
        #expect(store.visiblePaneSessions.isEmpty)
        #expect(Set(store.archivedSessions.map(\.sourceSessionID)) == originalIDs)
        #expect(savedSnapshot?.sessions.isEmpty == true)
        #expect(window.isVisible)
        #expect(window.isKeyWindow)
        #expect(window.contentViewController != nil)
        #expect(HolyWorkspaceWindowController.all.contains { $0 === controller })
        #expect(!AppDelegate.shouldAutomaticallyQuitAfterLastWindowClosed(configured: quitAfterLastWindow))

        // Clear is idempotent and the surviving workspace still accepts sessions.
        store.detachAllSessions()
        let created = store.createSession(with: spec) != nil
        #expect(created)
        #expect(store.sessions.count == 1)
        #expect(window.isKeyWindow)
        store.detachAllSessions()
        for _ in 0..<10 { await Task.yield() }
        withExtendedLifetime(ghostty) {}
    }
}
