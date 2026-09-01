import Foundation
import Testing
@testable import Ghostty

struct HolyAlertPersistenceTests {
    private func withMigratedStore(
        _ body: (HolyInboxAlertStore, HolyDatabase) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-alert-persistence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databaseURL = directory.appendingPathComponent("holy.sqlite3")
        let database = try HolyDatabase.open(at: databaseURL)
        try HolyDatabaseMigrator.migrate(database)
        try body(HolyInboxAlertStore(databaseURL: databaseURL), database)
    }

    @Test func notificationDeliveryStillLandsInAlertsHistory() throws {
        try withMigratedStore { store, database in
            let deliveredAt = Date(timeIntervalSince1970: 1_785_000_000)
            #expect(store.recordDelivery(
                sessionID: nil,
                alertType: "budget_warning",
                severity: "warning",
                title: "Budget nearing limit",
                body: "80% consumed",
                deliveredAt: deliveredAt
            ))

            let count = try database.scalarInt64("SELECT COUNT(*) FROM alerts;")
            let title = try database.scalarText("SELECT title FROM alerts;")
            let body = try database.scalarText("SELECT body FROM alerts;")
            let persistedAt = try database.scalarText("SELECT delivered_at FROM alerts;")
            #expect(count == 1)
            #expect(title == "Budget nearing limit")
            #expect(body == "80% consumed")
            #expect(persistedAt == HolyPersistenceCoders.string(from: deliveredAt))
        }
    }

    @Test func unknownSessionFallsBackToUnlinkedHistory() throws {
        try withMigratedStore { store, database in
            #expect(store.recordDelivery(
                sessionID: UUID(),
                alertType: "ownership_drift",
                severity: "critical",
                title: "Branch ownership drift",
                body: "detail"
            ))

            let total = try database.scalarInt64("SELECT COUNT(*) FROM alerts;")
            let unlinked = try database.scalarInt64(
                "SELECT COUNT(*) FROM alerts WHERE session_id IS NULL;"
            )
            #expect(total == 1)
            #expect(unlinked == 1)
        }
    }

    @Test func retiredTypeSweepKeepsHistoryAndTouchesOnlyThatType() throws {
        try withMigratedStore { store, database in
            for (index, type) in ["collision", "collision", "budget_warning"].enumerated() {
                #expect(store.recordDelivery(
                    sessionID: nil,
                    alertType: type,
                    severity: "warning",
                    title: "\(type) \(index)",
                    body: ""
                ))
            }

            store.acknowledgeAll(ofType: "collision")

            let total = try database.scalarInt64("SELECT COUNT(*) FROM alerts;")
            let acknowledgedCollisions = try database.scalarInt64(
                "SELECT COUNT(*) FROM alerts WHERE alert_type = 'collision' AND acknowledged_at IS NOT NULL;"
            )
            let pendingWarnings = try database.scalarInt64(
                "SELECT COUNT(*) FROM alerts WHERE alert_type = 'budget_warning' AND acknowledged_at IS NULL;"
            )
            #expect(total == 3)
            #expect(acknowledgedCollisions == 2)
            #expect(pendingWarnings == 1)
        }
    }
}
