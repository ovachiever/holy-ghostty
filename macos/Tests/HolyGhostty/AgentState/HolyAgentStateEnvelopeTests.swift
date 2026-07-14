import Foundation
import Testing
@testable import Ghostty

struct HolyAgentStateEnvelopeTests {
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

    @Test func transportUsesReservedOSC777TitleAndTmuxOption() throws {
        let envelope = try envelope(timestamp: 1_752_500_123_456, token: "event-1")
        let sequence = HolyAgentStateTransport.osc777Sequence(for: envelope)

        #expect(HolyAgentStateTransport.tmuxOption == "@holy_agent_state_v1")
        #expect(HolyAgentStateTransport.tmuxLastFinishedOption == "@holy_agent_last_finished_v1")
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

    private func envelope(
        timestamp: Int64,
        token: String
    ) throws -> HolyAgentStateEnvelope {
        try HolyAgentStateEnvelope(
            source: HolyAgentStateSource.codex,
            lifecycle: .finished,
            occurredAtMilliseconds: timestamp,
            eventToken: token,
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
}
