import Foundation

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
                .filter { protectedArchiveIDs.contains($0.id) }
                .map(\.id)
        )

        // Keep a useful relaunch floor even after a long period with no new
        // archives. Positively protected live archives may lift the final count
        // above the normal cap; preserving discovered truth wins over cleanup.
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

    var didDeleteRows: Bool {
        deletedGitSnapshots > 0 || deletedSessions > 0
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

    static func prune(
        in database: HolyDatabase,
        gitSnapshotBatchSize: Int = defaultGitSnapshotBatchSize,
        sessionBatchSize: Int = defaultSessionBatchSize
    ) throws -> HolyWorkspaceRetentionMaintenanceResult {
        precondition(gitSnapshotBatchSize >= 0)
        precondition(sessionBatchSize >= 0)

        var deletedGitSnapshots = 0
        var deletedSessions = 0

        try database.withTransaction {
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
                // bounded to at most its one referenced latest snapshot.
                let sql = """
                DELETE FROM sessions
                WHERE id IN (
                    SELECT sessions.id
                    FROM sessions
                    WHERE sessions.purge_pending_at IS NOT NULL
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
            deletedSessions: deletedSessions
        )
    }
}
