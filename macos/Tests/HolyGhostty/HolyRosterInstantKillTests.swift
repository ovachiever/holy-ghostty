import AppKit
import SwiftUI
import Testing
@testable import Ghostty

/// App-hosted: compile in the no-launch lane, execute at coordinated acceptance.
/// Store fixtures use disposable sleeping terminals and absent, unique tmux
/// sockets. Transport construction tests do not connect to any SSH host.
@MainActor
@Suite(.serialized)
struct HolyRosterInstantKillTests {
    @Test func indicatorsSwapOnlyWithCommandOverRosterAndRestoreOnRelease() async {
        let hosting = NSHostingView(rootView: indicator(command: false, hover: true))
        hosting.frame = NSRect(x: 0, y: 0, width: 18, height: 18)
        for (command, hover, expected) in [
            (false, true, false), (true, false, false), (true, true, true),
            (false, true, false), (true, true, true), (true, false, false),
        ] {
            hosting.rootView = indicator(command: command, hover: hover)
            hosting.layoutSubtreeIfNeeded()
            await Task.yield()
            #expect(!killButtons(in: hosting).isEmpty == expected)
            #expect(hosting.frame.size == NSSize(width: 18, height: 18))
        }
    }

    @Test func commandClickKillsWithoutSelectingVictimOrPresentingSheet() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let victim = try fixture.add("Alpha")
        let selected = try fixture.add("Beta")
        let button = HolyRosterKillButtonView()
        button.onKill = { fixture.store.killSessionFromRoster(victim) }
        fixture.window.contentView?.addSubview(button)
        let responder = fixture.window.firstResponder

        button.mouseDown(with: try mouseEvent(in: fixture.window, flags: .command))

        #expect(!fixture.store.sessions.contains { $0.id == victim.id })
        #expect(fixture.store.selectedSessionID == selected.id)
        #expect(fixture.window.firstResponder === responder)
        #expect(fixture.window.attachedSheet == nil)
        #expect(fixture.store.tmuxSessionTerminationError == nil)
        #expect(fixture.store.archivedSessions.contains { $0.sourceSessionID == victim.id })
    }

    @Test func staleXAfterCommandReleaseAndDisabledXNeverKill() throws {
        let window = NSWindow()
        defer { window.close() }
        let button = HolyRosterKillButtonView()
        var kills = 0
        button.onKill = { kills += 1 }
        button.mouseDown(with: try mouseEvent(in: window, flags: []))
        #expect(kills == 0)
        button.isEnabled = false
        button.mouseDown(with: try mouseEvent(in: window, flags: .command))
        #expect(kills == 0)
    }

    @Test(arguments: HolyRosterLayout.allCases)
    func commandDeleteChainsInDisplayedOrder(layout: HolyRosterLayout) throws {
        let previousLayout = UserDefaults.standard.object(forKey: HolyRosterLayout.defaultsKey)
        UserDefaults.standard.set(layout.rawValue, forKey: HolyRosterLayout.defaultsKey)
        defer { UserDefaults.standard.set(previousLayout, forKey: HolyRosterLayout.defaultsKey) }
        let fixture = try Fixture()
        defer { fixture.close() }
        // Creation order deliberately disagrees with the rendered order.
        _ = try fixture.add("Charlie")
        _ = try fixture.add("Alpha", pinned: true)
        _ = try fixture.add("Bravo", pinned: true)
        let ordered = HolyRosterSections(store: fixture.store, layout: layout).sections.flatMap(\.sessions)
        let ids = ordered.map(\.id)
        #expect(ids.count == 3)
        fixture.store.selectSession(ids[1])

        #expect(fixture.controller.handleWorkspaceKeyEquivalent(try deleteEvent(in: fixture.window)))
        #expect(fixture.store.selectedSessionID == ids[2])
        #expect(fixture.window.attachedSheet == nil)
        #expect(fixture.controller.handleWorkspaceKeyEquivalent(try deleteEvent(in: fixture.window)))
        #expect(fixture.store.selectedSessionID == ids[0])
        #expect(fixture.controller.handleWorkspaceKeyEquivalent(try deleteEvent(in: fixture.window)))
        #expect(fixture.store.sessions.isEmpty)
        #expect(fixture.store.selectedSessionID == nil)
        #expect(fixture.store.archivedSessions.count == 3)
    }

    @Test func commandDeletePreservesTextEditingAndIgnoresKeyRepeat() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        _ = try fixture.add("Alpha")
        let field = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 24))
        fixture.window.contentView?.addSubview(field)
        #expect(fixture.window.makeFirstResponder(field))
        #expect(!fixture.controller.handleWorkspaceKeyEquivalent(try deleteEvent(in: fixture.window)))
        #expect(fixture.store.sessions.count == 1)
        fixture.window.makeFirstResponder(nil)
        #expect(fixture.controller.handleWorkspaceKeyEquivalent(try deleteEvent(in: fixture.window, repeatKey: true)))
        #expect(fixture.store.sessions.count == 1)
        #expect(!fixture.controller.handleWorkspaceKeyEquivalent(try deleteEvent(in: fixture.window, flags: [])))
        #expect(fixture.store.sessions.count == 1)
    }

    @Test func pendingAdoptedKillDeduplicatesAndFailureStaysInlineThenRetries() async throws {
        var identities: [HolyTmuxLiveIdentity] = []
        var fail = true
        let fixture = try Fixture { identity in
            identities.append(identity)
            if fail {
                return .failure(.init(
                    stage: .connect, socketName: identity.socketName, target: "=\(identity.sessionName)",
                    stderr: "Transport unavailable", underlyingDescription: nil
                ))
            }
            return .success(.alreadyAbsent)
        }
        defer { fixture.close() }
        let session = try fixture.add("Adopted", tmux: true)
        fixture.store.killSessionFromRoster(session)
        fixture.store.killSessionFromRoster(session)
        #expect(fixture.store.pendingRosterKills.contains(session.id))
        await waitForKills(in: fixture.store)
        #expect(identities.count == 1)
        #expect(identities.first?.sessionName == session.record.launchSpec.tmux?.sessionName)
        #expect(identities.first?.socketName == session.record.launchSpec.tmux?.socketName)
        #expect(fixture.store.sessions.count == 1)
        #expect(fixture.store.selectedSessionID == session.id)
        #expect(fixture.store.rosterKillErrors[session.id]?.contains("Transport unavailable") == true)
        #expect(fixture.store.tmuxSessionTerminationError == nil)
        #expect(fixture.window.attachedSheet == nil)

        fail = false
        fixture.store.killSessionFromRoster(session)
        #expect(fixture.store.rosterKillErrors[session.id] == nil)
        await waitForKills(in: fixture.store)
        #expect(identities.count == 2)
        #expect(fixture.store.sessions.isEmpty)
        #expect(fixture.store.archivedSessions.count == 1)
    }

    @Test func remoteKillIdentityRetainsTransportAndExactTarget() throws {
        var spec = HolySessionLaunchSpec.interactiveTmuxShell(title: "Remote")
        spec.transport = .init(kind: .ssh, hostLabel: "Studio", sshDestination: "erik@example-host")
        spec.tmux = .init(socketName: "custom-socket", sessionName: "adopted-worker", createIfMissing: false)
        let identity = try #require(HolyTmuxLiveIdentity(exactLaunchSpec: spec))
        let command = HolyTmuxLifecycleCommand.killCommand(for: identity)
        #expect(command.isRemote)
        #expect(command.executablePath == "/bin/zsh")
        let script = command.arguments.last ?? ""
        #expect(script.contains("'/usr/bin/ssh'"))
        #expect(script.contains("'--' 'erik@example-host'"))
        #expect(script.contains("zsystem flock -e -t 0"))
        #expect(script.contains("=adopted-worker"))
        #expect(script.contains("custom-socket"))
    }

    @Test func remoteRowWithoutTmuxIdentityFailsInlineWithoutDetaching() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        // A malformed legacy spec must never turn remote kill into detach.
        var spec = HolySessionLaunchSpec.interactiveShell(title: "Incomplete remote")
        spec.transport = .init(kind: .ssh, hostLabel: "Studio", sshDestination: "erik@example-host")
        spec.command = "/bin/sleep 60"
        let session = try #require(fixture.store.createSession(with: spec))
        fixture.store.killSessionFromRoster(session)
        #expect(fixture.store.sessions.contains { $0.id == session.id })
        #expect(fixture.store.archivedSessions.isEmpty)
        #expect(fixture.store.rosterKillErrors[session.id]?.contains("identity is missing") == true)
        #expect(fixture.store.tmuxSessionTerminationError == nil)
        #expect(fixture.window.attachedSheet == nil)
    }

    @Test func windowResignAndModifierReleaseClearCommand() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.store.rosterCommandHeld = true
        fixture.controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
        #expect(!fixture.store.rosterCommandHeld)
        fixture.store.rosterCommandHeld = true
        let release = try #require(NSEvent.keyEvent(
            with: .flagsChanged, location: .zero, modifierFlags: [], timestamp: 1,
            windowNumber: fixture.window.windowNumber, context: nil, characters: "",
            charactersIgnoringModifiers: "", isARepeat: false, keyCode: 0x37
        ))
        fixture.controller.updateRosterModifiers(release)
        #expect(!fixture.store.rosterCommandHeld)
    }

    private func indicator(command: Bool, hover: Bool) -> HolyRosterIndicator {
        HolyRosterIndicator(
            attention: .init(kind: .inactive, symbolName: "circle.fill", title: "Inactive", detail: nil,
                             isProminent: false, becameAvailableAt: nil),
            commandHeld: command, pointerInRoster: hover, killPending: false,
            sessionTitle: "Fixture", onKill: {}
        )
    }

    private func killButtons(in view: NSView) -> [HolyRosterKillButtonView] {
        if let button = view as? HolyRosterKillButtonView { return [button] }
        return view.subviews.flatMap { killButtons(in: $0) }
    }

    private func mouseEvent(in window: NSWindow, flags: NSEvent.ModifierFlags) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: flags, timestamp: 1,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        ))
    }

    private func deleteEvent(
        in window: NSWindow, flags: NSEvent.ModifierFlags = .command, repeatKey: Bool = false
    ) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 1,
            windowNumber: window.windowNumber, context: nil, characters: "\u{7f}",
            charactersIgnoringModifiers: "\u{7f}", isARepeat: repeatKey, keyCode: 51
        ))
    }

    private func waitForKills(in store: HolyWorkspaceStore) async {
        for _ in 0..<100 where !store.pendingRosterKills.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.pendingRosterKills.isEmpty)
    }
}

@MainActor
private final class Fixture {
    let config: TemporaryConfig
    let ghostty: Ghostty.App
    let store: HolyWorkspaceStore
    let controller: HolyWorkspaceWindowController
    let archiveURL: URL
    var window: NSWindow { controller.window! }

    init(
        killer: @escaping (HolyTmuxLiveIdentity) async -> Result<HolyTmuxKillOutcome, HolyTmuxLifecycleFailure> = { _ in
            .success(.killed)
        }
    ) throws {
        config = try TemporaryConfig("command = /bin/sleep 60\nshell-integration = none\n")
        ghostty = Ghostty.App(configPath: config.temporaryFile.path)
        _ = try #require(ghostty.app)
        let supervisor = HolySessionSupervisor(ghostty: ghostty, seedDefaultSession: false, saveWorkspace: { _, _, _, _ in })
        store = HolyWorkspaceStore(sessionSupervisor: supervisor, tmuxSessionKiller: killer)
        archiveURL = config.temporaryFile.deletingPathExtension().appendingPathExtension("sqlite3")
        controller = HolyWorkspaceWindowController(
            ghostty: ghostty, seedDefaultSession: false, workspaceStore: store, archiveDatabaseURL: archiveURL
        )
    }

    func add(_ title: String, pinned: Bool = false, tmux: Bool = false) throws -> HolySession {
        var spec = HolySessionLaunchSpec.interactiveShell(title: title)
        spec.command = "/bin/sleep 60"
        spec.isFocused = pinned
        if tmux {
            spec.tmux = .init(
                socketName: "holy-roster-test-\(UUID().uuidString.lowercased())",
                sessionName: "adopted-fixture", createIfMissing: false
            )
        }
        return try #require(store.createSession(with: spec))
    }

    func close() {
        store.detachAllSessions()
        window.close()
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: archiveURL.path + suffix)
        }
    }
}
