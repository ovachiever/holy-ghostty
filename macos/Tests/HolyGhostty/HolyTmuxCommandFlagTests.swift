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
}
