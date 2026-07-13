import Foundation
import OSLog

/// In-place reclamation of the app database's on-disk footprint.
///
/// This is distinct from `HolyDatabaseMaintenance`, which exports a validated
/// *copy* for an operator to swap by hand and never touches the live file. The
/// compactor instead checkpoints the WAL and runs `VACUUM` directly on the
/// primary database, so it is only safe at a quiesced moment: at launch, before
/// the workspace store opens its save loop, or from an explicit user action.
///
/// Reclamation is gated. A `VACUUM` rewrites the whole file and holds an
/// exclusive lock, so running it unconditionally on every launch would tax a
/// healthy database for nothing. The compactor fires only when freed-but-unshrunk
/// space is genuinely large and the volume has room for the transient rewrite —
/// a no-op in the common case.
enum HolyDatabaseCompactor {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mitchellh.ghostty",
        category: "HolyDatabaseCompactor"
    )

    /// Reclaim once dead pages exceed this absolute size. Below it, the rewrite
    /// cost outweighs the space returned.
    static let minimumReclaimableBytes: Int64 = 512 * 1024 * 1024

    /// ...or once free pages dominate the file, even when the absolute figure is
    /// modest — a small database that is mostly holes still deserves a rewrite.
    static let minimumReclaimableFraction = 0.25

    struct Assessment: Equatable {
        let pageSize: Int64
        let pageCount: Int64
        let freelistCount: Int64

        var totalBytes: Int64 { pageSize * pageCount }
        var reclaimableBytes: Int64 { pageSize * freelistCount }
        var reclaimableFraction: Double {
            pageCount > 0 ? Double(freelistCount) / Double(pageCount) : 0
        }

        /// True when the file carries enough dead weight to justify a rewrite.
        var exceedsCompactionThreshold: Bool {
            if reclaimableBytes >= HolyDatabaseCompactor.minimumReclaimableBytes {
                return true
            }
            return reclaimableFraction >= HolyDatabaseCompactor.minimumReclaimableFraction
                && reclaimableBytes > 0
        }
    }

    enum Decision: Equatable {
        case skippedNotBloated(Assessment)
        case skippedInsufficientDisk(Assessment, availableBytes: Int64)
        case compacted(before: Assessment, after: Assessment)

        var reclaimedBytes: Int64 {
            switch self {
            case let .compacted(before, after):
                return max(0, before.totalBytes - after.totalBytes)
            case .skippedNotBloated, .skippedInsufficientDisk:
                return 0
            }
        }
    }

    static func assess(_ database: HolyDatabase) throws -> Assessment {
        .init(
            pageSize: try database.scalarInt64("PRAGMA page_size;"),
            pageCount: try database.scalarInt64("PRAGMA page_count;"),
            freelistCount: try database.scalarInt64("PRAGMA freelist_count;")
        )
    }

    /// In-place reclaim. The caller MUST guarantee no other connection has the
    /// database open, or `VACUUM` will fail on the exclusive-lock contention.
    /// The bracketing checkpoints fold the WAL back so the rewrite starts from a
    /// single file and the `-wal` sidecar does not immediately re-inflate the
    /// footprint afterward.
    static func compactInPlace(_ database: HolyDatabase) throws {
        try database.execute("PRAGMA wal_checkpoint(TRUNCATE);")
        try database.execute("VACUUM;")
        try database.execute("PRAGMA wal_checkpoint(TRUNCATE);")
    }

    /// Assess and, if warranted, compact the live app database.
    ///
    /// - Parameters:
    ///   - force: bypass the bloat threshold (still honors the disk-space gate).
    ///     Used by the explicit "Compact Database Now" action.
    ///   - availableCapacity: injectable free-space probe for tests.
    /// - Returns: the decision taken, or `nil` if the database could not be
    ///   opened or the reclaim failed. Maintenance is best-effort and must never
    ///   block launch or a user action.
    @discardableResult
    static func maintainAppDatabaseIfNeeded(
        force: Bool = false,
        availableCapacity: () -> Int64? = defaultAvailableCapacity
    ) -> Decision? {
        do {
            let database = try HolyDatabase.openAppDatabase()
            let decision = try maintain(
                database,
                force: force,
                availableCapacity: availableCapacity
            )

            switch decision {
            case let .compacted(before, after):
                logger.notice(
                    "Holy database compaction reclaimed \(before.totalBytes - after.totalBytes, privacy: .public) bytes (\(before.totalBytes, privacy: .public) -> \(after.totalBytes, privacy: .public))"
                )
            case let .skippedInsufficientDisk(assessment, availableBytes):
                logger.warning(
                    "Holy database compaction skipped: needs \(assessment.totalBytes, privacy: .public) free bytes, only \(availableBytes, privacy: .public) available"
                )
            case .skippedNotBloated:
                break
            }

            return decision
        } catch {
            logger.warning("Holy database compaction failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Testable core: decide and act against an already-open connection.
    static func maintain(
        _ database: HolyDatabase,
        force: Bool,
        availableCapacity: () -> Int64?
    ) throws -> Decision {
        let assessment = try assess(database)

        guard force || assessment.exceedsCompactionThreshold else {
            return .skippedNotBloated(assessment)
        }

        // An in-place VACUUM builds a transient rebuilt copy on the same volume.
        // Refuse rather than fail mid-rewrite when the volume cannot hold it.
        if let available = availableCapacity(), available < assessment.totalBytes {
            return .skippedInsufficientDisk(assessment, availableBytes: available)
        }

        try compactInPlace(database)
        return .compacted(before: assessment, after: try assess(database))
    }

    static func defaultAvailableCapacity() -> Int64? {
        let directory = HolyDatabasePaths.databaseURL.deletingLastPathComponent()
        guard let values = try? directory.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ]) else {
            return nil
        }

        let conservativeCapacity = values.volumeAvailableCapacity.map(Int64.init)
        if let conservativeCapacity,
           let importantUsageCapacity = values.volumeAvailableCapacityForImportantUsage {
            return min(conservativeCapacity, importantUsageCapacity)
        }
        return conservativeCapacity ?? values.volumeAvailableCapacityForImportantUsage
    }
}
