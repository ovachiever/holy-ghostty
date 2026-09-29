import Foundation
import Testing
@testable import Ghostty

private let tmuxAvailableForIdentityTests: Bool = {
    runIdentityDiscoveryTestShell("command -v tmux >/dev/null 2>&1") == 0
}()

private func runIdentityDiscoveryTestShell(_ script: String) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-lc", script]
    var environment = ProcessInfo.processInfo.environment
    environment.removeValue(forKey: "TMUX")
    environment.removeValue(forKey: "TMUX_PANE")
    environment.removeValue(forKey: "TMUX_TMPDIR")
    process.environment = environment
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    } catch {
        return -1
    }
}

private func localDiscoveryRow(_ name: String, runtime: String = "codex") -> String {
    [name, "0", "1", name, runtime, "", "/work/project", runtime, "", ""].joined(separator: "\u{1F}")
}

private actor LocalFleetDiscoveryProbe {
    // The reported failing fleet in mn-27d9fd is the acceptance denominator.
    let names = (1...55).map { "fleet-\($0)" }
    private(set) var censusCount = 0
    private(set) var inspected: [String] = []

    func reply(session: String?) -> HolyRemoteTmuxDiscoveryService.HostsTestReply {
        guard let session else {
            censusCount += 1
            return .output(names.map { localDiscoveryRow($0) }.joined(separator: "\n"))
        }
        inspected.append(session)
        return .output(localDiscoveryRow(session))
    }
}

// Regression coverage for the converge discovery wall-clock cap. A hung host
// (here a long `sleep`) must be terminated at the cap and reported as
// a typed timeout, so the converge sweep - and isConverging - can never wedge on
// a runaway discovery process. A fast process must complete normally within a
// generous cap.
struct HolyRemoteTmuxDiscoveryTimeoutTests {
    @Test func localFleetInspectsEachOf55CensusedSessionsIndependently() async throws {
        let probe = LocalFleetDiscoveryProbe()
        let sessions = try await HolyRemoteTmuxDiscoveryService.localDiscoveryForTesting(
            host: .init(sshDestination: "localhost", tmuxSocketName: "fixture")
        ) { _, session in
            await probe.reply(session: session)
        }
        let expected = probe.names
        #expect(sessions.count == expected.count)
        #expect(Set(sessions.map(\.sessionName)) == Set(expected))
        #expect(sessions.allSatisfy { $0.runtime == .codex && $0.workingDirectory == "/work/project" })
        #expect(await probe.censusCount == 1)
        #expect(Set(await probe.inspected) == Set(expected))
        #expect(await probe.inspected.count == expected.count)
    }

    @Test func localFleetKeepsSameNamedSessionsOnDistinctSockets() async throws {
        let sessions = try await HolyRemoteTmuxDiscoveryService.localDiscoveryForTesting(
            host: .init(sshDestination: "localhost")
        ) { _, _ in .output(localDiscoveryRow("same-name")) }
        #expect(sessions.count == 2)
        #expect(Set(sessions.map(\.id)).count == 2)
        #expect(Set(sessions.map { $0.tmuxSocketName ?? "default" }) == ["default", "holy"])
    }

    @Test(arguments: ["", localDiscoveryRow("wrong-session"), "malformed"])
    func missingMismatchedOrMalformedDetailsCannotAuthorizeReconciliation(detail: String) async {
        await #expect(throws: (any Error).self) {
            _ = try await HolyRemoteTmuxDiscoveryService.localDiscoveryForTesting(
                host: .init(sshDestination: "localhost", tmuxSocketName: "fixture")
            ) { _, session in
                .output(session == nil ? localDiscoveryRow("expected") : detail)
            }
        }
    }

    @Test func oneTimedOutInspectionFailsTheFleetClosed() async {
        await #expect(throws: (any Error).self) {
            _ = try await HolyRemoteTmuxDiscoveryService.localDiscoveryForTesting(
                host: .init(sshDestination: "localhost", tmuxSocketName: "fixture")
            ) { _, session in
                session == nil ? .output(localDiscoveryRow("expected")) : .timeout
            }
        }
    }

    @Test func largeStdoutAndStderrAreDrainedBeforeProcessExit() async throws {
        // A 1 MiB fixture on each pipe exercises backpressure independently
        // of session count and without reading any live tmux server.
        let byteCount = 1_048_576
        let result = try await HolyRemoteTmuxDiscoveryService.runLargeOutputForTesting(
            byteCount: byteCount,
            timeoutSeconds: 5
        )
        #expect(result.exitCode == 0)
        #expect(result.stdout.utf8.count == byteCount)
        #expect(result.stderr.utf8.count == byteCount)
    }

    @Test(.enabled(if: tmuxAvailableForIdentityTests))
    func localDiscoveryCompletesAtTheReported55SessionFleetSize() async throws {
        let socket = "holy-fleet-\(UUID().uuidString.lowercased())"
        defer {
            _ = runIdentityDiscoveryTestShell("""
            tmux -L \(socket) kill-server >/dev/null 2>&1 || true
            rm -f -- "/tmp/tmux-$(id -u)/\(socket)"
            """)
        }
        try #require(runIdentityDiscoveryTestShell("""
        for index in {1..55}; do
          tmux -L \(socket) new-session -d -s "fleet-$index" /bin/cat || exit $?
        done
        """) == 0)
        let sessions = try await HolyRemoteTmuxDiscoveryService.shared.discoverLocalSessionsThrowing(
            hostID: UUID(),
            hostLabel: "Fleet fixture",
            tmuxSocketName: socket,
            timeout: 5,
            includeHiddenSessions: true
        )
        #expect(sessions.count == 55)
        #expect(Set(sessions.map(\.sessionName)) == Set((1...55).map { "fleet-\($0)" }))
    }

    @Test func discoverySurfacesExplicitSSHInstanceSaturation() async {
        let message = await HolyRemoteTmuxDiscoveryService.friendlySSHErrorForTesting(
            destination: "studio",
            exitCode: 255,
            stderr: "kex_exchange_identification: read: Connection reset by peer"
        )

        #expect(message.contains("server instance limit is saturated"))
        #expect(!message.contains("could not reach"))
    }

    @Test func slowProcessIsCappedAndReportedAsUsefulTimeout() async {
        let start = Date()
        let error = await HolyRemoteTmuxDiscoveryService.runProcessWithTimeoutForTesting(
            sleepSeconds: 10,
            timeoutSeconds: 0.5
        )
        let elapsed = Date().timeIntervalSince(start)

        #expect(error?.contains("timed out after 0.5 seconds") == true)
        #expect(error?.contains("left untouched") == true)
        #expect(error?.contains("Cocoa") == false)
        // Proves the cap actually fired: we returned far sooner than the sleep.
        #expect(elapsed < 5)
    }

    @Test func fastProcessCompletesWithinCap() async {
        let error = await HolyRemoteTmuxDiscoveryService.runProcessWithTimeoutForTesting(
            sleepSeconds: 0,
            timeoutSeconds: 5
        )

        #expect(error == nil)
    }

    @Test func exitedParentWithInheritedPipeIsStillCapped() async {
        let start = Date()
        let error = await HolyRemoteTmuxDiscoveryService
            .runExitedParentWithInheritedPipeForTesting(
                childSleepSeconds: 2,
                timeoutSeconds: 0.2
            )
        let elapsed = Date().timeIntervalSince(start)

        #expect(error?.contains("timed out after 0.2 seconds") == true)
        #expect(elapsed < 1)
    }

    @Test func identityInventoryIsOneTmuxQueryWithoutProcessOrGitWalks() async {
        let script = await HolyRemoteTmuxDiscoveryService.identityDiscoveryScriptForTesting(
            socketName: "holy"
        )

        #expect(script.components(separatedBy: " list-sessions -F ").count == 2)
        #expect(script.contains("#{@holy_title}"))
        #expect(script.contains("#{@holy_runtime}"))
        #expect(script.contains("#{@holy_working_directory}"))
        #expect(!script.contains("show-options"))
        #expect(!script.contains("display-message"))
        #expect(!script.contains("pgrep"))
        #expect(!script.contains("ps -p"))
        #expect(!script.contains("git -C"))
    }

    @Test(.enabled(if: tmuxAvailableForIdentityTests))
    func identityInventoryReadsStableMetadataFromScratchServer() async throws {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let socketName = "holy-identity-\(suffix)"
        let sessionName = "verify-\(suffix)"
        let workingDirectory = "/tmp/holy-identity-\(suffix)"

        #expect(runIdentityDiscoveryTestShell("""
        tmux -L \(socketName) new-session -d -s \(sessionName) && \\
        tmux -L \(socketName) set-option -q -t \(sessionName) @holy_title $'identity-title\\nsecond\\x1fpart' && \\
        tmux -L \(socketName) set-option -q -t \(sessionName) @holy_runtime codex && \\
        tmux -L \(socketName) set-option -q -t \(sessionName) @holy_objective identity-objective && \\
        tmux -L \(socketName) set-option -q -t \(sessionName) @holy_working_directory \(workingDirectory) && \\
        tmux -L \(socketName) set-option -q -t \(sessionName) @holy_command codex && \\
        tmux -L \(socketName) set-option -q -t \(sessionName) @holy_task_title identity-task && \\
        tmux -L \(socketName) set-option -q -t \(sessionName) @holy_task_source identity-source
        """) == 0)
        defer {
            _ = runIdentityDiscoveryTestShell(
                "tmux -L \(socketName) kill-server >/dev/null 2>&1 || true"
            )
        }

        let sessions = try await HolyRemoteTmuxDiscoveryService.shared
            .discoverLocalIdentitySessionsThrowing(
                hostID: UUID(),
                hostLabel: "This Mac",
                tmuxSocketName: socketName,
                timeout: 2,
                includeHiddenSessions: true
            )
        let session = try #require(sessions.first)

        #expect(sessions.count == 1)
        #expect(session.sessionName == sessionName)
        #expect(session.tmuxSocketName == socketName)
        #expect(session.title == "identity-title second part")
        #expect(session.runtime == .codex)
        #expect(session.objective == "identity-objective")
        #expect(session.workingDirectory == workingDirectory)
        #expect(session.bootstrapCommand == "codex")
        #expect(session.taskTitle == "identity-task")
        #expect(session.taskSource == "identity-source")
    }
}
