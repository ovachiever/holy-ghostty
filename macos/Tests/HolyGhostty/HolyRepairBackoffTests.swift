import Foundation
import Testing
@testable import Ghostty

struct HolyRepairBackoffTests {
    @Test func delaysFollowScheduleThenStop() {
        var backoff = HolyRepairBackoff()
        let id = UUID()
        #expect(backoff.nextDelay(for: id) == 4)
        #expect(backoff.nextDelay(for: id) == 10)
        #expect(backoff.nextDelay(for: id) == 25)
        #expect(backoff.nextDelay(for: id) == nil)
    }

    @Test func sessionsBackOffIndependently() {
        var backoff = HolyRepairBackoff()
        let first = UUID()
        let second = UUID()
        #expect(backoff.nextDelay(for: first) == 4)
        #expect(backoff.nextDelay(for: second) == 4)
    }

    @Test func resetAllRestoresTheSchedule() {
        var backoff = HolyRepairBackoff()
        let id = UUID()
        _ = backoff.nextDelay(for: id)
        _ = backoff.nextDelay(for: id)
        backoff.resetAll()
        #expect(backoff.nextDelay(for: id) == 4)
    }
}
