import Foundation
import Testing
@testable import Ghostty

private let holyTmuxAvailableForLifecycleTests: Bool = {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-lc", "command -v tmux >/dev/null 2>&1"]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        return false
    }
}()

struct HolyTmuxCommandFlagTests {
    @Test func managedClaudeBootstrapClearsOwnedModelBeforeReturningToShell() throws {
        var launchSpec = HolySessionLaunchSpec.interactiveTmuxShell()
        launchSpec.runtime = .claude
        launchSpec.command = "claude"
        launchSpec.tmux = .init(
            socketName: "holy",
            sessionName: "claude-cleanup",
            createIfMissing: true
        )

        let script = try #require(HolyTmuxCommandBuilder.command(for: launchSpec))

        #expect(script.contains("claude"))
        #expect(script.contains("tmux if-shell -F"))
        #expect(script.contains("#{==:#{@holy_model_source},claude}"))
        #expect(script.contains("@holy_model_label"))
        #expect(script.contains("@holy_model_source"))
        #expect(script.contains("exec ${SHELL:-/bin/zsh} -l"))
    }

    // The long-lived attach ssh needs keepalives so post-sleep zombie panes
    // are detected in ~60s instead of never, and a bounded connect timeout
    // so reattach attempts fail fast instead of hanging on kernel TCP.
    @Test func remoteAttachWrapperCarriesKeepaliveFlags() {
        let wrapper = HolyTmuxCommandBuilder.remoteLaunchWrapperForTesting(
            destination: "erik@example-host",
            localScript: "exec tmux attach -t demo"
        )
        #expect(wrapper.contains("ServerAliveInterval=15"))
        #expect(wrapper.contains("ServerAliveCountMax=4"))
        #expect(wrapper.contains("TCPKeepAlive=no"))
        #expect(wrapper.contains("ConnectTimeout=8"))
        #expect(!wrapper.contains("BatchMode"))
    }

    // Detach commands are headless; without ConnectTimeout+BatchMode one
    // unreachable host stalls Sync for the full kernel TCP timeout per
    // session (the old minutes-long hang).
    @MainActor
    @Test func detachCommandFailsFast() {
        let arguments = HolyWorkspaceStore.detachCommandArgumentsForTesting(
            destination: "erik@example-host",
            socketName: "holy",
            sessionName: "demo"
        )
        #expect(arguments.contains("ConnectTimeout=5"))
        #expect(arguments.contains("BatchMode=yes"))
        #expect(arguments.first == "ssh")
    }

    // A Dock/Finder launch does not inherit Homebrew's bin directory. Local
    // termination must resolve tmux through the same login shell used by local
    // session launch instead of relying on the GUI process PATH.
    @MainActor
    @Test func localTerminationResolvesTmuxThroughLoginShell() {
        var launchSpec = HolySessionLaunchSpec.interactiveTmuxShell()
        launchSpec.tmux = .init(socketName: "holy", sessionName: "demo", createIfMissing: true)

        let command = HolyWorkspaceStore.terminationCommandForTesting(launchSpec: launchSpec)

        #expect(command?.executablePath == "/bin/zsh")
        let script = command?.arguments.last ?? ""
        #expect(script.contains("'tmux' '-L' 'holy' 'kill-session' '-t' '=demo'"))
        #expect(script.contains("if (( kill_status != 0 ))"))
        #expect(script.contains("while 'tmux' '-L' 'holy' 'has-session' '-t' '=demo'"))
        #expect(script.contains("tmux still reports the session after kill verification"))
    }

    @MainActor
    @Test func storedTerminationRefusesIncompleteIdentity() {
        var missingName = HolySessionLaunchSpec.interactiveTmuxShell()
        missingName.tmux = .init(socketName: "holy", sessionName: nil, createIfMissing: true)
        var missingSocket = HolySessionLaunchSpec.interactiveTmuxShell()
        missingSocket.tmux = .init(socketName: nil, sessionName: "demo", createIfMissing: true)

        #expect(HolyWorkspaceStore.terminationCommandForTesting(launchSpec: missingName) == nil)
        #expect(HolyWorkspaceStore.terminationCommandForTesting(launchSpec: missingSocket) == nil)
    }

    @MainActor
    @Test func discoveredDefaultSocketIdentityIsExplicitlyAllowed() {
        let command = HolyWorkspaceStore.discoveredTerminationCommandForTesting(
            transport: .local,
            socketName: nil,
            sessionName: "demo"
        )
        let script = command?.arguments.last ?? ""

        #expect(command?.executablePath == "/bin/zsh")
        #expect(script.contains("'tmux' 'kill-session' '-t' '=demo'"))
        #expect(!script.contains("'-L'"))
    }

    @MainActor
    @Test func terminationScrubsInheritedTmuxContext() {
        let environment = HolyWorkspaceStore.scrubbedTerminationEnvironmentForTesting([
            "PATH": "/usr/bin",
            "TMUX": "/tmp/tmux/default,1,0",
            "TMUX_PANE": "%1",
            "TMUX_TMPDIR": "/tmp/tmux",
        ])

        #expect(environment["PATH"] == "/usr/bin")
        #expect(environment["TMUX"] == nil)
        #expect(environment["TMUX_PANE"] == nil)
        #expect(environment["TMUX_TMPDIR"] == nil)
    }

    @MainActor
    @Test func localTmuxSessionIsEligibleForReattach() {
        var launchSpec = HolySessionLaunchSpec.interactiveTmuxShell()
        launchSpec.tmux = .init(socketName: "holy", sessionName: "demo", createIfMissing: true)

        #expect(HolyWorkspaceStore.canReattachLaunchSpecForTesting(launchSpec))
        #expect(!HolyWorkspaceStore.canReattachLaunchSpecForTesting(.interactiveShell()))
    }

    @MainActor
    @Test(.enabled(if: holyTmuxAvailableForLifecycleTests))
    func localTerminationKillsAndVerifiesLiveTmuxSession() throws {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let socketName = "holy-lifecycle-\(suffix)"
        let sessionName = "verify-\(suffix)"

        #expect(runLoginShell("tmux -L \(socketName) new-session -d -s \(sessionName)") == 0)
        defer {
            _ = runLoginShell("tmux -L \(socketName) kill-server >/dev/null 2>&1 || true")
        }

        let command = try #require(HolyWorkspaceStore.discoveredTerminationCommandForTesting(
            transport: .local,
            socketName: socketName,
            sessionName: sessionName
        ))
        #expect(run(executablePath: command.executablePath, arguments: command.arguments) == 0)
        #expect(runLoginShell("tmux -L \(socketName) has-session -t \(sessionName) >/dev/null 2>&1") != 0)
    }

    private func runLoginShell(_ script: String) -> Int32 {
        run(executablePath: "/bin/zsh", arguments: ["-lc", script])
    }

    private func run(executablePath: String, arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
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
}
