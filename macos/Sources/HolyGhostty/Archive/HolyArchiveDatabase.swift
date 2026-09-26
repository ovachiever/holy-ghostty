import Foundation
import SQLite3

enum HolyArchiveDatabaseSchema {
    static let filename = "holy-archive.sqlite3"
    static let currentUserVersion: Int32 = 3
    static let busyTimeoutMilliseconds: Int32 = 2_000
    static let walAutoCheckpointPages: Int64 = 4_096
    static let journalSizeLimitBytes: Int64 = 64 * 1_024 * 1_024

    /// `archive_chunks.message_id` references `archive_messages(id)` with
    /// ON DELETE SET NULL. SQLite runs that action as a lookup on the child
    /// column for every deleted parent row, and without an index the lookup
    /// is a full scan of archive_chunks per message (EXPLAIN QUERY PLAN shows
    /// "SCAN archive_chunks"). On a copy of the live archive (1.2 GB, 231,683
    /// messages, 223,389 chunks) deleting one 207-message session took
    /// 39.78 s without this index and 0.006 s with it; the index itself
    /// built in 0.22 s and occupies 12.7 MB. A fresh archive creates it with
    /// the schema; an existing one builds it through
    /// `HolyArchiveRepository.ensureDeletionIndexes()` on the indexer actor.
    static let chunkMessageIndexSQL =
        "CREATE INDEX IF NOT EXISTS archive_chunks_message_idx ON archive_chunks(message_id);"
}

enum HolyArchiveDatabaseError: LocalizedError {
    case unsupportedSchemaVersion(found: Int32, supported: Int32)
    case legacyForeignKeyViolations(Int)

    var errorDescription: String? {
        switch self {
        case let .unsupportedSchemaVersion(found, supported):
            return "Archive database schema version \(found) is newer than this build supports (\(supported))."
        case let .legacyForeignKeyViolations(count):
            return "Legacy Archive migration left \(count) foreign-key violation(s); migration remains incomplete."
        }
    }
}

enum HolyArchiveDatabaseMigrator {
    static func migrate(_ database: HolyDatabase) throws {
        let currentVersion = try database.userVersion()
        guard currentVersion <= HolyArchiveDatabaseSchema.currentUserVersion else {
            throw HolyArchiveDatabaseError.unsupportedSchemaVersion(
                found: currentVersion,
                supported: HolyArchiveDatabaseSchema.currentUserVersion
            )
        }

        if currentVersion < 1 {
            try database.withTransaction {
                for statement in HolyDatabaseMigrator.archiveSchemaStatements {
                    try database.execute(statement)
                }
                try database.setUserVersion(1)
            }
        }

        if currentVersion < 2 {
            try database.withTransaction {
                for statement in stagingSchema {
                    try database.execute(statement)
                }
                try database.setUserVersion(2)
            }
        }

        if currentVersion < 3 {
            try database.withTransaction {
                // The ingest digest is a hash over the stored messages, so a
                // re-parse of unchanged transcript bytes is recognized without
                // reading the rows back. The provider content hash (first
                // prompt + last response) cannot tell an appended message
                // from none.
                if try !columnExists("ingest_digest", table: "archive_sessions", in: database) {
                    try database.execute("ALTER TABLE archive_sessions ADD COLUMN ingest_digest TEXT;")
                }
                // The sessions FTS mirrors three columns. Bookkeeping updates
                // (message_count, file_mtime, indexed_at) must not delete and
                // re-insert the FTS row, so the trigger is scoped to them.
                try database.execute("DROP TRIGGER IF EXISTS archive_sessions_au;")
                try database.execute(sessionUpdateTriggerSQL)
                // Every statement above is O(1); the deletion index is only
                // O(1) while the chunk table is empty. An existing archive
                // builds it on the indexer actor, never on the thread that
                // happened to open the repository.
                if try database.scalarInt64("SELECT EXISTS(SELECT 1 FROM archive_chunks);") == 0 {
                    try database.execute(HolyArchiveDatabaseSchema.chunkMessageIndexSQL)
                }
                try database.setUserVersion(3)
            }
        }

        try configureWriter(database)
    }

    static func columnExists(_ column: String, table: String, in database: HolyDatabase) throws -> Bool {
        try columns(of: table, schema: nil, in: database).contains(column)
    }

    /// Column names in declaration order, for `schema`.`table` (main when nil).
    static func columns(of table: String, schema: String?, in database: HolyDatabase) throws -> [String] {
        let qualified = schema.map { "\($0)." } ?? ""
        var names: [String] = []
        try database.query("PRAGMA \(qualified)table_info(\(table));") { statement in
            if let value = sqlite3_column_text(statement, 1) { names.append(String(cString: value)) }
        }
        return names
    }

    static let sessionUpdateTriggerSQL = """
    CREATE TRIGGER IF NOT EXISTS archive_sessions_au
    AFTER UPDATE OF first_prompt_preview, project_name, auto_tags_json ON archive_sessions BEGIN
        INSERT INTO archive_sessions_fts(
            archive_sessions_fts, rowid, first_prompt_preview, project_name, auto_tags_json
        ) VALUES ('delete', old.rowid, old.first_prompt_preview, old.project_name, old.auto_tags_json);
        INSERT INTO archive_sessions_fts(rowid, first_prompt_preview, project_name, auto_tags_json)
        VALUES (new.rowid, new.first_prompt_preview, new.project_name, new.auto_tags_json);
    END;
    """

    static func configureWriter(_ database: HolyDatabase) throws {
        try database.execute("PRAGMA busy_timeout = \(HolyArchiveDatabaseSchema.busyTimeoutMilliseconds);")
        try database.execute("PRAGMA wal_autocheckpoint = \(HolyArchiveDatabaseSchema.walAutoCheckpointPages);")
        try database.execute("PRAGMA journal_size_limit = \(HolyArchiveDatabaseSchema.journalSizeLimitBytes);")
    }

    private static let stagingSchema: [String] = [
        """
        CREATE TABLE IF NOT EXISTS archive_staged_messages (
            ingest_id TEXT NOT NULL,
            id TEXT NOT NULL,
            session_id TEXT NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            timestamp REAL,
            sequence INTEGER NOT NULL,
            has_code INTEGER NOT NULL DEFAULT 0,
            tool_mentions_json TEXT NOT NULL DEFAULT '[]',
            PRIMARY KEY (ingest_id, id)
        );
        """,
        """
        CREATE INDEX IF NOT EXISTS archive_staged_messages_session_idx
        ON archive_staged_messages(session_id, ingest_id);
        """,
        """
        CREATE TABLE IF NOT EXISTS archive_staged_chunks (
            ingest_id TEXT NOT NULL,
            id TEXT NOT NULL,
            session_id TEXT NOT NULL,
            message_id TEXT,
            chunk_index INTEGER NOT NULL,
            chunk_type TEXT NOT NULL,
            content TEXT NOT NULL,
            metadata_json TEXT NOT NULL DEFAULT '{}',
            embedding BLOB,
            embedding_model TEXT,
            created_at REAL NOT NULL,
            PRIMARY KEY (ingest_id, id)
        );
        """,
        """
        CREATE INDEX IF NOT EXISTS archive_staged_chunks_session_idx
        ON archive_staged_chunks(session_id, ingest_id);
        """,
    ]
}

struct HolyArchiveWriteBudget: Equatable, Sendable {
    let rowsPerTransaction: Int
    let foregroundRowsPerSecond: Double
    let backgroundRowsPerSecond: Double
    let checkpointEveryRows: Int
    let maximumPauseNanoseconds: UInt64

    static let production = HolyArchiveWriteBudget(
        rowsPerTransaction: 250,
        foregroundRowsPerSecond: 600,
        backgroundRowsPerSecond: 6_000,
        checkpointEveryRows: 5_000,
        maximumPauseNanoseconds: 500_000_000
    )

    static let unthrottled = HolyArchiveWriteBudget(
        rowsPerTransaction: 1_000,
        foregroundRowsPerSecond: .infinity,
        backgroundRowsPerSecond: .infinity,
        checkpointEveryRows: 100_000,
        maximumPauseNanoseconds: 0
    )

    func delayNanoseconds(afterWritingRows rowCount: Int, foreground: Bool) -> UInt64 {
        let rate = foreground ? foregroundRowsPerSecond : backgroundRowsPerSecond
        guard rowCount > 0, rate.isFinite, rate > 0, maximumPauseNanoseconds > 0 else { return 0 }
        let requested = UInt64((Double(rowCount) / rate * 1_000_000_000).rounded(.up))
        return min(requested, maximumPauseNanoseconds)
    }
}

struct HolyArchiveWritePacer: Sendable {
    typealias ForegroundProvider = @Sendable () async -> Bool
    typealias Sleeper = @Sendable (UInt64) async -> Void

    let budget: HolyArchiveWriteBudget
    private let isForeground: ForegroundProvider
    private let sleep: Sleeper

    init(
        budget: HolyArchiveWriteBudget = .production,
        isForeground: @escaping ForegroundProvider = { false },
        sleep: @escaping Sleeper = { nanoseconds in
            guard nanoseconds > 0 else { return }
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.budget = budget
        self.isForeground = isForeground
        self.sleep = sleep
    }

    func yield(afterWritingRows rowCount: Int) async {
        await Task.yield()
        let foreground = await isForeground()
        let delay = budget.delayNanoseconds(afterWritingRows: rowCount, foreground: foreground)
        if delay > 0 { await sleep(delay) }
    }
}

struct HolyArchiveLegacyMigrationReceipt: Equatable, Sendable {
    let completedRows: Int
    let totalRows: Int
    let didComplete: Bool
}

/// Copies the version-12 `archive_*` tables out of the workspace database.
/// Every cursor advances in the same bounded transaction as its copied rows,
/// so interruption can only replay an idempotent batch. The source is attached
/// read-only in practice: all writes and checkpoints target the Archive file.
actor HolyArchiveLegacyDatabaseMigrator {
    static let completionKey = "storage.legacy_database_migration_v1"

    private struct LegacyTable: Sendable {
        let name: String
    }

    private static let tables = [
        LegacyTable(name: "archive_sessions"),
        LegacyTable(name: "archive_messages"),
        LegacyTable(name: "archive_chunks"),
        LegacyTable(name: "archive_search_history"),
        LegacyTable(name: "archive_project_stats"),
        LegacyTable(name: "archive_summaries"),
        LegacyTable(name: "archive_annotations"),
        LegacyTable(name: "archive_research_chats"),
        LegacyTable(name: "archive_research_messages"),
        LegacyTable(name: "archive_index_meta"),
    ]

    private let sourceURL: URL?
    private let destinationURL: URL
    private let pacer: HolyArchiveWritePacer

    init(
        sourceURL: URL?,
        destinationURL: URL,
        pacer: HolyArchiveWritePacer = .init()
    ) {
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.pacer = pacer
    }

    func migrateIfNeeded(
        maximumBatches: Int? = nil,
        progress: (@Sendable (HolyArchiveIndexProgress) async -> Void)? = nil
    ) async throws -> HolyArchiveLegacyMigrationReceipt {
        let destination = try HolyDatabase.open(at: destinationURL)
        try HolyArchiveDatabaseMigrator.migrate(destination)
        if try Self.metaValue(Self.completionKey, in: destination) == "complete" {
            return .init(completedRows: 0, totalRows: 0, didComplete: true)
        }

        guard let sourceURL,
              sourceURL.standardizedFileURL != destinationURL.standardizedFileURL,
              FileManager.default.fileExists(atPath: sourceURL.path)
        else {
            try Self.markComplete(in: destination)
            return .init(completedRows: 0, totalRows: 0, didComplete: true)
        }

        let source = try HolyDatabase.open(at: sourceURL, readOnly: true)
        guard try Self.tableExists("archive_sessions", in: source) else {
            try Self.markComplete(in: destination)
            return .init(completedRows: 0, totalRows: 0, didComplete: true)
        }

        try destination.execute("ATTACH DATABASE ? AS legacy_archive;", bindings: [.text(sourceURL.path)])
        defer { try? destination.execute("DETACH DATABASE legacy_archive;") }
        try destination.execute("PRAGMA foreign_keys = OFF;")
        defer { try? destination.execute("PRAGMA foreign_keys = ON;") }

        let availableTables = try Self.tables.filter {
            try Self.attachedTableExists($0.name, in: destination)
        }
        let totals = try Dictionary(uniqueKeysWithValues: availableTables.map { table in
            (table.name, try destination.scalarInt64("SELECT COUNT(*) FROM legacy_archive.\(table.name);"))
        })
        let totalRows = totals.values.reduce(0) { $0 + Int($1) }
        var completedRows = 0
        var rowsSinceCheckpoint = 0
        var batches = 0

        for table in availableTables {
            var cursor = Int64(try Self.metaValue(Self.cursorKey(table.name), in: destination) ?? "0") ?? 0
            completedRows += try Self.countRows(through: cursor, table: table.name, in: destination)
            // Named columns, never SELECT *: the destination schema can carry
            // columns the legacy table never had (ingest_digest since v3).
            let destinationColumns = Set(try HolyArchiveDatabaseMigrator.columns(
                of: table.name, schema: nil, in: destination
            ))
            let copiedColumns = try HolyArchiveDatabaseMigrator.columns(
                of: table.name, schema: "legacy_archive", in: destination
            ).filter { destinationColumns.contains($0) }
            let columnList = copiedColumns.joined(separator: ", ")

            while true {
                if let maximumBatches, batches >= maximumBatches {
                    return .init(completedRows: completedRows, totalRows: totalRows, didComplete: false)
                }
                let upper = try Self.nextUpperRowID(
                    after: cursor,
                    limit: pacer.budget.rowsPerTransaction,
                    table: table.name,
                    in: destination
                )
                guard upper > cursor else { break }
                let batchCount = try Self.countRows(
                    after: cursor,
                    through: upper,
                    table: table.name,
                    in: destination
                )
                try destination.withTransaction {
                    try destination.execute(
                        "INSERT OR IGNORE INTO \(table.name)(\(columnList)) SELECT \(columnList) FROM legacy_archive.\(table.name) WHERE rowid > ? AND rowid <= ? ORDER BY rowid;",
                        bindings: [.int64(cursor), .int64(upper)]
                    )
                    try Self.setMeta(Self.cursorKey(table.name), value: String(upper), in: destination)
                }
                cursor = upper
                completedRows += batchCount
                rowsSinceCheckpoint += batchCount
                batches += 1
                await progress?(.init(
                    phase: .migrating,
                    completed: completedRows,
                    total: totalRows,
                    detail: "Moving legacy \(table.name) into \(HolyArchiveDatabaseSchema.filename)"
                ))
                if rowsSinceCheckpoint >= pacer.budget.checkpointEveryRows {
                    try destination.execute("PRAGMA wal_checkpoint(PASSIVE);")
                    rowsSinceCheckpoint = 0
                }
                await pacer.yield(afterWritingRows: batchCount)
            }
        }

        try destination.execute("PRAGMA foreign_keys = ON;")
        var violations = 0
        try destination.query("PRAGMA foreign_key_check;") { _ in violations += 1 }
        guard violations == 0 else {
            throw HolyArchiveDatabaseError.legacyForeignKeyViolations(violations)
        }
        try Self.markComplete(in: destination)
        try destination.execute("PRAGMA wal_checkpoint(PASSIVE);")
        return .init(completedRows: completedRows, totalRows: totalRows, didComplete: true)
    }

    private static func tableExists(_ table: String, in database: HolyDatabase) throws -> Bool {
        try database.scalarInt64(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = '\(table)';"
        ) == 1
    }

    private static func attachedTableExists(_ table: String, in database: HolyDatabase) throws -> Bool {
        try database.scalarInt64(
            "SELECT COUNT(*) FROM legacy_archive.sqlite_master WHERE type = 'table' AND name = '\(table)';"
        ) == 1
    }

    private static func nextUpperRowID(
        after cursor: Int64,
        limit: Int,
        table: String,
        in database: HolyDatabase
    ) throws -> Int64 {
        try database.scalarInt64(
            "SELECT COALESCE(MAX(rowid), 0) FROM (SELECT rowid FROM legacy_archive.\(table) WHERE rowid > \(cursor) ORDER BY rowid LIMIT \(max(1, limit)));"
        )
    }

    private static func countRows(
        through cursor: Int64,
        table: String,
        in database: HolyDatabase
    ) throws -> Int {
        Int(try database.scalarInt64(
            "SELECT COUNT(*) FROM legacy_archive.\(table) WHERE rowid <= \(cursor);"
        ))
    }

    private static func countRows(
        after cursor: Int64,
        through upper: Int64,
        table: String,
        in database: HolyDatabase
    ) throws -> Int {
        Int(try database.scalarInt64(
            "SELECT COUNT(*) FROM legacy_archive.\(table) WHERE rowid > \(cursor) AND rowid <= \(upper);"
        ))
    }

    private static func cursorKey(_ table: String) -> String {
        "storage.legacy_database_migration_v1.cursor.\(table)"
    }

    private static func metaValue(_ key: String, in database: HolyDatabase) throws -> String? {
        var value: String?
        try database.query(
            "SELECT value FROM archive_index_meta WHERE key = ? LIMIT 1;",
            bindings: [.text(key)]
        ) { statement in
            if let text = sqlite3_column_text(statement, 0) { value = String(cString: text) }
        }
        return value
    }

    private static func setMeta(_ key: String, value: String, in database: HolyDatabase) throws {
        try database.execute(
            """
            INSERT INTO archive_index_meta(key, value, updated_at) VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at;
            """,
            bindings: [.text(key), .text(value), .double(Date.now.timeIntervalSince1970)]
        )
    }

    private static func markComplete(in database: HolyDatabase) throws {
        try setMeta(completionKey, value: "complete", in: database)
    }
}
