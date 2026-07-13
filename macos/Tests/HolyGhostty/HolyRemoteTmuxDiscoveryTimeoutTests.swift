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

// Regression coverage for the converge discovery wall-clock cap. A hung host
// (here a long `sleep`) must be terminated at the cap and reported as
// a typed timeout, so the converge sweep - and isConverging - can never wedge on
// a runaway discovery process. A fast process must complete normally within a
// generous cap.
struct HolyRemoteTmuxDiscoveryTimeoutTests {
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
