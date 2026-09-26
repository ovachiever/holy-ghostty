import Foundation
import SQLite3
import Testing
@testable import Ghostty

/// mn-59bbbf: restore preflight's archive refresh never runs indexing or
/// SQLite writes on the main actor, never walks a whole provider, appends
/// what grew instead of rewriting a session, and treats an unchanged
/// transcript as a no-op on every content table.
struct HolyArchiveRestoreRefreshTests {
    /// Apple, "Understanding hangs in your app": "Most of Apple's developer
    /// tools start reporting issues when the period of unresponsiveness for
    /// the main run loop exceeds 250 ms." The ticker samples 25 times per
    /// threshold so a blocked main actor cannot hide between two samples.
    private static let mainRunLoopHangThreshold: Duration = .milliseconds(250)
    private static let tickerPeriod: Duration = mainRunLoopHangThreshold / 25

    /// The work order asks for a "multi-megabyte" transcript: at least two.
    private static let multiMegabyteFloorBytes = 2 * 1_048_576

    // MARK: - Main actor stays responsive

    @Test @MainActor
    func mainActorKeepsTickingWhileResolveBatchRefreshesAStaleTranscript() async throws {
        var fixture = try ClaudeTranscriptFixture.make(pairs: 1_400)
        defer { fixture.remove() }
        let size = try #require(
            try fixture.transcript.resourceValues(forKeys: [.fileSizeKey]).fileSize
        )
        #expect(size >= Self.multiMegabyteFloorBytes)

        let accounting = HolyArchiveWriteAccounting(isEnabled: { true }, sink: { _ in })
        let recorder = ProviderThreadRecorder()
        let provider = RecordingClaudeProvider(inner: fixture.provider, recorder: recorder)
        let resolver = HolyArchiveRestoreResolver(
            databaseURL: fixture.databaseURL,
            legacyDatabaseURL: nil,
            registry: .init(providers: [provider]),
            accounting: accounting
        )
        let request = try fixture.request()

        // First pass: the archive has never seen the session; it is found
        // through the project directory and indexed.
        let first = await resolver.resolveBatch([request])
        guard case let .resolved(firstResults) = first else {
            Issue.record("Expected native batch resolution on the first pass")
            return
        }
        #expect(firstResults.first?.candidates.map(\.id) == [fixture.sessionID])

        // The transcript grows while the session runs; the row is now stale.
        try fixture.append(pairs: 100)
        let staleRequest = try fixture.request()
        // The first pass took this project's 120-second reindex claim
        // (HolyArchiveRestoreResolver.claimInterval), which stops a second
        // preflight inside that window from refreshing again. Release it
        // here, as the clock would, so the timed call performs the refresh.
        try Self.releaseReindexClaims(databaseURL: fixture.databaseURL)
        accounting.reset()
        recorder.reset()

        let ticker = MainActorTicker(period: Self.tickerPeriod)
        let queueProbe = MainQueueProbe()
        ticker.start()
        queueProbe.arm()
        let clock = ContinuousClock()
        let started = clock.now
        let second = await resolver.resolveBatch([staleRequest])
        let elapsed = clock.now - started
        let ticks = await ticker.stop()

        guard case let .resolved(secondResults) = second else {
            Issue.record("Expected native batch resolution on the stale pass")
            return
        }
        #expect(secondResults.first?.candidates.map(\.id) == [fixture.sessionID])
        let diagnostics = "resolveBatch took \(elapsed); ticks=\(ticks.count) longestGap=\(ticks.longestGap) "
            + "firstTickAfter=\(String(describing: ticks.firstTickAfterStart)) "
            + "mainQueueBlockRanAfter=\(String(describing: queueProbe.ranAfterArm))"
        #expect(ticks.count > 0, Comment(rawValue: diagnostics))
        #expect(ticks.longestGap < Self.mainRunLoopHangThreshold, Comment(rawValue: diagnostics))
        #expect(accounting.snapshot().mainThreadStatements == 0)
        #expect(recorder.mainThreadCalls == 0)
        #expect(recorder.calls > 0)

        let repository = try HolyArchiveRepository(databaseURL: fixture.databaseURL, accounting: accounting)
        #expect(try repository.session(id: fixture.sessionID)?.messageCount == fixture.messageCount)
    }

    // MARK: - Append what grew

    @Test func staleTranscriptRefreshWritesOnlyTheAppendedRows() async throws {
        var fixture = try ClaudeTranscriptFixture.make(pairs: 300)
        defer { fixture.remove() }
        let accounting = HolyArchiveWriteAccounting(isEnabled: { true }, sink: { _ in })
        let repository = try HolyArchiveRepository(databaseURL: fixture.databaseURL, accounting: accounting)
        let indexer = HolyArchiveIndexer(
            repository: repository,
            registry: .init(providers: [fixture.provider]),
            pacer: .init(budget: .unthrottled)
        )
        let initial = await indexer.indexPaths(provider: fixture.provider, paths: [fixture.transcript])
        #expect(initial.failures.isEmpty)
        #expect(initial.sessionsIndexed == 1)
        let storedBefore = try repository.messages(sessionID: fixture.sessionID)
        #expect(storedBefore.count == fixture.messageCount)
        let messageRowIDsBefore = try Self.rowIDs(
            table: "archive_messages", sessionID: fixture.sessionID, databaseURL: fixture.databaseURL
        )
        let chunkRowIDsBefore = try Self.rowIDs(
            table: "archive_chunks", sessionID: fixture.sessionID, databaseURL: fixture.databaseURL
        )
        let chunksBefore = try repository.chunkFingerprints(sessionID: fixture.sessionID)
        // One message per turn pack: each fixture message is over 1.4 KB and
        // the chunker closes a pack before a second one would exceed
        // HolyArchiveChunker.targetTokens, so every pre-existing pack is full
        // and an append can never rewrite one.
        #expect(chunksBefore.filter { $0.id.contains(":turn:") }.count == fixture.messageCount)

        let appendedPairs = 100
        try fixture.append(pairs: appendedPairs)
        accounting.reset()

        let resolver = HolyArchiveRestoreResolver(
            databaseURL: fixture.databaseURL,
            legacyDatabaseURL: nil,
            registry: .init(providers: [fixture.provider]),
            accounting: accounting
        )
        let outcome = await resolver.resolveBatch([try fixture.request()])
        guard case let .resolved(results) = outcome else {
            Issue.record("Expected native batch resolution")
            return
        }
        #expect(results.first?.candidates.map(\.id) == [fixture.sessionID])

        let writes = accounting.snapshot()
        let appendedMessages = appendedPairs * 2
        #expect(writes.rows(table: "archive_messages", verb: .insert) == appendedMessages)
        #expect(writes.rows(table: "archive_messages", verb: .delete) == 0)
        #expect(writes.rows(table: "archive_messages", verb: .update) == 0)
        #expect(writes.rows(table: "archive_staged_messages") == 0)
        #expect(writes.rows(table: "archive_staged_chunks") == 0)
        #expect(writes.rows(table: "archive_chunks", verb: .insert) == appendedMessages)
        #expect(writes.rows(table: "archive_chunks", verb: .delete) == 0)
        #expect(writes.rows(table: "archive_chunks", verb: .update) == 0)
        #expect(writes.rows(table: "archive_sessions", verb: .update) == 1)
        #expect(writes.mainThreadStatements == 0)

        // The rows that existed before the append are the same rows after it.
        let messageRowIDsAfter = try Self.rowIDs(
            table: "archive_messages", sessionID: fixture.sessionID, databaseURL: fixture.databaseURL
        )
        #expect(Array(messageRowIDsAfter.prefix(messageRowIDsBefore.count)) == messageRowIDsBefore)
        #expect(messageRowIDsAfter.count == fixture.messageCount)
        let chunkRowIDsAfter = try Self.rowIDs(
            table: "archive_chunks", sessionID: fixture.sessionID, databaseURL: fixture.databaseURL
        )
        #expect(Set(chunkRowIDsBefore).isSubset(of: Set(chunkRowIDsAfter)))
        #expect(chunkRowIDsAfter.count == chunkRowIDsBefore.count + appendedMessages)

        let stored = try repository.messages(sessionID: fixture.sessionID)
        #expect(stored.count == fixture.messageCount)
        #expect(Array(stored.prefix(storedBefore.count)) == storedBefore)
        #expect(try repository.session(id: fixture.sessionID)?.messageCount == fixture.messageCount)
        let database = try HolyDatabase.open(at: fixture.databaseURL, readOnly: true)
        #expect(try database.scalarInt64("SELECT COUNT(*) FROM archive_messages_fts;") == Int64(fixture.messageCount))
        let row = try #require(try repository.indexRows(rawPaths: [fixture.transcript.path]).first)
        #expect(row.ingestDigest == HolyArchiveIndexer.ingestDigest(of: stored))
    }

    // MARK: - Unchanged content is a no-op

    @Test func unchangedTranscriptWithANewModificationDateWritesNoContentRows() async throws {
        let fixture = try ClaudeTranscriptFixture.make(pairs: 40)
        defer { fixture.remove() }
        let accounting = HolyArchiveWriteAccounting(isEnabled: { true }, sink: { _ in })
        let repository = try HolyArchiveRepository(databaseURL: fixture.databaseURL, accounting: accounting)
        let indexer = HolyArchiveIndexer(
            repository: repository,
            registry: .init(providers: [fixture.provider]),
            pacer: .init(budget: .unthrottled)
        )
        _ = await indexer.indexPaths(provider: fixture.provider, paths: [fixture.transcript])
        let before = try #require(try repository.session(id: fixture.sessionID))

        // Same bytes, newer mtime: the file reads as stale until re-read.
        let touched = before.fileMTime.addingTimeInterval(1)
        try FileManager.default.setAttributes(
            [.modificationDate: touched], ofItemAtPath: fixture.transcript.path
        )
        accounting.reset()
        let resolver = HolyArchiveRestoreResolver(
            databaseURL: fixture.databaseURL,
            legacyDatabaseURL: nil,
            registry: .init(providers: [fixture.provider]),
            accounting: accounting
        )
        let outcome = await resolver.resolveBatch([try fixture.request()])
        guard case let .resolved(results) = outcome else {
            Issue.record("Expected native batch resolution")
            return
        }
        #expect(results.first?.candidates.map(\.id) == [fixture.sessionID])

        let writes = accounting.snapshot()
        #expect(writes.rows(table: "archive_messages") == 0)
        #expect(writes.rows(table: "archive_chunks") == 0)
        #expect(writes.rows(table: "archive_staged_messages") == 0)
        #expect(writes.rows(table: "archive_staged_chunks") == 0)
        // The one bookkeeping write: file_mtime and indexed_at, so the row
        // stops reading as stale.
        #expect(writes.rows(table: "archive_sessions", verb: .update) == 1)
        #expect(writes.rows(table: "archive_sessions", verb: .insert) == 0)
        #expect(writes.rows(table: "archive_sessions", verb: .delete) == 0)
        #expect(writes.mainThreadStatements == 0)

        let after = try #require(try repository.session(id: fixture.sessionID))
        #expect(HolyArchiveFileTime.matches(after.fileMTime, touched))
        #expect(after.messageCount == before.messageCount)
        #expect(after.contentHash == before.contentHash)
        #expect(try repository.messages(sessionID: fixture.sessionID).count == fixture.messageCount)
    }

    // MARK: - Never a whole-provider walk

    @Test func restoreRefreshTouchesOnlyTheCandidatesOfTheRowsBeingResolved() async throws {
        let root = try Self.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("archive.sqlite3")
        let accounting = HolyArchiveWriteAccounting(isEnabled: { true }, sink: { _ in })
        let repository = try HolyArchiveRepository(databaseURL: databaseURL, accounting: accounting)
        let project = root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let projectPath = project.standardizedFileURL.resolvingSymlinksInPath().path
        let elsewhere = root.appendingPathComponent("elsewhere", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath().path
        let files = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let activity: TimeInterval = 1_790_000_000

        var sessions: [HolyArchiveSession] = []
        for offset in 0..<33 {
            let inProject = offset < 3
            let id = inProject ? "project-\(offset)" : "other-\(offset)"
            let file = files.appendingPathComponent("\(id).jsonl")
            try Data("{}\n".utf8).write(to: file)
            let mtime = try #require(
                try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            )
            var session = Self.fixtureSession(
                id: id,
                projectPath: inProject ? projectPath : elsewhere,
                rawPath: file.path,
                fileMTime: mtime,
                activity: activity - Double(offset)
            )
            session.firstPrompt = "current prompt \(offset)"
            sessions.append(session)
            // The archive row for project-0 predates the file: stale.
            var stored = session
            if offset == 0 {
                stored = Self.fixtureSession(
                    id: id, projectPath: projectPath, rawPath: file.path,
                    fileMTime: .distantPast, activity: activity
                )
                stored.firstPrompt = "stale prompt"
            }
            try repository.replace(session: stored, messages: [], chunks: [])
        }

        let provider = CountingCodexLikeProvider(root: files, sessions: sessions)
        let resolver = HolyArchiveRestoreResolver(
            databaseURL: databaseURL,
            legacyDatabaseURL: nil,
            registry: .init(providers: [provider]),
            accounting: accounting
        )
        let outcome = await resolver.resolveBatch([
            .init(cwd: project.path, harness: "codex", near: Int(activity)),
        ])
        guard case let .resolved(results) = outcome, let result = results.first else {
            Issue.record("Expected native batch resolution")
            return
        }
        #expect(result.candidates.map(\.id) == ["project-0", "project-1", "project-2"])
        #expect(provider.wholeDiscoveries == 0)
        #expect(provider.parsedPaths == [files.appendingPathComponent("project-0.jsonl").path])
        // Three staleness checks (one per candidate) and one inside the
        // scoped refresh of the single stale file; never one per session.
        #expect(provider.modificationDateCalls == 4)
        #expect(try repository.session(id: "project-0")?.firstPrompt == "current prompt 0")
        #expect(accounting.snapshot().mainThreadStatements == 0)
    }

    // MARK: - Deletion index and trigger scope

    @Test func chunkMessageIndexExistsForFreshArchivesAndIsRebuiltBeforeAReplacement() throws {
        let root = try Self.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("archive.sqlite3")
        let repository = try HolyArchiveRepository(
            databaseURL: databaseURL,
            accounting: .init(isEnabled: { false })
        )
        #expect(try Self.indexNames(databaseURL: databaseURL).contains("archive_chunks_message_idx"))
        #expect(try HolyDatabaseMigratorProbe.userVersion(databaseURL: databaseURL) == HolyArchiveDatabaseSchema.currentUserVersion)

        let database = try HolyDatabase.open(at: databaseURL)
        try database.execute("DROP INDEX archive_chunks_message_idx;")
        #expect(!(try Self.indexNames(databaseURL: databaseURL).contains("archive_chunks_message_idx")))
        let plainPlan = try Self.deletePlan(databaseURL: databaseURL)
        #expect(plainPlan.contains { $0.contains("SCAN archive_chunks") })

        let session = Self.fixtureSession(
            id: "indexed", projectPath: "/project", rawPath: "/archive/indexed.jsonl",
            fileMTime: Date(timeIntervalSince1970: 1_790_000_000), activity: 1_790_000_000
        )
        try repository.replace(session: session, messages: [], chunks: [])
        #expect(try Self.indexNames(databaseURL: databaseURL).contains("archive_chunks_message_idx"))
        let indexedPlan = try Self.deletePlan(databaseURL: databaseURL)
        #expect(!indexedPlan.contains { $0.contains("SCAN archive_chunks") })
        #expect(indexedPlan.contains { $0.contains("archive_chunks_message_idx") })
    }

    @Test func sessionUpdateTriggerIsScopedToTheColumnsTheFTSMirrors() throws {
        let root = try Self.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("archive.sqlite3")
        _ = try HolyArchiveRepository(databaseURL: databaseURL, accounting: .init(isEnabled: { false }))
        let database = try HolyDatabase.open(at: databaseURL, readOnly: true)
        var triggerSQL = ""
        try database.query(
            "SELECT sql FROM sqlite_master WHERE type = 'trigger' AND name = 'archive_sessions_au';"
        ) { statement in
            if let value = sqlite3_column_text(statement, 0) { triggerSQL = String(cString: value) }
        }
        #expect(triggerSQL.contains("AFTER UPDATE OF first_prompt_preview, project_name, auto_tags_json ON archive_sessions"))
        #expect(try HolyArchiveDatabaseMigrator.columnExists("ingest_digest", table: "archive_sessions", in: database))
    }

    // MARK: - Write accounting

    @Test func writeAccountingBucketsByMinuteAndIsSilentWhenDisabled() {
        let sink = LineRecorder()
        let clock = ClockBox(now: Date(timeIntervalSince1970: 1_790_000_000))
        let accounting = HolyArchiveWriteAccounting(
            isEnabled: { true },
            now: { clock.now },
            sink: { sink.append($0) }
        )
        accounting.record(table: "archive_messages", verb: .insert, rows: 3)
        accounting.record(table: "archive_messages", verb: .insert, rows: 2)
        #expect(sink.lines.isEmpty)
        clock.advance(by: 60)
        accounting.record(table: "archive_sessions", verb: .update, rows: 1)
        #expect(sink.lines.count == 1)
        #expect(sink.lines.first?.contains("archive_messages insert statements=2 rows=5") == true)
        #expect(sink.lines.first?.contains("minute=2026-09-") == true)
        accounting.flush()
        #expect(sink.lines.count == 2)
        #expect(sink.lines.last?.contains("archive_sessions update statements=1 rows=1") == true)

        let snapshot = accounting.snapshot()
        #expect(snapshot.rows(table: "archive_messages") == 5)
        #expect(snapshot.statements(table: "archive_messages") == 2)
        #expect(snapshot.rows == 6)
        #expect(snapshot.statements == 3)

        let disabled = HolyArchiveWriteAccounting(isEnabled: { false }, sink: { sink.append($0) })
        disabled.record(table: "archive_messages", verb: .delete, rows: 9)
        disabled.flush()
        #expect(disabled.snapshot().byKey.isEmpty)
        #expect(sink.lines.count == 2)
    }

    // MARK: - OpenCode narrows by directory

    @Test func openCodeProviderNarrowsDiscoveryByDirectoryAndReadsOneRowForModificationDate() throws {
        let root = try Self.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appendingPathComponent(".local/share/opencode", isDirectory: true)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        do {
            let database = try HolyDatabase.open(at: storage.appendingPathComponent("opencode.db"))
            try database.execute(
                "CREATE TABLE session (id TEXT PRIMARY KEY, parent_id TEXT, directory TEXT, title TEXT, model TEXT, agent TEXT, time_created REAL, time_updated REAL);"
            )
            try database.execute(
                "INSERT INTO session VALUES ('ses_a', NULL, '/repo/a', 'A', NULL, NULL, 1700000000000, 1700000060000);"
            )
            try database.execute(
                "INSERT INTO session VALUES ('ses_b', NULL, '/repo/b', 'B', NULL, NULL, 1700000000000, 1700000120000);"
            )
        }
        let provider = HolyOpenCodeArchiveProvider(homeDirectory: root)
        let narrowed = try #require(try provider.discoverSessionFiles(forProjectPath: "/repo/a"))
        #expect(narrowed.map { $0.deletingPathExtension().lastPathComponent } == ["ses_a"])
        #expect(try provider.discoverSessionFiles(forProjectPath: "/repo/none")?.isEmpty == true)
        let url = try #require(narrowed.first)
        #expect(try provider.modificationDate(for: url).timeIntervalSince1970 == 1_700_000_060)

        let withoutDatabase = HolyOpenCodeArchiveProvider(homeDirectory: try Self.temporaryRoot())
        #expect(try withoutDatabase.discoverSessionFiles(forProjectPath: "/repo/a") == nil)
    }

    // MARK: - Stable chunk identity

    @Test func toolChunkIDsStayStableWhenMessagesAreAppended() {
        let session = Self.fixtureSession(
            id: "tools", projectPath: "/project", rawPath: "/archive/tools.jsonl",
            fileMTime: Date(timeIntervalSince1970: 1_790_000_000), activity: 1_790_000_000
        )
        let first = HolyArchiveMessage(
            id: "m0", sessionID: session.id, role: .user,
            content: "please run\nagent-do browse open https://example.com", timestamp: nil, sequence: 0
        )
        let second = HolyArchiveMessage(
            id: "m1", sessionID: session.id, role: .assistant, content: "done", timestamp: nil, sequence: 1
        )
        let before = HolyArchiveChunker.chunks(session: session, messages: [first, second])
        let toolIDsBefore = before.filter { $0.type == .toolUsage }.map(\.id)
        #expect(toolIDsBefore == ["tools:tool:0:0"])

        let third = HolyArchiveMessage(
            id: "m2", sessionID: session.id, role: .user,
            content: "and then\nagent-do git status\nagent-do notify send hi", timestamp: nil, sequence: 2
        )
        let after = HolyArchiveChunker.chunks(session: session, messages: [first, second, third])
        let toolIDsAfter = after.filter { $0.type == .toolUsage }.map(\.id)
        #expect(toolIDsAfter == ["tools:tool:0:0", "tools:tool:2:0", "tools:tool:2:1"])
        // Every tool chunk that existed before keeps its id and its content.
        // The summary chunk changes because its "Tools used" line names the
        // new tools, and these three short messages share one turn pack,
        // which grows; neither is a tool chunk.
        let beforeByID = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0) })
        for chunk in after where chunk.type == .toolUsage && beforeByID[chunk.id] != nil {
            #expect(beforeByID[chunk.id]?.content == chunk.content)
            #expect(beforeByID[chunk.id]?.messageID == chunk.messageID)
        }
        #expect(after.first { $0.type == .summary }?.content != before.first { $0.type == .summary }?.content)
    }

    @Test func chunkReconciliationDeletesGoneInsertsNewRewritesChangedAndMovesUnchanged() {
        func chunk(_ id: String, index: Int, content: String) -> HolyArchiveChunk {
            .init(
                id: id, sessionID: "s", messageID: nil, index: index, type: .turn,
                content: content, metadata: ["chunk_type": "turn"], embedding: nil,
                embeddingModel: nil, createdAt: Date(timeIntervalSince1970: 0)
            )
        }
        let existing: [HolyArchiveChunkFingerprint] = [
            .init(id: "a", index: 0, content: "a", metadata: ["chunk_type": "turn"]),
            .init(id: "b", index: 1, content: "b", metadata: ["chunk_type": "turn"]),
            .init(id: "c", index: 2, content: "c", metadata: ["chunk_type": "turn"]),
            .init(id: "gone", index: 3, content: "gone", metadata: ["chunk_type": "turn"]),
        ]
        let desired = [
            chunk("a", index: 0, content: "a"),
            chunk("b", index: 1, content: "b changed"),
            chunk("c", index: 3, content: "c"),
            chunk("d", index: 2, content: "d"),
        ]
        let plan = HolyArchiveIndexer.chunkReconciliation(existing: existing, desired: desired)
        #expect(plan.deletions == ["gone", "b"])
        #expect(plan.insertions.map(\.id) == ["b", "d"])
        #expect(plan.reindexes.map(\.id) == ["c"])
        #expect(plan.reindexes.map(\.index) == [3])
    }

    @Test func ingestDigestFollowsMessageIdentityAndContent() {
        let base = [
            HolyArchiveMessage(id: "m0", sessionID: "s", role: .user, content: "hello", timestamp: nil, sequence: 0),
            HolyArchiveMessage(id: "m1", sessionID: "s", role: .assistant, content: "world", timestamp: nil, sequence: 1),
        ]
        let same = HolyArchiveIndexer.ingestDigest(of: base)
        #expect(same == HolyArchiveIndexer.ingestDigest(of: base))
        #expect(same.count == 64)
        var edited = base
        edited[1] = .init(id: "m1", sessionID: "s", role: .assistant, content: "world!", timestamp: nil, sequence: 1)
        #expect(HolyArchiveIndexer.ingestDigest(of: edited) != same)
        #expect(HolyArchiveIndexer.ingestDigest(of: base + [edited[1]]) != same)
    }

    // MARK: - Helpers

    private static func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-archive-restore-refresh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func releaseReindexClaims(databaseURL: URL) throws {
        let database = try HolyDatabase.open(at: databaseURL)
        try database.execute("DELETE FROM archive_index_meta WHERE key LIKE 'resolve_reindex:%';")
    }

    private static func rowIDs(table: String, sessionID: String, databaseURL: URL) throws -> [Int64] {
        let database = try HolyDatabase.open(at: databaseURL, readOnly: true)
        var ids: [Int64] = []
        try database.query(
            "SELECT rowid FROM \(table) WHERE session_id = ? ORDER BY rowid;",
            bindings: [.text(sessionID)]
        ) { statement in
            ids.append(sqlite3_column_int64(statement, 0))
        }
        return ids
    }

    private static func indexNames(databaseURL: URL) throws -> Set<String> {
        let database = try HolyDatabase.open(at: databaseURL, readOnly: true)
        var names = Set<String>()
        try database.query("SELECT name FROM sqlite_master WHERE type = 'index';") { statement in
            if let value = sqlite3_column_text(statement, 0) { names.insert(String(cString: value)) }
        }
        return names
    }

    private static func deletePlan(databaseURL: URL) throws -> [String] {
        let database = try HolyDatabase.open(at: databaseURL)
        var details: [String] = []
        try database.query("EXPLAIN QUERY PLAN DELETE FROM archive_messages WHERE session_id = 'x';") { statement in
            if let value = sqlite3_column_text(statement, 3) { details.append(String(cString: value)) }
        }
        return details
    }

    private static func fixtureSession(
        id: String,
        projectPath: String,
        rawPath: String,
        fileMTime: Date,
        activity: TimeInterval
    ) -> HolyArchiveSession {
        .init(
            id: id, harness: .codex, rawPath: rawPath, projectPath: projectPath,
            projectName: URL(fileURLWithPath: projectPath).lastPathComponent,
            title: "Fixture \(id)", firstPrompt: "Build the fixture for \(id)",
            lastPrompt: "Verify the fixture", lastResponse: "Fixture verified",
            createdAt: Date(timeIntervalSince1970: activity - 60),
            modifiedAt: Date(timeIntervalSince1970: activity), isChild: false,
            childType: nil, parentID: nil, model: "fixture-model", toolCalls: [],
            tokensUsed: nil, summary: nil, contentHash: "hash-\(id)", extra: [:],
            resumeCommand: "codex resume \(id)", messageCount: 0, turnCount: 0,
            fileMTime: fileMTime, indexedAt: Date(timeIntervalSince1970: activity),
            autoTags: []
        )
    }
}

/// A Claude Code home directory with one project and one JSONL transcript,
/// parsed by the production provider. Every message carries over 1.4 KB of
/// prose so `pairs` sizes the file in the megabytes and every chunker pack
/// holds exactly one message.
private struct ClaudeTranscriptFixture {
    let root: URL
    let home: URL
    let projectPath: String
    let sessionID: String
    let transcript: URL
    let databaseURL: URL
    let provider: HolyClaudeArchiveProvider
    private(set) var pairs: Int

    var messageCount: Int { pairs * 2 }

    private static let baseTimestamp = Date(timeIntervalSince1970: 1_790_000_000)
    private static let prose = String(repeating: "restore preflight transcript fixture ", count: 40)

    static func make(pairs: Int) throws -> ClaudeTranscriptFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-archive-claude-fixture-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let projectPath = project.standardizedFileURL.resolvingSymlinksInPath().path
        let sessionID = "fixture-\(UUID().uuidString.lowercased())"
        let directory = home
            .appendingPathComponent(".claude/projects", isDirectory: true)
            .appendingPathComponent(HolyClaudeArchiveProvider.encodeProjectPath(projectPath), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let transcript = directory.appendingPathComponent("\(sessionID).jsonl")
        var fixture = ClaudeTranscriptFixture(
            root: root,
            home: home,
            projectPath: projectPath,
            sessionID: sessionID,
            transcript: transcript,
            databaseURL: root.appendingPathComponent("archive.sqlite3"),
            provider: HolyClaudeArchiveProvider(homeDirectory: home),
            pairs: 0
        )
        try Data(fixture.lines(from: 0, count: pairs).utf8).write(to: transcript)
        fixture.pairs = pairs
        return fixture
    }

    mutating func append(pairs count: Int) throws {
        let handle = try FileHandle(forWritingTo: transcript)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(lines(from: pairs, count: count).utf8))
        pairs += count
    }

    func request() throws -> HolyRestoreResolveBatchRequest {
        let mtime = try transcript.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        return .init(cwd: projectPath, harness: "claude", near: Int((mtime ?? .now).timeIntervalSince1970))
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private func lines(from start: Int, count: Int) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var rows: [String] = []
        for pair in start..<(start + count) {
            let userTime = Self.baseTimestamp.addingTimeInterval(TimeInterval(pair * 2))
            let assistantTime = userTime.addingTimeInterval(1)
            let user: [String: Any] = [
                "type": "user",
                "cwd": projectPath,
                "sessionId": sessionID,
                "uuid": "user-\(pair)",
                "timestamp": formatter.string(from: userTime),
                "version": "1.0.0",
                "gitBranch": "main",
                "message": ["role": "user", "content": "Turn \(pair) request: \(Self.prose)"],
            ]
            let assistant: [String: Any] = [
                "type": "assistant",
                "uuid": "assistant-\(pair)",
                "timestamp": formatter.string(from: assistantTime),
                "message": [
                    "role": "assistant",
                    "model": "fixture-model",
                    "content": [["type": "text", "text": "Turn \(pair) response: \(Self.prose)"]],
                ],
            ]
            for row in [user, assistant] {
                guard let data = try? JSONSerialization.data(withJSONObject: row),
                      let line = String(data: data, encoding: .utf8) else { continue }
                rows.append(line)
            }
        }
        return rows.joined(separator: "\n") + "\n"
    }
}

/// Wraps the production Claude provider and records the thread of every call.
private struct RecordingClaudeProvider: HolyArchiveProviding {
    let inner: HolyClaudeArchiveProvider
    let recorder: ProviderThreadRecorder

    var harness: HolyArchiveHarness { inner.harness }
    var sessionsDirectory: URL { inner.sessionsDirectory }

    func discoverSessionFiles() throws -> [URL] {
        recorder.note()
        return try inner.discoverSessionFiles()
    }

    func discoverSessionFiles(forProjectPath projectPath: String) throws -> [URL]? {
        recorder.note()
        return try inner.discoverSessionFiles(forProjectPath: projectPath)
    }

    func modificationDate(for url: URL) throws -> Date {
        recorder.note()
        return try inner.modificationDate(for: url)
    }

    func parseSession(at url: URL) throws -> (HolyArchiveSession, [HolyArchiveMessage])? {
        recorder.note()
        return try inner.parseSession(at: url)
    }

    func resumeCommand(for session: HolyArchiveSession) -> String? {
        inner.resumeCommand(for: session)
    }
}

private final class ProviderThreadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    private var mainThreadCallCount = 0

    var calls: Int { lock.withLock { callCount } }
    var mainThreadCalls: Int { lock.withLock { mainThreadCallCount } }

    func note() {
        let onMain = Thread.isMainThread
        lock.withLock {
            callCount += 1
            if onMain { mainThreadCallCount += 1 }
        }
    }

    func reset() {
        lock.withLock {
            callCount = 0
            mainThreadCallCount = 0
        }
    }
}

/// A provider that, like Codex and OpenCode's legacy tree, cannot narrow
/// discovery to a project, and counts every call the resolver makes.
private final class CountingCodexLikeProvider: HolyArchiveProviding, @unchecked Sendable {
    let harness = HolyArchiveHarness.codex
    let root: URL
    let sessions: [HolyArchiveSession]
    private let lock = NSLock()
    private var wholeDiscoveryCount = 0
    private var modificationDateCount = 0
    private var parsed: [String] = []

    init(root: URL, sessions: [HolyArchiveSession]) {
        self.root = root
        self.sessions = sessions
    }

    var sessionsDirectory: URL { root }
    var wholeDiscoveries: Int { lock.withLock { wholeDiscoveryCount } }
    var modificationDateCalls: Int { lock.withLock { modificationDateCount } }
    var parsedPaths: [String] { lock.withLock { parsed } }

    func discoverSessionFiles() throws -> [URL] {
        lock.withLock { wholeDiscoveryCount += 1 }
        return sessions.map { URL(fileURLWithPath: $0.rawPath) }
    }

    func discoverSessionFiles(forProjectPath projectPath: String) throws -> [URL]? {
        nil
    }

    func modificationDate(for url: URL) throws -> Date {
        lock.withLock { modificationDateCount += 1 }
        return try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
    }

    func parseSession(at url: URL) throws -> (HolyArchiveSession, [HolyArchiveMessage])? {
        lock.withLock { parsed.append(url.path) }
        guard let session = sessions.first(where: { $0.rawPath == url.path }) else { return nil }
        return (session, [
            .init(
                id: "\(session.id)-u", sessionID: session.id, role: .user,
                content: session.firstPrompt, timestamp: session.createdAt, sequence: 0
            ),
        ])
    }

    func resumeCommand(for session: HolyArchiveSession) -> String? {
        "codex resume \(session.id)"
    }
}

/// Samples the main actor: every wakeup records the gap since the previous
/// one, so any stretch where the main actor could not run shows up as the
/// longest gap.
@MainActor
private final class MainActorTicker {
    struct Report {
        let count: Int
        let longestGap: Duration
        let firstTickAfterStart: Duration?
    }

    private let period: Duration
    private var task: Task<Void, Never>?
    private var count = 0
    private var longestGap: Duration = .zero
    private var firstTickAfterStart: Duration?

    init(period: Duration) {
        self.period = period
    }

    func start() {
        let period = period
        task = Task { @MainActor [weak self] in
            let clock = ContinuousClock()
            let started = clock.now
            var last = started
            while true {
                // A cancelled sleep throws at once; that wakeup is not a tick.
                guard (try? await Task.sleep(for: period)) != nil else { return }
                let now = clock.now
                guard let self else { return }
                if self.firstTickAfterStart == nil { self.firstTickAfterStart = now - started }
                self.longestGap = max(self.longestGap, now - last)
                self.count += 1
                last = now
            }
        }
    }

    /// Cancels the ticker and waits for its task to finish, so the report
    /// includes every tick that had already run.
    func stop() async -> Report {
        task?.cancel()
        await task?.value
        task = nil
        return Report(count: count, longestGap: longestGap, firstTickAfterStart: firstTickAfterStart)
    }
}

/// A GCD block on the main queue: independent of Swift concurrency's main
/// actor hop, it tells whether the main queue was drained at all while the
/// call ran.
private final class MainQueueProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var armedAt: ContinuousClock.Instant?
    private var ranAt: ContinuousClock.Instant?

    func arm() {
        let clock = ContinuousClock()
        lock.withLock { armedAt = clock.now }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.withLock { self.ranAt = clock.now }
        }
    }

    var ranAfterArm: Duration? {
        lock.withLock {
            guard let armedAt, let ranAt else { return nil }
            return ranAt - armedAt
        }
    }
}

private final class LineRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    var lines: [String] { lock.withLock { values } }

    func append(_ line: String) {
        lock.withLock { values.append(line) }
    }
}

private final class ClockBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(now: Date) {
        value = now
    }

    var now: Date { lock.withLock { value } }

    func advance(by seconds: TimeInterval) {
        lock.withLock { value = value.addingTimeInterval(seconds) }
    }
}

private enum HolyDatabaseMigratorProbe {
    static func userVersion(databaseURL: URL) throws -> Int32 {
        try HolyDatabase.open(at: databaseURL, readOnly: true).userVersion()
    }
}
