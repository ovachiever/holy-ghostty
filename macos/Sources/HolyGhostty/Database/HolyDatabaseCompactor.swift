import Foundation
import OSLog

/// In-place reclamation of the app database's on-disk footprint.
///
/// Uses HolyDatabaseMaintenance's integrity, foreign-key, schema and row-count
/// checks around the rewrite. Runs only from the explicit menu action, off the
/// main thread. A concurrent writer invalidates the preservation receipt.
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
        case skippedUnknownDisk(Assessment)
        case compacted(before: Assessment, after: Assessment)

        var reclaimedBytes: Int64 {
            switch self {
            case let .compacted(before, after):
                return max(0, before.totalBytes - after.totalBytes)
            case .skippedNotBloated, .skippedInsufficientDisk, .skippedUnknownDisk:
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

    /// In-place reclaim. Compaction refuses lock contention instead of waiting
    /// behind a foreground writer. Call only through the validating entry point.
    /// The bracketing checkpoints fold the WAL back so the rewrite starts from a
    /// single file and the `-wal` sidecar does not immediately re-inflate the
    /// footprint afterward.
    private static func compactInPlace(_ database: HolyDatabase) throws {
        guard try database.checkpoint(.truncate).isComplete else {
            throw HolyDatabaseMaintenanceError.concurrentWrite
        }
        try database.execute("VACUUM;")
        guard try database.checkpoint(.truncate).isComplete else {
            throw HolyDatabaseMaintenanceError.concurrentWrite
        }
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
            case .skippedUnknownDisk:
                logger.warning("Holy database compaction skipped: free disk capacity is unknown")
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
        guard let available = availableCapacity() else {
            return .skippedUnknownDisk(assessment)
        }
        if available < assessment.totalBytes {
            return .skippedInsufficientDisk(assessment, availableBytes: available)
        }

        let originalTimeout = try database.scalarInt64("PRAGMA busy_timeout;")
        try database.execute("PRAGMA busy_timeout = 0;")
        defer { try? database.execute("PRAGMA busy_timeout = \(originalTimeout);") }

        let dataVersion = try database.scalarInt64("PRAGMA data_version;")
        let source = try HolyDatabaseMaintenance.validatedSnapshot(in: database)
        try compactInPlace(database)
        try HolyDatabaseMaintenance.validateUnchanged(in: database, from: source)
        guard try database.scalarInt64("PRAGMA data_version;") == dataVersion else {
            throw HolyDatabaseMaintenanceError.concurrentWrite
        }
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
