import Foundation

/// One restore pass, as a durable receipt: when it ran, what asked for it,
/// which archives it touched, and what became of each. Erik restored about
/// 38 sessions on 2026-09-26 and Session History showed nothing of it; this
/// is the record that was missing.
struct HolyRestoreRunRecord: Codable, Equatable, Identifiable, Sendable {
    enum Trigger: String, Codable, Equatable, Sendable {
        case restoreAll
        case restoreSelected
        case restoreShutdownGroup
        case retry
        case attach

        var displayName: String {
            switch self {
            case .restoreAll: return "Restore All"
            case .restoreSelected: return "Restore Selected"
            case .restoreShutdownGroup: return "Restore this shutdown"
            case .retry: return "Retry"
            case .attach: return "Attach"
            }
        }
    }

    enum Outcome: Codable, Equatable, Sendable {
        case restored(attached: Bool)
        case failed(String)
        /// Not actionable when the pass ran (blocked, ambiguous, conflict,
        /// remote); the reason is the row's verdict at that moment.
        case skipped(String)

        var isRestored: Bool {
            if case .restored = self { return true }
            return false
        }

        var summary: String {
            switch self {
            case let .restored(attached):
                return attached ? "restored and attached" : "restored headless"
            case let .failed(reason):
                return "failed: \(reason)"
            case let .skipped(reason):
                return "skipped: \(reason)"
            }
        }
    }

    struct RowResult: Codable, Equatable, Identifiable, Sendable {
        let archiveID: UUID
        let sourceSessionID: UUID
        let title: String
        let runtime: String
        let workingDirectory: String?
        /// The exact conversation id the row resumed, when it was one.
        let providerSessionID: String?
        let outcome: Outcome

        var id: UUID { archiveID }
    }

    let id: UUID
    let startedAt: Date
    let finishedAt: Date
    let trigger: Trigger
    /// Whether the pass attached each verified session or left it headless.
    let attach: Bool
    let rows: [RowResult]

    init(
        id: UUID = UUID(),
        startedAt: Date,
        finishedAt: Date,
        trigger: Trigger,
        attach: Bool,
        rows: [RowResult]
    ) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.trigger = trigger
        self.attach = attach
        self.rows = rows
    }

    var requestedCount: Int { rows.count }
    var restoredCount: Int { rows.filter { $0.outcome.isRestored }.count }
    var attachedCount: Int {
        rows.filter { if case .restored(attached: true) = $0.outcome { return true } else { return false } }.count
    }
    var failedCount: Int {
        rows.filter { if case .failed = $0.outcome { return true } else { return false } }.count
    }
    var skippedCount: Int {
        rows.filter { if case .skipped = $0.outcome { return true } else { return false } }.count
    }
    var archiveIDs: [UUID] { rows.map(\.archiveID) }
    var errors: [(title: String, reason: String)] {
        rows.compactMap { row in
            if case let .failed(reason) = row.outcome { return (row.title, reason) }
            return nil
        }
    }
}

/// The run log's own file, next to the liveness ledger. Append-only by
/// construction: every save writes the whole list, newest first.
enum HolyRestoreRunLogStore {
    static let filename = "restore-runs.json"

    static func url(in directory: URL) -> URL {
        directory.appendingPathComponent(filename, isDirectory: false)
    }

    static func load(from url: URL) -> [HolyRestoreRunRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? HolyRestoreFileCoding.decoder.decode([HolyRestoreRunRecord].self, from: data)) ?? []
    }

    static func save(_ runs: [HolyRestoreRunRecord], to url: URL) throws {
        let data = try HolyRestoreFileCoding.encoder.encode(runs)
        try HolyRestoreFileCoding.writeDurably(data, to: url)
    }
}
