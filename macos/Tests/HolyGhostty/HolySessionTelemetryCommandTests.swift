import Testing
@testable import Ghostty

struct HolySessionTelemetryCommandTests {
    // OpenCode renders a persistent status footer that brands itself, e.g.
    // "97.9K (10%)  ctrl+p commands    - OpenCode 1.17.7". That branding is
    // chrome, not a command the agent is running, so the telemetry parser must
    // not extract it as a command (doing so marks an idle session as working).
    @Test func openCodeStatusFooterIsNotACommand() {
        let footer = "97.9K (10%)  ctrl+p commands    - OpenCode 1.17.7"
        #expect(HolySessionRuntimeTelemetryParser.extractCommandForTesting(from: footer) == nil)
    }

    @Test func realCommandLineStillExtractsCommand() {
        let line = "$ git status --short"
        #expect(HolySessionRuntimeTelemetryParser.extractCommandForTesting(from: line) == "git status --short")
    }
}
