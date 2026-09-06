import Foundation
import Testing
@testable import Ghostty

struct HolyAgentStateEnvelopeTests {
    @Test func lifecycleHooksCaptureTheHarnessIdentityForEveryRuntime() throws {
        let cases: [(HolySessionRuntime, String, String)] = [
            (.claude, HolyAgentStateSource.claude, "3c15edbd-4860-45ef-a705-8d6f4916f911"),
            (.codex, HolyAgentStateSource.codex, "019f6280-5fc7-7093-a705-8d6f4916f911"),
            (.opencode, HolyAgentStateSource.openCode, "ses_4f2c67d0"),
        ]

        for (runtime, source, harnessSessionID) in cases {
            var launchSpec = HolySessionLaunchSpec.interactiveTmuxShell(title: runtime.displayName)
            launchSpec.runtime = runtime
            var record = HolySessionRecord(launchSpec: launchSpec)
            let envelope = try HolyAgentStateEnvelope(
                source: source,
                lifecycle: .working,
                occurredAtMilliseconds: 1_752_500_123_456,
                eventToken: "capture-\(source)",
                sessionID: harnessSessionID,
                reasonCode: "user-prompt"
            )

            let captured = record.captureHarnessSessionIdentity(from: envelope)
            #expect(captured)
            #expect(record.harnessSessionID == harnessSessionID)
            #expect(
                record.launchSpec.providerSessionID
                    == (runtime == .claude ? harnessSessionID : nil)
            )
            let recaptured = record.captureHarnessSessionIdentity(from: envelope)
            #expect(!recaptured)
        }
    }

    @Test func syntheticCodexTurnTokenCannotReplaceTheHookSessionIdentity() throws {
        var launchSpec = HolySessionLaunchSpec.interactiveTmuxShell(title: "Codex")
        launchSpec.runtime = .codex
        var record = HolySessionRecord(
            launchSpec: launchSpec,
            harnessSessionID: "019f6280-5fc7-7093-a705-8d6f4916f911"
        )
        let notification = try HolyAgentStateEnvelope(
            source: HolyAgentStateSource.codex,
            lifecycle: .finished,
            occurredAtMilliseconds: 1_752_500_123_457,
            eventToken: "notify-turn",
            sessionID: "thread-42:turn-7",
            reasonCode: "turn-finished"
        )

        let captured = record.captureHarnessSessionIdentity(from: notification)
        #expect(!captured)
        #expect(record.harnessSessionID == "019f6280-5fc7-7093-a705-8d6f4916f911")
    }

    @Test func sharedIdentityJoinResolvesRosterClaimantCoordArchiveAndRestore() throws {
        let harnessSessionID = "3C15EDBD-4860-45EF-A705-8D6F4916F911"
        let rosterRow = HolySessionRecord(
            launchSpec: .interactiveTmuxShell(title: "Keystone"),
            harnessSessionID: harnessSessionID
        )
        let unrelatedRow = HolySessionRecord(
            launchSpec: .interactiveTmuxShell(title: "Other"),
            harnessSessionID: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
        )
        let rows = [rosterRow, unrelatedRow]
        let mannaClaimant = "claude-3c15edbd486045ef"
        let coordPeer = "session-3c15edbd4860"
        let archiveTranscript = harnessSessionID.lowercased()
        let restoreTarget = harnessSessionID

        for identity in [mannaClaimant, coordPeer, archiveTranscript, restoreTarget] {
            let match = HolyHarnessSessionIdentity.uniqueMatch(
                for: identity,
                in: rows,
                identityOf: \.effectiveHarnessSessionID
            )
            #expect(match?.id == rosterRow.id)
            #expect(rosterRow.matchesHarnessSessionIdentity(identity))
        }

        #expect(HolyHarnessSessionIdentity.matches(mannaClaimant, coordPeer))
        #expect(!HolyHarnessSessionIdentity.matches(mannaClaimant, "session-ffffffffffff"))
        #expect(!HolyHarnessSessionIdentity.matches("session-ab", "claude-ab"))

        let prefixCollision = HolySessionRecord(
            launchSpec: .interactiveTmuxShell(title: "Collision"),
            harnessSessionID: "3c15edbd-4860-ffff-b111-222222222222"
        )
        #expect(
            HolyHarnessSessionIdentity.uniqueMatch(
                for: coordPeer,
                in: [rosterRow, prefixCollision],
                identityOf: \.effectiveHarnessSessionID
            ) == nil
        )
    }

    @Test func wireValueRoundTripsWithoutTranscriptText() throws {
        let envelope = try HolyAgentStateEnvelope(
            source: "future-harness.v2",
            lifecycle: .needsUser,
            occurredAtMilliseconds: 1_752_500_123_456,
            eventToken: "1752500123456-42",
            sessionID: "session-abc/child:1",
            reasonCode: "permission"
        )

        #expect(
            envelope.wireValue
                == "v1|future-harness.v2|needs-user|1752500123456|1752500123456-42|session-abc/child:1|permission"
        )
        #expect(try HolyAgentStateEnvelope(wireValue: envelope.wireValue) == envelope)
        #expect(envelope.source == "future-harness.v2")
        #expect(envelope.lifecycle == .needsUser)
    }

    @Test func parserRejectsUnknownVersionsAndLifecycleValues() {
        expectEnvelopeError(.unsupportedVersion("v2")) {
            try HolyAgentStateEnvelope(
                wireValue: "v2|codex|working|1752500123456|event-1||user-prompt"
            )
        }
        expectEnvelopeError(.invalidLifecycle("thinking")) {
            try HolyAgentStateEnvelope(
                wireValue: "v1|codex|thinking|1752500123456|event-1||user-prompt"
            )
        }
    }

    @Test func parserFailsClosedOnSeparatorsControlsAndProse() {
        expectEnvelopeError(.invalidFieldCount) {
            try HolyAgentStateEnvelope(
                wireValue: "v1|codex|working|1752500123456|event-1||user|prompt"
            )
        }
        expectEnvelopeError(.invalidReasonCode) {
            try HolyAgentStateEnvelope(
                wireValue: "v1|codex|working|1752500123456|event-1||user prompt"
            )
        }
        expectEnvelopeError(.invalidSource) {
            try HolyAgentStateEnvelope(
                wireValue: "v1|codex\u{1B}|working|1752500123456|event-1||user-prompt"
            )
        }
        expectEnvelopeError(.invalidTimestamp) {
            try HolyAgentStateEnvelope(
                wireValue: "v1|codex|working|-1|event-1||user-prompt"
            )
        }
    }

    @Test func parserCapsTheEntireTransportValue() {
        let oversized = "v1|codex|working|1752500123456|"
            + String(repeating: "a", count: HolyAgentStateEnvelope.maximumWireLength)
            + "||"
        expectEnvelopeError(.wireValueTooLong) {
            try HolyAgentStateEnvelope(wireValue: oversized)
        }
    }

    @Test func orderingRejectsDuplicatesAndOlderDeliveries() throws {
        let first = try envelope(timestamp: 100, token: "100-1")
        let duplicate = try HolyAgentStateEnvelope(wireValue: first.wireValue)
        let sameTimeLaterToken = try envelope(timestamp: 100, token: "100-2")
        let later = try envelope(timestamp: 101, token: "101-1")

        #expect(duplicate.isDuplicate(of: first))
        #expect(!duplicate.isNewer(than: first))
        #expect(sameTimeLaterToken.isNewer(than: first))
        #expect(later.isNewer(than: sameTimeLaterToken))
        #expect(!first.isNewer(than: later))
        #expect(HolyAgentStateEnvelope.monotonicTimestamp(nowMilliseconds: 99, after: later) == 102)
        #expect(HolyAgentStateEnvelope.monotonicTimestamp(nowMilliseconds: 200, after: later) == 200)
    }

    @Test func identifiedWireShapeSupersedesNewerLegacyTimestamp() throws {
        let legacy = try envelope(timestamp: 101, token: "legacy")
        let identified = try envelope(
            timestamp: 100,
            token: "identified",
            sessionID: "0b15c3a3-1d98-4498-96fd-a6dc20d4a521"
        )

        #expect(identified.isNewer(than: legacy))
        #expect(!legacy.isNewer(than: identified))
    }

    @Test func transportUsesReservedOSC777TitleAndTmuxOption() throws {
        let envelope = try envelope(timestamp: 1_752_500_123_456, token: "event-1")
        let sequence = HolyAgentStateTransport.osc777Sequence(for: envelope)

        #expect(HolyAgentStateTransport.tmuxOption == "@holy_agent_state_v1")
        #expect(HolyAgentStateTransport.tmuxLastFinishedOption == "@holy_agent_last_finished_v1")
        #expect(HolyAgentStateTransport.tmuxLastUsedOption == "@holy_agent_last_used_v1")
        #expect(HolyAgentStateTransport.tmuxSeenOption == "@holy_seen_v1")
        #expect(HolyAgentStateTransport.tmuxOwnershipOption == "@holy_agent_state_owner_v1")
        #expect(HolyAgentStateTransport.tmuxOwnershipValue == "holy")
        #expect(HolyAgentStateTransport.notificationTitle == "com.holyghostty.agent-state.v1")
        #expect(
            sequence
                == "\u{1B}]777;notify;com.holyghostty.agent-state.v1;\(envelope.wireValue)\u{7}"
        )
        #expect(
            try HolyAgentStateTransport.envelope(
                notificationTitle: HolyAgentStateTransport.notificationTitle,
                body: envelope.wireValue
            ) == envelope
        )
        expectEnvelopeError(.unexpectedNotificationTitle("other")) {
            try HolyAgentStateTransport.envelope(
                notificationTitle: "other",
                body: envelope.wireValue
            )
        }
    }

    @Test func sharedSeenStateRoundTripsAnEventWatermarkAndExplicitUnreadTombstone() throws {
        let firstSeen = try #require(HolyAgentSeenState.seen(
            acknowledgingEventAtMilliseconds: 1_752_500_123_456,
            at: Date(timeIntervalSince1970: 1_752_500_124),
            after: nil
        ))
        #expect(firstSeen.wireValue == "v1|seen|1752500123456|1752500124000")
        #expect(try HolyAgentSeenState(wireValue: firstSeen.wireValue) == firstSeen)
        #expect(firstSeen.acknowledges(eventAtMilliseconds: 1_752_500_123_456))
        #expect(!firstSeen.acknowledges(eventAtMilliseconds: 1_752_500_123_457))
        let finished = try HolyAgentStateEnvelope(
            source: "claude",
            lifecycle: .finished,
            occurredAtMilliseconds: 1_752_500_123_456,
            eventToken: "finish-1"
        )
        let question = try HolyAgentStateEnvelope(
            source: "claude",
            lifecycle: .needsUser,
            occurredAtMilliseconds: 1_752_500_123_456,
            eventToken: "question-1",
            reasonCode: "permission"
        )
        #expect(firstSeen.acknowledgesNotification(for: finished))
        #expect(!firstSeen.acknowledgesNotification(for: question))
        let failed = try HolyAgentStateEnvelope(
            source: "claude",
            lifecycle: .failed,
            occurredAtMilliseconds: 1_752_500_123_456,
            eventToken: "failed-1"
        )
        #expect(firstSeen.acknowledgesNotification(for: failed))

        let unread = try #require(HolyAgentSeenState.unread(
            at: Date(timeIntervalSince1970: 1_752_500_123),
            after: firstSeen
        ))
        #expect(unread.wireValue == "v1|unread||1752500124001")
        #expect(try HolyAgentSeenState(wireValue: unread.wireValue) == unread)
        #expect(unread.seenAt == nil)
        #expect(!unread.acknowledges(eventAtMilliseconds: 1))
        #expect(unread.isNewer(than: firstSeen))

        let tiedSeen = try HolyAgentSeenState(
            wireValue: "v1|seen|1752500123456|1752500124001"
        )
        #expect(unread.isNewer(than: tiedSeen))
        #expect(!tiedSeen.isNewer(than: unread))
    }

    @Test func sharedSeenStateFailsClosedOnMalformedOrContradictoryValues() {
        expectSeenStateError(.unsupportedVersion("v2")) {
            try HolyAgentSeenState(wireValue: "v2|seen|1752500123456|1752500124000")
        }
        expectSeenStateError(.invalidAcknowledgedTimestamp) {
            try HolyAgentSeenState(wireValue: "v1|seen||1752500124000")
        }
        expectSeenStateError(.invalidAcknowledgedTimestamp) {
            try HolyAgentSeenState(wireValue: "v1|unread|1752500123456|1752500124000")
        }
        expectSeenStateError(.invalidChangedTimestamp) {
            try HolyAgentSeenState(wireValue: "v1|seen|1752500124001|1752500124000")
        }
        expectSeenStateError(.invalidChangedTimestamp) {
            try HolyAgentSeenState(wireValue: "v1|unread||not-a-time")
        }
        expectSeenStateError(.invalidDisposition("maybe")) {
            try HolyAgentSeenState(wireValue: "v1|maybe||1752500124000")
        }
    }

    private func envelope(
        timestamp: Int64,
        token: String,
        sessionID: String? = nil
    ) throws -> HolyAgentStateEnvelope {
        try HolyAgentStateEnvelope(
            source: HolyAgentStateSource.codex,
            lifecycle: .finished,
            occurredAtMilliseconds: timestamp,
            eventToken: token,
            sessionID: sessionID,
            reasonCode: "turn-finished"
        )
    }

    private func expectEnvelopeError<Result>(
        _ expected: HolyAgentStateEnvelopeError,
        operation: () throws -> Result
    ) {
        do {
            _ = try operation()
            Issue.record("Expected agent-state envelope parsing to fail")
        } catch let error as HolyAgentStateEnvelopeError {
            #expect(error == expected)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func expectSeenStateError<Result>(
        _ expected: HolyAgentSeenStateError,
        operation: () throws -> Result
    ) {
        do {
            _ = try operation()
            Issue.record("Expected shared seen-state parsing to fail")
        } catch let error as HolyAgentSeenStateError {
            #expect(error == expected)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
