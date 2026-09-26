import Foundation
import OSLog
import SQLite3

enum HolyDatabaseError: LocalizedError {
    case openFailed(path: String, code: Int32, message: String)
    case executeFailed(sql: String, code: Int32, message: String)
    case prepareFailed(sql: String, code: Int32, message: String)
    case stepFailed(sql: String, code: Int32, message: String)
    case missingScalar(sql: String)
    case unsupportedSchemaVersion(found: Int32, supported: Int32)

    var errorDescription: String? {
        switch self {
        case let .openFailed(path, code, message):
            return "Failed to open Holy Ghostty database at \(path) (SQLite \(code)): \(message)"
        case let .executeFailed(sql, code, message):
            return "Failed to execute SQL (SQLite \(code)): \(message)\n\(sql)"
        case let .prepareFailed(sql, code, message):
            return "Failed to prepare SQL (SQLite \(code)): \(message)\n\(sql)"
        case let .stepFailed(sql, code, message):
            return "Failed to step SQL (SQLite \(code)): \(message)\n\(sql)"
        case let .missingScalar(sql):
            return "Expected a scalar result but query returned no rows: \(sql)"
        case let .unsupportedSchemaVersion(found, supported):
            return "Holy Ghostty database schema version \(found) is newer than this build supports (\(supported))."
        }
    }
}

/// One row of `PRAGMA wal_checkpoint(<mode>)`: whether a reader kept the
/// checkpoint from finishing, how many frames the WAL held, and how many of
/// them were copied into the main file.
struct HolyDatabaseCheckpointReceipt: Equatable {
    let busy: Bool
    let walFrames: Int
    let checkpointedFrames: Int

    /// Every frame is in the main file and nothing blocked; the next write
    /// transaction restarts the WAL from its beginning.
    var isComplete: Bool {
        !busy && walFrames == checkpointedFrames
    }
}

enum HolyDatabaseCheckpointMode: String {
    case passive = "PASSIVE"
    case full = "FULL"
    case restart = "RESTART"
    case truncate = "TRUNCATE"
}

/// Checkpoint schedule for a long-lived writer connection.
///
/// A connection that closes after every transaction checkpoints on every
/// close (`sqlite3WalClose`): the whole WAL is copied into the main file
/// and both are F_FULLFSYNC'd, on the committing thread, for every flush.
/// A connection that stays open checkpoints instead on SQLite's own
/// automatic schedule: once the WAL holds `walFrameThreshold` frames after
/// a commit. This policy keeps that schedule (the threshold is read from
/// the linked library's `PRAGMA wal_autocheckpoint`, whose default is
/// `SQLITE_DEFAULT_WAL_AUTOCHECKPOINT`; it is never a literal here) but
/// runs the PASSIVE checkpoint on a utility queue through its own
/// connection, so the committing thread never copies pages. PASSIVE never
/// blocks the writer or any reader.
final class HolyDatabaseCheckpointPolicy: @unchecked Sendable {
    let databaseURL: URL
    let walFrameThreshold: Int32

    private let queue = DispatchQueue(
        label: "com.mitchellh.ghostty.holy-database-checkpoint",
        qos: .utility
    )
    private let lock = NSLock()
    private var isScheduled = false
    private var isShutDown = false
    private var connection: HolyDatabase?
    private var completedCheckpoints = 0
    private var receipts: [HolyDatabaseCheckpointReceipt] = []
    private var observers: [(HolyDatabaseCheckpointReceipt, Bool) -> Void] = []

    init(databaseURL: URL, walFrameThreshold: Int32) {
        self.databaseURL = databaseURL
        self.walFrameThreshold = walFrameThreshold
    }

    /// Number of PASSIVE checkpoints this policy has run (complete or not).
    var completedCheckpointCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return completedCheckpoints
    }

    var checkpointReceipts: [HolyDatabaseCheckpointReceipt] {
        lock.lock()
        defer { lock.unlock() }
        return receipts
    }

    /// Observe every checkpoint the policy runs: the receipt and whether it
    /// ran off the main thread. Observers are called on the checkpoint queue.
    func addObserver(_ observer: @escaping (HolyDatabaseCheckpointReceipt, Bool) -> Void) {
        lock.lock()
        observers.append(observer)
        lock.unlock()
    }

    /// The WAL hook: called by SQLite on the committing thread after every
    /// committed write transaction with the number of frames the WAL holds.
    func walDidCommit(frames: Int32) {
        guard frames >= walFrameThreshold else { return }

        lock.lock()
        guard !isScheduled, !isShutDown else {
            lock.unlock()
            return
        }
        isScheduled = true
        lock.unlock()

        queue.async { [self] in
            runCheckpoint()
        }
    }

    /// Closes the policy's connection and refuses further work. Runs the
    /// close on the checkpoint queue and waits for it, so it must not be
    /// called from that queue.
    func shutdown() {
        lock.lock()
        isShutDown = true
        lock.unlock()

        queue.sync {
            connection?.close()
            connection = nil
        }
    }

    private func runCheckpoint() {
        defer {
            lock.lock()
            isScheduled = false
            lock.unlock()
        }

        lock.lock()
        let shutDown = isShutDown
        lock.unlock()
        guard !shutDown else { return }

        do {
            let database = try openConnectionIfNeeded()
            let receipt = try database.checkpoint(.passive)
            let offMainThread = !Thread.isMainThread

            lock.lock()
            completedCheckpoints += 1
            receipts.append(receipt)
            let currentObservers = observers
            lock.unlock()

            for observer in currentObservers {
                observer(receipt, offMainThread)
            }
        } catch {
            HolyDatabase.logger.warning(
                "Holy database WAL checkpoint failed: \(error.localizedDescription, privacy: .public)"
            )
            connection = nil
        }
    }

    private func openConnectionIfNeeded() throws -> HolyDatabase {
        if let connection {
            return connection
        }
        let opened = try HolyDatabase.open(at: databaseURL)
        connection = opened
        return opened
    }
}

final class HolyDatabase {
    fileprivate static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mitchellh.ghostty",
        category: "HolyDatabase"
    )
    private static let bootstrapLock = NSLock()
    private static var hasBootstrapped = false

    let url: URL
    private let handle: OpaquePointer
    private var isClosed = false
    /// Present only on a connection opened with `openDurableWriter(at:)`.
    private(set) var checkpointPolicy: HolyDatabaseCheckpointPolicy?

    private init(url: URL, handle: OpaquePointer) {
        self.url = url
        self.handle = handle
    }

    deinit {
        close()
    }

    /// Closes the connection. On a durable writer the WAL hook is removed
    /// and the checkpoint policy's own connection is closed first. Safe to
    /// call more than once; `deinit` calls it.
    func close() {
        guard !isClosed else { return }
        isClosed = true

        if checkpointPolicy != nil {
            sqlite3_wal_hook(handle, nil, nil)
        }
        checkpointPolicy?.shutdown()
        checkpointPolicy = nil
        sqlite3_close_v2(handle)
    }

    /// Opens the connection that owns the workspace save loop for the life
    /// of the process.
    ///
    /// Durability parity with the per-flush close this replaces: a close
    /// checkpoint syncs the WAL and the main file with the checkpoint sync
    /// flags, which on the linked library are F_FULLFSYNC
    /// (`PRAGMA checkpoint_fullfsync` defaults to 1: the library is built
    /// with `SQLITE_DEFAULT_CKPTFULLFSYNC`, read from
    /// `PRAGMA compile_options` on this machine, SQLite 3.51.0). So today
    /// every flush reaches the platter before the next one. A connection
    /// that stays open commits into the WAL and never closes, so the
    /// commit itself must carry that guarantee: `synchronous = FULL` syncs
    /// the WAL on every commit that wrote a frame, and `fullfsync = ON`
    /// makes that sync F_FULLFSYNC. A commit that dirtied no page writes
    /// no frame and performs no sync at all.
    ///
    /// Checkpoints move to `HolyDatabaseCheckpointPolicy`: the library's
    /// own automatic threshold, run off the committing thread.
    static func openDurableWriter(at url: URL) throws -> HolyDatabase {
        let database = try open(at: url, readOnly: false)
        try database.configureDurableWriter()
        return database
    }

    static func bootstrapIfNeeded() {
        bootstrapLock.lock()
        defer { bootstrapLock.unlock() }

        guard !hasBootstrapped else { return }

        do {
            try HolyDatabasePaths.ensureContainerDirectory()
            let database = try openAppDatabase()
            try HolyDatabaseMigrator.migrate(database)
            hasBootstrapped = true
            logger.notice("Holy database is ready at \(database.url.path, privacy: .public)")
        } catch {
            logger.error("Failed to bootstrap Holy database: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func openAppDatabase(readOnly: Bool = false) throws -> HolyDatabase {
        let url = HolyDatabasePaths.databaseURL
        try HolyDatabasePaths.ensureContainerDirectory()

        return try open(at: url, readOnly: readOnly)
    }

    static func open(at url: URL, readOnly: Bool = false) throws -> HolyDatabase {

        var handle: OpaquePointer?
        let flags: Int32
        if readOnly {
            // A READONLY connection to a WAL database cannot create the
            // -shm/-wal companions, so once a checkpoint removes them every
            // prepare fails with SQLITE_CANTOPEN (reproduced live on the app
            // DB, mn-d32871). Open read-write — never CREATE — so SQLite can
            // rebuild WAL infrastructure; configure() enforces the read-only
            // contract with query_only. Files this user cannot write (a
            // federated foreign archive) fall back to a true readonly open.
            flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        } else {
            flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        }

        var result = sqlite3_open_v2(url.path, &handle, flags, nil)
        if result != SQLITE_OK, readOnly {
            if let handle {
                sqlite3_close_v2(handle)
            }
            handle = nil
            result = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        }
        guard result == SQLITE_OK, let handle else {
            let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
            if let handle {
                sqlite3_close_v2(handle)
            }
            throw HolyDatabaseError.openFailed(path: url.path, code: result, message: message)
        }

        sqlite3_extended_result_codes(handle, 1)
        sqlite3_busy_timeout(handle, HolyDatabaseSchema.busyTimeoutMilliseconds)

        let database = HolyDatabase(url: url, handle: handle)
        try database.configure(readOnly: readOnly)
        return database
    }

    func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &errorMessage)

        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? self.errorMessage()
            sqlite3_free(errorMessage)
            throw HolyDatabaseError.executeFailed(sql: sql, code: result, message: message)
        }
    }

    func execute(_ sql: String, bindings: [HolyDatabaseBinding]) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        try bind(bindings, to: statement, sql: sql)

        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            throw HolyDatabaseError.stepFailed(sql: sql, code: result, message: errorMessage())
        }
    }

    func scalarInt32(_ sql: String) throws -> Int32 {
        Int32(try scalarInt64(sql))
    }

    func scalarInt64(_ sql: String) throws -> Int64 {
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw HolyDatabaseError.prepareFailed(sql: sql, code: prepareResult, message: errorMessage())
        }
        defer { sqlite3_finalize(statement) }

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_ROW else {
            if stepResult == SQLITE_DONE {
                throw HolyDatabaseError.missingScalar(sql: sql)
            }

            throw HolyDatabaseError.stepFailed(sql: sql, code: stepResult, message: errorMessage())
        }

        return sqlite3_column_int64(statement, 0)
    }

    func scalarText(_ sql: String) throws -> String {
        var value: String?
        try query(sql) { statement in
            guard value == nil, let bytes = sqlite3_column_text(statement, 0) else { return }
            value = String(cString: bytes)
        }

        guard let value else {
            throw HolyDatabaseError.missingScalar(sql: sql)
        }
        return value
    }

    func query(
        _ sql: String,
        bindings: [HolyDatabaseBinding] = [],
        rowHandler: (OpaquePointer) throws -> Void
    ) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        try bind(bindings, to: statement, sql: sql)

        while true {
            let result = sqlite3_step(statement)
            switch result {
            case SQLITE_ROW:
                try rowHandler(statement)
            case SQLITE_DONE:
                return
            default:
                throw HolyDatabaseError.stepFailed(sql: sql, code: result, message: errorMessage())
            }
        }
    }

    func userVersion() throws -> Int32 {
        try scalarInt32("PRAGMA user_version;")
    }

    func setUserVersion(_ version: Int32) throws {
        try execute("PRAGMA user_version = \(version);")
    }

    func withTransaction(_ work: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION;")

        do {
            try work()
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    /// Runs `PRAGMA wal_checkpoint(<mode>)` on this connection and returns
    /// its row. PASSIVE never blocks; the other modes wait on the busy
    /// timeout for readers and writers.
    func checkpoint(_ mode: HolyDatabaseCheckpointMode) throws -> HolyDatabaseCheckpointReceipt {
        let sql = "PRAGMA wal_checkpoint(\(mode.rawValue));"
        var receipt: HolyDatabaseCheckpointReceipt?
        try query(sql) { statement in
            receipt = .init(
                busy: sqlite3_column_int(statement, 0) != 0,
                walFrames: Int(sqlite3_column_int(statement, 1)),
                checkpointedFrames: Int(sqlite3_column_int(statement, 2))
            )
        }

        guard let receipt else {
            throw HolyDatabaseError.missingScalar(sql: sql)
        }
        return receipt
    }

    /// Rows inserted, updated, or deleted through this connection since it
    /// was opened (`sqlite3_total_changes64`). The difference across a
    /// transaction is what that transaction wrote.
    var totalChangedRowCount: Int64 {
        sqlite3_total_changes64(handle)
    }

    #if DEBUG
    /// The raw connection, for tests that install SQLite hooks
    /// (`sqlite3_update_hook`, `sqlite3_commit_hook`) to observe or veto
    /// what the production save path does. Never used by the app.
    var rawHandleForTesting: OpaquePointer {
        handle
    }
    #endif

    private func configureDurableWriter() throws {
        try execute("PRAGMA synchronous = FULL;")
        try execute("PRAGMA fullfsync = ON;")

        // Read the library's automatic schedule before replacing its hook:
        // installing a WAL hook disables sqlite3_wal_autocheckpoint on this
        // connection (its default hook is what runs the automatic
        // checkpoint), so the threshold must be carried over explicitly.
        let walFrameThreshold = try scalarInt32("PRAGMA wal_autocheckpoint;")
        let policy = HolyDatabaseCheckpointPolicy(
            databaseURL: url,
            walFrameThreshold: walFrameThreshold
        )
        checkpointPolicy = policy

        let context = Unmanaged.passUnretained(policy).toOpaque()
        sqlite3_wal_hook(
            handle,
            { context, _, _, frames -> Int32 in
                guard let context else { return SQLITE_OK }
                Unmanaged<HolyDatabaseCheckpointPolicy>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                    .walDidCommit(frames: frames)
                return SQLITE_OK
            },
            context
        )

        Self.logger.notice(
            "Holy database durable writer open at \(self.url.path, privacy: .public): synchronous=FULL fullfsync=ON, WAL checkpoint off-thread at \(walFrameThreshold, privacy: .public) frames"
        )
    }

    private func configure(readOnly: Bool) throws {
        try execute("PRAGMA foreign_keys = ON;")

        guard !readOnly else {
            // The connection may be physically read-write (see open); this
            // pragma is the read-only contract for every caller.
            try execute("PRAGMA query_only = ON;")
            return
        }

        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA synchronous = NORMAL;")
        try execute("PRAGMA temp_store = MEMORY;")
    }

    private func errorMessage() -> String {
        String(cString: sqlite3_errmsg(handle))
    }

    var lastInsertedRowID: Int64 {
        sqlite3_last_insert_rowid(handle)
    }

    var changedRowCount: Int32 {
        sqlite3_changes(handle)
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw HolyDatabaseError.prepareFailed(sql: sql, code: prepareResult, message: errorMessage())
        }

        return statement
    }

    private func bind(_ bindings: [HolyDatabaseBinding], to statement: OpaquePointer, sql: String) throws {
        for (index, binding) in bindings.enumerated() {
            let parameterIndex = Int32(index + 1)
            let result: Int32

            switch binding {
            case .null:
                result = sqlite3_bind_null(statement, parameterIndex)
            case let .text(value):
                result = value.withCString {
                    sqlite3_bind_text(statement, parameterIndex, $0, -1, sqliteTransientDestructor)
                }
            case let .int(value):
                result = sqlite3_bind_int(statement, parameterIndex, value)
            case let .int64(value):
                result = sqlite3_bind_int64(statement, parameterIndex, value)
            case let .double(value):
                result = sqlite3_bind_double(statement, parameterIndex, value)
            case let .bool(value):
                result = sqlite3_bind_int(statement, parameterIndex, value ? 1 : 0)
            case let .blob(value):
                result = value.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(
                        statement,
                        parameterIndex,
                        bytes.baseAddress,
                        Int32(bytes.count),
                        sqliteTransientDestructor
                    )
                }
            }

            guard result == SQLITE_OK else {
                throw HolyDatabaseError.executeFailed(sql: sql, code: result, message: errorMessage())
            }
        }
    }
}

private let sqliteTransientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
