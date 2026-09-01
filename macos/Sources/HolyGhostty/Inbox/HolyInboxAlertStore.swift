import Foundation
import OSLog

/// Best-effort delivery ledger for the alerts table. Notifications remain the
/// user-facing surface; the table preserves history and retired-type cleanup.
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
                    Self.logger.error("Failed to record alert delivery unlinked: \(error.localizedDescription, privacy: .public)")
                    return false
                }
            }
            Self.logger.error("Failed to record alert delivery: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Bulk-acknowledge every unacknowledged delivery of one retired alert
    /// type. Records stay because the delivery ledger is historical.
    func acknowledgeAll(ofType alertType: String, at date: Date = .now) {
        do {
            let database = try HolyDatabase.open(at: databaseURL)
            try database.execute(
                "UPDATE alerts SET acknowledged_at = ? WHERE alert_type = ? AND acknowledged_at IS NULL;",
                bindings: [
                    .text(HolyPersistenceCoders.string(from: date)),
                    .text(alertType),
                ]
            )
        } catch {
            Self.logger.error(
                "Alert backlog sweep for \(alertType, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
