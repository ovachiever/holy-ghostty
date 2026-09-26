import Foundation
import SQLite3
import Testing
@testable import Ghostty

/// Receipts for mn-2c8f51: a flush rewrites nothing that is already on disk,
/// the writer connection outlives the flush, and what the flush committed is
/// on disk when `save` returns even if the process dies before any
/// checkpoint. Every count comes from SQLite's own hooks on the production
/// connection, never from grepping.
struct HolyWorkspacePersistenceWriteChurnTests {
    // Fixture shape, not a bound: enough sessions for per-row effects to be
    // visible, enough rounds that the second and later flushes dominate.
    private static let sessionCount = 8
    private static let runtimeUpdateRounds = 5
    /// How long a test waits on the checkpoint queue: the app's own ceiling
    /// for waiting on the database (`HolyDatabaseSchema.busyTimeoutMilliseconds`).
    private static let databaseWaitSeconds = TimeInterval(HolyDatabaseSchema.busyTimeoutMilliseconds) / 1_000

    // MARK: - Deliverable 4: N sessions, M runtime updates

    @MainActor
    @Test func runtimeUpdatesWriteNoJSONAndAtMostOneRowPerChangedRow() throws {
        try withTemporaryDirectory { directory in
            let writer = try makeWriter(in: directory)
            let jsonURL = directory.appendingPathComponent("workspace-state.json")
            let counter = try RowWriteCounter.install(on: writer.openConnection())

            let records = (0..<Self.sessionCount).map { index in sessionRecord(index: index) }
            let baseSnapshot = HolyWorkspaceSnapshot(
                sessions: records,
                selectedSessionID: records.first?.id,
                templates: [template()],
                archivedSessions: [archivedSession(sourceSessionID: UUID(), gitSnapshot: gitSnapshot(branch: "main"))],
                paneLayout: .single,
                attentionMetadata: records.map { attentionMetadata(sessionID: $0.id) }
            )

            var jsonReceipts: [HolyWorkspaceLegacySnapshotWriteReceipt] = []
            var databaseReceipts: [HolyWorkspaceSaveReceipt] = []

            for round in 0..<Self.runtimeUpdateRounds {
                // Even-indexed sessions produce output this round (preview,
                // telemetry, and the record's activity clock move); odd ones
                // are untouched since round 0.
                let changedIndices = Set(records.indices.filter { round > 0 && $0.isMultiple(of: 2) })
                var snapshot = baseSnapshot
                for index in changedIndices {
                    snapshot.sessions[index].updatedAt = Self.baseDate.addingTimeInterval(TimeInterval(round))
                }
                let liveStates = records.enumerated().map { index, record in
                    liveState(for: record.id, round: changedIndices.contains(index) ? round : 0)
                }
                let events = changedIndices.map { index in
                    HolySessionEventDraft(
                        sessionID: records[index].id,
                        occurredAt: Self.baseDate.addingTimeInterval(TimeInterval(round)),
                        eventType: .runtimeUpdated,
                        phase: .working,
                        attention: .watch,
                        payload: .init(activityKind: .editing)
                    )
                }

                counter.reset()
                let receipt = try writer.save(
                    .init(
                        snapshot: snapshot,
                        liveSessionStates: liveStates,
                        attentionBySessionID: [:],
                        pendingEvents: events
                    )
                )
                databaseReceipts.append(receipt)
                jsonReceipts.append(HolyWorkspacePersistence.save(snapshot, to: jsonURL))

                if round == 0 {
                    #expect(counter.inserts["sessions"] == Self.sessionCount + 1)
                    #expect(receipt.templatesRewritten)
                    #expect(receipt.gitSnapshotsInserted == 1)
                    continue
                }

                // At most one row write per changed row: each changed session
                // is one UPDATE, no INSERT, no DELETE; unchanged sessions,
                // the archive row, templates, app_state, and git_snapshots
                // are not touched; events are appends only.
                #expect(counter.updates["sessions"] == changedIndices.count, "round \(round): \(counter.summary)")
                #expect(counter.inserts["sessions"] ?? 0 == 0)
                #expect(counter.deletes["sessions"] ?? 0 == 0)
                #expect(counter.inserts["session_events"] == changedIndices.count)
                #expect(counter.writes(to: "app_state") == 0)
                #expect(counter.writes(to: "templates") == 0)
                #expect(counter.writes(to: "git_snapshots") == 0)
                #expect(counter.writes(to: "budget_samples") == 0)
                #expect(counter.totalWrites == changedIndices.count * 2, "round \(round): \(counter.summary)")
                #expect(receipt.sessionRowsWritten == changedIndices.count)
                #expect(receipt.rowsChanged == Int64(changedIndices.count * 2))
            }

            // Zero JSON rewrites after the first: every later round changed
            // only live fields and activity clocks.
            #expect(jsonReceipts.first == .written(bytes: try Data(contentsOf: jsonURL).count))
            #expect(jsonReceipts.dropFirst().allSatisfy { $0 == .skippedDurableStateUnchanged })
            #expect(writer.connectionOpenCount == 1)
            #expect(writer.flushCount == Self.runtimeUpdateRounds)
            #expect(databaseReceipts.count == Self.runtimeUpdateRounds)

            // The rows carry the last round's live fields.
            let lastRound = Self.runtimeUpdateRounds - 1
            let changedID = records[0].id
            let preview = try writer.openConnection().scalarText(
                "SELECT latest_preview_text FROM sessions WHERE id = '\(changedID.uuidString)';"
            )
            #expect(preview == liveState(for: changedID, round: lastRound).preview)
        }
    }

    @MainActor
    @Test func unchangedFlushWritesNothingAndKeepsTheConnectionOpen() throws {
        try withTemporaryDirectory { directory in
            let writer = try makeWriter(in: directory)
            let databaseURL = writer.databaseURL
            let counter = try RowWriteCounter.install(on: writer.openConnection())
            let snapshot = fixtureSnapshot()
            let liveStates = snapshot.sessions.map { liveState(for: $0.id, round: 0) }

            let first = try writer.save(.init(snapshot: snapshot, liveSessionStates: liveStates))
            #expect(first.wroteAnything)
            let walSizeAfterFirst = fileSize(at: walURL(for: databaseURL))
            let databaseModifiedAfterFirst = modificationDate(at: databaseURL)
            let firstConnection = try writer.openConnection()

            counter.reset()
            let second = try writer.save(.init(snapshot: snapshot, liveSessionStates: liveStates))

            #expect(second == HolyWorkspaceSaveReceipt())
            #expect(counter.totalWrites == 0, "\(counter.summary)")
            #expect(fileSize(at: walURL(for: databaseURL)) == walSizeAfterFirst)
            #expect(modificationDate(at: databaseURL) == databaseModifiedAfterFirst)
            #expect(try writer.openConnection() === firstConnection)
            #expect(writer.connectionOpenCount == 1)
            #expect(writer.flushCount == 2)
        }
    }

    // MARK: - Deliverable 3: crash restore inputs stay durable

    @MainActor
    @Test func committedFlushSurvivesTheWriterDyingBeforeAnyCheckpoint() throws {
        try withTemporaryDirectory { directory in
            let writer = try makeWriter(in: directory)
            let databaseURL = writer.databaseURL
            let snapshot = fixtureSnapshot()
            let liveStates = snapshot.sessions.map { liveState(for: $0.id, round: 3) }

            try writer.save(.init(snapshot: snapshot, liveSessionStates: liveStates))

            // Nothing has been checkpointed: the flush lives in the WAL only,
            // and the writer is still open (no close checkpoint either).
            let policy = try #require(try writer.openConnection().checkpointPolicy)
            #expect(policy.completedCheckpointCount == 0)
            #expect(fileSize(at: walURL(for: databaseURL)) > 0)
            #expect(writer.isConnected)

            // A SIGKILL leaves exactly the bytes on disk: the main file and
            // the WAL. The -shm is rebuilt from the WAL on the next open.
            let crashCopy = try copyDatabaseAsAfterCrash(databaseURL, to: directory.appendingPathComponent("crash"))
            let restored = try HolyDatabase.open(at: crashCopy, readOnly: true)
            let loaded = try #require(try HolyWorkspaceDatabasePersistence.load(from: restored))

            #expect(loaded.sessions.map(\.id) == snapshot.sessions.map(\.id))
            #expect(loaded.selectedSessionID == snapshot.selectedSessionID)
            #expect(loaded.templates.map(\.id) == snapshot.templates.map(\.id))
            #expect(loaded.archivedSessions.map(\.id) == snapshot.archivedSessions.map(\.id))
            #expect(loaded.archivedSessions.first?.gitSnapshot == snapshot.archivedSessions.first?.gitSnapshot)
            #expect(loaded.attentionMetadata == snapshot.attentionMetadata)

            let preview = try restored.scalarText(
                "SELECT latest_preview_text FROM sessions WHERE id = '\(snapshot.sessions[0].id.uuidString)';"
            )
            #expect(preview == liveStates[0].preview)

            // The main file alone does not carry the flush: the WAL was the
            // durable carrier, which is why the commit sync matters.
            let mainOnly = try copyDatabaseAsAfterCrash(
                databaseURL,
                to: directory.appendingPathComponent("main-only"),
                includeWAL: false
            )
            let withoutWAL = try? HolyDatabase.open(at: mainOnly, readOnly: true)
            let loadedWithoutWAL = withoutWAL.flatMap { try? HolyWorkspaceDatabasePersistence.load(from: $0) }
            #expect(loadedWithoutWAL?.sessions.map(\.id) != snapshot.sessions.map(\.id))
        }
    }

    @MainActor
    @Test func flushKilledBeforeCommitLeavesThePreviousFlushIntactAndTheWriterRecovers() throws {
        try withTemporaryDirectory { directory in
            let writer = try makeWriter(in: directory)
            let databaseURL = writer.databaseURL
            let first = fixtureSnapshot()
            try writer.save(.init(snapshot: first, liveSessionStates: first.sessions.map { liveState(for: $0.id, round: 0) }))

            var second = first
            second.sessions.append(sessionRecord(index: 99))
            second.selectedSessionID = second.sessions.last?.id
            second.templates = []

            // The writer executes every statement of the second flush, then
            // dies at the instant before COMMIT: the commit hook snapshots
            // the bytes on disk at that instant and vetoes the commit.
            let crashDirectory = directory.appendingPathComponent("crash")
            var crashCopy: URL?
            let interceptor = try CommitInterceptor.install(on: writer.openConnection()) {
                crashCopy = try? copyDatabaseAsAfterCrash(databaseURL, to: crashDirectory)
                return .veto
            }
            defer { withExtendedLifetime(interceptor) {} }

            #expect(throws: HolyDatabaseError.self) {
                try writer.save(.init(snapshot: second, liveSessionStates: second.sessions.map { liveState(for: $0.id, round: 1) }))
            }
            #expect(!writer.isConnected)
            let copy = try #require(crashCopy)

            let restored = try HolyDatabase.open(at: copy, readOnly: true)
            let loadedFromCrash = try #require(try HolyWorkspaceDatabasePersistence.load(from: restored))
            #expect(loadedFromCrash.sessions.map(\.id) == first.sessions.map(\.id))
            #expect(loadedFromCrash.selectedSessionID == first.selectedSessionID)
            #expect(loadedFromCrash.templates.map(\.id) == first.templates.map(\.id))

            let live = try HolyDatabase.open(at: databaseURL, readOnly: true)
            let loadedLive = try #require(try HolyWorkspaceDatabasePersistence.load(from: live))
            #expect(loadedLive.sessions.map(\.id) == first.sessions.map(\.id))

            // The next flush reopens the writer and lands the second state.
            let receipt = try writer.save(.init(snapshot: second, liveSessionStates: second.sessions.map { liveState(for: $0.id, round: 1) }))
            #expect(receipt.wroteAnything)
            #expect(writer.connectionOpenCount == 2)
            let loadedAfterRecovery = try #require(try HolyWorkspaceDatabasePersistence.load(from: live))
            #expect(loadedAfterRecovery.sessions.map(\.id) == second.sessions.map(\.id))
            #expect(loadedAfterRecovery.selectedSessionID == second.selectedSessionID)
            #expect(loadedAfterRecovery.templates.isEmpty)
        }
    }

    // MARK: - Deliverable 2: connection lifetime and checkpoint policy

    @MainActor
    @Test func durableWriterCarriesTheCloseCheckpointsSyncGuarantee() throws {
        try withTemporaryDirectory { directory in
            let databaseURL = directory.appendingPathComponent("durable.sqlite3")
            let plain = try HolyDatabase.open(at: databaseURL)
            let libraryThreshold = try plain.scalarInt32("PRAGMA wal_autocheckpoint;")
            let plainSynchronous = try plain.scalarInt32("PRAGMA synchronous;")
            plain.close()

            let writer = try HolyDatabase.openDurableWriter(at: databaseURL)
            defer { writer.close() }

            #expect(try writer.scalarText("PRAGMA journal_mode;") == "wal")
            // synchronous: 1 = NORMAL (the plain connection), 2 = FULL.
            #expect(plainSynchronous == 1)
            #expect(try writer.scalarInt32("PRAGMA synchronous;") == 2)
            #expect(try writer.scalarInt32("PRAGMA fullfsync;") == 1)
            let policy = try #require(writer.checkpointPolicy)
            #expect(policy.walFrameThreshold == libraryThreshold)
            #expect(policy.walFrameThreshold > 0)
        }
    }

    @MainActor
    @Test func walCheckpointRunsOffTheCommittingThreadAtTheLibraryThreshold() throws {
        try withTemporaryDirectory { directory in
            let writer = try makeWriter(in: directory)
            let connection = try writer.openConnection()
            let policy = try #require(connection.checkpointPolicy)
            let pageSize = try connection.scalarInt64("PRAGMA page_size;")

            let observed = CheckpointObservation()
            policy.addObserver { receipt, offMainThread in
                observed.record(receipt: receipt, offMainThread: offMainThread)
            }

            // Fill the WAL past the library threshold in one transaction: one
            // page-sized row per frame.
            try connection.execute("CREATE TABLE churn_probe (id INTEGER PRIMARY KEY, payload BLOB NOT NULL);")
            let payload = Data(repeating: 0x5A, count: Int(pageSize))
            try connection.withTransaction {
                for _ in 0...Int(policy.walFrameThreshold) {
                    try connection.execute(
                        "INSERT INTO churn_probe (payload) VALUES (?);",
                        bindings: [.blob(payload)]
                    )
                }
            }

            #expect(Thread.isMainThread)
            let receipt = try #require(observed.wait(seconds: Self.databaseWaitSeconds))
            #expect(observed.offMainThread == true)
            #expect(receipt.walFrames >= Int(policy.walFrameThreshold))
            #expect(receipt.checkpointedFrames == receipt.walFrames)
            #expect(receipt.isComplete)
            #expect(policy.completedCheckpointCount == 1)

            // The main file now holds the pages the checkpoint copied.
            let mainFileSize = fileSize(at: writer.databaseURL)
            #expect(mainFileSize >= Int64(policy.walFrameThreshold) * pageSize)
        }
    }

    @MainActor
    @Test func inPlaceCompactionSucceedsWhileTheDurableWriterIsOpen() throws {
        try withTemporaryDirectory { directory in
            let writer = try makeWriter(in: directory)
            let snapshot = fixtureSnapshot()
            try writer.save(.init(snapshot: snapshot, liveSessionStates: snapshot.sessions.map { liveState(for: $0.id, round: 0) }))
            #expect(writer.isConnected)

            let maintenance = try HolyDatabase.open(at: writer.databaseURL)
            let decision = try HolyDatabaseCompactor.maintain(maintenance, force: true, availableCapacity: { .max })
            guard case .compacted = decision else {
                Issue.record("expected an in-place compaction, got \(decision)")
                return
            }

            // The writer is still usable afterwards.
            let receipt = try writer.save(.init(snapshot: snapshot, liveSessionStates: snapshot.sessions.map { liveState(for: $0.id, round: 1) }))
            #expect(receipt.sessionRowsWritten == snapshot.sessions.count)
            #expect(writer.connectionOpenCount == 1)
        }
    }

    @MainActor
    @Test func orderlyQuitFoldsTheWALAndTheNextFlushReopens() throws {
        try withTemporaryDirectory { directory in
            let writer = try makeWriter(in: directory)
            let databaseURL = writer.databaseURL
            let snapshot = fixtureSnapshot()
            try writer.save(.init(snapshot: snapshot, liveSessionStates: snapshot.sessions.map { liveState(for: $0.id, round: 0) }))
            #expect(fileSize(at: walURL(for: databaseURL)) > 0)

            let receipt = try #require(writer.checkpointAndClose())
            #expect(receipt.isComplete)
            #expect(!writer.isConnected)
            // The last connection's close removes the WAL once it is folded.
            #expect(fileSize(at: walURL(for: databaseURL)) == 0)

            let reader = try HolyDatabase.open(at: databaseURL, readOnly: true)
            let loaded = try #require(try HolyWorkspaceDatabasePersistence.load(from: reader))
            #expect(loaded.sessions.map(\.id) == snapshot.sessions.map(\.id))
            reader.close()

            try writer.save(.init(snapshot: snapshot, liveSessionStates: snapshot.sessions.map { liveState(for: $0.id, round: 1) }))
            #expect(writer.connectionOpenCount == 2)
            #expect(writer.isConnected)
        }
    }

    // MARK: - Deliverable 1: the legacy snapshot

    @MainActor
    @Test func legacySnapshotRewritesOnlyForDurableChangesAndExactlyAtQuit() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("workspace-state.json")
            let snapshot = fixtureSnapshot()

            #expect(HolyWorkspacePersistence.save(snapshot, to: url) == .written(bytes: fileSizeInt(at: url)))

            var activityOnly = snapshot
            for index in activityOnly.sessions.indices {
                activityOnly.sessions[index].updatedAt = Self.baseDate.addingTimeInterval(60)
            }
            #expect(activityOnly.durableStateEquals(snapshot))
            #expect(HolyWorkspacePersistence.save(activityOnly, to: url) == .skippedDurableStateUnchanged)
            #expect(HolyWorkspacePersistence.load(from: url).sessions.map(\.updatedAt) == snapshot.sessions.map(\.updatedAt))

            var retitled = activityOnly
            retitled.sessions[0].launchSpec.title = "renamed"
            #expect(!retitled.durableStateEquals(snapshot))
            #expect(HolyWorkspacePersistence.save(retitled, to: url) == .written(bytes: fileSizeInt(at: url)))
            #expect(HolyWorkspacePersistence.load(from: url).sessions[0].launchSpec.title == "renamed")

            // A fresh run compares against the bytes on disk before writing.
            HolyWorkspacePersistence.forgetJournalForTesting(at: url)
            #expect(HolyWorkspacePersistence.save(retitled, to: url) == .skippedIdenticalOnDisk)

            var selectionChanged = retitled
            selectionChanged.selectedSessionID = retitled.sessions.last?.id
            #expect(HolyWorkspacePersistence.save(selectionChanged, to: url) == .written(bytes: fileSizeInt(at: url)))

            // At quit the activity clocks land exactly.
            var atQuit = selectionChanged
            for index in atQuit.sessions.indices {
                atQuit.sessions[index].updatedAt = Self.baseDate.addingTimeInterval(120)
            }
            #expect(HolyWorkspacePersistence.save(atQuit, to: url) == .skippedDurableStateUnchanged)
            #expect(HolyWorkspacePersistence.flushForTermination(to: url) == .written(bytes: fileSizeInt(at: url)))
            #expect(HolyWorkspacePersistence.load(from: url).sessions.map(\.updatedAt) == atQuit.sessions.map(\.updatedAt))
            #expect(HolyWorkspacePersistence.flushForTermination(to: url) == .skippedIdenticalOnDisk)
        }
    }

    // MARK: - Fixtures

    private static let baseDate = Date(timeIntervalSince1970: 1_790_000_000)

    @MainActor
    private func makeWriter(in directory: URL) throws -> HolyWorkspaceDatabaseWriter {
        let writer = HolyWorkspaceDatabaseWriter(databaseURL: directory.appendingPathComponent("holy-ghostty.sqlite3"))
        try HolyDatabaseMigrator.migrate(try writer.openConnection())
        return writer
    }

    private func fixtureSnapshot() -> HolyWorkspaceSnapshot {
        let records = (0..<Self.sessionCount).map { index in sessionRecord(index: index) }
        return HolyWorkspaceSnapshot(
            sessions: records,
            selectedSessionID: records.first?.id,
            templates: [template()],
            archivedSessions: [archivedSession(sourceSessionID: UUID(), gitSnapshot: gitSnapshot(branch: "main"))],
            paneLayout: .single,
            attentionMetadata: records.map { attentionMetadata(sessionID: $0.id) }
        )
    }

    private func sessionRecord(index: Int) -> HolySessionRecord {
        var launchSpec = HolySessionLaunchSpec.interactiveTmuxShell(title: "churn \(index)")
        launchSpec.tmux = .init(
            socketName: HolySessionTmuxSpec.defaultSocketName,
            sessionName: "churn-\(index)",
            createIfMissing: true
        )
        launchSpec.workingDirectory = "/tmp/churn-\(index)"
        return HolySessionRecord(
            id: UUID(),
            launchSpec: launchSpec,
            createdAt: Self.baseDate,
            updatedAt: Self.baseDate
        )
    }

    private func liveState(for sessionID: UUID, round: Int) -> HolyWorkspaceLiveSessionState {
        var runtimeTelemetry = HolySessionRuntimeTelemetry.empty
        runtimeTelemetry.activityKind = round == 0 ? .idle : .editing
        runtimeTelemetry.headline = round == 0 ? nil : "round \(round)"
        var budgetTelemetry = HolySessionBudgetTelemetry.empty
        budgetTelemetry.totalTokens = round * 1_000
        return HolyWorkspaceLiveSessionState(
            sessionID: sessionID,
            phase: round == 0 ? .active : .working,
            preview: "output line \(round) of \(sessionID.uuidString)",
            signals: [],
            commandTelemetry: .empty,
            budgetTelemetry: budgetTelemetry,
            runtimeTelemetry: runtimeTelemetry,
            gitSnapshot: nil,
            workingDirectory: "/tmp/churn",
            repositoryRoot: nil,
            worktreePath: nil,
            branchName: nil
        )
    }

    private func attentionMetadata(sessionID: UUID) -> HolySessionAttentionMetadata {
        HolySessionAttentionMetadata(
            sessionID: sessionID,
            lastSeenAt: Self.baseDate,
            seenTrackingVersion: HolySessionAttentionMetadata.currentSeenTrackingVersion,
            updatedAt: Self.baseDate
        )
    }

    private func template() -> HolySessionTemplate {
        HolySessionTemplate(
            id: UUID(),
            name: "Churn template",
            summary: "fixture",
            launchSpec: .interactiveTmuxShell(title: "template"),
            createdAt: Self.baseDate,
            updatedAt: Self.baseDate
        )
    }

    private func archivedSession(sourceSessionID: UUID, gitSnapshot: HolyGitSnapshot?) -> HolyArchivedSession {
        var launchSpec = HolySessionLaunchSpec.interactiveTmuxShell(title: "Archived churn")
        launchSpec.tmux = .init(
            socketName: HolySessionTmuxSpec.defaultSocketName,
            sessionName: "archived-\(sourceSessionID.uuidString)",
            createIfMissing: true
        )
        let record = HolySessionRecord(
            id: sourceSessionID,
            launchSpec: launchSpec,
            createdAt: Self.baseDate.addingTimeInterval(-120),
            updatedAt: Self.baseDate.addingTimeInterval(-60)
        )
        return HolyArchivedSession(
            id: UUID(),
            sourceSessionID: sourceSessionID,
            record: record,
            phase: .completed,
            preview: "archived preview",
            signals: [],
            commandTelemetry: .empty,
            budgetTelemetry: .empty,
            runtimeTelemetry: .empty,
            gitSnapshot: gitSnapshot,
            lastKnownWorkingDirectory: "/tmp",
            lastActivityAt: Self.baseDate.addingTimeInterval(-60),
            archivedAt: Self.baseDate.addingTimeInterval(-30)
        )
    }

    private func gitSnapshot(branch: String) -> HolyGitSnapshot {
        HolyGitSnapshot(
            repositoryRoot: "/tmp/repository",
            worktreePath: "/tmp/repository",
            commonGitDirectory: "/tmp/repository/.git",
            branch: branch,
            upstreamBranch: "origin/\(branch)",
            isDetachedHead: false,
            aheadCount: 0,
            behindCount: 0,
            stagedCount: 0,
            unstagedCount: 1,
            untrackedCount: 0,
            conflictedCount: 0,
            changedFiles: [
                .init(path: "README.md", category: .modified, stagedStatus: " ", unstagedStatus: "M"),
            ]
        )
    }

    // MARK: - Files

    private func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-write-churn-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        return try body(directory)
    }

    private func walURL(for databaseURL: URL) -> URL {
        URL(fileURLWithPath: databaseURL.path + "-wal")
    }

    private func fileSize(at url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func fileSizeInt(at url: URL) -> Int {
        Int(fileSize(at: url))
    }

    private func modificationDate(at url: URL) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date
    }
}

/// Copies what a killed process leaves behind: the main file and, unless
/// told otherwise, the WAL. Never the -shm, which SQLite rebuilds.
private func copyDatabaseAsAfterCrash(_ databaseURL: URL, to directory: URL, includeWAL: Bool = true) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let destination = directory.appendingPathComponent(databaseURL.lastPathComponent)
    try FileManager.default.copyItem(at: databaseURL, to: destination)
    let wal = URL(fileURLWithPath: databaseURL.path + "-wal")
    if includeWAL, FileManager.default.fileExists(atPath: wal.path) {
        try FileManager.default.copyItem(at: wal, to: URL(fileURLWithPath: destination.path + "-wal"))
    }
    return destination
}

/// Counts every row SQLite inserts, updates, or deletes on a connection
/// (`sqlite3_update_hook`): the ground truth for "one row write per changed
/// row".
private final class RowWriteCounter {
    private(set) var inserts: [String: Int] = [:]
    private(set) var updates: [String: Int] = [:]
    private(set) var deletes: [String: Int] = [:]

    static func install(on database: HolyDatabase) -> RowWriteCounter {
        let counter = RowWriteCounter()
        sqlite3_update_hook(
            database.rawHandleForTesting,
            { context, operation, _, tableName, _ in
                guard let context, let tableName else { return }
                Unmanaged<RowWriteCounter>.fromOpaque(context).takeUnretainedValue()
                    .record(operation: operation, table: String(cString: tableName))
            },
            Unmanaged.passRetained(counter).toOpaque()
        )
        return counter
    }

    func reset() {
        inserts = [:]
        updates = [:]
        deletes = [:]
    }

    func writes(to table: String) -> Int {
        (inserts[table] ?? 0) + (updates[table] ?? 0) + (deletes[table] ?? 0)
    }

    var totalWrites: Int {
        inserts.values.reduce(0, +) + updates.values.reduce(0, +) + deletes.values.reduce(0, +)
    }

    var summary: String {
        "inserts=\(inserts) updates=\(updates) deletes=\(deletes)"
    }

    private func record(operation: Int32, table: String) {
        switch operation {
        case SQLITE_INSERT:
            inserts[table, default: 0] += 1
        case SQLITE_UPDATE:
            updates[table, default: 0] += 1
        case SQLITE_DELETE:
            deletes[table, default: 0] += 1
        default:
            break
        }
    }
}

/// Runs at the instant before COMMIT (`sqlite3_commit_hook`) and may veto
/// it, which SQLite turns into a ROLLBACK: the writer has executed every
/// statement of the flush and dies before committing.
private final class CommitInterceptor {
    enum Verdict {
        case commit
        case veto
    }

    private let onCommit: () -> Verdict

    private init(onCommit: @escaping () -> Verdict) {
        self.onCommit = onCommit
    }

    static func install(on database: HolyDatabase, onCommit: @escaping () -> Verdict) -> CommitInterceptor {
        let interceptor = CommitInterceptor(onCommit: onCommit)
        sqlite3_commit_hook(
            database.rawHandleForTesting,
            { context -> Int32 in
                guard let context else { return 0 }
                let interceptor = Unmanaged<CommitInterceptor>.fromOpaque(context).takeUnretainedValue()
                return interceptor.onCommit() == .veto ? 1 : 0
            },
            Unmanaged.passRetained(interceptor).toOpaque()
        )
        return interceptor
    }
}

/// Collects the first checkpoint the policy reports and lets the test wait
/// for it.
private final class CheckpointObservation {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var receipt: HolyDatabaseCheckpointReceipt?
    private(set) var offMainThread: Bool?

    func record(receipt: HolyDatabaseCheckpointReceipt, offMainThread: Bool) {
        lock.lock()
        if self.receipt == nil {
            self.receipt = receipt
            self.offMainThread = offMainThread
        }
        lock.unlock()
        semaphore.signal()
    }

    func wait(seconds: TimeInterval) -> HolyDatabaseCheckpointReceipt? {
        _ = semaphore.wait(timeout: .now() + seconds)
        lock.lock()
        defer { lock.unlock() }
        return receipt
    }
}
