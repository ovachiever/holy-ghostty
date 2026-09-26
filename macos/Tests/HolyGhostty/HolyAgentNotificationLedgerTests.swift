import Foundation
import Testing
@testable import Ghostty

// mn-3aeeef. Measured on the installed app 2026-09-26 12:32:42-12:33:42:
// `log show --predicate 'process == "holy-ghostty"'` returned 2,304 entries,
// every one `com.apple.UserNotifications:Connections`, 1,151 "Removing 1
// pending" plus 1,151 "Removing 1 delivered" across 14 identifiers, about 124
// per identifier per minute. The attention recompute retracted each
// acknowledged session's alert on every poll whether or not one was posted.
// The law under test: a retraction reaches the notification center only for
// an identifier this app posted (or the center reported at launch), once.

/// The per-identifier pending-remove count in that minute, the observed
/// number of recompute passes that each retracted one session's alert.
private let observedRecomputesPerSessionPerMinute = 124

@MainActor
private final class RecordingNotificationCenter: HolyUserNotificationCenterClient {
    var pendingRemovals: [[String]] = []
    var deliveredRemovals: [[String]] = []
    var outstandingQueries = 0
    var reported: [String] = []
    private var gate: CheckedContinuation<Void, Never>?
    var holdsQuery = false

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        pendingRemovals.append(identifiers)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        deliveredRemovals.append(identifiers)
    }

    func outstandingNotificationIdentifiers() async -> [String] {
        outstandingQueries += 1
        if holdsQuery {
            await withCheckedContinuation { gate = $0 }
        }
        return reported
    }

    var isHoldingQuery: Bool { gate != nil }

    func releaseQuery() {
        gate?.resume()
        gate = nil
    }
}

private func identifier(_ sessionID: UUID, _ eventID: String) -> String {
    HolyAgentNotificationPolicy.requestIdentifier(sessionID: sessionID, eventID: eventID)
}

/// One attention-recompute pass for an acknowledged session: the shared-seen
/// retraction in scheduleAuthoritativeAgentNotificationIfNeeded and the
/// focused-visibility retraction in markSessionSeenIfNeeded, as the store
/// issues them.
@MainActor
private func recompute(_ ledger: HolyAgentNotificationLedger, sessionID: UUID, eventID: String) {
    ledger.retract([identifier(sessionID, eventID)])
    ledger.retract([identifier(sessionID, eventID), identifier(sessionID, "older-\(eventID)")])
}

@MainActor
struct HolyAgentNotificationLedgerTests {
    @Test func recomputeWithoutAPostedNotificationNeverCallsTheCenter() async {
        let center = RecordingNotificationCenter()
        let ledger = HolyAgentNotificationLedger(center: center)
        let sessionID = UUID()

        for _ in 0..<observedRecomputesPerSessionPerMinute {
            recompute(ledger, sessionID: sessionID, eventID: "finished-1")
        }

        #expect(center.pendingRemovals.isEmpty)
        #expect(center.deliveredRemovals.isEmpty)
    }

    @Test func onePostIsRetractedExactlyOnceAcrossManyRecomputes() async {
        let center = RecordingNotificationCenter()
        let ledger = HolyAgentNotificationLedger(center: center)
        let sessionID = UUID()
        let posted = identifier(sessionID, "finished-1")

        ledger.notePosting(posted)
        for _ in 0..<observedRecomputesPerSessionPerMinute {
            recompute(ledger, sessionID: sessionID, eventID: "finished-1")
        }

        #expect(center.pendingRemovals == [[posted]])
        #expect(center.deliveredRemovals == [[posted]])
        #expect(!ledger.isOutstanding(posted))
    }

    @Test func refusedPostIsNeverRetracted() async {
        let center = RecordingNotificationCenter()
        let ledger = HolyAgentNotificationLedger(center: center)
        let posted = identifier(UUID(), "failed-1")

        ledger.notePosting(posted)
        ledger.noteNotPosted(posted)
        ledger.retract([posted])

        #expect(center.pendingRemovals.isEmpty)
        #expect(center.deliveredRemovals.isEmpty)
    }

    @Test func lateAddAfterFocusRetractionIsRemovedAgainOnce() async {
        let center = RecordingNotificationCenter()
        let ledger = HolyAgentNotificationLedger(center: center)
        let posted = identifier(UUID(), "finished-1")

        ledger.notePosting(posted)        // request handed to the center
        ledger.retract([posted])          // focus acknowledges while add is in flight
        ledger.notePosting(posted)        // add completes: the center accepted it
        ledger.retract([posted])          // completion removes the late add
        ledger.retract([posted])          // later recomputes cost nothing

        #expect(center.pendingRemovals == [[posted], [posted]])
        #expect(center.deliveredRemovals == [[posted], [posted]])
    }

    @Test func alertsSurvivingRelaunchAreLearnedOnceAndRetractedOnce() async {
        let center = RecordingNotificationCenter()
        let sessionID = UUID()
        let survivor = identifier(sessionID, "finished-0")
        center.reported = [survivor, "bell-surface-banner"]
        let ledger = HolyAgentNotificationLedger(center: center)

        await ledger.seedFromCenter()
        await ledger.seedFromCenter()
        for _ in 0..<observedRecomputesPerSessionPerMinute {
            recompute(ledger, sessionID: sessionID, eventID: "finished-0")
        }
        ledger.retract(["bell-surface-banner"])

        #expect(center.outstandingQueries == 1)
        #expect(center.pendingRemovals == [[survivor]])
        #expect(center.deliveredRemovals == [[survivor]])
    }

    @Test func retractionDuringTheLaunchQueryIsHonouredWhenItAnswers() async {
        let center = RecordingNotificationCenter()
        let sessionID = UUID()
        let survivor = identifier(sessionID, "finished-0")
        let neverPosted = identifier(UUID(), "finished-9")
        center.reported = [survivor]
        center.holdsQuery = true
        let ledger = HolyAgentNotificationLedger(center: center)

        let seed = Task { @MainActor in await ledger.seedFromCenter() }
        while !center.isHoldingQuery { await Task.yield() }
        for _ in 0..<observedRecomputesPerSessionPerMinute {
            recompute(ledger, sessionID: sessionID, eventID: "finished-0")
            ledger.retract([neverPosted])
        }
        #expect(center.pendingRemovals.isEmpty)

        center.releaseQuery()
        await seed.value

        #expect(center.pendingRemovals == [[survivor]])
        #expect(center.deliveredRemovals == [[survivor]])
        #expect(!ledger.isOutstanding(survivor))
    }
}
