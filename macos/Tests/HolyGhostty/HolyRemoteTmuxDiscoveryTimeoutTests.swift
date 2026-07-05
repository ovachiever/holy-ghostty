import Foundation
import Testing
@testable import Ghostty

// Regression coverage for the converge discovery wall-clock cap. A hung host
// (here a long `sleep`) must be terminated at the cap and reported as
// unreachable (nil), so the converge sweep - and isConverging - can never wedge
// on a runaway discovery process. A fast process must complete normally within
// a generous cap.
struct HolyRemoteTmuxDiscoveryTimeoutTests {
    @Test func slowProcessIsCappedAndReportedUnreachable() async {
        let start = Date()
        let capped = await HolyRemoteTmuxDiscoveryService.runProcessWithTimeoutForTesting(
            sleepSeconds: 10,
            timeoutSeconds: 0.5
        )
        let elapsed = Date().timeIntervalSince(start)

        // The 10s sleep is terminated at the 0.5s cap and surfaces as nil.
        #expect(capped)
        // Proves the cap actually fired: we returned far sooner than the sleep.
        #expect(elapsed < 5)
    }

    @Test func fastProcessCompletesWithinCap() async {
        let capped = await HolyRemoteTmuxDiscoveryService.runProcessWithTimeoutForTesting(
            sleepSeconds: 0,
            timeoutSeconds: 5
        )

        // An immediate process finishes normally, so the cap never fires.
        #expect(!capped)
    }
}
