import Foundation
import Testing
@testable import Ghostty

struct HolySessionIndicatorPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    @Test func vocabularyIsExactlyTheSixCanonicalStates() {
        #expect(Set(HolySessionAttentionKind.allCases) == Set([
            .working,
            .needsUser,
            .unread,
            .usedToday,
            .inactive,
            .sleeping,
        ]))
    }

    @Test func authoritativeOperationalStatesWin() {
        #expect(kind(lifecycle: .working, occurredAgo: 1) == .working)
        #expect(kind(lifecycle: .needsUser, occurredAgo: 1) == .needsUser)
        #expect(kind(lifecycle: .failed, occurredAgo: 1) == .needsUser)
    }

    @Test func hardProcessExitInvalidatesOperationalClaim() {
        #expect(kind(lifecycle: .working, occurredAgo: 1, processExited: true) == .usedToday)
        #expect(kind(lifecycle: .needsUser, occurredAgo: 1, processExited: true) == .usedToday)
    }

    @Test func workingLeaseExpiresFailClosed() {
        #expect(kind(lifecycle: .working, occurredAgo: 29 * 60) == .working)
        #expect(kind(lifecycle: .working, occurredAgo: 30 * 60) == .usedToday)
    }

    @Test func needsUserLeaseAlsoExpiresFailClosed() {
        #expect(kind(lifecycle: .needsUser, occurredAgo: 29 * 60) == .needsUser)
        #expect(kind(lifecycle: .needsUser, occurredAgo: 30 * 60) == .usedToday)
    }

    @Test func expiredQuestionDoesNotBecomeAnUnreadReplyThroughMetadata() throws {
        let eventTime = now.addingTimeInterval(-30 * 60)
        let envelope = try HolyAgentStateEnvelope(
            source: "future-harness.v2",
            lifecycle: .needsUser,
            occurredAt: eventTime,
            eventToken: "question-1",
            reasonCode: "question"
        )
        var metadata = HolySessionAttentionMetadata(sessionID: UUID())
        _ = metadata.migrateSeenTracking(at: eventTime.addingTimeInterval(-1))
        let didRecord = metadata.record(envelope: envelope, observedAt: now)
        #expect(didRecord)
        #expect(metadata.lastAgentFinishedAt == nil)
        #expect(kind(
            lifecycle: envelope.lifecycle,
            occurredAgo: 30 * 60,
            lastFinishedAt: metadata.lastAgentFinishedAt
        ) == .usedToday)
    }

    @Test func unreadPersistsUntilSeen() {
        let finished = now.addingTimeInterval(-60)
        #expect(kind(lastFinishedAt: finished, lastSeenAt: nil) == .unread)
        #expect(kind(lastFinishedAt: finished, lastSeenAt: finished.addingTimeInterval(-1)) == .unread)
        #expect(kind(lastFinishedAt: finished, lastSeenAt: finished) == .usedToday)
        #expect(kind(lastFinishedAt: finished, lastSeenAt: finished.addingTimeInterval(1)) == .usedToday)
    }

    @Test func recencyUsesRollingTwentyFourAndFortyEightHourWindows() {
        #expect(kind(lastUsedAgo: (24 * 60 * 60) - 1) == .usedToday)
        #expect(kind(lastUsedAgo: 24 * 60 * 60) == .inactive)
        #expect(kind(lastUsedAgo: (48 * 60 * 60) - 1) == .inactive)
        #expect(kind(lastUsedAgo: 48 * 60 * 60) == .sleeping)
    }

    @Test func metadataMigrationBaselinesOnceAndNextReplyBecomesUnread() throws {
        var metadata = HolySessionAttentionMetadata(sessionID: UUID())
        let baseline = now.addingTimeInterval(-10)
        let didBaseline = metadata.migrateSeenTracking(at: baseline)
        let didBaselineAgain = metadata.migrateSeenTracking(at: now)
        #expect(didBaseline)
        #expect(!didBaselineAgain)
        #expect(metadata.lastSeenAt == baseline)

        let envelope = try HolyAgentStateEnvelope(
            source: HolyAgentStateSource.claude,
            lifecycle: .finished,
            occurredAt: now,
            eventToken: "event-1"
        )
        let didRecord = metadata.record(envelope: envelope, observedAt: now)
        let didRecordAgain = metadata.record(envelope: envelope, observedAt: now)
        #expect(didRecord)
        #expect(!didRecordAgain)
        #expect(metadata.hasUnreadAgentReply)
        let didMarkSeen = metadata.markSeen(at: now.addingTimeInterval(1))
        #expect(didMarkSeen)
        #expect(!metadata.hasUnreadAgentReply)
    }

    @Test func notificationGateAdoptsHistoryAndReplaysOfflineEventsExactlyOnce() throws {
        let trackingStartedAt = now.addingTimeInterval(-60)
        let historical = try HolyAgentStateEnvelope(
            source: HolyAgentStateSource.codex,
            lifecycle: .finished,
            occurredAt: trackingStartedAt.addingTimeInterval(-1),
            eventToken: "historical"
        )
        let offline = try HolyAgentStateEnvelope(
            source: HolyAgentStateSource.codex,
            lifecycle: .finished,
            occurredAt: trackingStartedAt.addingTimeInterval(1),
            eventToken: "offline"
        )
        let working = try HolyAgentStateEnvelope(
            source: HolyAgentStateSource.codex,
            lifecycle: .working,
            occurredAt: trackingStartedAt.addingTimeInterval(2),
            eventToken: "working"
        )

        #expect(!shouldNotify(
            envelope: historical,
            trackingStartedAt: trackingStartedAt,
            lastNotifiedEventID: nil
        ))
        #expect(shouldNotify(
            envelope: offline,
            trackingStartedAt: trackingStartedAt,
            lastNotifiedEventID: nil
        ))
        #expect(!shouldNotify(
            envelope: offline,
            trackingStartedAt: trackingStartedAt,
            lastNotifiedEventID: offline.eventIdentity
        ))
        #expect(!shouldNotify(
            envelope: working,
            trackingStartedAt: trackingStartedAt,
            lastNotifiedEventID: nil
        ))
    }

    @Test func notificationWatermarkNeverReplaysAnOlderFinishedRegister() throws {
        let trackingStartedAt = now.addingTimeInterval(-120)
        let finished = try HolyAgentStateEnvelope(
            source: HolyAgentStateSource.openCode,
            lifecycle: .finished,
            occurredAt: now.addingTimeInterval(-60),
            eventToken: "finish-a"
        )
        let question = try HolyAgentStateEnvelope(
            source: HolyAgentStateSource.openCode,
            lifecycle: .needsUser,
            occurredAt: now.addingTimeInterval(-30),
            eventToken: "question-c"
        )
        let questionMilliseconds = HolyAgentNotificationPolicy.committedAtMilliseconds(
            envelope: question,
            observedAt: now
        )

        #expect(!shouldNotify(
            envelope: finished,
            trackingStartedAt: trackingStartedAt,
            lastNotifiedEventID: question.eventIdentity,
            lastNotifiedOccurredAtMilliseconds: questionMilliseconds
        ))
    }

    @Test func notificationNeedsUserUsesTheCanonicalExitAndLeaseGuards() throws {
        let stale = try HolyAgentStateEnvelope(
            source: HolyAgentStateSource.claude,
            lifecycle: .needsUser,
            occurredAt: now.addingTimeInterval(-HolySessionIndicatorPolicy.needsUserLease),
            eventToken: "stale-question"
        )
        let fresh = try HolyAgentStateEnvelope(
            source: HolyAgentStateSource.claude,
            lifecycle: .needsUser,
            occurredAt: now.addingTimeInterval(-1),
            eventToken: "fresh-question"
        )
        let trackingStartedAt = now.addingTimeInterval(-24 * 60 * 60)

        #expect(!shouldNotify(
            envelope: stale,
            trackingStartedAt: trackingStartedAt,
            lastNotifiedEventID: nil
        ))
        #expect(!shouldNotify(
            envelope: fresh,
            trackingStartedAt: trackingStartedAt,
            lastNotifiedEventID: nil,
            processExited: true
        ))
        #expect(shouldNotify(
            envelope: fresh,
            trackingStartedAt: trackingStartedAt,
            lastNotifiedEventID: nil
        ))
    }

    @Test func notificationIdentityScopesEqualTokensByHarnessSource() throws {
        let sessionID = UUID()
        let first = try HolyAgentStateEnvelope(
            source: "future-harness-a",
            lifecycle: .finished,
            occurredAt: now,
            eventToken: "shared-token"
        )
        let second = try HolyAgentStateEnvelope(
            source: "future-harness-b",
            lifecycle: .finished,
            occurredAt: now,
            eventToken: "shared-token"
        )
        let colonInSource = try HolyAgentStateEnvelope(
            source: "future-harness:a",
            lifecycle: .finished,
            occurredAt: now,
            eventToken: "b"
        )
        let colonInToken = try HolyAgentStateEnvelope(
            source: "future-harness",
            lifecycle: .finished,
            occurredAt: now,
            eventToken: "a:b"
        )

        #expect(
            HolyAgentNotificationPolicy.requestIdentifier(sessionID: sessionID, envelope: first)
                != HolyAgentNotificationPolicy.requestIdentifier(sessionID: sessionID, envelope: second)
        )
        #expect(colonInSource.eventIdentity != colonInToken.eventIdentity)
        #expect(
            HolyAgentNotificationPolicy.requestIdentifier(sessionID: sessionID, envelope: colonInSource)
                != HolyAgentNotificationPolicy.requestIdentifier(sessionID: sessionID, envelope: colonInToken)
        )
    }

    @Test func independentFinishedRegisterSurvivesALaterEndedLifecycle() throws {
        var metadata = HolySessionAttentionMetadata(sessionID: UUID())
        _ = metadata.migrateSeenTracking(at: now.addingTimeInterval(-120))
        let finished = try HolyAgentStateEnvelope(
            source: HolyAgentStateSource.openCode,
            lifecycle: .finished,
            occurredAt: now.addingTimeInterval(-60),
            eventToken: "finish"
        )
        let ended = try HolyAgentStateEnvelope(
            source: HolyAgentStateSource.openCode,
            lifecycle: .ended,
            occurredAt: now.addingTimeInterval(-30),
            eventToken: "ended"
        )

        let didRecordFinish = metadata.recordFinished(envelope: finished, observedAt: now)
        let didRecordEnd = metadata.record(envelope: ended, observedAt: now)
        #expect(didRecordFinish)
        #expect(didRecordEnd)
        #expect(metadata.lastAuthoritativeFinishedEventID == finished.eventIdentity)
        #expect(metadata.lastAgentFinishedAt == finished.occurredAt)
        #expect(metadata.hasUnreadAgentReply)
    }

    @Test func durableFinishedMetadataRejectsOutOfOrderRecoveryReads() throws {
        var metadata = HolySessionAttentionMetadata(sessionID: UUID())
        let newer = try HolyAgentStateEnvelope(
            source: "future-harness.v2",
            lifecycle: .finished,
            occurredAt: now,
            eventToken: "finish-new"
        )
        let older = try HolyAgentStateEnvelope(
            source: "future-harness.v2",
            lifecycle: .finished,
            occurredAt: now.addingTimeInterval(-1),
            eventToken: "finish-old"
        )

        let didRecordNewer = metadata.recordFinished(envelope: newer, observedAt: now)
        let didRecordOlder = metadata.recordFinished(envelope: older, observedAt: now)

        #expect(didRecordNewer)
        #expect(!didRecordOlder)
        #expect(metadata.lastAuthoritativeFinishedEventID == newer.eventIdentity)
        #expect(metadata.lastAgentFinishedAt == newer.occurredAt)
    }

    private func kind(
        lifecycle: HolyAgentLifecycleState? = nil,
        occurredAgo: TimeInterval? = nil,
        processExited: Bool = false,
        lastFinishedAt: Date? = nil,
        lastSeenAt: Date? = nil,
        lastUsedAgo: TimeInterval = 0,
        producerProcessAlive: Bool? = nil
    ) -> HolySessionAttentionKind {
        HolySessionIndicatorPolicy.kind(for: .init(
            lifecycle: lifecycle,
            lifecycleOccurredAt: occurredAgo.map { now.addingTimeInterval(-$0) },
            processExited: processExited,
            lastAgentFinishedAt: lastFinishedAt,
            lastSeenAt: lastSeenAt,
            lastUsedAt: now.addingTimeInterval(-lastUsedAgo),
            producerProcessAlive: producerProcessAlive,
            now: now
        ))
    }

    // Human freshness: blue is earned by prompts alone. Agent events,
    // finishes, and seen-marks acknowledge or inform, but never claim use.
    @Test func humanUseAdvancesOnlyOnUserPromptEnvelopes() throws {
        var metadata = HolySessionAttentionMetadata(sessionID: UUID())
        _ = metadata.migrateSeenTracking(at: now.addingTimeInterval(-3_600))
        #expect(metadata.lastUsedAt == nil)

        let toolComplete = try HolyAgentStateEnvelope(
            source: HolyAgentStateSource.claude,
            lifecycle: .working,
            occurredAt: now.addingTimeInterval(-60),
            eventToken: "tool-1",
            reasonCode: "tool-complete"
        )
        _ = metadata.record(envelope: toolComplete, observedAt: now)
        #expect(metadata.lastUsedAt == nil)

        let finished = try HolyAgentStateEnvelope(
            source: HolyAgentStateSource.claude,
            lifecycle: .finished,
            occurredAt: now.addingTimeInterval(-50),
            eventToken: "finish-1",
            reasonCode: "idle-finished"
        )
        _ = metadata.recordFinished(envelope: finished, observedAt: now)
        #expect(metadata.lastUsedAt == nil)

        _ = metadata.markSeen(at: now.addingTimeInterval(-40))
        #expect(metadata.lastUsedAt == nil)

        let prompt = try HolyAgentStateEnvelope(
            source: HolyAgentStateSource.claude,
            lifecycle: .working,
            occurredAt: now.addingTimeInterval(-30),
            eventToken: "prompt-1",
            reasonCode: HolySessionAttentionMetadata.humanUseReasonCode
        )
        _ = metadata.record(envelope: prompt, observedAt: now)
        #expect(metadata.lastUsedAt == prompt.occurredAt)
    }

    @Test func migrationClearsPreV2UseStampsButKeepsSeenAndRunsOnce() {
        let seenAt = now.addingTimeInterval(-7_200)
        var metadata = HolySessionAttentionMetadata(
            sessionID: UUID(),
            lastSeenAt: seenAt,
            seenTrackingVersion: 1,
            lastUsedAt: now.addingTimeInterval(-60),
            updatedAt: now.addingTimeInterval(-60)
        )
        let didMigrate = metadata.migrateSeenTracking(at: now)
        let didMigrateAgain = metadata.migrateSeenTracking(at: now.addingTimeInterval(1))
        #expect(didMigrate)
        #expect(!didMigrateAgain)
        #expect(metadata.lastUsedAt == nil)
        #expect(metadata.lastSeenAt == seenAt)
    }

    // Process evidence may extend or invalidate a working claim, never
    // create one (mn-8cec74).
    @Test func deadProducerInvalidatesAWorkingClaimWithinItsLease() {
        #expect(kind(lifecycle: .working, occurredAgo: 60, producerProcessAlive: false) == .usedToday)
        #expect(kind(lifecycle: .working, occurredAgo: 60, producerProcessAlive: true) == .working)
        #expect(kind(lifecycle: .working, occurredAgo: 60, producerProcessAlive: nil) == .working)
    }

    @Test func liveProducerExtendsAWorkingClaimPastTheLease() {
        #expect(kind(lifecycle: .working, occurredAgo: 31 * 60, producerProcessAlive: true) == .working)
        #expect(kind(lifecycle: .working, occurredAgo: 31 * 60, producerProcessAlive: nil) == .usedToday)
        #expect(kind(lifecycle: .working, occurredAgo: 31 * 60, producerProcessAlive: false) == .usedToday)
    }

    @Test func processEvidenceNeverCreatesOrExtendsOtherStates() {
        #expect(kind(lifecycle: .needsUser, occurredAgo: 31 * 60, producerProcessAlive: true) == .usedToday)
        #expect(kind(lifecycle: .idle, occurredAgo: 60, producerProcessAlive: true) == .usedToday)
    }

    // Mark Unread (roster context menu): clearing the seen timestamp returns
    // the session to unread; the next genuine visit re-marks seen as usual.
    @Test func markUnreadClearsSeenAndRestoresUnreadState() {
        var metadata = HolySessionAttentionMetadata(
            sessionID: UUID(),
            lastSeenAt: now,
            lastAgentFinishedAt: now.addingTimeInterval(-60),
            updatedAt: now
        )
        let later = now.addingTimeInterval(10)
        let didMark = metadata.markUnread(at: later)
        #expect(didMark)
        #expect(metadata.lastSeenAt == nil)
        #expect(metadata.hasUnreadAgentReply)
        #expect(metadata.updatedAt == later)
    }

    // Without a finished reply there is nothing to be unread about.
    @Test func markUnreadRequiresAFinishedReply() {
        var metadata = HolySessionAttentionMetadata(
            sessionID: UUID(),
            lastSeenAt: now,
            updatedAt: now
        )
        let didMark = metadata.markUnread(at: now.addingTimeInterval(1))
        #expect(!didMark)
        #expect(metadata.lastSeenAt == now)
    }

    // Already-unread is a no-op — no churn, no persist trigger.
    @Test func markUnreadIsIdempotentWhenAlreadyUnread() {
        var metadata = HolySessionAttentionMetadata(
            sessionID: UUID(),
            lastSeenAt: nil,
            lastAgentFinishedAt: now,
            updatedAt: now
        )
        let didMark = metadata.markUnread(at: now.addingTimeInterval(1))
        #expect(!didMark)
        #expect(metadata.updatedAt == now)
    }

    // Marking unread must not fabricate recency: lastUsedAt stays untouched,
    // so the time-tier dot underneath remains honest.
    @Test func markUnreadDoesNotBumpLastUsedAt() {
        let used = now.addingTimeInterval(-3_600)
        var metadata = HolySessionAttentionMetadata(
            sessionID: UUID(),
            lastSeenAt: now,
            lastAgentFinishedAt: now.addingTimeInterval(-60),
            lastUsedAt: used,
            updatedAt: now
        )
        let didMark = metadata.markUnread(at: now.addingTimeInterval(5))
        #expect(didMark)
        #expect(metadata.lastUsedAt == used)
    }

    private func shouldNotify(
        envelope: HolyAgentStateEnvelope,
        trackingStartedAt: Date,
        lastNotifiedEventID: String?,
        lastNotifiedOccurredAtMilliseconds: Int64? = nil,
        processExited: Bool = false
    ) -> Bool {
        HolyAgentNotificationPolicy.shouldNotify(for: .init(
            envelope: envelope,
            observedAt: now,
            trackingStartedAt: trackingStartedAt,
            lastNotifiedEventID: lastNotifiedEventID,
            lastNotifiedOccurredAtMilliseconds: lastNotifiedOccurredAtMilliseconds,
            processExited: processExited,
            now: now
        ))
    }
}
