import Foundation
import Testing
@testable import Ghostty

@MainActor
struct HolyConvergeGateTests {
    @Test func neverStartsWhileRunning() {
        #expect(!HolyWorkspaceStore.shouldStartConverge(
            now: Date(timeIntervalSince1970: 100),
            lastStartedAt: Date(timeIntervalSince1970: 0),
            isRunning: true,
            reason: .manual
        ))
    }

    @Test func manualBypassesDebounce() {
        #expect(HolyWorkspaceStore.shouldStartConverge(
            now: Date(timeIntervalSince1970: 5),
            lastStartedAt: Date(timeIntervalSince1970: 0),
            isRunning: false,
            reason: .manual
        ))
    }

    @Test func wakeWithinDebounceWindowIsSkipped() {
        #expect(!HolyWorkspaceStore.shouldStartConverge(
            now: Date(timeIntervalSince1970: 5),
            lastStartedAt: Date(timeIntervalSince1970: 0),
            isRunning: false,
            reason: .wake
        ))
    }

    @Test func wakeAfterDebounceWindowRuns() {
        #expect(HolyWorkspaceStore.shouldStartConverge(
            now: Date(timeIntervalSince1970: 11),
            lastStartedAt: Date(timeIntervalSince1970: 0),
            isRunning: false,
            reason: .wake
        ))
    }

    @Test func firstRunAlwaysAllowed() {
        #expect(HolyWorkspaceStore.shouldStartConverge(
            now: Date(),
            lastStartedAt: nil,
            isRunning: false,
            reason: .wake
        ))
    }
}
