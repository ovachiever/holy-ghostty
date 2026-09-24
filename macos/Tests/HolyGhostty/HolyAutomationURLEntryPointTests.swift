import AppKit
import Carbon
import Foundation
import Testing
@testable import Ghostty

/// App-hosted. Drives the two doors macOS uses for the URL scheme,
/// `application(_:open:)` and the kAEGetURL Apple Event handler, through the
/// live AppDelegate. Every seam is recorded; the shipped-default cases leave
/// the real launch path in place and prove it was never reached (mn-e9f9a9).
@MainActor
@Suite(.serialized)
struct HolyAutomationURLEntryPointTests {
    enum Door: CaseIterable, Sendable, CustomTestStringConvertible {
        case applicationOpen
        case appleEvent

        var testDescription: String {
            switch self {
            case .applicationOpen: "application(_:open:)"
            case .appleEvent: "Apple Event kAEGetURL"
            }
        }
    }

    private static let fullPolicy = HolyAutomationURLGate.Policy(allowSpawnURL: true, allowSpawnURLCommands: true)

    @Test(arguments: Door.allCases)
    func shippedDefaultRefusesAHostileSpawnAndCreatesNothing(door: Door) async throws {
        let delegate = try #require(NSApp.delegate as? AppDelegate)
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-spawn-gate-\(UUID().uuidString).pwned")
        defer { try? FileManager.default.removeItem(at: marker) }
        let url = try hostileURL(touching: marker)

        // The launch seam stays nil on purpose: the real createAutomatedHolySession
        // path is live, and the assertions below prove it was never reached.
        let seams = Seams(policy: .shippedDefault)
        let restore = delegate.holyAutomationURLHooks
        delegate.holyAutomationURLHooks = seams.hooks(interceptLaunch: false)
        defer { delegate.holyAutomationURLHooks = restore }

        let sessionsBefore = liveSessionIDs()
        let tmuxBefore = holyTmuxSessionNames()

        deliver(url, through: door, to: delegate)
        try await eventually { seams.entries.count == 1 }

        let entry = try #require(seams.entries.first)
        #expect(entry.verdict == .refused)
        #expect(entry.detail == HolyAutomationURLGate.Refusal.spawnURLsDisabled.reason)
        #expect(entry.url == url)
        #expect(entry.line.contains(url.absoluteString))
        #expect(seams.entries.count == 1, "exactly one log line")
        #expect(seams.confirmations.isEmpty, "no sheet")
        #expect(liveSessionIDs() == sessionsBefore, "no session row")
        #expect(holyTmuxSessionNames() == tmuxBefore, "no tmux session")
        #expect(!FileManager.default.fileExists(atPath: marker.path), "nothing ran")
    }

    @Test(arguments: Door.allCases)
    func preferenceOnPresentsTheSheetAndCreatesNothingUntilConfirmed(door: Door) async throws {
        let delegate = try #require(NSApp.delegate as? AppDelegate)
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-spawn-gate-\(UUID().uuidString).pwned")
        defer { try? FileManager.default.removeItem(at: marker) }
        let url = try hostileURL(touching: marker)

        let seams = Seams(policy: Self.fullPolicy)
        let restore = delegate.holyAutomationURLHooks
        delegate.holyAutomationURLHooks = seams.hooks(interceptLaunch: true)
        defer { delegate.holyAutomationURLHooks = restore }
        let sessionsBefore = liveSessionIDs()

        deliver(url, through: door, to: delegate)
        try await eventually { seams.confirmations.count == 1 }

        #expect(seams.launches.isEmpty, "nothing launched before the click")
        #expect(liveSessionIDs() == sessionsBefore)
        #expect(seams.entries.map(\.verdict) == [.prompted])
        #expect(seams.entries.first?.line.contains(url.absoluteString) == true)
        let pending = try #require(seams.confirmations.first)
        #expect(pending.request.url == url)
        #expect(pending.request.launchSpec.command == "touch \(marker.path)")
        #expect(pending.request.carriesCommand)

        // The sheet the app would show for exactly this request: Cancel owns Return.
        let alert = HolyAutomationSpawnConfirmation.makeAlert(for: pending.request, origin: pending.origin)
        #expect(alert.buttons[0].title == HolyAutomationSpawnConfirmation.cancelTitle)
        #expect(alert.buttons[0].keyEquivalent == "\r")
        #expect(alert.buttons[1].keyEquivalent == "")

        pending.complete(false)
        #expect(seams.launches.isEmpty, "Cancel launches nothing")
        #expect(seams.entries.map(\.verdict) == [.prompted, .cancelled])

        deliver(url, through: door, to: delegate)
        try await eventually { seams.confirmations.count == 2 }
        #expect(seams.launches.isEmpty)
        seams.confirmations[1].complete(true)
        #expect(seams.launches.count == 1, "the click is what launches")
        #expect(seams.launches.first?.command == "touch \(marker.path)")
        #expect(seams.entries.map(\.verdict) == [.prompted, .cancelled, .prompted, .confirmed])
        #expect(seams.entries.allSatisfy { $0.line.contains(url.absoluteString) })
        #expect(liveSessionIDs() == sessionsBefore, "the intercepted launch created no real session")
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test(arguments: Door.allCases)
    func boardRouteStillNavigatesWithoutTouchingTheGate(door: Door) async throws {
        let delegate = try #require(NSApp.delegate as? AppDelegate)
        let url = try #require(URL(string: "holy-ghostty://board?item=mn-abcdef"))

        let seams = Seams(policy: .shippedDefault)
        let restore = delegate.holyAutomationURLHooks
        delegate.holyAutomationURLHooks = seams.hooks(interceptLaunch: true)
        defer { delegate.holyAutomationURLHooks = restore }

        // The route opens the board on the preferred workspace, creating one
        // when none exists; a fresh workspace restores its persisted roster,
        // which is not a spawn. Take the row snapshot once that workspace is
        // showing, so the comparison below sees only what the route adds.
        let workspace = HolyWorkspaceWindowController.preferred ?? delegate.automationWorkspaceController()
        workspace.showAndActivate()
        try await eventually { HolyWorkspaceWindowController.preferred === workspace }
        let sessionsBefore = liveSessionIDs()

        deliver(url, through: door, to: delegate)
        try await eventually { workspace.boardModeStore.isPresented }
        defer { workspace.boardModeStore.dismiss() }

        #expect(workspace.boardModeStore.surface == .board)
        #expect(seams.entries.isEmpty, "navigation writes no spawn audit line")
        #expect(seams.confirmations.isEmpty)
        #expect(seams.launches.isEmpty)
        #expect(liveSessionIDs() == sessionsBefore)
    }

    @Test(arguments: Door.allCases, HolyAutomationHostileShape.all)
    func hostileShapeNeverReachesAShellThroughEitherDoor(door: Door, shape: HolyAutomationHostileShape) async throws {
        let delegate = try #require(NSApp.delegate as? AppDelegate)
        let url = try #require(URL(string: shape.url), "\(shape.url) is not a URL")

        // Worst case for the app: the user allowed everything.
        let seams = Seams(policy: Self.fullPolicy)
        let restore = delegate.holyAutomationURLHooks
        delegate.holyAutomationURLHooks = seams.hooks(interceptLaunch: true)
        defer { delegate.holyAutomationURLHooks = restore }
        let sessionsBefore = liveSessionIDs()

        deliver(url, through: door, to: delegate)
        try await eventually { seams.entries.count == 1 }

        let entry = try #require(seams.entries.first)
        #expect(entry.url == url)
        #expect(entry.line.contains(url.absoluteString))
        #expect(seams.launches.isEmpty, "\(shape.name): nothing launched")
        #expect(liveSessionIDs() == sessionsBefore, "\(shape.name): no session row")
        switch shape.underFullPolicy {
        case .refused:
            #expect(entry.verdict == .refused, "\(shape.name)")
            #expect(entry.detail.hasPrefix("malformed spawn URL:"), "\(shape.name): \(entry.detail)")
            #expect(seams.confirmations.isEmpty, "\(shape.name): no sheet for a malformed URL")
        case .confirmSpawn:
            #expect(entry.verdict == .prompted, "\(shape.name)")
            #expect(seams.confirmations.count == 1, "\(shape.name): the sheet is the only way forward")
            seams.confirmations.first?.complete(false)
            #expect(seams.launches.isEmpty)
        }
    }

    // MARK: - Doors

    private func deliver(_ url: URL, through door: Door, to delegate: AppDelegate) {
        switch door {
        case .applicationOpen:
            delegate.application(NSApp, open: [url])
        case .appleEvent:
            let event = NSAppleEventDescriptor(
                eventClass: AEEventClass(kInternetEventClass),
                eventID: AEEventID(kAEGetURL),
                targetDescriptor: nil,
                returnID: AEReturnID(kAutoGenerateReturnID),
                transactionID: AETransactionID(kAnyTransactionID)
            )
            event.setParam(NSAppleEventDescriptor(string: url.absoluteString), forKeyword: keyDirectObject)
            delegate.handleGetURLEvent(event, withReplyEvent: NSAppleEventDescriptor.null())
        }
    }

    private func hostileURL(touching marker: URL) throws -> URL {
        let encodedPath = try #require(marker.path.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
        return try #require(URL(string: "holy-ghostty://spawn?command=touch%20\(encodedPath)&runtime=shell"))
    }

    // MARK: - Ground truth

    private func liveSessionIDs() -> Set<UUID> {
        Set(HolyWorkspaceWindowController.all.flatMap { $0.workspaceStore.sessions.map(\.id) })
    }

    /// Session names on Holy's managed tmux server, read the way the app's own
    /// scripts do (scrubbed TMUX environment, login shell). An absent server or
    /// binary reads as no sessions, on both sides of the comparison.
    private func holyTmuxSessionNames() -> Set<String> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            "-lc",
            "unset TMUX TMUX_PANE TMUX_TMPDIR; tmux -L \(HolySessionTmuxSpec.defaultSocketName)"
                + " list-sessions -F '#S' 2>/dev/null; true",
        ]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return []
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(bytes: data, encoding: .utf8) ?? ""
        return Set(text.split(separator: "\n").map(String.init).filter { !$0.isEmpty })
    }
}

/// Records what the delegate asked of each seam. The launch seam is only
/// installed when a test wants the real path intercepted.
@MainActor
private final class Seams {
    struct Confirmation {
        let request: HolyAutomationSpawnRequest
        let origin: HolyAutomationURLOrigin?
        let complete: @MainActor @Sendable (Bool) -> Void
    }

    var policy: HolyAutomationURLGate.Policy
    private(set) var entries: [HolyAutomationURLAuditEntry] = []
    private(set) var confirmations: [Confirmation] = []
    private(set) var launches: [HolySessionLaunchSpec] = []

    init(policy: HolyAutomationURLGate.Policy) {
        self.policy = policy
    }

    func hooks(interceptLaunch: Bool) -> HolyAutomationURLHooks {
        var hooks = HolyAutomationURLHooks()
        hooks.policy = { [unowned self] in self.policy }
        hooks.audit = { [unowned self] entry in self.entries.append(entry) }
        hooks.confirm = { [unowned self] request, origin, completion in
            self.confirmations.append(.init(request: request, origin: origin, complete: completion))
        }
        if interceptLaunch {
            hooks.launch = { [unowned self] spec in
                self.launches.append(spec)
                return nil
            }
        }
        return hooks
    }
}

/// The repo's settle helper (HolyMannaBoardActionsTests.swift), copied because
/// it is file-private there.
@MainActor private func eventually(_ predicate: () -> Bool) async throws {
    for _ in 0..<200 {
        if predicate() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    try #require(predicate(), "Synthetic operation did not settle")
}
