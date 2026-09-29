import Foundation
import OSLog
import SQLite3

/// Retention rules shared by workspace lifecycle code and database persistence.
///
/// Archive rows are user-visible relaunch records, so automatic retention runs
/// only after discovery has had a chance to positively protect any archive
/// that still corresponds to a live session. Active session IDs are always
/// authoritative over stale archive copies of the same source session.
enum HolyWorkspaceRetentionPolicy {
    static let archivedSessionAgeLimit: TimeInterval = 90 * 24 * 60 * 60
    static let minimumArchivedSessionCount = 64
    static let maximumArchivedSessionCount = 256

    static func retainedArchivedSessions(
        _ archivedSessions: [HolyArchivedSession],
        activeSessionIDs: Set<UUID> = [],
        protectedArchiveIDs: Set<UUID> = [],
        now: Date = .now
    ) -> [HolyArchivedSession] {
        let candidates = archivedSessions
            .filter { !activeSessionIDs.contains($0.sourceSessionID) }
            .sorted(by: archiveSort)

        var retainedIDs = Set(
            candidates
                .filter {
                    protectedArchiveIDs.contains($0.id)
                        || $0.recoveryReason != nil
                        || $0.recoveryBootBatchID != nil
                }
                .map(\.id)
        )

        // Keep a useful relaunch floor even after a long period with no new
        // archives. Positively protected live archives may lift the final count
        // above the normal cap. Recovery records also belong to the user until
        // restored or explicitly removed, even when their tmux process is dead.
        retainedIDs.formUnion(candidates.prefix(minimumArchivedSessionCount).map(\.id))

        let cutoff = now.addingTimeInterval(-archivedSessionAgeLimit)
        for archivedSession in candidates where archivedSession.archivedAt >= cutoff {
            if retainedIDs.contains(archivedSession.id) {
                continue
            }
            guard retainedIDs.count < maximumArchivedSessionCount else { break }
            retainedIDs.insert(archivedSession.id)
        }

        return candidates.filter { retainedIDs.contains($0.id) }
    }

    private static func archiveSort(_ lhs: HolyArchivedSession, _ rhs: HolyArchivedSession) -> Bool {
        if lhs.archivedAt != rhs.archivedAt {
            return lhs.archivedAt > rhs.archivedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

struct HolyWorkspaceRetentionMaintenanceResult: Equatable {
    let deletedGitSnapshots: Int
    let deletedSessions: Int
    let deletedSessionEvents: Int

    var didDeleteRows: Bool {
        deletedGitSnapshots > 0 || deletedSessions > 0 || deletedSessionEvents > 0
    }
}

/// Drains legacy persistence in bounded transactions. Git history is
/// intentionally latest-only: every product read joins through
/// sessions.latest_git_snapshot_id, so older rows carry no restorable state.
/// The current referenced snapshot is retained regardless of age; all
/// unreferenced history is immediately beyond the global history ceiling.
enum HolyWorkspaceRetentionMaintenance {
    // Keep each BEGIN IMMEDIATE window short. A full legacy drain is spread
    // across utility-queue passes so foreground workspace saves do not wait on
    // a multi-million-row delete transaction.
    static let defaultGitSnapshotBatchSize = 1_000
    static let defaultSessionBatchSize = 8
    static let defaultEventBatchSize = 256

    // The timeline is a recent diagnostic view, not a recovery store. Recovery
    // metadata lives on sessions.resume_metadata_json. Keep its last screen of
    // events even for quiet sessions; retaining the sequence tail also prevents
    // HolySessionEventRepository from reusing sequence numbers after a prune.
    static let eventAgeLimit: TimeInterval = 30 * 24 * 60 * 60
    static let maximumEventsPerSession = 512
    static let minimumEventsPerSession = 12

    static func prune(
        in database: HolyDatabase,
        gitSnapshotBatchSize: Int = defaultGitSnapshotBatchSize,
        sessionBatchSize: Int = defaultSessionBatchSize,
        eventBatchSize: Int = defaultEventBatchSize,
        now: Date = .now
    ) throws -> HolyWorkspaceRetentionMaintenanceResult {
        precondition(gitSnapshotBatchSize >= 0)
        precondition(sessionBatchSize >= 0)
        precondition(eventBatchSize >= 0)

        // Index probes and backlog selection do not own the writer lock.
        // Appends can only move the retained sequence boundaries forward.
        let cutoff = HolyPersistenceCoders.string(from: now.addingTimeInterval(-eventAgeLimit))
        let eventBatches = try eventPruneBatches(in: database, limit: eventBatchSize, cutoff: cutoff)

        var deletedGitSnapshots = 0
        var deletedSessions = 0
        var deletedSessionEvents = 0

        try database.withTransaction {
            for batch in eventBatches {
                let placeholders = Array(repeating: "?", count: batch.ids.count).joined(separator: ",")
                // Recheck the tombstone inside the transaction: a workspace
                // save may have readopted this session since candidate selection.
                try database.execute(
                    """
                    DELETE FROM session_events
                    WHERE id IN (\(placeholders)) AND (
                        EXISTS (SELECT 1 FROM sessions
                                WHERE sessions.id = session_events.session_id
                                  AND sessions.purge_pending_at IS NOT NULL)
                        OR sequence < ?
                        OR (occurred_at < ? AND sequence < ?)
                    );
                    """,
                    bindings: batch.ids.map(HolyDatabaseBinding.int64) + [
                        .int64(batch.capSequence), .text(cutoff), .int64(batch.floorSequence),
                    ]
                )
                deletedSessionEvents += Int(database.changedRowCount)
            }

            if gitSnapshotBatchSize > 0 {
                // IDs follow insertion order, so this drains the oldest legacy
                // history first without adding a large captured_at index to a
                // table that may already contain tens of millions of rows.
                let sql = """
                DELETE FROM git_snapshots
                WHERE id IN (
                    SELECT git_snapshots.id
                    FROM git_snapshots
                    WHERE NOT EXISTS (
                        SELECT 1
                        FROM sessions
                        WHERE sessions.latest_git_snapshot_id = git_snapshots.id
                    )
                    ORDER BY git_snapshots.id ASC
                    LIMIT ?
                );
                """
                try database.execute(sql, bindings: [.int64(Int64(gitSnapshotBatchSize))])
                deletedGitSnapshots = Int(database.changedRowCount)
            }

            if sessionBatchSize > 0 {
                // A tombstoned session stays physically present while its old
                // snapshot history drains, but load paths and compatibility
                // views hide it immediately. The final cascade is therefore
                // bounded to at most its one referenced latest snapshot. Event
                // history must drain first too, never through an unbounded FK
                // cascade from a single parent deletion.
                let sql = """
                DELETE FROM sessions
                WHERE id IN (
                    SELECT sessions.id
                    FROM sessions
                    WHERE sessions.purge_pending_at IS NOT NULL
                      AND NOT EXISTS (
                          SELECT 1 FROM session_events
                          WHERE session_events.session_id = sessions.id
                      )
                      AND NOT EXISTS (
                          SELECT 1
                          FROM git_snapshots
                          WHERE git_snapshots.session_id = sessions.id
                            AND (
                                sessions.latest_git_snapshot_id IS NULL
                                OR git_snapshots.id <> sessions.latest_git_snapshot_id
                            )
                      )
                    ORDER BY sessions.purge_pending_at ASC, sessions.id ASC
                    LIMIT ?
                );
                """
                try database.execute(sql, bindings: [.int64(Int64(sessionBatchSize))])
                deletedSessions = Int(database.changedRowCount)
            }
        }

        return .init(
            deletedGitSnapshots: deletedGitSnapshots,
            deletedSessions: deletedSessions,
            deletedSessionEvents: deletedSessionEvents
        )
    }

    private struct EventPruneBatch {
        let ids: [Int64]
        let capSequence: Int64
        let floorSequence: Int64
    }

    private static func eventPruneBatches(
        in database: HolyDatabase,
        limit: Int,
        cutoff: String
    ) throws -> [EventPruneBatch] {
        guard limit > 0 else { return [] }
        var sessions: [(id: String, retired: Bool)] = []
        try database.query("SELECT id, purge_pending_at IS NOT NULL FROM sessions ORDER BY id;") { row in
            guard let id = sqlite3_column_text(row, 0) else { return }
            sessions.append((String(cString: id), sqlite3_column_int(row, 1) != 0))
        }

        var batches: [EventPruneBatch] = []
        var remaining = limit
        for session in sessions {
            let cap = try retainedSequence(in: database, sessionID: session.id, count: maximumEventsPerSession)
            let floor = try retainedSequence(in: database, sessionID: session.id, count: minimumEventsPerSession)
            var ids: [Int64] = []
            try database.query(
                """
                SELECT id FROM session_events
                WHERE session_id = ? AND (? OR sequence < ? OR (occurred_at < ? AND sequence < ?))
                ORDER BY sequence LIMIT ?;
                """,
                bindings: [
                    .text(session.id), .bool(session.retired), .int64(cap), .text(cutoff),
                    .int64(floor), .int64(Int64(remaining)),
                ]
            ) { ids.append(sqlite3_column_int64($0, 0)) }
            if !ids.isEmpty {
                batches.append(.init(ids: ids, capSequence: cap, floorSequence: floor))
                remaining -= ids.count
            }
            if remaining == 0 { break }
        }
        return batches
    }

    private static func retainedSequence(in database: HolyDatabase, sessionID: String, count: Int) throws -> Int64 {
        var sequence: Int64 = 0
        try database.query(
            "SELECT sequence FROM session_events WHERE session_id = ? ORDER BY sequence DESC LIMIT 1 OFFSET ?;",
            bindings: [.text(sessionID), .int64(Int64(count - 1))]
        ) { sequence = sqlite3_column_int64($0, 0) }
        return sequence
    }
}

/// A timer owns retention, so quiet workspaces and failed/busy passes recover
/// without requiring another save. The connection and all scheduling state are
/// confined to this utility queue. Each saturated batch yields before the next.
final class HolyWorkspaceRetentionWorker: @unchecked Sendable {
    private static let logger = Logger(subsystem: "org.holyghostty.app", category: "HolyRetention")
    private let databaseURL: URL
    private let interval: TimeInterval
    private let queue = DispatchQueue(label: "org.holyghostty.retention", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var connection: HolyDatabase?
    private var isScheduled = false

    init(databaseURL: URL, interval: TimeInterval = 60) {
        precondition(interval > 0)
        self.databaseURL = databaseURL
        self.interval = interval
    }

    func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now(), repeating: interval)
            source.setEventHandler { [weak self] in self?.schedulePass() }
            timer = source
            source.resume()
        }
    }

    func requestPass() {
        queue.async { [self] in schedulePass() }
    }

    func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
            connection?.close()
            connection = nil
        }
    }

    private func schedulePass(after delay: TimeInterval = 0) {
        guard timer != nil, !isScheduled else { return }
        isScheduled = true
        queue.asyncAfter(deadline: .now() + delay) { [self] in
            isScheduled = false
            guard timer != nil else { return }
            runPass()
        }
    }

    private func runPass() {
        do {
            if connection == nil {
                let opened = try HolyDatabase.openDurableWriter(at: databaseURL)
                // Maintenance yields to an existing writer instead of joining
                // the foreground's five-second busy wait.
                try opened.execute("PRAGMA busy_timeout = 0;")
                connection = opened
            }
            guard let connection else { return }
            let result = try HolyWorkspaceRetentionMaintenance.prune(in: connection)
            if result.didDeleteRows {
                Self.logger.notice("Retention removed \(result.deletedSessionEvents) events, \(result.deletedGitSnapshots) snapshots, \(result.deletedSessions) retired sessions")
            }
            if result.deletedSessionEvents == HolyWorkspaceRetentionMaintenance.defaultEventBatchSize
                || result.deletedGitSnapshots == HolyWorkspaceRetentionMaintenance.defaultGitSnapshotBatchSize
                || result.deletedSessions == HolyWorkspaceRetentionMaintenance.defaultSessionBatchSize {
                schedulePass(after: 0.25)
            }
        } catch {
            Self.logger.warning("Retention deferred: \(error.localizedDescription, privacy: .public)")
            // The independent timer retries even if no foreground save occurs.
        }
    }
}
