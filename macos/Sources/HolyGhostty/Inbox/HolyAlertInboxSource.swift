import Foundation

/// The in-app surface for the alerts table. Rows are unacknowledged alert
/// deliveries; the acknowledge affordance writes acknowledged_at and the row
/// leaves on the next refresh (the Row Law, database edition). Clicking an
/// alert selects its owning session in the roster.
final class HolyAlertInboxSource: HolyInboxRowSource {
    private static let sectionSourceID = "alerts"
    private static let rowIDPrefix = "alerts:"

    let sourceID = HolyAlertInboxSource.sectionSourceID

    private let store: HolyInboxAlertStore

    init(store: HolyInboxAlertStore = HolyInboxAlertStore()) {
        self.store = store
    }

    func refresh(context: HolyInboxRefreshContext) async -> HolyInboxSourceSnapshot {
        let records: [HolyInboxAlertRecord]
        do {
            records = try store.unacknowledged()
        } catch {
            return HolyInboxSourceSnapshot(sections: [
                HolyInboxSection(
                    id: "alerts.degraded",
                    sourceID: sourceID,
                    title: "Alerts",
                    rows: [
                        HolyInboxRow(
                            id: "alerts:degraded",
                            title: "Alerts unavailable",
                            subtitle: error.localizedDescription,
                            isDegraded: true
                        ),
                    ]
                ),
            ])
        }

        guard !records.isEmpty else { return .empty }

        return HolyInboxSourceSnapshot(sections: [
            HolyInboxSection(
                id: "alerts",
                sourceID: sourceID,
                title: "Alerts",
                rows: Self.rows(for: records),
                countsTowardBadge: true
            ),
        ])
    }

    func acknowledge(rowID: String) async {
        guard rowID.hasPrefix(Self.rowIDPrefix),
              let id = Int64(rowID.dropFirst(Self.rowIDPrefix.count)) else {
            return
        }
        try? store.acknowledge(id: id)
    }

    static func rows(for records: [HolyInboxAlertRecord]) -> [HolyInboxRow] {
        records.map { record in
            HolyInboxRow(
                id: "\(rowIDPrefix)\(record.id)",
                title: record.title,
                subtitle: record.body,
                updatedAt: record.deliveredAt,
                chips: [severityChip(for: record.severity)],
                action: record.sessionID.map(HolyInboxRowAction.selectSession) ?? .none,
                acknowledgeable: true
            )
        }
    }

    private static func severityChip(for severity: String) -> HolyInboxChip {
        switch severity {
        case "critical":
            return HolyInboxChip("critical", emphasis: .danger)
        case "warning":
            return HolyInboxChip("warning", emphasis: .warning)
        default:
            return HolyInboxChip(severity, emphasis: .neutral)
        }
    }
}
