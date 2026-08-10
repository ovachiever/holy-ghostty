import Foundation
import SQLite3
import Testing
@testable import Ghostty

// The alerts table (HolyDatabaseMigrator, alerts schema) finally gets its
// in-app surface. Lifecycle law: a delivered alert is a row until Erik
// acknowledges it; acknowledge writes acknowledged_at and the row leaves the
// pane on the next refresh. Nothing here is local dismissed-state — the
// database is the truth the source re-states.
struct HolyInboxRowLifecycleTests {
    private func makeMigratedStore() throws -> HolyInboxAlertStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-inbox-lifecycle-\(UUID().uuidString).sqlite3")
        let database = try HolyDatabase.open(at: url)
        try HolyDatabaseMigrator.migrate(database)
        return HolyInboxAlertStore(databaseURL: url)
    }

    // MARK: - Store lifecycle

    @Test func deliveryAppearsUnacknowledgedNewestFirst() throws {
        let store = try makeMigratedStore()
        let earlier = Date(timeIntervalSince1970: 1_785_000_000)
        let later = Date(timeIntervalSince1970: 1_785_000_100)

        #expect(store.recordDelivery(
            sessionID: nil,
            alertType: "collision",
            severity: "critical",
            title: "Session collision detected",
            body: "Two sessions share a worktree",
            deliveredAt: earlier
        ))
        #expect(store.recordDelivery(
            sessionID: nil,
            alertType: "budget_warning",
            severity: "warning",
            title: "Budget nearing limit",
            body: "80% consumed",
            deliveredAt: later
        ))

        let records = try store.unacknowledged()
        #expect(records.count == 2)
        #expect(records[0].title == "Budget nearing limit")
        #expect(records[1].title == "Session collision detected")
        #expect(records[1].alertType == "collision")
        #expect(records[1].severity == "critical")
        #expect(records[1].body == "Two sessions share a worktree")
        #expect(records[1].sessionID == nil)
        #expect(abs(records[1].deliveredAt.timeIntervalSince(earlier)) < 0.01)
    }

    @Test func retiredTypeSweepAcknowledgesOnlyThatTypeAndKeepsHistory() throws {
        let store = try makeMigratedStore()
        for (index, type) in ["collision", "collision", "budget_warning"].enumerated() {
            #expect(store.recordDelivery(
                sessionID: nil,
                alertType: type,
                severity: "warning",
                title: "\(type) \(index)",
                body: "",
                deliveredAt: Date(timeIntervalSince1970: 1_785_000_000 + Double(index))
            ))
        }

        store.acknowledgeAll(ofType: "collision")

        let remaining = try store.unacknowledged()
        #expect(remaining.count == 1)
        #expect(remaining[0].alertType == "budget_warning")

        // Idempotent: a second sweep changes nothing.
        store.acknowledgeAll(ofType: "collision")
        #expect(try store.unacknowledged().count == 1)
    }

    @Test func acknowledgeClearsTheRowAndWritesAcknowledgedAt() throws {
        let store = try makeMigratedStore()
        #expect(store.recordDelivery(
            sessionID: nil,
            alertType: "collision",
            severity: "critical",
            title: "Session collision detected",
            body: "detail"
        ))

        let id = try #require(try store.unacknowledged().first?.id)
        try store.acknowledge(id: id)

        #expect(try store.unacknowledged().isEmpty)

        // acknowledged_at is written, not deleted-and-forgotten: the record
        // stays for history, it just leaves the pane.
        let database = try HolyDatabase.open(at: store.databaseURL, readOnly: true)
        var acknowledgedAt: String?
        try database.query(
            "SELECT acknowledged_at FROM alerts WHERE id = ?;",
            bindings: [.int64(id)]
        ) { statement in
            acknowledgedAt = sqlite3_column_text(statement, 0).map { String(cString: $0) }
        }
        #expect(acknowledgedAt?.isEmpty == false)
    }

    @Test func unknownSessionFallsBackToUnlinkedDelivery() throws {
        // foreign_keys is ON; a session that never reached the sessions table
        // must not lose the alert — it lands unlinked instead.
        let store = try makeMigratedStore()
        #expect(store.recordDelivery(
            sessionID: UUID(),
            alertType: "ownership_drift",
            severity: "critical",
            title: "Branch ownership drift",
            body: "detail"
        ))

        let records = try store.unacknowledged()
        #expect(records.count == 1)
        #expect(records[0].sessionID == nil)
    }

    // MARK: - Source snapshot

    @Test func sourceMapsRecordsToAcknowledgeableSessionLinkedRows() {
        let sessionID = UUID()
        let rows = HolyAlertInboxSource.rows(for: [
            HolyInboxAlertRecord(
                id: 12,
                sessionID: sessionID,
                alertType: "collision",
                severity: "critical",
                title: "Session collision detected",
                body: "Two sessions share a worktree",
                deliveredAt: Date(timeIntervalSince1970: 1_785_000_000)
            ),
        ])

        #expect(rows.count == 1)
        #expect(rows[0].id == "alerts:12")
        #expect(rows[0].title == "Session collision detected")
        #expect(rows[0].subtitle == "Two sessions share a worktree")
        #expect(rows[0].acknowledgeable == true)
        #expect(rows[0].action == .selectSession(sessionID))
        #expect(rows[0].chips.contains(HolyInboxChip("critical", emphasis: .danger)) == true)
    }

    @Test func sourceRefreshBuildsBadgeCountingSectionAndAcknowledgeClears() async throws {
        let store = try makeMigratedStore()
        #expect(store.recordDelivery(
            sessionID: nil,
            alertType: "budget_exceeded",
            severity: "critical",
            title: "Budget exceeded",
            body: "detail"
        ))

        let source = HolyAlertInboxSource(store: store)
        let snapshot = await source.refresh(context: HolyInboxRefreshContext())
        #expect(snapshot.sections.count == 1)
        #expect(snapshot.sections[0].id == "alerts")
        #expect(snapshot.sections[0].sourceID == "alerts")
        #expect(snapshot.sections[0].countsTowardBadge == true)
        #expect(snapshot.sections[0].rows.count == 1)

        // Acknowledge through the source's row id — the pane's affordance.
        await source.acknowledge(rowID: snapshot.sections[0].rows[0].id)
        let after = await source.refresh(context: HolyInboxRefreshContext())
        #expect(after.sections.isEmpty)
    }

    @Test func emptyTableIsEmptySnapshotNotDegradedRow() async throws {
        let store = try makeMigratedStore()
        let source = HolyAlertInboxSource(store: store)
        let snapshot = await source.refresh(context: HolyInboxRefreshContext())
        #expect(snapshot.sections.isEmpty)
    }

    @Test func brokenDatabaseDegradesQuietlyNeverCrashes() async {
        // A database that was never migrated has no alerts table: the source
        // reports itself unavailable instead of pretending the inbox is clear.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-inbox-unmigrated-\(UUID().uuidString).sqlite3")
        let source = HolyAlertInboxSource(store: HolyInboxAlertStore(databaseURL: url))

        let snapshot = await source.refresh(context: HolyInboxRefreshContext())
        #expect(snapshot.sections.count == 1)
        #expect(snapshot.sections[0].rows.count == 1)
        #expect(snapshot.sections[0].rows[0].isDegraded == true)
        #expect(snapshot.sections[0].rows[0].title == "Alerts unavailable")
        #expect(snapshot.sections[0].countsTowardBadge == false)
    }
}
