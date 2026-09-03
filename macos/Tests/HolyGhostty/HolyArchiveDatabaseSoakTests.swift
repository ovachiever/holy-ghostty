import Foundation
import SQLite3
import Testing
@testable import Ghostty

private let holyArchiveRealCorpusSoakEnabled = {
    let environment = ProcessInfo.processInfo.environment
    return environment["HOLY_ARCHIVE_SOAK"] == "1"
        || environment["TEST_RUNNER_HOLY_ARCHIVE_SOAK"] == "1"
}()

/// Opt-in acceptance test for mn-b775ac. The caller supplies copies of the
/// real provider home and workspace database. The test never opens production
/// persistence for writing.
struct HolyArchiveDatabaseSoakTests {
    @Test(.enabled(if: holyArchiveRealCorpusSoakEnabled))
    func fullCorpusIngestDoesNotStallWorkspaceWrites() async throws {
        let environment = ProcessInfo.processInfo.environment
        let homePath = try #require(Self.environmentValue("HOLY_ARCHIVE_SOAK_HOME", in: environment))
        let workspacePath = try #require(Self.environmentValue("HOLY_ARCHIVE_SOAK_WORKSPACE_DATABASE", in: environment))
        let archivePath = try #require(Self.environmentValue("HOLY_ARCHIVE_SOAK_ARCHIVE_DATABASE", in: environment))
        let receiptPath = try #require(Self.environmentValue("HOLY_ARCHIVE_SOAK_RECEIPT", in: environment))
        let homeURL = URL(fileURLWithPath: homePath, isDirectory: true)
        let workspaceURL = URL(fileURLWithPath: workspacePath)
        let archiveURL = URL(fileURLWithPath: archivePath)
        let receiptURL = URL(fileURLWithPath: receiptPath)

        #expect(workspaceURL.standardizedFileURL != archiveURL.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: workspaceURL.path))

        let registry = HolyArchiveProviderRegistry(homeDirectory: homeURL)
        let providers = registry.availableProviders
        var discoveredSourceCount = 0
        for provider in providers {
            discoveredSourceCount += try provider.discoverSessionFiles().count
        }
        #expect(discoveredSourceCount > 0)

        let repository = try HolyArchiveRepository(databaseURL: archiveURL)
        let indexer = HolyArchiveIndexer(
            repository: repository,
            registry: registry,
            pacer: .init(budget: .production, isForeground: { false })
        )
        let progressRecorder = HolyArchiveSoakProgressRecorder()
        let workspaceWriter = try await HolyArchiveSoakWorkspaceWriter(databaseURL: workspaceURL)
        let clock = ContinuousClock()

        await workspaceWriter.write(sequence: 0, scheduledAt: clock.now)
        let writerTask = Task {
            var sequence = 1
            while !Task.isCancelled {
                let scheduledAt = clock.now
                await workspaceWriter.write(sequence: sequence, scheduledAt: scheduledAt)
                sequence += 1
                try? await Task.sleep(for: .milliseconds(10))
            }
        }

        let indexReceipt = await indexer.fullReindex { progress in
            await progressRecorder.record(progress)
        }
        writerTask.cancel()
        await writerTask.value

        let workspaceMetrics = await workspaceWriter.metrics()
        let progress = await progressRecorder.snapshot()
        let archive = try HolyDatabase.open(at: archiveURL, readOnly: true)
        let sessionCount = try archive.scalarInt64("SELECT COUNT(*) FROM archive_sessions;")
        let messageCount = try archive.scalarInt64("SELECT COUNT(*) FROM archive_messages;")
        let chunkCount = try archive.scalarInt64("SELECT COUNT(*) FROM archive_chunks;")
        let messageFTSCount = try archive.scalarInt64("SELECT COUNT(*) FROM archive_messages_fts;")
        let sessionFTSCount = try archive.scalarInt64("SELECT COUNT(*) FROM archive_sessions_fts;")
        let integrity = try archive.scalarText("PRAGMA integrity_check;")
        let sortedDatabaseLatencies = workspaceMetrics.databaseLatenciesMilliseconds.sorted()
        let sortedEndToEndLatencies = workspaceMetrics.endToEndLatenciesMilliseconds.sorted()
        let maximumDatabaseLatency = sortedDatabaseLatencies.last ?? .infinity
        let p99DatabaseLatency = Self.percentile(0.99, values: sortedDatabaseLatencies)
        let maximumEndToEndLatency = sortedEndToEndLatencies.last ?? .infinity
        let p99EndToEndLatency = Self.percentile(0.99, values: sortedEndToEndLatencies)

        let receipt = HolyArchiveSoakReceipt(
            completedAt: ISO8601DateFormatter().string(from: .now),
            providerCount: providers.count,
            discoveredSourceCount: discoveredSourceCount,
            sessionsIndexed: indexReceipt.sessionsIndexed,
            messagesIndexed: indexReceipt.messagesIndexed,
            chunksCreated: indexReceipt.chunksCreated,
            archiveSessionCount: sessionCount,
            archiveMessageCount: messageCount,
            archiveChunkCount: chunkCount,
            progressTotal: progress.maximumTotal,
            ingestElapsedMilliseconds: indexReceipt.elapsedMilliseconds,
            ingestFailures: indexReceipt.failures,
            workspaceWriteSamples: sortedDatabaseLatencies.count,
            workspaceWriteFailures: workspaceMetrics.failures,
            dbWriteMaxMilliseconds: maximumDatabaseLatency,
            dbWriteP99Milliseconds: p99DatabaseLatency,
            endToEndMaxMilliseconds: maximumEndToEndLatency,
            endToEndP99Milliseconds: p99EndToEndLatency,
            endToEndOver100MillisecondCount: sortedEndToEndLatencies.count { $0 >= 100 },
            archiveIntegrityCheck: integrity
        )
        try FileManager.default.createDirectory(
            at: receiptURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(receipt).write(to: receiptURL, options: .atomic)

        #expect(indexReceipt.failures.isEmpty)
        #expect(indexReceipt.sessionsIndexed > 0)
        #expect(progress.maximumTotal == discoveredSourceCount)
        #expect(workspaceMetrics.failures.isEmpty)
        #expect(sortedDatabaseLatencies.count >= 2)
        #expect(maximumDatabaseLatency < 100)
        #expect(p99EndToEndLatency < 100)
        #expect(messageFTSCount == messageCount)
        #expect(sessionFTSCount == sessionCount)
        #expect(integrity == "ok")
    }

    private static func percentile(_ percentile: Double, values: [Double]) -> Double {
        guard !values.isEmpty else { return .infinity }
        let index = Int((Double(values.count - 1) * percentile).rounded(.up))
        return values[min(max(0, index), values.count - 1)]
    }

    private static func environmentValue(
        _ key: String,
        in environment: [String: String]
    ) -> String? {
        environment[key] ?? environment["TEST_RUNNER_\(key)"]
    }
}

@MainActor
private final class HolyArchiveSoakWorkspaceWriter {
    struct Metrics: Sendable {
        let databaseLatenciesMilliseconds: [Double]
        let endToEndLatenciesMilliseconds: [Double]
        let failures: [String]
    }

    private let database: HolyDatabase
    private let sessionID: String
    private var nextEventSequence: Int64
    private var databaseLatenciesMilliseconds: [Double] = []
    private var endToEndLatenciesMilliseconds: [Double] = []
    private var failures: [String] = []

    init(databaseURL: URL) throws {
        database = try HolyDatabase.open(at: databaseURL)
        var selectedSessionID: String?
        try database.query("SELECT id FROM sessions ORDER BY updated_at DESC LIMIT 1;") { statement in
            guard let bytes = sqlite3_column_text(statement, 0) else { return }
            selectedSessionID = String(cString: bytes)
        }
        sessionID = try #require(selectedSessionID)
        nextEventSequence = try database.scalarInt64(
            "SELECT COALESCE(MAX(sequence), 0) + 1 FROM session_events WHERE session_id = '\(Self.sqlLiteral(sessionID))';"
        )
    }

    func write(sequence: Int, scheduledAt: ContinuousClock.Instant) {
        let clock = ContinuousClock()
        let databaseStartedAt = clock.now
        do {
            try database.withTransaction {
                try database.execute(
                    """
                    INSERT INTO app_state(key, value_json, updated_at)
                    VALUES ('archive-soak', ?, ?)
                    ON CONFLICT(key) DO UPDATE SET value_json = excluded.value_json,
                                                   updated_at = excluded.updated_at;
                    """,
                    bindings: [
                        .text("{\"sequence\":\(sequence)}"),
                        .text(ISO8601DateFormatter().string(from: .now)),
                    ]
                )
                try database.execute(
                    """
                    INSERT INTO session_events(
                        session_id, sequence, occurred_at, event_type, phase, attention, payload_json
                    ) VALUES (?, ?, ?, 'session_agent_state_changed', NULL, NULL, ?);
                    """,
                    bindings: [
                        .text(sessionID),
                        .int64(nextEventSequence),
                        .text(ISO8601DateFormatter().string(from: .now)),
                        .text("{\"soak_sequence\":\(sequence)}"),
                    ]
                )
            }
            nextEventSequence += 1
        } catch {
            failures.append(error.localizedDescription)
        }
        let completedAt = clock.now
        databaseLatenciesMilliseconds.append(Self.milliseconds(
            databaseStartedAt.duration(to: completedAt)
        ))
        endToEndLatenciesMilliseconds.append(Self.milliseconds(
            scheduledAt.duration(to: completedAt)
        ))
    }

    func metrics() -> Metrics {
        .init(
            databaseLatenciesMilliseconds: databaseLatenciesMilliseconds,
            endToEndLatenciesMilliseconds: endToEndLatenciesMilliseconds,
            failures: failures
        )
    }

    private static func sqlLiteral(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}

private actor HolyArchiveSoakProgressRecorder {
    struct Snapshot: Sendable {
        let maximumTotal: Int
    }

    private var maximumTotal = 0

    func record(_ progress: HolyArchiveIndexProgress) {
        maximumTotal = max(maximumTotal, progress.total)
    }

    func snapshot() -> Snapshot {
        .init(maximumTotal: maximumTotal)
    }
}

private struct HolyArchiveSoakReceipt: Codable {
    let completedAt: String
    let providerCount: Int
    let discoveredSourceCount: Int
    let sessionsIndexed: Int
    let messagesIndexed: Int
    let chunksCreated: Int
    let archiveSessionCount: Int64
    let archiveMessageCount: Int64
    let archiveChunkCount: Int64
    let progressTotal: Int
    let ingestElapsedMilliseconds: Double
    let ingestFailures: [String]
    let workspaceWriteSamples: Int
    let workspaceWriteFailures: [String]
    let dbWriteMaxMilliseconds: Double
    let dbWriteP99Milliseconds: Double
    let endToEndMaxMilliseconds: Double
    let endToEndP99Milliseconds: Double
    let endToEndOver100MillisecondCount: Int
    let archiveIntegrityCheck: String
}
