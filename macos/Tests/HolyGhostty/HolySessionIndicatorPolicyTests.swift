import Foundation
import Testing
@testable import Ghostty

struct HolySessionIndicatorPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    @Test func vocabularyIsExactlyTheSixCanonicalStates() {
        #expect(Set(HolySessionAttentionKind.allCases) == Set([
            .working,
            .needsUser,
            .usedToday,
            .onAutomation,
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
        #expect(kind(lifecycle: .working, occurredAgo: 1, processExited: true) == .sleeping)
        #expect(kind(lifecycle: .needsUser, occurredAgo: 1, processExited: true) == .sleeping)
    }

    @Test func workingLeaseExpiresFailClosed() {
        #expect(kind(lifecycle: .working, occurredAgo: 29 * 60) == .working)
        #expect(kind(lifecycle: .working, occurredAgo: 30 * 60) == .sleeping)
    }

    @Test func needsUserLeaseAlsoExpiresFailClosed() {
        #expect(kind(lifecycle: .needsUser, occurredAgo: 29 * 60) == .needsUser)
        #expect(kind(lifecycle: .needsUser, occurredAgo: 30 * 60) == .sleeping)
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
        _ = metadata.migrateToCurrentSeenTracking(at: now)
        let didRecord = metadata.record(envelope: envelope, observedAt: now)
        #expect(didRecord)
        #expect(metadata.lastAgentFinishedAt == nil)
        #expect(kind(
            lifecycle: envelope.lifecycle,
            occurredAgo: 30 * 60,
            lastFinishedAt: metadata.lastAgentFinishedAt,
            lastAgentActiveAgo: 30 * 60
        ) == .onAutomation)
    }

    @Test func unreadIsAnOverlayAndNeverReplacesTheRecencyTier() {
        let finished = now.addingTimeInterval(-60)
        let unread = decision(
            lastFinishedAt: finished,
            lastSeenAt: finished.addingTimeInterval(-1),
            lastAgentActiveAt: finished
        )
        #expect(unread.kind == .onAutomation)
        #expect(unread.showsUnreadPip)

        let seen = decision(
            lastFinishedAt: finished,
            lastSeenAt: finished,
            lastAgentActiveAt: finished
        )
        #expect(seen.kind == .onAutomation)
        #expect(!seen.showsUnreadPip)
    }

    @Test func recencySeparatesHumanBlueFromAutomationViolet() {
        #expect(kind(lastHumanUsedAgo: 60, lastAgentActiveAgo: 1) == .usedToday)
        #expect(kind(lastAgentActiveAgo: 60) == .onAutomation)
        #expect(kind(lastHumanUsedAgo: 24 * 60 * 60, lastAgentActiveAgo: 60) == .onAutomation)
    }

    @Test func greyAndSleepingUseTheLaterOfBothClocks() {
        #expect(kind(lastHumanUsedAgo: 25 * 60 * 60, lastAgentActiveAgo: 47 * 60 * 60) == .inactive)
        #expect(kind(lastHumanUsedAgo: 47 * 60 * 60, lastAgentActiveAgo: 25 * 60 * 60) == .inactive)
        #expect(kind(lastHumanUsedAgo: 48 * 60 * 60, lastAgentActiveAgo: 49 * 60 * 60) == .sleeping)
        #expect(kind() == .sleeping)
    }

    @Test func recencyMigrationSeedsHumanFromSeenEvidenceAndAgentFromLastFinish() {
        let seen = now.addingTimeInterval(-3_600)
        let finished = now.addingTimeInterval(-7_200)
        var metadata = HolySessionAttentionMetadata(
            sessionID: UUID(),
            lastSeenAt: seen,
            lastAgentFinishedAt: finished,
            seenTrackingVersion: 1,
            updatedAt: now
        )

        let didMigrate = metadata.migrateToCurrentSeenTracking(at: now)
        let didMigrateAgain = metadata.migrateToCurrentSeenTracking(at: now.addingTimeInterval(1))
        #expect(didMigrate)
        #expect(!didMigrateAgain)
        #expect(metadata.lastSeenAt == seen)
        #expect(metadata.lastHumanUsedAt == seen)
        #expect(metadata.lastAgentActiveAt == finished)
        #expect(metadata.seenTrackingVersion == HolySessionAttentionMetadata.currentSeenTrackingVersion)
    }

    @Test func recencyRepairPreservesExistingV2Clocks() {
        let human = now.addingTimeInterval(-120)
        let agent = now.addingTimeInterval(-60)
        var metadata = HolySessionAttentionMetadata(
            sessionID: UUID(),
            lastSeenAt: now.addingTimeInterval(-3_600),
            seenTrackingVersion: 2,
            lastHumanUsedAt: human,
            lastAgentActiveAt: agent,
            updatedAt: now
        )

        let didMigrate = metadata.migrateToCurrentSeenTracking(at: now)
        #expect(didMigrate)
        #expect(metadata.lastHumanUsedAt == human)
        #expect(metadata.lastAgentActiveAt == agent)
    }

    @Test func recencyRepairSeedsMissingV2HumanFromPreservedSeenEvidence() {
        let seen = now.addingTimeInterval(-300)
        var metadata = HolySessionAttentionMetadata(
            sessionID: UUID(),
            lastSeenAt: seen,
            seenTrackingVersion: 2,
            lastHumanUsedAt: nil,
            lastAgentActiveAt: now.addingTimeInterval(-60),
            updatedAt: now
        )

        let didMigrate = metadata.migrateToCurrentSeenTracking(at: now)
        #expect(didMigrate)
        #expect(metadata.lastHumanUsedAt == seen)
    }

    @Test func baselineSeenDoesNotFabricateEitherRecencyClock() {
        var metadata = HolySessionAttentionMetadata(sessionID: UUID())
        let didBaseline = metadata.markSeenBaseline(at: now)
        #expect(didBaseline)
        #expect(metadata.lastSeenAt == now)
        #expect(metadata.lastHumanUsedAt == nil)
        #expect(metadata.lastAgentActiveAt == nil)
    }

    @Test func humanFocusDwellMarksSeenAndHumanUseOnly() {
        var metadata = HolySessionAttentionMetadata(
            sessionID: UUID(),
            lastAgentActiveAt: now.addingTimeInterval(-60),
            updatedAt: now.addingTimeInterval(-60)
        )
        let didMarkHumanUsed = metadata.markHumanUsed(at: now)
        #expect(didMarkHumanUsed)
        #expect(metadata.lastSeenAt == now)
        #expect(metadata.lastHumanUsedAt == now)
        #expect(metadata.lastAgentActiveAt == now.addingTimeInterval(-60))
    }

    @Test func focusDwellRequiresContinuousFocusAndPostRestoreQuiescence() {
        let workspaceStartedAt = now
        let launchFocusBeganAt = now.addingTimeInterval(0.25)
        #expect(!HolySessionFocusDwellPolicy.canCommit(
            focusBeganAt: launchFocusBeganAt,
            workspaceStartedAt: workspaceStartedAt,
            now: now.addingTimeInterval(60)
        ))

        let focusBeganAt = workspaceStartedAt.addingTimeInterval(
            HolySessionFocusDwellPolicy.postRestoreQuiescence
        )
        #expect(!HolySessionFocusDwellPolicy.canCommit(
            focusBeganAt: focusBeganAt,
            workspaceStartedAt: workspaceStartedAt,
            now: focusBeganAt.addingTimeInterval(HolySessionFocusDwellPolicy.minimumDwell - 0.01)
        ))
        #expect(HolySessionFocusDwellPolicy.canCommit(
            focusBeganAt: focusBeganAt,
            workspaceStartedAt: workspaceStartedAt,
            now: focusBeganAt.addingTimeInterval(HolySessionFocusDwellPolicy.minimumDwell)
        ))
    }

    @Test func userPromptAdvancesBothClocksWhileAgentEventsAdvanceOnlyAgentClock() throws {
        var metadata = HolySessionAttentionMetadata(sessionID: UUID())
        let userPrompt = try HolyAgentStateEnvelope(
            source: HolyAgentStateSource.claude,
            lifecycle: .working,
            occurredAt: now.addingTimeInterval(-2),
            eventToken: "prompt",
            reasonCode: "user-prompt"
        )
        let didRecordPrompt = metadata.record(envelope: userPrompt, observedAt: now)
        #expect(didRecordPrompt)
        #expect(metadata.lastHumanUsedAt == userPrompt.occurredAt)
        #expect(metadata.lastAgentActiveAt == userPrompt.occurredAt)

        let toolEvent = try HolyAgentStateEnvelope(
            source: HolyAgentStateSource.claude,
            lifecycle: .working,
            occurredAt: now,
            eventToken: "tool",
            reasonCode: "tool-complete"
        )
        let didRecordTool = metadata.record(envelope: toolEvent, observedAt: now)
        #expect(didRecordTool)
        #expect(metadata.lastHumanUsedAt == userPrompt.occurredAt)
        #expect(metadata.lastAgentActiveAt == now)
    }

    @Test func attentionMetadataRoundTripPreservesBothRecencyClocks() throws {
        let original = HolySessionAttentionMetadata(
            sessionID: UUID(),
            lastSeenAt: now.addingTimeInterval(-3),
            seenTrackingVersion: HolySessionAttentionMetadata.currentSeenTrackingVersion,
            lastHumanUsedAt: now.addingTimeInterval(-2),
            lastAgentActiveAt: now.addingTimeInterval(-1),
            updatedAt: now
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HolySessionAttentionMetadata.self, from: encoded)
        #expect(decoded == original)
    }

    @Test func legacyLastUsedPayloadSeedsHumanFromNewestSeenTrackingEvidence() throws {
        let seen = now.addingTimeInterval(-3_600)
        let finished = now.addingTimeInterval(-7_200)
        let legacyUsed = now.addingTimeInterval(-1_800)
        let encoded = try JSONEncoder().encode(LegacyAttentionMetadata(
            sessionID: UUID(),
            lastSeenAt: seen,
            lastAgentFinishedAt: finished,
            seenTrackingVersion: 1,
            lastUsedAt: legacyUsed,
            updatedAt: now
        ))
        var decoded = try JSONDecoder().decode(HolySessionAttentionMetadata.self, from: encoded)

        #expect(decoded.lastSeenAt == seen)
        #expect(decoded.lastHumanUsedAt == nil)
        #expect(decoded.lastAgentActiveAt == nil)
        let didMigrate = decoded.migrateToCurrentSeenTracking(at: now)
        #expect(didMigrate)
        #expect(decoded.lastHumanUsedAt == legacyUsed)
        #expect(decoded.lastAgentActiveAt == finished)
        let migratedJSON = try #require(String(
            bytes: try JSONEncoder().encode(decoded),
            encoding: .utf8
        ))
        #expect(!migratedJSON.contains("\"lastUsedAt\""))
    }

    @Test func migrationTakesNewerLastSeenOverOlderLegacyUsedEvidence() {
        let seen = now.addingTimeInterval(-600)
        let legacyUsed = now.addingTimeInterval(-1_200)
        var metadata = HolySessionAttentionMetadata(
            sessionID: UUID(),
            lastSeenAt: seen,
            seenTrackingVersion: 1,
            lastUsedAt: legacyUsed,
            updatedAt: now
        )

        let didMigrate = metadata.migrateToCurrentSeenTracking(at: now)
        #expect(didMigrate)
        #expect(metadata.lastHumanUsedAt == seen)
    }

    @Test func nextReplyBecomesUnreadUntilHumanDwell() throws {
        var metadata = HolySessionAttentionMetadata(sessionID: UUID())
        _ = metadata.migrateToCurrentSeenTracking(at: now)
        _ = metadata.markSeenBaseline(at: now.addingTimeInterval(-10))

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
        let didMarkSeen = metadata.markHumanUsed(at: now.addingTimeInterval(1))
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
        _ = metadata.migrateToCurrentSeenTracking(at: now)
        _ = metadata.markSeenBaseline(at: now.addingTimeInterval(-120))
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
        lastHumanUsedAgo: TimeInterval? = nil,
        lastAgentActiveAgo: TimeInterval? = nil
    ) -> HolySessionAttentionKind {
        decision(
            lifecycle: lifecycle,
            lifecycleOccurredAt: occurredAgo.map { now.addingTimeInterval(-$0) },
            processExited: processExited,
            lastFinishedAt: lastFinishedAt,
            lastSeenAt: lastSeenAt,
            lastHumanUsedAt: lastHumanUsedAgo.map { now.addingTimeInterval(-$0) },
            lastAgentActiveAt: lastAgentActiveAgo.map { now.addingTimeInterval(-$0) }
        ).kind
    }

    private func decision(
        lifecycle: HolyAgentLifecycleState? = nil,
        lifecycleOccurredAt: Date? = nil,
        processExited: Bool = false,
        lastFinishedAt: Date? = nil,
        lastSeenAt: Date? = nil,
        lastHumanUsedAt: Date? = nil,
        lastAgentActiveAt: Date? = nil
    ) -> HolySessionIndicatorDecision {
        HolySessionIndicatorPolicy.decision(for: .init(
            lifecycle: lifecycle,
            lifecycleOccurredAt: lifecycleOccurredAt,
            processExited: processExited,
            lastAgentFinishedAt: lastFinishedAt,
            lastSeenAt: lastSeenAt,
            lastHumanUsedAt: lastHumanUsedAt,
            lastAgentActiveAt: lastAgentActiveAt,
            now: now
        ))
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

    // Marking unread must not fabricate either recency clock, so the tier dot
    // underneath the green pip remains honest.
    @Test func markUnreadDoesNotBumpRecencyClocks() {
        let humanUsed = now.addingTimeInterval(-3_600)
        let agentActive = now.addingTimeInterval(-1_800)
        var metadata = HolySessionAttentionMetadata(
            sessionID: UUID(),
            lastSeenAt: now,
            lastAgentFinishedAt: now.addingTimeInterval(-60),
            lastHumanUsedAt: humanUsed,
            lastAgentActiveAt: agentActive,
            updatedAt: now
        )
        let didMark = metadata.markUnread(at: now.addingTimeInterval(5))
        #expect(didMark)
        #expect(metadata.lastHumanUsedAt == humanUsed)
        #expect(metadata.lastAgentActiveAt == agentActive)
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

    private struct LegacyAttentionMetadata: Encodable {
        let sessionID: UUID
        let lastSeenAt: Date?
        let lastAgentFinishedAt: Date?
        let seenTrackingVersion: Int?
        let lastUsedAt: Date?
        let updatedAt: Date
    }
}
