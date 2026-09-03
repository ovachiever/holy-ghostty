import Foundation
import SQLite3
import Testing
@testable import Ghostty

struct HolyArchiveModeTests {
    @Test func migrationCreatesNativeArchiveSchema() throws {
        try withRepository { repository, databaseURL, _ in
            _ = repository
            let database = try HolyDatabase.open(at: databaseURL, readOnly: true)
            #expect(try database.userVersion() == HolyArchiveDatabaseSchema.currentUserVersion)
            let names = try tableNames(database)
            #expect(names.contains("archive_sessions"))
            #expect(names.contains("archive_messages_fts"))
            #expect(names.contains("archive_research_chats"))
            #expect(names.contains("archive_annotations"))
            #expect(names.contains("archive_staged_messages"))
            #expect(try database.scalarText("PRAGMA journal_mode;").lowercased() == "wal")
        }
    }

    @Test func archiveAndWorkspaceUseDifferentDatabaseFilesAndWriterLocks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-archive-isolation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspaceURL = root.appendingPathComponent("holy-ghostty.sqlite3")
        let archiveURL = root.appendingPathComponent("holy-archive.sqlite3")
        let workspace = try HolyDatabase.open(at: workspaceURL)
        try HolyDatabaseMigrator.migrate(workspace)
        _ = try HolyArchiveRepository(databaseURL: archiveURL)
        let archiveWriter = try HolyDatabase.open(at: archiveURL)

        #expect(workspaceURL.standardizedFileURL != archiveURL.standardizedFileURL)
        try archiveWriter.execute("BEGIN IMMEDIATE TRANSACTION;")
        defer { try? archiveWriter.execute("ROLLBACK;") }

        let clock = ContinuousClock()
        for value in 0..<20 {
            let started = clock.now
            try workspace.execute(
                """
                INSERT INTO app_state(key, value_json, updated_at) VALUES ('archive-soak', ?, ?)
                ON CONFLICT(key) DO UPDATE SET value_json = excluded.value_json,
                                               updated_at = excluded.updated_at;
                """,
                bindings: [.text(String(value)), .text(String(value))]
            )
            #expect(started.duration(to: clock.now) < .milliseconds(100))
        }
    }

    @Test func legacyDatabaseMigrationResumesByCommittedRowBatch() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-archive-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let legacyURL = root.appendingPathComponent("holy-ghostty.sqlite3")
        let archiveURL = root.appendingPathComponent("holy-archive.sqlite3")
        let legacy = try HolyDatabase.open(at: legacyURL)
        try HolyDatabaseMigrator.migrate(legacy)
        try insertLegacySession(id: "legacy-session", in: legacy)
        try legacy.execute(
            """
            INSERT INTO archive_messages(
                id, session_id, role, content, timestamp, sequence, has_code, tool_mentions_json
            ) VALUES ('legacy-message', 'legacy-session', 'user', 'legacy database migration',
                      1700000000, 0, 0, '[]');
            """
        )

        let migrator = HolyArchiveLegacyDatabaseMigrator(
            sourceURL: legacyURL,
            destinationURL: archiveURL,
            pacer: .init(budget: .unthrottled)
        )
        let interrupted = try await migrator.migrateIfNeeded(maximumBatches: 1)
        #expect(!interrupted.didComplete)
        #expect(interrupted.completedRows == 1)

        let completed = try await migrator.migrateIfNeeded()
        #expect(completed.didComplete)
        let repository = try HolyArchiveRepository(databaseURL: archiveURL)
        #expect(try repository.session(id: "legacy-session")?.title == "Legacy session")
        #expect(try repository.messages(sessionID: "legacy-session").map(\.content) == [
            "legacy database migration",
        ])
        #expect(try legacy.scalarInt64("SELECT COUNT(*) FROM archive_sessions;") == 1)
        let replay = try await migrator.migrateIfNeeded()
        #expect(replay == .init(completedRows: 0, totalRows: 0, didComplete: true))
    }

    @Test func stagedReplacementKeepsLastCompleteSessionUntilAtomicPublish() throws {
        try withRepository { repository, databaseURL, _ in
            let original = sampleSession(id: "resume-safe")
            let originalMessages = sampleMessages(sessionID: original.id, content: "last complete transcript")
            try repository.replace(session: original, messages: originalMessages, chunks: [])

            let replacement = HolyArchiveMessage(
                id: "replacement", sessionID: original.id, role: .assistant,
                content: "new transcript", timestamp: .now, sequence: 0
            )
            let token = try repository.beginReplacement(
                sessionID: original.id,
                expectedMessageCount: 1,
                expectedChunkCount: 0
            )
            try repository.stage(messages: [replacement], for: token)

            #expect(try repository.messages(sessionID: original.id) == originalMessages)
            try repository.replace(session: original, messages: [replacement], chunks: [])
            let published = try repository.messages(sessionID: original.id)
            #expect(published.map(\.id) == [replacement.id])
            #expect(published.map(\.content) == [replacement.content])
            let database = try HolyDatabase.open(at: databaseURL, readOnly: true)
            #expect(try database.scalarInt64("SELECT COUNT(*) FROM archive_staged_messages;") == 0)
        }
    }

    @Test func progressRoundTripsForRelaunchResume() throws {
        try withRepository { repository, _, _ in
            let progress = HolyArchiveIndexProgress(
                phase: .indexing,
                completed: 750,
                total: 79_000,
                detail: "Codex: rollout.jsonl"
            )
            try repository.saveIndexProgress(progress)
            #expect(try repository.storedIndexProgress() == progress)
            try repository.clearIndexProgress()
            #expect(try repository.storedIndexProgress() == nil)
        }
    }

    @Test func foregroundWriteBudgetAppliesStrongerBackpressure() async {
        let budget = HolyArchiveWriteBudget(
            rowsPerTransaction: 25,
            foregroundRowsPerSecond: 100,
            backgroundRowsPerSecond: 1_000,
            checkpointEveryRows: 100,
            maximumPauseNanoseconds: 2_000_000_000
        )
        #expect(budget.delayNanoseconds(afterWritingRows: 50, foreground: true) == 500_000_000)
        #expect(budget.delayNanoseconds(afterWritingRows: 50, foreground: false) == 50_000_000)

        let sleeps = ArchiveSleepRecorder()
        let pacer = HolyArchiveWritePacer(
            budget: budget,
            isForeground: { true },
            sleep: { value in await sleeps.record(value) }
        )
        await pacer.yield(afterWritingRows: 50)
        #expect(await sleeps.values == [500_000_000])
    }

    @Test func embeddingWorkerIsSeparateFromIngestAndCommitsBoundedBatches() async throws {
        try await withRepositoryAsync { repository, _, _ in
            let session = sampleSession(id: "embedding-queue")
            let messages = sampleMessages(sessionID: session.id)
            let chunks = HolyArchiveChunker.chunks(session: session, messages: messages)
            try repository.replace(session: session, messages: messages, chunks: chunks)
            #expect(try repository.embeddingRows().isEmpty)

            let worker = HolyArchiveEmbeddingWorker(
                repository: repository,
                embedder: FixedEmbeddingProvider(vector: [0.25, 0.75]),
                pacer: .init(budget: .unthrottled),
                minimumRequestIntervalNanoseconds: 0
            )
            let receipt = await worker.generateMissingEmbeddings()
            #expect(receipt.failures.isEmpty)
            #expect(receipt.embeddingsCreated == chunks.count)
            #expect(try repository.embeddingRows().count == chunks.count)
        }
    }

    @Test func indexerNamespacesProviderMessageIDsByOwningSession() async throws {
        try await withRepositoryAsync { repository, _, root in
            let firstURL = root.appendingPathComponent("first.jsonl")
            let secondURL = root.appendingPathComponent("second.jsonl")
            try Data("fixture\n".utf8).write(to: firstURL)
            try Data("fixture\n".utf8).write(to: secondURL)
            let first = sampleSession(id: "first-session", rawPath: firstURL.path)
            let second = sampleSession(id: "second-session", rawPath: secondURL.path)
            let provider = FixtureArchiveProvider(
                root: root,
                sessions: [first, second],
                messageID: "shared-provider-message"
            )
            let indexer = HolyArchiveIndexer(
                repository: repository,
                registry: .init(providers: [provider]),
                pacer: .init(budget: .unthrottled)
            )

            let receipt = await indexer.fullReindex()

            #expect(receipt.failures.isEmpty)
            let firstIDs = try repository.messages(sessionID: first.id).map(\.id)
            let secondIDs = try repository.messages(sessionID: second.id).map(\.id)
            #expect(firstIDs == ["first-session:message:0:shared-provider-message"])
            #expect(secondIDs == ["second-session:message:0:shared-provider-message"])
        }
    }

    @Test func repositoryRoundTripsTranscriptChunksAnnotationsAndChat() throws {
        try withRepository { repository, _, _ in
            let session = sampleSession(id: "session-a")
            let messages = sampleMessages(sessionID: session.id)
            let chunks = HolyArchiveChunker.chunks(session: session, messages: messages)
            try repository.replace(session: session, messages: messages, chunks: chunks)

            #expect(try repository.session(id: session.id)?.title == "Built Archive Search")
            #expect(try repository.messages(sessionID: session.id) == messages)
            #expect(try repository.chunks(sessionID: session.id).count >= 2)

            let annotation = try repository.addAnnotation(
                sessionID: session.id, kind: .tag, value: "breakthrough"
            )
            #expect(try repository.annotations(sessionID: session.id).map(\.value) == ["breakthrough"])
            #expect(try repository.tagCounts().first == .init(tag: "breakthrough", count: 1))
            try repository.deleteAnnotation(id: annotation.id)
            #expect(try repository.annotations(sessionID: session.id).isEmpty)

            let now = Date(timeIntervalSince1970: 1_700_000_000)
            let chat = HolyArchiveResearchChat(
                id: "chat-a", title: "Archive question", createdAt: now, updatedAt: now,
                backend: "openai", model: "gpt-5.6", stateJSON: "{}", metadataJSON: "{}"
            )
            try repository.saveChat(chat)
            _ = try repository.appendResearchMessage(
                chatID: chat.id, role: .assistant, content: "Answer", citedSessionIDs: [session.id]
            )
            #expect(try repository.chat(id: chat.id) == chat)
            #expect(try repository.researchMessages(chatID: chat.id).first?.citedSessionIDs == [session.id])
            try repository.deleteChat(id: chat.id)
            #expect(try repository.chat(id: chat.id) == nil)
        }
    }

    @Test func childCanIndexBeforeItsParentAndLinkAfterThePass() throws {
        try withRepository { repository, _, _ in
            let parent = sampleSession(id: "parent-late")
            let child = sampleSession(id: "child-first", child: true, parentID: parent.id)

            try repository.replace(
                session: child,
                messages: sampleMessages(sessionID: child.id),
                chunks: []
            )
            #expect(try repository.session(id: child.id)?.parentID == nil)

            try repository.replace(
                session: parent,
                messages: sampleMessages(sessionID: parent.id),
                chunks: []
            )
            try repository.applyParentLinks([(childID: child.id, parentID: parent.id)])
            #expect(try repository.session(id: child.id)?.parentID == parent.id)
        }
    }

    @Test func childCountsPreferExplicitLinksThenUseProviderTimeWindows() throws {
        try withRepository { repository, _, _ in
            let explicitParent = sampleSession(
                id: "explicit-parent", activity: 10_000, projectPath: "/explicit"
            )
            let explicitChild = sampleSession(
                id: "explicit-child", child: true, parentID: explicitParent.id,
                activity: 10_010, projectPath: "/explicit"
            )
            let unlinkedNeighbor = sampleSession(
                id: "unlinked-neighbor", child: true,
                activity: 10_020, projectPath: "/explicit"
            )
            let heuristicParent = sampleSession(
                id: "heuristic-parent", activity: 20_000, projectPath: "/heuristic"
            )
            let heuristicChild = sampleSession(
                id: "heuristic-child", child: true,
                activity: 20_100, projectPath: "/heuristic"
            )
            for session in [
                explicitParent, explicitChild, unlinkedNeighbor, heuristicParent, heuristicChild,
            ] {
                try repository.replace(session: session, messages: [], chunks: [])
            }

            let counts = try repository.childCounts(parentIDs: [explicitParent.id, heuristicParent.id])
            #expect(counts[explicitParent.id] == 1)
            #expect(counts[heuristicParent.id] == 1)
            #expect(try repository.relatedChildren(of: explicitParent.id).map(\.id) == [explicitChild.id])
            #expect(try repository.relatedChildren(of: heuristicParent.id).map(\.id) == [heuristicChild.id])
        }
    }

    @Test func legacyTitlesMigrateIntoHolyDatabaseWithoutOverwritingNativeTitles() throws {
        try withRepository { repository, _, root in
            let first = sampleSession(id: "legacy-first")
            var native = sampleSession(id: "native-title")
            native.summary = "Native title wins"
            try repository.replace(session: first, messages: [], chunks: [])
            try repository.replace(session: native, messages: [], chunks: [])

            let factory = root.appendingPathComponent("factory.json")
            let newer = root.appendingPathComponent("agent-sessions.json")
            try Data(#"{"legacy-first":{"hash":"first-hash","summary":"Factory title"},"native-title":{"hash":"old","summary":"Legacy loses"}}"#.utf8).write(to: factory)
            try Data(#"{"legacy-first":{"hash":"second-hash","summary":"Later title"}}"#.utf8).write(to: newer)

            let entries = HolyArchiveLegacySummaryImporter.load(from: [factory, newer])
            #expect(try repository.importLegacySummaries(entries) == 1)
            #expect(try repository.session(id: first.id)?.summary == "Factory title")
            #expect(try repository.session(id: native.id)?.summary == "Native title wins")
        }
    }

    @Test func queryParserPreservesExactGrammarAndNaturalTopic() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-09-02T12:00:00Z"))
        let query = HolyArchiveSearchParser.parse(
            "find me the sessions where we worked on auth caching harness:codex project:\"holy ghostty\" after:2w before:2026-09-02 #tag:ship #tag:review",
            now: now,
            calendar: Calendar(identifier: .gregorian)
        )
        #expect(query.text == "auth caching")
        #expect(query.harness == .codex)
        #expect(query.project == "holy ghostty")
        #expect(query.tags == ["ship", "review"])
        #expect(query.after != nil)
        #expect(query.before != nil)

        #expect(HolyArchiveSearchParser.cleanNaturalLanguage("which sessions did we fix ctrl+A") == "ctrl+A")
        #expect(HolyArchiveRepository.ftsQuery("ctrl A") == "\"ctrl\" AND \"a\"")

        let repeated = HolyArchiveSearchParser.parse("harness:codex harness:droid auth")
        #expect(repeated.harness == .droid)
        #expect(repeated.rawHarness == "droid")

        let unknown = HolyArchiveSearchParser.parse("auth#tag:ship harness:unknown")
        #expect(unknown.text == "auth")
        #expect(unknown.tags == ["ship"])
        #expect(unknown.harness == nil)
        #expect(unknown.rawHarness == "unknown")
    }

    @Test func unknownHarnessFilterFailsClosed() throws {
        try withRepository { repository, _, _ in
            try repository.replace(session: sampleSession(id: "known-harness"), messages: [], chunks: [])
            let query = HolyArchiveSearchParser.parse("harness:unknown")
            #expect(try repository.sessions(query: query).isEmpty)
        }
    }

    @Test func chunkerOrdersSummaryTurnsAndToolUsageAndTaggerScoresTools() {
        var session = sampleSession(id: "chunk-a")
        session.firstPrompt = "short stored preview"
        let fullPrompt = String(repeating: "x", count: 300)
        var messages = sampleMessages(sessionID: session.id)
        messages[0] = .init(
            id: "first-full-message", sessionID: session.id, role: .user,
            content: fullPrompt, timestamp: messages[0].timestamp, sequence: 0
        )
        messages += [
            .init(
                id: "tool-message", sessionID: session.id, role: .assistant,
                content: "Add authentication with Mongo and Google Cloud, assert coverage.\nagent-do browse open https://example.com",
                timestamp: .now, sequence: 2
            ),
        ]
        let chunks = HolyArchiveChunker.chunks(session: session, messages: messages)
        #expect(chunks.first?.type == .summary)
        #expect(chunks.first?.content.contains(String(repeating: "x", count: 200)) == true)
        let turn = chunks.first { $0.type == .turn }
        #expect(turn?.messageID == "first-full-message")
        #expect(turn?.metadata["chunk_type"] == "turn")
        #expect(turn?.metadata["session_id"] == session.id)
        let tool = chunks.first { $0.type == .toolUsage }
        #expect(tool?.metadata["tool"] == "agent-do-browse")
        #expect(tool?.metadata["chunk_type"] == "tool_usage")
        #expect(tool?.metadata["message_id"] == "tool-message")
        let tags = HolyArchiveTagger.tags(session: session, messages: messages)
        #expect(tags.contains("tool:agent-do-browse"))
        #expect(tags.contains("harness:codex"))
        #expect(tags.contains("implementing"))
        #expect(tags.contains("testing"))
        #expect(tags.contains("auth"))
        #expect(tags.contains("mongodb"))
        #expect(tags.contains("gcp"))
        #expect(tags.count <= 15)
    }

    @Test func hybridSearchUsesExactWeightsFloorAndChildPropagation() async throws {
        try await withRepositoryAsync { repository, _, _ in
            var parent = sampleSession(id: "parent")
            parent.firstPrompt = "unrelated parent"
            var child = sampleSession(id: "child", child: true, parentID: parent.id)
            child.firstPrompt = "vector archive breakthrough"
            let parentMessages = sampleMessages(sessionID: parent.id, content: "plain parent")
            let childMessages = sampleMessages(sessionID: child.id, content: "vector archive breakthrough")
            let vector: [Float] = [1, 0]
            let parentChunks = HolyArchiveChunker.chunks(session: parent, messages: parentMessages).map {
                embedded($0, vector: [0, 1])
            }
            let childChunks = HolyArchiveChunker.chunks(session: child, messages: childMessages).map {
                embedded($0, vector: vector)
            }
            try repository.replace(session: parent, messages: parentMessages, chunks: parentChunks)
            try repository.replace(session: child, messages: childMessages, chunks: childChunks)
            try repository.applyParentLinks([(childID: child.id, parentID: parent.id)])

            let search = HolyArchiveHybridSearch(
                repository: repository,
                embedder: FixedEmbeddingProvider(vector: vector)
            )
            let response = try await search.search("vector archive", limit: 50)
            #expect(response.results.first?.session.id == parent.id)
            #expect(response.matchingChildrenByParentID[parent.id]?.map(\.id) == [child.id])
            #expect(response.results.first?.semanticScore ?? 0 >= 0.35)
            #expect(response.results.first?.score ?? 0 >= 0.2)
            #expect(try repository.searchHistory().first?.query == "vector archive")
        }
    }

    @Test func filtersOnlySearchReturnsRecentRowsAtUnitScore() async throws {
        try await withRepositoryAsync { repository, _, _ in
            let first = sampleSession(id: "one", activity: 100)
            let second = sampleSession(id: "two", activity: 200)
            try repository.replace(session: first, messages: sampleMessages(sessionID: first.id), chunks: [])
            try repository.replace(session: second, messages: sampleMessages(sessionID: second.id), chunks: [])
            let search = HolyArchiveHybridSearch(repository: repository, embedder: nil)
            let response = try await search.search("harness:codex", limit: 50)
            #expect(response.results.map(\.session.id) == ["two", "one"])
            #expect(response.results.allSatisfy { $0.score == 1 })
        }
    }

    @Test func restoreResolverWaitsForLegacyDatabaseMigration() async throws {
        try await withRepositoryAsync { repository, databaseURL, root in
            let legacyURL = root.appendingPathComponent("legacy-workspace.sqlite3")
            let legacy = try HolyDatabase.open(at: legacyURL)
            try HolyDatabaseMigrator.migrate(legacy)
            try insertLegacySession(id: "legacy-session", in: legacy)
            let resolver = HolyArchiveRestoreResolver(
                databaseURL: databaseURL,
                legacyDatabaseURL: legacyURL,
                registry: .init(providers: [])
            )

            let outcome = await resolver.resolve(.init(
                workingDirectory: "/legacy",
                harness: "codex",
                nearUnixSeconds: 1_700_000_001
            ))

            guard case let .resolved(result) = outcome else {
                Issue.record("Expected resolution after storage migration")
                return
            }
            #expect(result.matched)
            #expect(result.providerSessionID == "legacy-session")
            #expect(try repository.session(id: "legacy-session") != nil)
        }
    }

    @Test func restoreResolverExcludesChildrenAndUsesOneTwentySecondAmbiguityBoundary() async throws {
        try await withRepositoryAsync { repository, databaseURL, root in
            let project = root.appendingPathComponent("project", isDirectory: true)
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            let linkedProject = root.appendingPathComponent("linked-project", isDirectory: true)
            try FileManager.default.createSymbolicLink(
                at: linkedProject,
                withDestinationURL: project
            )
            let raw = root.appendingPathComponent("provider.jsonl")
            try Data("{}\n".utf8).write(to: raw)
            let rawMTime = try raw.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate ?? .distantPast
            let near = 10_000.0
            let first = sampleSession(
                id: "first", activity: near - 10, projectPath: project.path,
                rawPath: raw.path, fileMTime: rawMTime
            )
            let second = sampleSession(
                id: "second", activity: near - 130, projectPath: project.path,
                rawPath: raw.path, fileMTime: rawMTime
            )
            let child = sampleSession(
                id: "child", child: true, parentID: first.id, activity: near,
                projectPath: project.path, rawPath: raw.path, fileMTime: rawMTime
            )
            try repository.replace(session: first, messages: sampleMessages(sessionID: first.id), chunks: [])
            try repository.replace(session: second, messages: sampleMessages(sessionID: second.id), chunks: [])
            try repository.replace(session: child, messages: sampleMessages(sessionID: child.id), chunks: [])

            let provider = FixtureArchiveProvider(root: root, sessions: [first, second, child])
            let resolver = HolyArchiveRestoreResolver(
                databaseURL: databaseURL,
                registry: .init(providers: [provider])
            )
            let outcome = await resolver.resolve(.init(
                workingDirectory: linkedProject.path,
                harness: "codex",
                nearUnixSeconds: Int(near)
            ))
            guard case let .resolved(result) = outcome else {
                Issue.record("Expected native resolution")
                return
            }
            #expect(result.confidence == .ambiguous)
            #expect(result.projectPath == project.path)
            #expect(result.candidates.map(\.id) == ["first", "second"])
            #expect(!result.candidates.contains { $0.id == "child" })
            #expect(result.candidates.first?.resumeCommand == "codex resume first")

            let narrowOutcome = await resolver.resolve(.init(
                workingDirectory: project.path, harness: "codex", nearUnixSeconds: Int(near),
                windowSeconds: 20, limit: 1
            ))
            guard case let .resolved(narrow) = narrowOutcome else {
                Issue.record("Expected native narrow-window resolution")
                return
            }
            #expect(narrow.confidence == .exact)
            #expect(narrow.candidates.map(\.id) == ["first"])
        }
    }

    @Test func batchRestoreReturnsTenCandidatesAndRefreshesChangedMTime() async throws {
        try await withRepositoryAsync { repository, databaseURL, root in
            let project = root.appendingPathComponent("batch-project", isDirectory: true)
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            let linkedProject = root.appendingPathComponent("linked-batch-project", isDirectory: true)
            try FileManager.default.createSymbolicLink(
                at: linkedProject,
                withDestinationURL: project
            )
            let raw = root.appendingPathComponent("batch-provider.jsonl")
            try Data("{}\n".utf8).write(to: raw)
            let actualMTime = try #require(
                try raw.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            )
            // The resolver contract takes whole Unix seconds. Keep the nearest
            // fixture on that same coordinate so sub-second file mtimes cannot
            // make the one-second-older candidate appear closer.
            let near = floor(actualMTime.timeIntervalSince1970)
            var stored = sampleSession(
                id: "batch-00", activity: near, projectPath: project.path,
                rawPath: raw.path, fileMTime: .distantPast
            )
            stored.firstPrompt = "stale prompt"
            stored.indexedAt = Date(timeIntervalSince1970: near + 10_000)
            try repository.replace(
                session: stored, messages: sampleMessages(sessionID: stored.id), chunks: []
            )

            var providerSessions: [HolyArchiveSession] = []
            for offset in 0..<11 {
                let candidateURL: URL
                let candidateMTime: Date
                if offset == 0 {
                    candidateURL = raw
                    candidateMTime = actualMTime
                } else {
                    candidateURL = root.appendingPathComponent("batch-provider-\(offset).jsonl")
                    try Data("{}\n".utf8).write(to: candidateURL)
                    candidateMTime = try #require(
                        try candidateURL.resourceValues(forKeys: [.contentModificationDateKey])
                            .contentModificationDate
                    )
                }
                var session = sampleSession(
                    id: String(format: "batch-%02d", offset),
                    activity: near - Double(offset), projectPath: project.path,
                    rawPath: candidateURL.path, fileMTime: candidateMTime
                )
                session.firstPrompt = offset == 0 ? "refreshed prompt" : "candidate \(offset)"
                providerSessions.append(session)
                if offset > 0 {
                    try repository.replace(
                        session: session,
                        messages: sampleMessages(sessionID: session.id),
                        chunks: []
                    )
                }
            }
            let resolver = HolyArchiveRestoreResolver(
                databaseURL: databaseURL,
                registry: .init(providers: [
                    FixtureArchiveProvider(root: root, sessions: providerSessions),
                ])
            )
            let outcome = await resolver.resolveBatch([
                .init(cwd: linkedProject.path, harness: "codex", near: Int(near)),
            ])
            guard case let .resolved(results) = outcome,
                  let result = results.first else {
                Issue.record("Expected native batch resolution")
                return
            }
            #expect(result.candidates.count == HolyArchiveRestoreResolver.batchLimit)
            #expect(result.candidates.first?.id == "batch-00")
            #expect(try repository.session(id: "batch-00")?.firstPrompt == "refreshed prompt")
            let refreshedMTime = try #require(repository.session(id: "batch-00")?.fileMTime)
            #expect(HolyArchiveFileTime.matches(refreshedMTime, actualMTime))
        }
    }

    @Test func researchGuardsOutputsAndChoosesOnlyMentionedCitations() {
        let oversized = String(repeating: "x", count: HolyArchiveResearchAgent.outputGuardCharacters + 1_000)
        let guarded = HolyArchiveResearchAgent.guarded(oversized)
        #expect(guarded.count <= HolyArchiveResearchAgent.outputGuardCharacters + 100)
        #expect(guarded.contains("characters elided"))
        #expect(HolyArchiveResearchAgent.pickRecommendedSession(
            text: "Resume bbbbbbbb before aaaaaaaa",
            citedIDs: ["aaaaaaaa-1111", "bbbbbbbb-2222"]
        ) == "bbbbbbbb-2222")
        #expect(HolyArchiveResearchAgent.pickRecommendedSession(
            text: "No concrete recommendation", citedIDs: ["aaaaaaaa-1111"]
        ) == nil)
        let ids = HolyArchiveResearchAgent.collectSessionIDs(
            fromJSON: #"{"sessions":[{"session_id":"a"},{"nested":{"session_id":"b"}},{"session_id":"a"}]}"#
        )
        #expect(ids == ["a", "b"])
    }

    @Test func researchToolSchemasAreStrictPagedAndExposeNoLimitKnobs() throws {
        let definitions = HolyArchiveResearchTools.definitions
        #expect(definitions.count == 8)
        #expect(definitions.compactMap { $0["name"] as? String } == [
            "today", "list_projects", "list_tags", "find_sessions", "search_sessions",
            "get_session", "get_messages", "get_chunks",
        ])
        for definition in definitions {
            #expect(definition["strict"] as? Bool == true)
            let parameters = try #require(definition["parameters"] as? [String: Any])
            let properties = try #require(parameters["properties"] as? [String: Any])
            let required = Set(try #require(parameters["required"] as? [String]))
            #expect(required == Set(properties.keys))
            #expect(parameters["additionalProperties"] as? Bool == false)
            #expect(properties["limit"] == nil)
        }
        for name in ["find_sessions", "search_sessions", "get_messages", "get_chunks"] {
            let definition = try #require(definitions.first { $0["name"] as? String == name })
            let parameters = try #require(definition["parameters"] as? [String: Any])
            let properties = try #require(parameters["properties"] as? [String: Any])
            #expect(properties["start"] != nil)
        }
    }

    @Test func researchTurnCapsToolOutputAndPersistsTheUnabridgedEvidence() async throws {
        try await withRepositoryAsync { repository, _, root in
            let session = sampleSession(id: "research-session")
            let huge = String(repeating: "e", count: 450_000)
            let messages = [HolyArchiveMessage(
                id: "huge-message", sessionID: session.id, role: .assistant,
                content: huge, timestamp: session.modifiedAt, sequence: 0
            )]
            try repository.replace(session: session, messages: messages, chunks: [])
            let arguments = try jsonString([
                "session_id": session.id, "role": NSNull(), "last_n": NSNull(),
                "around_query": NSNull(), "start": 0,
            ])
            let model = ScriptedResearchModel(mode: .budget(arguments))
            let search = HolyArchiveHybridSearch(repository: repository, embedder: nil)
            let tools = HolyArchiveResearchTools(
                repository: repository,
                search: search,
                registry: .init(providers: [FixtureArchiveProvider(root: root, sessions: [session])])
            )
            let agent = HolyArchiveResearchAgent(repository: repository, tools: tools, model: model)
            let chat = try await agent.startChat()
            let answer = await agent.runTurn(chatID: chat.id, userText: "Read the large transcript")

            #expect(answer.text == "Budget respected")
            #expect(answer.citedSessionIDs == [session.id])
            #expect(await model.allowToolsHistory() == [true, false])
            let persisted = try repository.researchMessages(chatID: chat.id)
            let toolOutputs = persisted.filter { $0.role == .tool }
            #expect(toolOutputs.count == 2)
            #expect(toolOutputs.allSatisfy { ($0.toolOutputJSON?.count ?? 0) > 450_000 })
            #expect(toolOutputs.allSatisfy { $0.content.contains(huge) })
        }
    }

    @Test func researchFailureRollsBackStateAndKeepsCompletedToolWork() async throws {
        try await withRepositoryAsync { repository, _, root in
            let session = sampleSession(id: "rollback-session")
            try repository.replace(
                session: session,
                messages: sampleMessages(sessionID: session.id),
                chunks: []
            )
            let arguments = try jsonString(["session_id": session.id])
            let model = ScriptedResearchModel(mode: .rollback(arguments))
            let search = HolyArchiveHybridSearch(repository: repository, embedder: nil)
            let tools = HolyArchiveResearchTools(
                repository: repository,
                search: search,
                registry: .init(providers: [FixtureArchiveProvider(root: root, sessions: [session])])
            )
            let agent = HolyArchiveResearchAgent(repository: repository, tools: tools, model: model)
            let chat = try await agent.startChat()
            let answer = await agent.runTurn(chatID: chat.id, userText: "Inspect this session")

            #expect(answer.text.contains("Chat turn failed mid-flight"))
            #expect(answer.text.contains("1 tool call(s) completed"))
            #expect(try repository.chat(id: chat.id)?.stateJSON == "{}")
            let persisted = try repository.researchMessages(chatID: chat.id)
            #expect(persisted.contains { $0.role == .tool && $0.citedSessionIDs == [session.id] })
            #expect(persisted.last?.content.contains("state was rolled back") == true)
        }
    }

    @Test func transcriptFindIsOverlappingAndCaseInsensitive() {
        let text = "Banana\nBANANA"
        let ranges = HolyArchiveTranscriptFind.ranges(of: "ana", in: text)
        #expect(ranges.count == 4)
        guard let lastRange = ranges.last else {
            Issue.record("Expected at least one transcript match")
            return
        }
        let coordinate = HolyArchiveTranscriptFind.lineAndColumn(at: lastRange.lowerBound, in: text)
        #expect(coordinate.line == 2)
    }

    @Test func embeddingBlobIsLittleWidthFloat32RoundTrip() throws {
        let vector: [Float] = [1.25, -2.5, 0]
        let data = HolyArchiveRepository.embeddingData(vector)
        #expect(data.count == vector.count * MemoryLayout<Float>.size)
        #expect(HolyArchiveRepository.embedding(from: data) == vector)
    }

    @Test func claudeProviderFindsAlternateRootsWorkersAndToolResults() throws {
        try withRepository { _, _, root in
            let projectPath = "/repo/ophanim"
            let alternate = root.appendingPathComponent(".claude-1m", isDirectory: true)
            let project = alternate.appendingPathComponent("projects", isDirectory: true)
                .appendingPathComponent(
                    HolyClaudeArchiveProvider.encodeProjectPath(projectPath), isDirectory: true
                )
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            try Data("claude --model opus".utf8).write(
                to: alternate.appendingPathComponent(".resume-cmd")
            )
            let sessionURL = project.appendingPathComponent("claude-session.jsonl")
            let toolResult = String(repeating: "y", count: 70)
            try writeJSONLines([
                [
                    "type": "user", "uuid": "claude-user", "cwd": projectPath,
                    "sessionId": "claude-session", "timestamp": "2026-09-02T12:00:00Z",
                    "message": [
                        "role": "user",
                        "content": "# Wings.md\nOne task only: inspect the archive provider",
                    ],
                ],
                [
                    "type": "assistant", "uuid": "claude-assistant",
                    "timestamp": "2026-09-02T12:01:00Z",
                    "message": [
                        "role": "assistant", "model": "claude-opus",
                        "content": [
                            ["type": "text", "text": "Inspection complete"],
                            ["type": "tool_result", "content": toolResult],
                        ],
                    ],
                ],
            ], to: sessionURL)

            let provider = HolyClaudeArchiveProvider(homeDirectory: root)
            let discovered = try provider.discoverSessionFiles()
            #expect(discovered.count == 1)
            let expectedPath = sessionURL.standardizedFileURL.resolvingSymlinksInPath().path
            #expect(discovered.contains {
                $0.standardizedFileURL.resolvingSymlinksInPath().path == expectedPath
            })
            let parsed = try #require(try provider.parseSession(at: sessionURL))
            #expect(parsed.0.childType == "ophanim-worker")
            #expect(parsed.0.model == "claude-opus")
            #expect(parsed.0.resumeCommand == "claude --model opus --resume claude-session")
            #expect(parsed.1.last?.content.contains(
                "(tool_result: \(String(repeating: "y", count: 50))...)"
            ) == true)
        }
    }

    @Test func codexProviderLocksMatchingMetadataAndPreservesChildLineage() throws {
        try withRepository { _, _, root in
            let directory = root.appendingPathComponent(".codex/sessions/2026/09/02", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let sessionURL = directory.appendingPathComponent("codex-session.jsonl")
            try writeJSONLines([
                [
                    "type": "session_meta", "timestamp": "2026-09-02T12:00:00Z",
                    "payload": ["id": "wrong-session", "cwd": "/wrong"],
                ],
                [
                    "type": "session_meta", "timestamp": "2026-09-02T12:00:01Z",
                    "payload": [
                        "id": "codex-session", "cwd": "/repo/codex",
                        "source": [
                            "subagent": [
                                "thread_spawn": [
                                    "parent_thread_id": "parent-thread",
                                    "agent_nickname": "Ada", "agent_role": "reviewer",
                                ],
                            ],
                        ],
                    ],
                ],
                [
                    "type": "session_meta", "timestamp": "2026-09-02T12:00:02Z",
                    "payload": ["id": "codex-session", "cwd": "/must-not-win"],
                ],
                [
                    "type": "turn_context", "payload": ["model": "gpt-5.6"],
                ],
                [
                    "type": "event_msg", "timestamp": "2026-09-02T12:01:00Z",
                    "payload": ["type": "user_message", "text": "Review the native archive implementation"],
                ],
                [
                    "type": "event_msg", "timestamp": "2026-09-02T12:02:00Z",
                    "payload": ["type": "agent_message", "text": "Review complete"],
                ],
                [
                    "type": "response_item",
                    "payload": ["type": "function_call", "name": "exec_command"],
                ],
            ], to: sessionURL)
            let indexURL = root.appendingPathComponent(".codex/session_index.jsonl")
            try writeJSONLines([
                ["id": "codex-session", "thread_name": "First title"],
                ["id": "codex-session", "thread_name": "Canonical title"],
            ], to: indexURL)

            let provider = HolyCodexArchiveProvider(homeDirectory: root)
            let parsed = try #require(try provider.parseSession(at: sessionURL))
            #expect(parsed.0.id == "codex-session")
            #expect(parsed.0.projectPath == "/repo/codex")
            #expect(parsed.0.title == "Canonical title")
            #expect(parsed.0.parentID == "parent-thread")
            #expect(parsed.0.childType == "reviewer")
            #expect(parsed.0.extra["agent_nickname"] == "Ada")
            #expect(parsed.0.toolCalls == ["exec_command"])
        }
    }

    @Test func droidProviderLoadsSettingsAndTaskInvocationIdentity() throws {
        try withRepository { _, _, root in
            let project = root.appendingPathComponent(".factory/sessions/project", isDirectory: true)
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            let sessionURL = project.appendingPathComponent("droid-session.jsonl")
            try writeJSONLines([
                [
                    "type": "session_start", "title": "# Task Tool Invocation\nSubagent type: scout",
                    "cwd": "/repo/droid",
                ],
                [
                    "type": "message", "uuid": "droid-user", "timestamp": "2026-09-02T12:00:00Z",
                    "message": ["role": "user", "content": "Inspect the Droid archive provider"],
                ],
                [
                    "type": "message", "uuid": "droid-assistant", "timestamp": "2026-09-02T12:01:00Z",
                    "message": ["role": "assistant", "content": "Provider inspected"],
                ],
            ], to: sessionURL)
            try Data(#"{"model":"factory-model"}"#.utf8).write(
                to: project.appendingPathComponent("droid-session.settings.json")
            )

            let provider = HolyDroidArchiveProvider(homeDirectory: root)
            let parsed = try #require(try provider.parseSession(at: sessionURL))
            #expect(parsed.0.isChild)
            #expect(parsed.0.childType == "scout")
            #expect(parsed.0.model == "factory-model")
            #expect(parsed.0.resumeCommand == "droid --resume droid-session")
        }
    }

    @Test func cursorProviderDecodesLexicalPromptAndFindsRepositoryRoot() throws {
        try withRepository { _, _, root in
            let globalStorage = root.appendingPathComponent(
                "Library/Application Support/Cursor/User/globalStorage", isDirectory: true
            )
            try FileManager.default.createDirectory(at: globalStorage, withIntermediateDirectories: true)
            let repositoryRoot = root.appendingPathComponent("cursor-repo", isDirectory: true)
            try FileManager.default.createDirectory(
                at: repositoryRoot.appendingPathComponent(".git", isDirectory: true),
                withIntermediateDirectories: true
            )
            let referenced = repositoryRoot.appendingPathComponent("Sources/Feature.swift").path
            let richText = try jsonString([
                "root": [
                    "children": [
                        ["type": "text", "text": "Build Cursor archive support"],
                        ["type": "mention", "name": "Feature.swift", "fsPath": referenced],
                    ],
                ],
            ])
            let input = try jsonData(["composerData": ["richText": richText]])
            let details = try jsonData([
                "model": "cursor-model", "lastResponse": "Cursor support built",
            ])
            let databaseURL = globalStorage.appendingPathComponent("state.vscdb")
            do {
                let database = try HolyDatabase.open(at: databaseURL)
                try database.execute("CREATE TABLE cursorDiskKV (key TEXT PRIMARY KEY, value BLOB);")
                try database.execute(
                    "INSERT INTO cursorDiskKV(key, value) VALUES (?, ?);",
                    bindings: [.text("backgroundComposerModalInputData:cursor-session"), .blob(input)]
                )
                try database.execute(
                    "INSERT INTO cursorDiskKV(key, value) VALUES (?, ?);",
                    bindings: [.text("bcCachedDetails:cursor-session"), .blob(details)]
                )
            }

            let provider = HolyCursorArchiveProvider(homeDirectory: root)
            let sessionURL = try #require(provider.discoverSessionFiles().first)
            let parsed = try #require(try provider.parseSession(at: sessionURL))
            #expect(parsed.0.projectPath == repositoryRoot.path)
            #expect(parsed.0.firstPrompt == "Build Cursor archive support @Feature.swift")
            #expect(parsed.0.lastResponse == "Cursor support built")
            #expect(parsed.0.model == "cursor-model")
            #expect(parsed.0.resumeCommand == nil)
        }
    }

    @Test func openCodeProviderReadsLiveDatabaseWithMillisecondTimestamps() throws {
        try withRepository { _, _, root in
            let storage = root.appendingPathComponent(".local/share/opencode", isDirectory: true)
            try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
            let databaseURL = storage.appendingPathComponent("opencode.db")
            do {
                let database = try HolyDatabase.open(at: databaseURL)
                try database.execute(
                    "CREATE TABLE session (id TEXT PRIMARY KEY, parent_id TEXT, directory TEXT, title TEXT, model TEXT, agent TEXT, time_created REAL, time_updated REAL);"
                )
                try database.execute(
                    "CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created REAL, data TEXT);"
                )
                try database.execute(
                    "CREATE TABLE part (id TEXT PRIMARY KEY, message_id TEXT, session_id TEXT, time_created REAL, data TEXT);"
                )
                try database.execute(
                    "INSERT INTO session VALUES (?, ?, ?, ?, ?, ?, ?, ?);",
                    bindings: [
                        .text("ses_live"), .text("ses_parent"), .text("/repo/opencode"),
                        .text("OpenCode title"), .text(#"{"id":"stored-model"}"#),
                        .text("build"), .double(1_700_000_000_000), .double(1_700_000_060_000),
                    ]
                )
                try database.execute(
                    "INSERT INTO message VALUES (?, ?, ?, ?);",
                    bindings: [
                        .text("msg-user"), .text("ses_live"), .double(1_700_000_000_000),
                        .text(#"{"role":"user"}"#),
                    ]
                )
                try database.execute(
                    "INSERT INTO message VALUES (?, ?, ?, ?);",
                    bindings: [
                        .text("msg-assistant"), .text("ses_live"), .double(1_700_000_060_000),
                        .text(#"{"role":"assistant","model":{"id":"observed-model"},"agent":"review"}"#),
                    ]
                )
                try database.execute(
                    "INSERT INTO part VALUES (?, ?, ?, ?, ?);",
                    bindings: [
                        .text("part-user"), .text("msg-user"), .text("ses_live"),
                        .double(1_700_000_000_000), .text(#"{"type":"text","text":"Build OpenCode archive support"}"#),
                    ]
                )
                try database.execute(
                    "INSERT INTO part VALUES (?, ?, ?, ?, ?);",
                    bindings: [
                        .text("part-assistant"), .text("msg-assistant"), .text("ses_live"),
                        .double(1_700_000_060_000), .text(#"{"type":"text","text":"OpenCode support built"}"#),
                    ]
                )
            }

            let provider = HolyOpenCodeArchiveProvider(homeDirectory: root)
            let sessionURL = try #require(provider.discoverSessionFiles().first)
            let parsed = try #require(try provider.parseSession(at: sessionURL))
            #expect(parsed.0.id == "ses_live")
            #expect(parsed.0.parentID == "ses_parent")
            #expect(parsed.0.model == "stored-model")
            #expect(parsed.0.extra["agent"] == "build")
            #expect(parsed.0.createdAt.timeIntervalSince1970 == 1_700_000_000)
            #expect(parsed.0.modifiedAt?.timeIntervalSince1970 == 1_700_000_060)
            #expect(parsed.1.map(\.content) == ["Build OpenCode archive support", "OpenCode support built"])
        }
    }

    private func withRepository<T>(
        _ body: (HolyArchiveRepository, URL, URL) throws -> T
    ) throws -> T {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-archive-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("holy.sqlite3")
        let repository = try HolyArchiveRepository(databaseURL: databaseURL)
        return try body(repository, databaseURL, root)
    }

    private func withRepositoryAsync<T>(
        _ body: (HolyArchiveRepository, URL, URL) async throws -> T
    ) async throws -> T {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-archive-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("holy.sqlite3")
        let repository = try HolyArchiveRepository(databaseURL: databaseURL)
        return try await body(repository, databaseURL, root)
    }

    private func tableNames(_ database: HolyDatabase) throws -> Set<String> {
        var names = Set<String>()
        try database.query("SELECT name FROM sqlite_master WHERE type IN ('table', 'view');") { statement in
            if let value = sqlite3_column_text(statement, 0) { names.insert(String(cString: value)) }
        }
        return names
    }

    private func writeJSONLines(_ rows: [[String: Any]], to url: URL) throws {
        let strings = try rows.map { row in
            let data = try JSONSerialization.data(withJSONObject: row)
            return try #require(String(bytes: data, encoding: .utf8))
        }
        try Data((strings.joined(separator: "\n") + "\n").utf8).write(to: url)
    }

    private func jsonData(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    private func jsonString(_ value: Any) throws -> String {
        try #require(String(bytes: jsonData(value), encoding: .utf8))
    }

    private func insertLegacySession(id: String, in database: HolyDatabase) throws {
        try database.execute(
            """
            INSERT INTO archive_sessions(
                id, harness, raw_path, project_path, project_name, title,
                first_prompt_preview, last_prompt_preview, last_response_preview,
                timestamp, timestamp_end, is_child, child_type, parent_id, model,
                tool_calls_json, tokens_used, summary, content_hash, extra_json,
                resume_command, message_count, turn_count, file_mtime, indexed_at,
                auto_tags_json
            ) VALUES (?, 'codex', '/legacy/session.jsonl', '/legacy', 'legacy',
                      'Legacy session', 'Move legacy archive', 'Move legacy archive',
                      'Moved', 1700000000, 1700000001, 0, NULL, NULL, 'gpt-5.6',
                      '[]', 10, NULL, 'legacy-hash', '{}', 'codex resume legacy-session',
                      1, 1, 1700000001, 1700000001, '[]');
            """,
            bindings: [.text(id)]
        )
    }

    private func sampleSession(
        id: String,
        child: Bool = false,
        parentID: String? = nil,
        activity: TimeInterval = 1_700_000_000,
        projectPath: String = "/project",
        rawPath: String = "/archive/session.jsonl",
        fileMTime: Date? = nil
    ) -> HolyArchiveSession {
        .init(
            id: id, harness: .codex, rawPath: rawPath, projectPath: projectPath,
            projectName: "holy-ghostty", title: "Built Archive Search",
            firstPrompt: "Build native archive search", lastPrompt: "Verify the search",
            lastResponse: "Implemented and tested archive search", createdAt: Date(timeIntervalSince1970: activity - 60),
            modifiedAt: Date(timeIntervalSince1970: activity), isChild: child,
            childType: child ? "worker" : nil, parentID: parentID, model: "gpt-5.6",
            toolCalls: ["rg"], tokensUsed: 100, summary: nil, contentHash: "hash-\(id)",
            extra: [:], resumeCommand: "codex resume \(id)", messageCount: 2, turnCount: 1,
            fileMTime: fileMTime ?? Date(timeIntervalSince1970: activity),
            indexedAt: Date(timeIntervalSince1970: activity),
            autoTags: ["search", "harness:codex"]
        )
    }

    private func sampleMessages(sessionID: String, content: String = "archive search implementation") -> [HolyArchiveMessage] {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        return [
            .init(id: "\(sessionID)-u", sessionID: sessionID, role: .user, content: content, timestamp: timestamp, sequence: 0),
            .init(id: "\(sessionID)-a", sessionID: sessionID, role: .assistant, content: "Completed \(content)", timestamp: timestamp, sequence: 1),
        ]
    }

    private func embedded(_ chunk: HolyArchiveChunk, vector: [Float]) -> HolyArchiveChunk {
        .init(
            id: chunk.id, sessionID: chunk.sessionID, messageID: chunk.messageID,
            index: chunk.index, type: chunk.type, content: chunk.content,
            metadata: chunk.metadata, embedding: vector, embeddingModel: "fixed",
            createdAt: chunk.createdAt
        )
    }
}

private actor ArchiveSleepRecorder {
    private(set) var values: [UInt64] = []

    func record(_ value: UInt64) {
        values.append(value)
    }
}

private struct FixedEmbeddingProvider: HolyArchiveEmbeddingProviding {
    let id = "fixed"
    let displayName = "Fixed"
    let model = "fixed"
    let isAvailable = true
    let vector: [Float]

    func embed(_ texts: [String], purpose: HolyArchiveEmbeddingPurpose) async throws -> [[Float]] {
        texts.map { _ in vector }
    }
}

private struct FixtureArchiveProvider: HolyArchiveProviding {
    let harness = HolyArchiveHarness.codex
    let root: URL
    let sessions: [HolyArchiveSession]
    var messageID: String?
    var sessionsDirectory: URL { root }

    func discoverSessionFiles() throws -> [URL] {
        sessions.map { URL(fileURLWithPath: $0.rawPath) }
    }

    func discoverSessionFiles(forProjectPath projectPath: String) throws -> [URL]? {
        sessions.filter { $0.projectPath == projectPath }.map { URL(fileURLWithPath: $0.rawPath) }
    }

    func modificationDate(for url: URL) throws -> Date {
        try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
    }

    func parseSession(at url: URL) throws -> (HolyArchiveSession, [HolyArchiveMessage])? {
        guard let session = sessions.first(where: { $0.rawPath == url.path }) else { return nil }
        return (session, [
            .init(id: messageID ?? "\(session.id)-u", sessionID: session.id, role: .user, content: session.firstPrompt, timestamp: session.createdAt, sequence: 0),
        ])
    }

    func resumeCommand(for session: HolyArchiveSession) -> String? {
        "codex resume \(session.id)"
    }
}

private actor ScriptedResearchModel: HolyArchiveResearchModeling {
    enum Mode: Sendable {
        case budget(String)
        case rollback(String)
    }

    nonisolated let backend = "fixture"
    private let mode: Mode
    private var callCount = 0
    private var allowToolsValues: [Bool] = []

    init(mode: Mode) {
        self.mode = mode
    }

    func respond(
        _ request: HolyArchiveResearchRequest
    ) async throws -> HolyArchiveResearchModelResponse {
        callCount += 1
        allowToolsValues.append(request.allowTools)
        switch mode {
        case let .budget(arguments):
            if callCount == 1 {
                return .init(
                    responseID: "budget-tools",
                    text: "",
                    toolCalls: [
                        .init(callID: "budget-a", name: "get_messages", argumentsJSON: arguments),
                        .init(callID: "budget-b", name: "get_messages", argumentsJSON: arguments),
                    ]
                )
            }
            return .init(responseID: "budget-final", text: "Budget respected", toolCalls: [])
        case let .rollback(arguments):
            if callCount == 1 {
                return .init(
                    responseID: "rollback-tools",
                    text: "",
                    toolCalls: [
                        .init(callID: "rollback-a", name: "get_session", argumentsJSON: arguments),
                    ]
                )
            }
            throw ScriptedResearchError.expectedFailure
        }
    }

    func allowToolsHistory() -> [Bool] {
        allowToolsValues
    }
}

private enum ScriptedResearchError: LocalizedError {
    case expectedFailure

    var errorDescription: String? { "Expected scripted failure" }
}
