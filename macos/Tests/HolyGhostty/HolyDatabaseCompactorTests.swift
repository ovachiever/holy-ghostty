import Foundation
import Testing
@testable import Ghostty

struct HolyDatabaseCompactorTests {
    // MARK: - Threshold gating (pure)

    @Test func absoluteReclaimableSizeCrossesThreshold() {
        // 512 MB of dead pages at 4 KB/page.
        let pages = HolyDatabaseCompactor.minimumReclaimableBytes / 4096
        let assessment = HolyDatabaseCompactor.Assessment(
            pageSize: 4096,
            pageCount: pages * 10,
            freelistCount: pages
        )
        #expect(assessment.exceedsCompactionThreshold)
    }

    @Test func smallButMostlyHollowFileCrossesThreshold() {
        let assessment = HolyDatabaseCompactor.Assessment(
            pageSize: 4096,
            pageCount: 100,
            freelistCount: 30 // 30% dead
        )
        #expect(assessment.reclaimableFraction >= HolyDatabaseCompactor.minimumReclaimableFraction)
        #expect(assessment.exceedsCompactionThreshold)
    }

    @Test func modestFragmentationStaysBelowThreshold() {
        let assessment = HolyDatabaseCompactor.Assessment(
            pageSize: 4096,
            pageCount: 100,
            freelistCount: 10 // 10% dead, far under 512 MB
        )
        #expect(!assessment.exceedsCompactionThreshold)
    }

    @Test func aCleanFileIsNeverBloated() {
        let assessment = HolyDatabaseCompactor.Assessment(
            pageSize: 4096,
            pageCount: 1_000,
            freelistCount: 0
        )
        #expect(assessment.reclaimableFraction == 0)
        #expect(!assessment.exceedsCompactionThreshold)
    }

    @Test func reclaimedBytesReflectsShrink() {
        let before = HolyDatabaseCompactor.Assessment(pageSize: 4096, pageCount: 1_000, freelistCount: 400)
        let after = HolyDatabaseCompactor.Assessment(pageSize: 4096, pageCount: 600, freelistCount: 0)
        let decision = HolyDatabaseCompactor.Decision.compacted(before: before, after: after)
        #expect(decision.reclaimedBytes == 400 * 4096)
    }

    // MARK: - In-place reclaim (real VACUUM)

    @Test func vacuumReturnsFreedPagesToTheFilesystem() throws {
        try withTemporaryDatabase { database in
            try database.execute("CREATE TABLE blob_holder (id INTEGER PRIMARY KEY, payload BLOB);")
            try database.withTransaction {
                for _ in 0..<2_000 {
                    try database.execute("INSERT INTO blob_holder (payload) VALUES (zeroblob(4096));")
                }
            }
            try database.execute("DELETE FROM blob_holder;")

            let before = try HolyDatabaseCompactor.assess(database)
            #expect(before.freelistCount > 0)

            let decision = try HolyDatabaseCompactor.maintain(
                database,
                force: true,
                availableCapacity: { Int64.max }
            )
            guard case .compacted = decision else {
                Issue.record("expected .compacted, got \(decision)")
                return
            }

            let after = try HolyDatabaseCompactor.assess(database)
            #expect(after.freelistCount == 0)
            #expect(after.pageCount < before.pageCount)
        }
    }

    @Test func healthyDatabaseIsLeftUntouched() throws {
        try withTemporaryDatabase { database in
            let decision = try HolyDatabaseCompactor.maintain(
                database,
                force: false,
                availableCapacity: { Int64.max }
            )
            guard case .skippedNotBloated = decision else {
                Issue.record("expected .skippedNotBloated, got \(decision)")
                return
            }
        }
    }

    @Test func compactionRefusesWhenTheVolumeCannotHoldTheRewrite() throws {
        try withTemporaryDatabase { database in
            try database.execute("CREATE TABLE blob_holder (id INTEGER PRIMARY KEY, payload BLOB);")
            try database.withTransaction {
                for _ in 0..<64 {
                    try database.execute("INSERT INTO blob_holder (payload) VALUES (zeroblob(4096));")
                }
            }
            try database.execute("DELETE FROM blob_holder;")

            let decision = try HolyDatabaseCompactor.maintain(
                database,
                force: true, // bypass the bloat gate so only the disk gate can stop it
                availableCapacity: { 1 }
            )
            guard case .skippedInsufficientDisk = decision else {
                Issue.record("expected .skippedInsufficientDisk, got \(decision)")
                return
            }
        }
    }

    // MARK: - Helpers

    private func withTemporaryDatabase<T>(_ body: (HolyDatabase) throws -> T) throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-compactor-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = try HolyDatabase.open(at: directory.appendingPathComponent("source.sqlite3"))
        try HolyDatabaseMigrator.migrate(database)
        return try body(database)
    }
}
