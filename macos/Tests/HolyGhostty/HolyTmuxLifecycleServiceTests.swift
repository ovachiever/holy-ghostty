import Foundation
import Testing
@testable import Ghostty

private let tmuxAvailableForLifecycleServiceTests: Bool = {
    runLifecycleTestShell("command -v tmux >/dev/null 2>&1") == 0
}()

@discardableResult
private func runLifecycleTestShell(_ script: String) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-lc", script]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    process.environment = HolyTmuxLifecycleService.scrubbedTmuxEnvironment(
        ProcessInfo.processInfo.environment
    )
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    } catch {
        return -1
    }
}

/// A disposable tmux server namespace for destructive lifecycle tests. Every
/// test runs on its own isolated `-L` socket so nothing here can ever touch
/// the default server or the managed `holy` server.
private struct IsolatedTmuxServer {
    let socketName: String

    init() {
        let suffix = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .prefix(10)
            .lowercased()
        socketName = "holy-lifecycle-svc-\(suffix)"
    }

    func createSession(_ sessionName: String) -> Bool {
        runLifecycleTestShell("tmux -L \(socketName) new-session -d -s \(sessionName)") == 0
    }

    // The exact target must be single-quoted: an unquoted leading `=` is
    // zsh equals-expansion and errors out before tmux ever runs.
    func hasSession(_ sessionName: String) -> Bool {
        runLifecycleTestShell("tmux -L \(socketName) has-session -t '=\(sessionName)' >/dev/null 2>&1") == 0
    }

    func killSessionOutOfBand(_ sessionName: String) {
        runLifecycleTestShell("tmux -L \(socketName) kill-session -t '=\(sessionName)' >/dev/null 2>&1 || true")
    }

    func destroy() {
        runLifecycleTestShell("tmux -L \(socketName) kill-server >/dev/null 2>&1 || true")
    }

    func identity(for sessionName: String) throws -> HolyTmuxLiveIdentity {
        try #require(HolyTmuxLiveIdentity(
            transport: .local,
            socketName: socketName,
            sessionName: sessionName
        ))
    }
}

// The reusable verified-kill primitive. The roster kill flow, the Hosts
// panel, and the crash-restore engine all depend on these three verbs:
// verify an exact identity is live, kill exactly that identity, and poll
// until absence is proven by inventory.
struct HolyTmuxLifecycleServiceTests {
    // MARK: - Failure anatomy (no tmux required)

    @Test func failureMessageExposesStageSocketTargetStderrAndUnderlying() {
        let failure = HolyTmuxLifecycleFailure(
            stage: .kill,
            socketName: "holy",
            target: "=demo",
            stderr: "can't find window: 3",
            underlyingDescription: "NSCocoaErrorDomain code 3584"
        )

        #expect(failure.message.contains("stage: kill"))
        #expect(failure.message.contains("socket: holy"))
        #expect(failure.message.contains("target: =demo"))
        #expect(failure.message.contains("can't find window: 3"))
        #expect(failure.message.contains("NSCocoaErrorDomain code 3584"))
    }

    @Test func failureMessageNamesTheDefaultSocketExplicitly() {
        let failure = HolyTmuxLifecycleFailure(
            stage: .verify,
            socketName: nil,
            target: "=demo",
            stderr: nil,
            underlyingDescription: nil
        )

        #expect(failure.message.contains("socket: default"))
        #expect(failure.message.contains("still reported the session"))
    }

    @Test func stageMarkerIsSplitFromTmuxStderr() {
        let (stage, detail) = HolyTmuxLifecycleCommand.parseStage(
            fromStderr: "HOLY_TMUX_STAGE:kill\nserver exited unexpectedly\n"
        )

        #expect(stage == .kill)
        #expect(detail == "server exited unexpectedly")
    }

    @Test func stderrWithoutMarkerYieldsNoStage() {
        let (stage, detail) = HolyTmuxLifecycleCommand.parseStage(
            fromStderr: "ssh: connect to host example port 22: Connection refused"
        )

        #expect(stage == nil)
        #expect(detail?.contains("Connection refused") == true)
    }

    // Cocoa 3584 was the field failure: an unmapped Foundation launch error
    // rendered as "(Cocoa error 3584.)" with every diagnostic coordinate
    // destroyed. The detailed rendering must preserve domain, code, and the
    // errno name for POSIX failures.
    @Test func detailedLaunchErrorPreservesDomainCodeAndErrno() {
        let cocoa = holyDetailedProcessLaunchErrorDescription(
            NSError(domain: NSCocoaErrorDomain, code: 3584)
        )
        #expect(cocoa.contains("NSCocoaErrorDomain code 3584"))
        #expect(cocoa.contains("executable not loadable"))

        let posix = holyDetailedProcessLaunchErrorDescription(
            NSError(domain: NSPOSIXErrorDomain, code: 35)
        )
        #expect(posix.contains("NSPOSIXErrorDomain code 35"))
        #expect(posix.contains("Resource temporarily unavailable"))
    }

    @Test func remoteKillCommandTargetsExactIdentityOverSSH() throws {
        let identity = try #require(HolyTmuxLiveIdentity(
            transport: .init(kind: .ssh, hostLabel: "Remote", sshDestination: "erik@example-host"),
            socketName: "holy",
            sessionName: "demo"
        ))
        let command = HolyTmuxLifecycleCommand.killCommand(for: identity)

        #expect(command.isRemote)
        #expect(command.executablePath == "/usr/bin/env")
        #expect(command.arguments.contains("erik@example-host"))
        let script = command.arguments.last ?? ""
        #expect(script.contains("kill-session"))
        #expect(script.contains("=demo"))
        #expect(script.contains("-L"))
    }

    // MARK: - Live integration on isolated sockets

    @Test(.enabled(if: tmuxAvailableForLifecycleServiceTests))
    func killVerifiedKillsLiveSessionAndInventoryProvesAbsence() async throws {
        let server = IsolatedTmuxServer()
        defer { server.destroy() }
        let sessionName = "victim-\(UUID().uuidString.prefix(8).lowercased())"
        #expect(server.createSession(sessionName))

        let result = await HolyTmuxLifecycleService.killVerified(
            try server.identity(for: sessionName)
        )

        #expect(result == .success(.killed))
        #expect(!server.hasSession(sessionName))
    }

    @Test(.enabled(if: tmuxAvailableForLifecycleServiceTests))
    func killVerifiedOnRunningServerWithMissingSessionIsAlreadyAbsentAndTouchesNothingElse() async throws {
        let server = IsolatedTmuxServer()
        defer { server.destroy() }
        let bystander = "bystander-\(UUID().uuidString.prefix(8).lowercased())"
        #expect(server.createSession(bystander))

        let result = await HolyTmuxLifecycleService.killVerified(
            try server.identity(for: "never-created-session")
        )

        #expect(result == .success(.alreadyAbsent))
        // Exactness proof: the kill of a missing name must not disturb any
        // other session on the same server.
        #expect(server.hasSession(bystander))
    }

    @Test(.enabled(if: tmuxAvailableForLifecycleServiceTests))
    func killVerifiedOnDeadServerSocketIsAlreadyAbsent() async throws {
        let server = IsolatedTmuxServer()

        let result = await HolyTmuxLifecycleService.killVerified(
            try server.identity(for: "ghost-session")
        )

        #expect(result == .success(.alreadyAbsent))
    }

    @Test(.enabled(if: tmuxAvailableForLifecycleServiceTests))
    func verifyLiveIdentityReportsPresenceThenAbsence() async throws {
        let server = IsolatedTmuxServer()
        defer { server.destroy() }
        let sessionName = "probe-\(UUID().uuidString.prefix(8).lowercased())"
        #expect(server.createSession(sessionName))
        let identity = try server.identity(for: sessionName)

        let before = await HolyTmuxLifecycleService.verifyLiveIdentity(identity)
        #expect(before == .present)

        server.killSessionOutOfBand(sessionName)

        let after = await HolyTmuxLifecycleService.verifyLiveIdentity(identity)
        #expect(after == .absent)
    }

    @Test(.enabled(if: tmuxAvailableForLifecycleServiceTests))
    func pollUntilAbsentProvesAbsenceAfterOutOfBandKill() async throws {
        let server = IsolatedTmuxServer()
        defer { server.destroy() }
        let sessionName = "poll-\(UUID().uuidString.prefix(8).lowercased())"
        #expect(server.createSession(sessionName))
        let identity = try server.identity(for: sessionName)

        server.killSessionOutOfBand(sessionName)
        let liveness = await HolyTmuxLifecycleService.pollUntilAbsent(identity, timeout: 5)

        #expect(liveness == .absent)
    }
}
