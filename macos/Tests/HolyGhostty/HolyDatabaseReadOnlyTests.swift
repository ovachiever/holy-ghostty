import Foundation
import SQLite3
import Testing
@testable import Ghostty

/// mn-d32871: a READONLY connection to a WAL database cannot create the
/// -shm/-wal companions, so after a checkpoint removes them every prepare
/// failed with SQLITE_CANTOPEN. Read-only opens are now physically
/// read-write (query_only enforced) with a true readonly fallback for
/// files this user cannot write.
struct HolyDatabaseReadOnlyTests {
    private func temporaryDatabaseURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-db-readonly-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("test.sqlite3", isDirectory: false)
    }

    private func notes(in database: HolyDatabase) throws -> [String] {
        var collected: [String] = []
        try database.query("SELECT note FROM facts ORDER BY id;") { statement in
            collected.append(String(cString: sqlite3_column_text(statement, 0)))
        }
        return collected
    }

    /// A WAL database whose companions were checkpointed away: the state
    /// that broke the board digest cache and every other readOnly reader.
    private func makeCheckpointedWALDatabase(at url: URL) throws {
        do {
            let database = try HolyDatabase.open(at: url)
            try database.execute("CREATE TABLE facts (id INTEGER PRIMARY KEY, note TEXT);")
            try database.execute("INSERT INTO facts (note) VALUES ('receipt');")
            try database.execute("PRAGMA wal_checkpoint(TRUNCATE);")
        }
        let base = url.path
        try? FileManager.default.removeItem(atPath: base + "-wal")
        try? FileManager.default.removeItem(atPath: base + "-shm")
        #expect(!FileManager.default.fileExists(atPath: base + "-shm"))
    }

    @Test func readOnlyOpenSurvivesMissingWALCompanions() throws {
        let url = try temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try makeCheckpointedWALDatabase(at: url)

        let readOnly = try HolyDatabase.open(at: url, readOnly: true)
        #expect(try notes(in: readOnly) == ["receipt"])
    }

    @Test func readOnlyConnectionRefusesWrites() throws {
        let url = try temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try makeCheckpointedWALDatabase(at: url)

        let readOnly = try HolyDatabase.open(at: url, readOnly: true)
        #expect(throws: (any Error).self) {
            try readOnly.execute("INSERT INTO facts (note) VALUES ('forbidden');")
        }
        #expect(try notes(in: readOnly) == ["receipt"])
    }

    @Test func unwritableFileFallsBackToTrueReadonlyOpen() throws {
        let url = try temporaryDatabaseURL()
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644], ofItemAtPath: url.path
            )
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        do {
            let database = try HolyDatabase.open(at: url)
            try database.execute("CREATE TABLE facts (id INTEGER PRIMARY KEY, note TEXT);")
            try database.execute("INSERT INTO facts (note) VALUES ('foreign');")
            // A WAL file without companions is unreadable for ANY readonly
            // connection — that is the disease. The fallback path exists for
            // unwritable rollback-journal files, so model exactly that.
            try database.execute("PRAGMA wal_checkpoint(TRUNCATE);")
            try database.execute("PRAGMA journal_mode = DELETE;")
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)

        let readOnly = try HolyDatabase.open(at: url, readOnly: true)
        #expect(try notes(in: readOnly) == ["foreign"])
    }

    @Test func missingFileStillRefusesReadOnlyOpen() throws {
        let url = try temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(throws: (any Error).self) {
            _ = try HolyDatabase.open(at: url, readOnly: true)
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
