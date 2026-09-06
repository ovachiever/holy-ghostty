import Foundation
import Testing
@testable import Ghostty

struct HolySessionIndicatorPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    @Test func vocabularyIncludesExplicitWireConflictState() {
        #expect(Set(HolySessionAttentionKind.allCases) == Set([
            .conflict,
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

    // Erik's field report 2026-07-22 (ORCHA): a turn-failed badge survived
    // him opening the session and reading the wreck. A failure asks for
    // nothing but eyes, so seeing the session after it occurred acknowledges
    // it. Questions and permission prompts stay demanding until answered —
    // looking at an unanswered question resolves nothing.
    @Test func seeingASessionAcknowledgesItsFailedTurn() {
        let failedAt = now.addingTimeInterval(-5 * 60)
        #expect(kind(lifecycle: .failed, occurredAgo: 5 * 60, lastSeenAt: nil) == .needsUser)
        #expect(kind(
            lifecycle: .failed,
            occurredAgo: 5 * 60,
            lastSeenAt: failedAt.addingTimeInterval(-1)
        ) == .needsUser)
        #expect(kind(
            lifecycle: .failed,
            occurredAgo: 5 * 60,
            lastSeenAt: failedAt
        ) == .usedToday)
        #expect(kind(
            lifecycle: .failed,
            occurredAgo: 5 * 60,
            lastSeenAt: failedAt.addingTimeInterval(60)
        ) == .usedToday)
    }

    @Test func seeingAnUnansweredQuestionResolvesNothing() {
        #expect(kind(
            lifecycle: .needsUser,
            occurredAgo: 5 * 60,
            lastSeenAt: now
        ) == .needsUser)
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

    @Test func freshCacheMigrationDoesNotPretendHostHistoryWasSeen() throws {
        var metadata = HolySessionAttentionMetadata(sessionID: UUID())
        let baseline = now.addingTimeInterval(-10)
        let didBaseline = metadata.migrateSeenTracking(at: baseline)
        let didBaselineAgain = metadata.migrateSeenTracking(at: now)
        #expect(didBaseline)
        #expect(!didBaselineAgain)
        #expect(metadata.lastSeenAt == nil)

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
        let sharedSeen = try #require(HolyAgentSeenState.seen(
            acknowledgingEventAtMilliseconds: envelope.occurredAtMilliseconds,
            at: now.addingTimeInterval(1),
            after: nil
        ))
        let didApplySeen = metadata.applySharedSeenState(sharedSeen, observedAt: now)
        #expect(didApplySeen)
        #expect(!metadata.hasUnreadAgentReply)
    }

    @Test func sharedSeenWatermarkAcknowledgesTheObservedEventWithoutTrustingViewerClock() throws {
        let finished = try HolyAgentStateEnvelope(
            source: HolyAgentStateSource.codex,
            lifecycle: .finished,
            occurredAtMilliseconds: 1_750_000_000_000,
            eventToken: "finish-1"
        )
        var metadata = HolySessionAttentionMetadata(sessionID: UUID())
        _ = metadata.migrateSeenTracking(at: now.addingTimeInterval(-60))
        let didRecordFinished = metadata.recordFinished(envelope: finished, observedAt: now)
        #expect(didRecordFinished)

        // The viewer clock is behind the producer, but the acknowledgement
        // names the producer watermark it actually displayed.
        let sharedSeen = try #require(HolyAgentSeenState.seen(
            acknowledgingEventAtMilliseconds: finished.occurredAtMilliseconds,
            at: finished.occurredAt.addingTimeInterval(-30),
            after: nil
        ))
        let didApplySharedSeen = metadata.applySharedSeenState(sharedSeen, observedAt: now)
        #expect(didApplySharedSeen)
        #expect(!metadata.hasUnreadAgentReply)
        #expect(kind(
            lastFinishedAt: finished.occurredAt,
            lastSeenAt: metadata.lastSeenAt,
            lastSeenAuthoritativeEventAt: metadata.acknowledgedAuthoritativeEventAt
        ) == .usedToday)

        let olderUnread = try HolyAgentSeenState(wireValue: "v1|unread||1749999999999")
        let didApplyOlder = metadata.applySharedSeenState(olderUnread, observedAt: now)
        #expect(!didApplyOlder)
        #expect(metadata.sharedSeenState == sharedSeen)
    }

    @Test func durableHumanUseRegisterRebuildsBlueAfterLaterLifecycleEvents() throws {
        let prompt = try HolyAgentStateEnvelope(
            source: HolyAgentStateSource.claude,
            lifecycle: .working,
            occurredAt: now.addingTimeInterval(-60),
            eventToken: "prompt-1",
            reasonCode: HolySessionAttentionMetadata.humanUseReasonCode
        )
        let ended = try HolyAgentStateEnvelope(
            source: HolyAgentStateSource.claude,
            lifecycle: .ended,
            occurredAt: now.addingTimeInterval(-30),
            eventToken: "ended-1"
        )
        var rebuilt = HolySessionAttentionMetadata(sessionID: UUID())
        _ = rebuilt.migrateSeenTracking(at: now)

        let didRecordEnded = rebuilt.record(envelope: ended, observedAt: now)
        #expect(didRecordEnded)
        #expect(rebuilt.lastUsedAt == nil)
        let didRecordUse = rebuilt.recordUsed(envelope: prompt, observedAt: now)
        #expect(didRecordUse)
        #expect(rebuilt.lastUsedAt == prompt.occurredAt)
        let didRecordUseAgain = rebuilt.recordUsed(envelope: prompt, observedAt: now)
        #expect(!didRecordUseAgain)
    }

    @Test func hostEventTimesRebuildIdenticallyAcrossViewerClockSkew() throws {
        let hostNow = Date(timeIntervalSince1970: 1_750_000_120)
        let prompt = try HolyAgentStateEnvelope(
            source: HolyAgentStateSource.claude,
            lifecycle: .working,
            occurredAt: hostNow,
            eventToken: "prompt-skew",
            reasonCode: HolySessionAttentionMetadata.humanUseReasonCode
        )
        let finished = try HolyAgentStateEnvelope(
            source: HolyAgentStateSource.claude,
            lifecycle: .finished,
            occurredAt: hostNow.addingTimeInterval(5),
            eventToken: "finish-skew"
        )
        var slowViewer = HolySessionAttentionMetadata(sessionID: UUID())
        var fastViewer = HolySessionAttentionMetadata(sessionID: UUID())

        let slowObservedAt = hostNow.addingTimeInterval(-60)
        let fastObservedAt = hostNow.addingTimeInterval(60)
        _ = slowViewer.record(envelope: finished, observedAt: slowObservedAt)
        _ = slowViewer.recordFinished(envelope: finished, observedAt: slowObservedAt)
        _ = slowViewer.recordUsed(envelope: prompt, observedAt: slowObservedAt)
        _ = fastViewer.record(envelope: finished, observedAt: fastObservedAt)
        _ = fastViewer.recordFinished(envelope: finished, observedAt: fastObservedAt)
        _ = fastViewer.recordUsed(envelope: prompt, observedAt: fastObservedAt)

        #expect(slowViewer.lastAuthoritativeEventOccurredAt == finished.occurredAt)
        #expect(slowViewer.lastAuthoritativeEventOccurredAt == fastViewer.lastAuthoritativeEventOccurredAt)
        #expect(slowViewer.lastAgentFinishedAt == fastViewer.lastAgentFinishedAt)
        #expect(slowViewer.lastUsedAt == fastViewer.lastUsedAt)
    }

    @Test func clearAndReattachRebuildsSameSeenAndRecencyFromHostRegisters() throws {
        let prompt = try HolyAgentStateEnvelope(
            source: HolyAgentStateSource.claude,
            lifecycle: .working,
            occurredAt: now.addingTimeInterval(-2 * 60 * 60),
            eventToken: "prompt-before-clear",
            reasonCode: HolySessionAttentionMetadata.humanUseReasonCode
        )
        let finished = try HolyAgentStateEnvelope(
            source: HolyAgentStateSource.claude,
            lifecycle: .finished,
            occurredAt: now.addingTimeInterval(-60 * 60),
            eventToken: "finish-before-clear"
        )
        let ended = try HolyAgentStateEnvelope(
            source: HolyAgentStateSource.claude,
            lifecycle: .ended,
            occurredAt: now.addingTimeInterval(-20 * 60),
            eventToken: "ended-before-clear"
        )
        let sharedSeen = try #require(HolyAgentSeenState.seen(
            acknowledgingEventAtMilliseconds: finished.occurredAtMilliseconds,
            at: now.addingTimeInterval(-30 * 60),
            after: nil
        ))

        func rebuild(observedAt: Date) -> HolySessionAttentionMetadata {
            var metadata = HolySessionAttentionMetadata(sessionID: UUID())
            _ = metadata.migrateSeenTracking(at: observedAt)
            _ = metadata.record(envelope: ended, observedAt: observedAt)
            _ = metadata.recordFinished(envelope: finished, observedAt: observedAt)
            _ = metadata.recordUsed(envelope: prompt, observedAt: observedAt)
            _ = metadata.applySharedSeenState(sharedSeen, observedAt: observedAt)
            return metadata
        }

        var studio = rebuild(observedAt: now.addingTimeInterval(-10 * 60))
        var clearedMacBook = rebuild(observedAt: now)
        #expect(studio.lastUsedAt == clearedMacBook.lastUsedAt)
        #expect(studio.lastAgentFinishedAt == clearedMacBook.lastAgentFinishedAt)
        #expect(studio.lastAuthoritativeEventOccurredAt == clearedMacBook.lastAuthoritativeEventOccurredAt)
        #expect(studio.acknowledgedAuthoritativeEventAt == clearedMacBook.acknowledgedAuthoritativeEventAt)
        #expect(!studio.hasUnreadAgentReply)
        #expect(!clearedMacBook.hasUnreadAgentReply)

        let unseenFinish = try HolyAgentStateEnvelope(
            source: HolyAgentStateSource.claude,
            lifecycle: .finished,
            occurredAt: now.addingTimeInterval(-60),
            eventToken: "finish-after-seen"
        )
        _ = studio.recordFinished(envelope: unseenFinish, observedAt: now)
        _ = clearedMacBook.recordFinished(envelope: unseenFinish, observedAt: now)
        #expect(studio.hasUnreadAgentReply)
        #expect(clearedMacBook.hasUnreadAgentReply)
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
        lastSeenAuthoritativeEventAt: Date? = nil,
        lastUsedAgo: TimeInterval = 0,
        producerProcessAlive: Bool? = nil,
        producerOutputAgo: TimeInterval? = nil,
        lastActivityAgo: TimeInterval? = nil,
        scrapePhase: HolySessionPhase? = nil
    ) -> HolySessionAttentionKind {
        HolySessionIndicatorPolicy.kind(for: .init(
            lifecycle: lifecycle,
            lifecycleOccurredAt: occurredAgo.map { now.addingTimeInterval(-$0) },
            processExited: processExited,
            lastAgentFinishedAt: lastFinishedAt,
            lastSeenAt: lastSeenAt,
            lastSeenAuthoritativeEventAt: lastSeenAuthoritativeEventAt,
            lastUsedAt: now.addingTimeInterval(-lastUsedAgo),
            producerProcessAlive: producerProcessAlive,
            producerLastOutputAt: producerOutputAgo.map { now.addingTimeInterval(-$0) },
            lastActivityAt: lastActivityAgo.map { now.addingTimeInterval(-$0) },
            scrapePhase: scrapePhase,
            now: now
        ))
    }

    // Erik's field report 2026-07-21: an old session's fresh reply was read
    // and the row jumped straight to sleeping-z off its ancient creation
    // date. Aging must key off the whole session going quiet, not the
    // human-use axis alone.
    @Test func readingAnOldSessionsFreshReplyLandsOnPlainGreyNotSleeping() {
        #expect(kind(
            lastFinishedAt: now.addingTimeInterval(-3_600),
            lastSeenAt: now,
            lastUsedAgo: 72 * 60 * 60,
            lastActivityAgo: 0
        ) == .inactive)
    }

    @Test func sleepingRequiresEveryAxisQuietForFortyEightHours() {
        #expect(kind(lastUsedAgo: 72 * 60 * 60, lastActivityAgo: (48 * 60 * 60) - 1) == .inactive)
        #expect(kind(lastUsedAgo: 72 * 60 * 60, lastActivityAgo: 48 * 60 * 60) == .sleeping)
        // Recent agent activity never earns blue — that stays human-only.
        #expect(kind(lastUsedAgo: 25 * 60 * 60, lastActivityAgo: 0) == .inactive)
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

        let sharedSeen = try #require(HolyAgentSeenState.seen(
            acknowledgingEventAtMilliseconds: finished.occurredAtMilliseconds,
            at: now.addingTimeInterval(-40),
            after: nil
        ))
        _ = metadata.applySharedSeenState(sharedSeen, observedAt: now)
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

    @Test func v3MigrationClearsMachineLocalSeenAndUseExactlyOnce() {
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
        #expect(metadata.lastSeenAt == nil)
    }

    // Process evidence may invalidate a working claim, never create or renew
    // one. Only a newer hook envelope renews the lease.
    @Test func deadProducerInvalidatesAWorkingClaimWithinItsLease() {
        #expect(kind(lifecycle: .working, occurredAgo: 60, producerProcessAlive: false) == .usedToday)
        #expect(kind(lifecycle: .working, occurredAgo: 60, producerProcessAlive: true) == .working)
        #expect(kind(lifecycle: .working, occurredAgo: 60, producerProcessAlive: nil) == .working)
    }

    // Erik's live repro 2026-09-03: claude.exe and fresh window activity
    // survived a lost Stop hook. Neither is hook traffic, so neither may renew
    // the 30-minute authoritative working lease.
    @Test func processAndPaneActivityCannotRenewAWorkingLease() {
        #expect(kind(
            lifecycle: .working,
            occurredAgo: 31 * 60,
            producerProcessAlive: true,
            producerOutputAgo: 30,
            scrapePhase: .active
        ) == .usedToday)
        #expect(kind(
            lifecycle: .working,
            occurredAgo: 31 * 60,
            producerProcessAlive: true,
            producerOutputAgo: 10 * 60,
            scrapePhase: .active
        ) == .usedToday)
        #expect(kind(lifecycle: .working, occurredAgo: 31 * 60, producerProcessAlive: true) == .usedToday)
        #expect(kind(
            lifecycle: .working,
            occurredAgo: 31 * 60,
            producerProcessAlive: nil,
            producerOutputAgo: 30
        ) == .usedToday)
        #expect(kind(lifecycle: .working, occurredAgo: 31 * 60, producerProcessAlive: false) == .usedToday)
    }

    @Test func expiredWorkingLeaseFallsBackToCurrentScrapeVerdict() {
        #expect(kind(
            lifecycle: .working,
            occurredAgo: 31 * 60,
            producerProcessAlive: true,
            producerOutputAgo: 1,
            scrapePhase: .working
        ) == .working)
        #expect(kind(
            lifecycle: .working,
            occurredAgo: 31 * 60,
            producerProcessAlive: true,
            producerOutputAgo: 1,
            scrapePhase: .waitingInput
        ) == .needsUser)
        #expect(kind(
            lifecycle: .working,
            occurredAgo: 31 * 60,
            producerProcessAlive: true,
            producerOutputAgo: 1,
            scrapePhase: .active
        ) == .usedToday)
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
