import Foundation

enum HolyDatabaseMaintenanceError: LocalizedError {
    case sourceAndDestinationMatch(URL)
    case destinationAlreadyExists(URL)
    case capacityUnavailable(URL)
    case insufficientCapacity(requiredBytes: Int64, availableBytes: Int64)
    case integrityCheckFailed(destination: URL, result: String)
    case foreignKeyCheckFailed(destination: URL, violationCount: Int)
    case schemaVersionMismatch(source: Int32, destination: Int32)
    case rowCountMismatch(table: HolyDatabaseTable, source: Int64, destination: Int64)

    var errorDescription: String? {
        switch self {
        case let .sourceAndDestinationMatch(url):
            return "Compaction destination must differ from the source database at \(url.path)."
        case let .destinationAlreadyExists(url):
            return "Compaction destination already exists at \(url.path); refusing to overwrite it."
        case let .capacityUnavailable(url):
            return "Could not determine free capacity for \(url.path); refusing to start compaction."
        case let .insufficientCapacity(requiredBytes, availableBytes):
            return "Compaction requires at least \(requiredBytes) free bytes; only \(availableBytes) are available."
        case let .integrityCheckFailed(destination, result):
            return "Compacted database at \(destination.path) failed integrity_check: \(result)"
        case let .foreignKeyCheckFailed(destination, violationCount):
            return "Compacted database at \(destination.path) has \(violationCount) foreign-key violations."
        case let .schemaVersionMismatch(source, destination):
            return "Compacted database schema changed from version \(source) to \(destination)."
        case let .rowCountMismatch(table, source, destination):
            return "Compacted \(table.rawValue) row count changed from \(source) to \(destination)."
        }
    }
}

struct HolyDatabaseCompactionReport: Equatable {
    let destinationURL: URL
    let sourceBytes: Int64
    let compactedBytes: Int64
    let schemaVersion: Int32
    let rowCounts: [HolyDatabaseTable: Int64]
}

/// Explicit, copy-only space reclamation. This is intentionally never called
/// from bootstrap or routine persistence: a large VACUUM needs deliberate
/// operator timing and roughly the source footprint in transient free space.
/// The caller must quiesce app writes and perform any later swap separately.
enum HolyDatabaseMaintenance {
    static func createCompactedAppDatabaseCopy(
        at destinationURL: URL
    ) throws -> HolyDatabaseCompactionReport {
        let database = try HolyDatabase.openAppDatabase()
        return try createCompactedCopy(of: database, at: destinationURL)
    }

    static func createCompactedCopy(
        of database: HolyDatabase,
        at destinationURL: URL,
        requireSourceSizedFreeSpace: Bool = true
    ) throws -> HolyDatabaseCompactionReport {
        let sourceURL = database.url.standardizedFileURL.resolvingSymlinksInPath()
        let destinationURL = destinationURL.standardizedFileURL

        guard sourceURL != destinationURL.resolvingSymlinksInPath() else {
            throw HolyDatabaseMaintenanceError.sourceAndDestinationMatch(sourceURL)
        }
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw HolyDatabaseMaintenanceError.destinationAlreadyExists(destinationURL)
        }

        let destinationDirectory = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )

        let sourceBytes = try sourceFootprintBytes(at: sourceURL)
        if requireSourceSizedFreeSpace {
            guard let availableBytes = try availableCapacity(at: destinationDirectory) else {
                throw HolyDatabaseMaintenanceError.capacityUnavailable(destinationDirectory)
            }
            if availableBytes < sourceBytes {
                throw HolyDatabaseMaintenanceError.insufficientCapacity(
                    requiredBytes: sourceBytes,
                    availableBytes: availableBytes
                )
            }
        }

        let sourceVersion = try database.userVersion()
        let sourceRowCounts = try rowCounts(in: database)
        let temporaryURL = destinationDirectory.appendingPathComponent(
            ".\(destinationURL.lastPathComponent).building-\(UUID().uuidString)",
            isDirectory: false
        )
        var installedCopy = false
        defer {
            if !installedCopy {
                removeSQLiteFiles(at: temporaryURL)
            }
        }

        // PASSIVE never forces active readers/writers out. VACUUM INTO then
        // creates a transactionally consistent, compact copy at a new path.
        try database.execute("PRAGMA wal_checkpoint(PASSIVE);")
        try database.execute(
            "VACUUM INTO ?;",
            bindings: [.text(temporaryURL.path)]
        )

        let validation = try validateCompactedCopy(
            at: temporaryURL,
            sourceVersion: sourceVersion,
            sourceRowCounts: sourceRowCounts
        )
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        installedCopy = true

        return .init(
            destinationURL: destinationURL,
            sourceBytes: sourceBytes,
            compactedBytes: validation.bytes,
            schemaVersion: validation.schemaVersion,
            rowCounts: validation.rowCounts
        )
    }

    private static func validateCompactedCopy(
        at url: URL,
        sourceVersion: Int32,
        sourceRowCounts: [HolyDatabaseTable: Int64]
    ) throws -> (
        bytes: Int64,
        schemaVersion: Int32,
        rowCounts: [HolyDatabaseTable: Int64]
    ) {
        let database = try HolyDatabase.open(at: url, readOnly: true)
        let integrityResult = try database.scalarText("PRAGMA integrity_check;")
        guard integrityResult.lowercased() == "ok" else {
            throw HolyDatabaseMaintenanceError.integrityCheckFailed(
                destination: url,
                result: integrityResult
            )
        }

        var foreignKeyViolationCount = 0
        try database.query("PRAGMA foreign_key_check;") { _ in
            foreignKeyViolationCount += 1
        }
        guard foreignKeyViolationCount == 0 else {
            throw HolyDatabaseMaintenanceError.foreignKeyCheckFailed(
                destination: url,
                violationCount: foreignKeyViolationCount
            )
        }

        let destinationVersion = try database.userVersion()
        guard destinationVersion == sourceVersion else {
            throw HolyDatabaseMaintenanceError.schemaVersionMismatch(
                source: sourceVersion,
                destination: destinationVersion
            )
        }

        let destinationRowCounts = try rowCounts(in: database)
        for table in HolyDatabaseTable.allCases {
            let sourceCount = sourceRowCounts[table] ?? 0
            let destinationCount = destinationRowCounts[table] ?? 0
            guard sourceCount == destinationCount else {
                throw HolyDatabaseMaintenanceError.rowCountMismatch(
                    table: table,
                    source: sourceCount,
                    destination: destinationCount
                )
            }
        }

        return (
            bytes: try fileSize(at: url),
            schemaVersion: destinationVersion,
            rowCounts: destinationRowCounts
        )
    }

    private static func rowCounts(
        in database: HolyDatabase
    ) throws -> [HolyDatabaseTable: Int64] {
        try Dictionary(uniqueKeysWithValues: HolyDatabaseTable.allCases.map { table in
            let count = try database.scalarInt64("SELECT COUNT(*) FROM \(table.rawValue);")
            return (table, count)
        })
    }

    private static func sourceFootprintBytes(at databaseURL: URL) throws -> Int64 {
        let sidecars = [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm"),
        ]
        return try sidecars.reduce(into: Int64(0)) { total, url in
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            total += try fileSize(at: url)
        }
    }

    private static func removeSQLiteFiles(at databaseURL: URL) {
        for suffix in ["", "-wal", "-shm", "-journal"] {
            let url = URL(fileURLWithPath: databaseURL.path + suffix)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func fileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func availableCapacity(at directoryURL: URL) throws -> Int64? {
        let values = try directoryURL.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ])
        let conservativeCapacity = values.volumeAvailableCapacity.map(Int64.init)
        if let conservativeCapacity,
           let importantUsageCapacity = values.volumeAvailableCapacityForImportantUsage {
            // "Important usage" may count purgeable space that is not
            // immediately writable. Use the smaller value for a 50 GB-class
            // copy gate rather than promising space that may not materialize.
            return min(conservativeCapacity, importantUsageCapacity)
        }
        return conservativeCapacity ?? values.volumeAvailableCapacityForImportantUsage
    }
}
