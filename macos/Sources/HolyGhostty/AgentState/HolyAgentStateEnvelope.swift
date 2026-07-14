import Foundation

/// The small lifecycle vocabulary that agent harnesses may publish to Holy.
///
/// This deliberately describes lifecycle facts, not rendered roster states.
/// Unread and recency are derived locally from these facts plus Holy's own
/// seen timestamps.
enum HolyAgentLifecycleState: String, Codable, CaseIterable, Sendable {
    case working
    case needsUser = "needs-user"
    case finished
    case failed
    case idle
    case ended
}

/// Stable names for adapters Holy ships. `HolyAgentStateEnvelope.source`
/// remains an open string so a future harness does not require a wire-format
/// migration.
enum HolyAgentStateSource {
    static let claude = "claude"
    static let codex = "codex"
    static let openCode = "opencode"
}

enum HolyAgentStateEnvelopeError: Error, Equatable, LocalizedError {
    case wireValueTooLong
    case invalidFieldCount
    case unsupportedVersion(String)
    case invalidSource
    case invalidLifecycle(String)
    case invalidTimestamp
    case invalidEventToken
    case invalidSessionID
    case invalidReasonCode
    case unexpectedNotificationTitle(String)

    var errorDescription: String? {
        switch self {
        case .wireValueTooLong:
            "Agent-state metadata exceeds its size limit"
        case .invalidFieldCount:
            "Agent-state metadata has the wrong number of fields"
        case let .unsupportedVersion(version):
            "Unsupported agent-state metadata version: \(version)"
        case .invalidSource:
            "Agent-state metadata has an invalid source"
        case let .invalidLifecycle(value):
            "Agent-state metadata has an invalid lifecycle value: \(value)"
        case .invalidTimestamp:
            "Agent-state metadata has an invalid timestamp"
        case .invalidEventToken:
            "Agent-state metadata has an invalid event token"
        case .invalidSessionID:
            "Agent-state metadata has an invalid session ID"
        case .invalidReasonCode:
            "Agent-state metadata has an invalid reason code"
        case let .unexpectedNotificationTitle(title):
            "Unexpected agent-state notification title: \(title)"
        }
    }
}

/// Versioned, text-free lifecycle metadata published by a harness.
///
/// The wire representation is intentionally tiny and restricted to printable
/// ASCII so it is safe to carry in both a pane-scoped tmux option and an OSC
/// notification without escaping or evaluating any field:
///
///     v1|source|lifecycle|epoch-ms|event-token|session-id|reason-code
///
/// The envelope never contains prompts, responses, terminal text, tool input,
/// or tool output.
struct HolyAgentStateEnvelope: Equatable, Sendable {
    static let currentVersion = 1
    static let maximumWireLength = 512

    let version: Int
    let source: String
    let lifecycle: HolyAgentLifecycleState
    let occurredAtMilliseconds: Int64
    let eventToken: String
    let sessionID: String?
    let reasonCode: String?

    /// `|` is excluded from metadata identifiers, so this pair cannot alias
    /// even when a future harness uses `:` in its source or token.
    var eventIdentity: String { "\(source)|\(eventToken)" }

    var occurredAt: Date {
        Date(timeIntervalSince1970: TimeInterval(occurredAtMilliseconds) / 1_000)
    }

    init(
        source: String,
        lifecycle: HolyAgentLifecycleState,
        occurredAtMilliseconds: Int64,
        eventToken: String,
        sessionID: String? = nil,
        reasonCode: String? = nil
    ) throws {
        try self.init(
            version: Self.currentVersion,
            source: source,
            lifecycle: lifecycle,
            occurredAtMilliseconds: occurredAtMilliseconds,
            eventToken: eventToken,
            sessionID: sessionID,
            reasonCode: reasonCode
        )
    }

    init(
        source: String,
        lifecycle: HolyAgentLifecycleState,
        occurredAt: Date,
        eventToken: String,
        sessionID: String? = nil,
        reasonCode: String? = nil
    ) throws {
        let milliseconds = occurredAt.timeIntervalSince1970 * 1_000
        guard milliseconds.isFinite,
              milliseconds >= 1,
              milliseconds <= Double(Int64.max) else {
            throw HolyAgentStateEnvelopeError.invalidTimestamp
        }
        try self.init(
            source: source,
            lifecycle: lifecycle,
            occurredAtMilliseconds: Int64(milliseconds.rounded(.down)),
            eventToken: eventToken,
            sessionID: sessionID,
            reasonCode: reasonCode
        )
    }

    init(wireValue: String) throws {
        guard wireValue.utf8.count <= Self.maximumWireLength else {
            throw HolyAgentStateEnvelopeError.wireValueTooLong
        }
        let fields = wireValue.split(separator: "|", omittingEmptySubsequences: false)
        guard fields.count == 7 else {
            throw HolyAgentStateEnvelopeError.invalidFieldCount
        }

        let versionField = String(fields[0])
        guard versionField == "v\(Self.currentVersion)" else {
            throw HolyAgentStateEnvelopeError.unsupportedVersion(versionField)
        }
        let source = String(fields[1])
        let lifecycleField = String(fields[2])
        guard let lifecycle = HolyAgentLifecycleState(rawValue: lifecycleField) else {
            throw HolyAgentStateEnvelopeError.invalidLifecycle(lifecycleField)
        }
        let timestampField = String(fields[3])
        guard Self.isUnsignedDecimal(timestampField),
              let timestamp = Int64(timestampField),
              timestamp > 0 else {
            throw HolyAgentStateEnvelopeError.invalidTimestamp
        }
        let eventToken = String(fields[4])
        let sessionID = fields[5].isEmpty ? nil : String(fields[5])
        let reasonCode = fields[6].isEmpty ? nil : String(fields[6])

        try self.init(
            version: Self.currentVersion,
            source: source,
            lifecycle: lifecycle,
            occurredAtMilliseconds: timestamp,
            eventToken: eventToken,
            sessionID: sessionID,
            reasonCode: reasonCode
        )
    }

    var wireValue: String {
        [
            "v\(version)",
            source,
            lifecycle.rawValue,
            String(occurredAtMilliseconds),
            eventToken,
            sessionID ?? "",
            reasonCode ?? "",
        ].joined(separator: "|")
    }

    /// Event identity is scoped to a source. This lets the OSC fast path and
    /// the later tmux discovery copy collapse to one lifecycle transition.
    func hasSameEventToken(as other: Self) -> Bool {
        source == other.source && eventToken == other.eventToken
    }

    /// A duplicate must also carry the same facts. A token collision with
    /// contradictory metadata therefore does not masquerade as a valid replay.
    func isDuplicate(of other: Self) -> Bool {
        hasSameEventToken(as: other) && self == other
    }

    /// Total order for consumer-side stale-event rejection. Generated hooks
    /// make pane timestamps monotonic; the token is a deterministic tie-break
    /// for independently delivered OSC and tmux copies of the same moment.
    func isNewer(than other: Self) -> Bool {
        if occurredAtMilliseconds != other.occurredAtMilliseconds {
            return occurredAtMilliseconds > other.occurredAtMilliseconds
        }
        if source != other.source {
            return source > other.source
        }
        if eventToken != other.eventToken {
            return eventToken > other.eventToken
        }
        return false
    }

    /// Advances a producer timestamp past the last pane value, protecting
    /// ordering when the wall clock stalls or moves backward.
    static func monotonicTimestamp(
        nowMilliseconds: Int64,
        after previous: Self?
    ) -> Int64 {
        guard let previous else { return max(1, nowMilliseconds) }
        guard previous.occurredAtMilliseconds < Int64.max else { return Int64.max }
        return max(max(1, nowMilliseconds), previous.occurredAtMilliseconds + 1)
    }

    private init(
        version: Int,
        source: String,
        lifecycle: HolyAgentLifecycleState,
        occurredAtMilliseconds: Int64,
        eventToken: String,
        sessionID: String?,
        reasonCode: String?
    ) throws {
        guard version == Self.currentVersion else {
            throw HolyAgentStateEnvelopeError.unsupportedVersion("v\(version)")
        }
        guard Self.isMetadataIdentifier(source, maximumLength: 48) else {
            throw HolyAgentStateEnvelopeError.invalidSource
        }
        guard occurredAtMilliseconds > 0 else {
            throw HolyAgentStateEnvelopeError.invalidTimestamp
        }
        guard Self.isMetadataIdentifier(eventToken, maximumLength: 96) else {
            throw HolyAgentStateEnvelopeError.invalidEventToken
        }
        if let sessionID,
           !Self.isMetadataIdentifier(sessionID, maximumLength: 128) {
            throw HolyAgentStateEnvelopeError.invalidSessionID
        }
        if let reasonCode,
           !Self.isMetadataIdentifier(reasonCode, maximumLength: 64) {
            throw HolyAgentStateEnvelopeError.invalidReasonCode
        }

        self.version = version
        self.source = source
        self.lifecycle = lifecycle
        self.occurredAtMilliseconds = occurredAtMilliseconds
        self.eventToken = eventToken
        self.sessionID = sessionID
        self.reasonCode = reasonCode

        guard wireValue.utf8.count <= Self.maximumWireLength else {
            throw HolyAgentStateEnvelopeError.wireValueTooLong
        }
    }

    /// Metadata fields use only an intentionally boring ASCII alphabet. That
    /// excludes separators, terminal controls, shell syntax, and prose.
    private static func isMetadataIdentifier(
        _ value: String,
        maximumLength: Int
    ) -> Bool {
        guard !value.isEmpty, value.utf8.count <= maximumLength else { return false }
        return value.utf8.allSatisfy { byte in
            switch byte {
            case 45, 46, 47, 48 ... 57, 58, 65 ... 90, 95, 97 ... 122:
                true
            default:
                false
            }
        }
    }

    private static func isUnsignedDecimal(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48 ... 57).contains($0) }
    }
}

enum HolyAgentStateTransport {
    static let notificationTitle = "com.holyghostty.agent-state.v1"
    static let tmuxOption = "@holy_agent_state_v1"
    /// A finish is durable independently of the latest lifecycle. Later
    /// working/idle/ended events must not erase evidence used to derive unread.
    static let tmuxLastFinishedOption = "@holy_agent_last_finished_v1"
    /// Explicit opt-in for adopted panes that did not originate from Holy's
    /// launch builder and therefore have no legacy `@holy_runtime` metadata.
    static let tmuxOwnershipOption = "@holy_agent_state_owner_v1"
    static let tmuxOwnershipValue = "holy"

    static func osc777Sequence(for envelope: HolyAgentStateEnvelope) -> String {
        "\u{1B}]777;notify;\(notificationTitle);\(envelope.wireValue)\u{7}"
    }

    static func envelope(
        notificationTitle title: String,
        body: String
    ) throws -> HolyAgentStateEnvelope {
        guard title == notificationTitle else {
            throw HolyAgentStateEnvelopeError.unexpectedNotificationTitle(title)
        }
        return try HolyAgentStateEnvelope(wireValue: body)
    }
}
