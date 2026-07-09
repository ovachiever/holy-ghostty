import Testing
@testable import Ghostty

struct HolyTmuxCommandFlagTests {
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
        #expect(command?.arguments == ["-lc", "'tmux' '-L' 'holy' 'kill-session' '-t' 'demo'"])
    }

    @MainActor
    @Test func localTmuxSessionIsEligibleForReattach() {
        var launchSpec = HolySessionLaunchSpec.interactiveTmuxShell()
        launchSpec.tmux = .init(socketName: "holy", sessionName: "demo", createIfMissing: true)

        #expect(HolyWorkspaceStore.canReattachLaunchSpecForTesting(launchSpec))
        #expect(!HolyWorkspaceStore.canReattachLaunchSpecForTesting(.interactiveShell()))
    }
}
