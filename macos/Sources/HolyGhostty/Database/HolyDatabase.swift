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

final class HolyDatabase {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mitchellh.ghostty",
        category: "HolyDatabase"
    )
    private static let bootstrapLock = NSLock()
    private static var hasBootstrapped = false

    let url: URL
    private let handle: OpaquePointer

    private init(url: URL, handle: OpaquePointer) {
        self.url = url
        self.handle = handle
    }

    deinit {
        sqlite3_close_v2(handle)
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

        var handle: OpaquePointer?
        let flags: Int32
        if readOnly {
            flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        } else {
            flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        }

        let result = sqlite3_open_v2(url.path, &handle, flags, nil)
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

        return sqlite3_column_int(statement, 0)
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

    private func configure(readOnly: Bool) throws {
        try execute("PRAGMA foreign_keys = ON;")

        guard !readOnly else { return }

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
            }

            guard result == SQLITE_OK else {
                throw HolyDatabaseError.executeFailed(sql: sql, code: result, message: errorMessage())
            }
        }
    }
}

private let sqliteTransientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
