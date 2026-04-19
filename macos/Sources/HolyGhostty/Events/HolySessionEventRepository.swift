import Foundation
import SQLite3

enum HolySessionEventRepository {
    static func recentEvents(for sessionID: UUID, limit: Int = 12) throws -> [HolySessionTimelineEvent] {
        let database = try HolyDatabase.openAppDatabase(readOnly: true)
        return try recentEvents(for: sessionID, limit: limit, in: database)
    }

    static func append(_ events: [HolySessionEventDraft], in database: HolyDatabase) throws {
        guard !events.isEmpty else { return }

        var nextSequenceBySessionID: [UUID: Int64] = [:]
        for sessionID in Set(events.map(\.sessionID)) {
            nextSequenceBySessionID[sessionID] = try nextSequence(for: sessionID, in: database)
        }

        let sql = """
        INSERT INTO session_events (
            session_id, sequence, occurred_at, event_type, phase, attention, payload_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?);
        """

        for event in events {
            let nextSequence = nextSequenceBySessionID[event.sessionID] ?? 1

            try database.execute(sql, bindings: [
                .text(event.sessionID.uuidString),
                .int64(nextSequence),
                .text(HolyPersistenceCoders.string(from: event.occurredAt)),
                .text(event.eventType.rawValue),
                binding(for: event.phase?.rawValue),
                binding(for: event.attention?.rawValue),
                binding(for: try encodeOptionalJSON(event.payload)),
            ])

            nextSequenceBySessionID[event.sessionID] = nextSequence + 1
        }
    }

    private static func nextSequence(for sessionID: UUID, in database: HolyDatabase) throws -> Int64 {
        let sql = """
        SELECT COALESCE(MAX(sequence), 0)
        FROM session_events
        WHERE session_id = ?;
        """

        var sequence: Int64 = 0
        try database.query(sql, bindings: [.text(sessionID.uuidString)]) { statement in
            sequence = sqlite3_column_int64(statement, 0)
        }
        return sequence + 1
    }

    private static func recentEvents(
        for sessionID: UUID,
        limit: Int,
        in database: HolyDatabase
    ) throws -> [HolySessionTimelineEvent] {
        let sql = """
        SELECT session_id, sequence, occurred_at, event_type, phase, attention, payload_json
        FROM session_events
        WHERE session_id = ?
        ORDER BY sequence DESC
        LIMIT ?;
        """

        var events: [HolySessionTimelineEvent] = []
        try database.query(
            sql,
            bindings: [.text(sessionID.uuidString), .int64(Int64(limit))]
        ) { statement in
            let eventSessionID = try uuidColumn(statement, index: 0)
            let sequence = sqlite3_column_int64(statement, 1)
            let occurredAt = try HolyPersistenceCoders.date(from: requiredTextColumn(statement, index: 2))
            let eventTypeRaw = try requiredTextColumn(statement, index: 3)
            guard let eventType = HolySessionEventType(rawValue: eventTypeRaw) else {
                throw CocoaError(.coderInvalidValue)
            }

            let phase = textColumn(statement, index: 4).flatMap(HolySessionPhase.init(rawValue:))
            let attention = textColumn(statement, index: 5).flatMap(HolySessionAttention.init(rawValue:))
            let payload: HolySessionEventPayload? = try decodeOptionalJSON(
                HolySessionEventPayload.self,
                from: textColumn(statement, index: 6)
            )

            events.append(
                .init(
                    sessionID: eventSessionID,
                    sequence: sequence,
                    occurredAt: occurredAt,
                    eventType: eventType,
                    phase: phase,
                    attention: attention,
                    payload: payload
                )
            )
        }

        return events
    }

    private static func encodeOptionalJSON<T: Encodable>(_ value: T?) throws -> String? {
        guard let value else { return nil }
        return try HolyPersistenceCoders.encodeJSON(value)
    }

    private static func decodeOptionalJSON<T: Decodable>(_ type: T.Type, from json: String?) throws -> T? {
        guard let json else { return nil }
        return try HolyPersistenceCoders.decodeJSON(T.self, from: json)
    }

    private static func requiredTextColumn(_ statement: OpaquePointer, index: Int32) throws -> String {
        guard let value = sqlite3_column_text(statement, index) else {
            throw CocoaError(.coderValueNotFound)
        }
        return String(cString: value)
    }

    private static func textColumn(_ statement: OpaquePointer, index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    private static func uuidColumn(_ statement: OpaquePointer, index: Int32) throws -> UUID {
        let value = try requiredTextColumn(statement, index: index)
        guard let uuid = UUID(uuidString: value) else {
            throw CocoaError(.coderInvalidValue)
        }
        return uuid
    }

    private static func binding(for string: String?) -> HolyDatabaseBinding {
        guard let string else { return .null }
        return .text(string)
    }
}
