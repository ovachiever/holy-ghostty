import Foundation
import OSLog
import SQLite3

/// One delivered alert, read back from the alerts table.
struct HolyInboxAlertRecord: Equatable, Sendable, Identifiable {
    let id: Int64
    let sessionID: UUID?
    let alertType: String
    let severity: String
    let title: String
    let body: String
    let deliveredAt: Date
}

/// Read/write bridge to the alerts table (schema in HolyDatabaseMigrator).
/// Deliveries are recorded when the alert coordinator notifies; acknowledge
/// writes acknowledged_at and the row leaves the pane on the next refresh.
/// Records are never deleted here — history stays.
struct HolyInboxAlertStore: Sendable {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mitchellh.ghostty",
        category: "HolyInboxAlertStore"
    )

    let databaseURL: URL

    init(databaseURL: URL = HolyDatabasePaths.databaseURL) {
        self.databaseURL = databaseURL
    }

    /// Best-effort persistence beside the macOS notification: a failed write
    /// must never break alert delivery. foreign_keys is ON, so a session id
    /// missing from the sessions table falls back to an unlinked row rather
    /// than losing the alert.
    @discardableResult
    func recordDelivery(
        sessionID: UUID?,
        alertType: String,
        severity: String,
        title: String,
        body: String,
        deliveredAt: Date = .now
    ) -> Bool {
        let sql = """
        INSERT INTO alerts (session_id, alert_type, severity, title, body, delivered_at)
        VALUES (?, ?, ?, ?, ?, ?);
        """

        func insert(linkedTo sessionBinding: HolyDatabaseBinding) throws {
            let database = try HolyDatabase.open(at: databaseURL)
            try database.execute(sql, bindings: [
                sessionBinding,
                .text(alertType),
                .text(severity),
                .text(title),
                .text(body),
                .text(HolyPersistenceCoders.string(from: deliveredAt)),
            ])
        }

        do {
            try insert(linkedTo: sessionID.map { .text($0.uuidString) } ?? .null)
            return true
        } catch {
            if sessionID != nil {
                do {
                    try insert(linkedTo: .null)
                    return true
                } catch {
                    Self.logger.error("Failed to record inbox alert unlinked: \(error.localizedDescription, privacy: .public)")
                    return false
                }
            }
            Self.logger.error("Failed to record inbox alert: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Rows still owed to the human, newest delivery first.
    func unacknowledged() throws -> [HolyInboxAlertRecord] {
        let database = try HolyDatabase.open(at: databaseURL, readOnly: true)
        let sql = """
        SELECT id, session_id, alert_type, severity, title, body, delivered_at
        FROM alerts
        WHERE acknowledged_at IS NULL
        ORDER BY delivered_at DESC, id DESC;
        """

        var records: [HolyInboxAlertRecord] = []
        try database.query(sql) { statement in
            let sessionText = sqlite3_column_text(statement, 1).map { String(cString: $0) }
            let deliveredText = sqlite3_column_text(statement, 6).map { String(cString: $0) } ?? ""

            records.append(HolyInboxAlertRecord(
                id: sqlite3_column_int64(statement, 0),
                sessionID: sessionText.flatMap(UUID.init(uuidString:)),
                alertType: sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? "",
                severity: sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? "",
                title: sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? "",
                body: sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? "",
                deliveredAt: (try? HolyPersistenceCoders.date(from: deliveredText)) ?? .distantPast
            ))
        }
        return records
    }

    func acknowledge(id: Int64, at date: Date = .now) throws {
        let database = try HolyDatabase.open(at: databaseURL)
        try database.execute(
            "UPDATE alerts SET acknowledged_at = ? WHERE id = ? AND acknowledged_at IS NULL;",
            bindings: [
                .text(HolyPersistenceCoders.string(from: date)),
                .int64(id),
            ]
        )
    }
}
