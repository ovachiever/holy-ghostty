import Testing
@testable import Ghostty

@MainActor
struct HolySessionLiveStatusTests {
    // While OpenCode is generating it shows an interrupt hint ("esc interrupt")
    // in its footer. That phrasing lacks the "to" used by Claude/Codex, so it
    // must be recognized as a live working signal or active sessions show no
    // throbber at all.
    @Test func openCodeWorkingFooterIsLiveStatus() {
        let working = "esc interrupt   190.4K (19%)  ctrl+p commands   - OpenCode 1.17.7"
        #expect(HolySession.isLiveAgentStatusLineForTesting(working))
    }

    @Test func openCodeIdleFooterIsNotLiveStatus() {
        let idle = "97.9K (10%)  ctrl+p commands   - OpenCode 1.17.7"
        #expect(!HolySession.isLiveAgentStatusLineForTesting(idle))
    }
}
