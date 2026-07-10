import Foundation
import SQLite3
import Testing
@testable import Ghostty

struct HolyWorkspacePersistenceRetentionTests {
    @MainActor
    @Test func unchangedGitStateReusesLatestSnapshotRow() throws {
        try withTemporaryDatabase { database, _ in
            let sessionID = UUID()
            let snapshot = gitSnapshot(branch: "main")
            let archivedSession = archivedSession(
                sourceSessionID: sessionID,
                gitSnapshot: snapshot
            )
            let workspace = HolyWorkspaceSnapshot(
                sessions: [],
                selectedSessionID: nil,
                archivedSessions: [archivedSession]
            )

            try persist(workspace, in: database)
            let firstID = try database.scalarInt64("SELECT latest_git_snapshot_id FROM sessions;")

            try persist(workspace, in: database)
            let secondID = try database.scalarInt64("SELECT latest_git_snapshot_id FROM sessions;")

            #expect(firstID == secondID)
            #expect(try database.scalarInt64("SELECT COUNT(*) FROM git_snapshots;") == 1)
        }
    }

    @MainActor
    @Test func retentionKeepsOnlyTheLatestMeaningfulGitState() throws {
        try withTemporaryDatabase { database, _ in
            let sessionID = UUID()
            for branch in ["one", "two", "three", "four", "five"] {
                let workspace = HolyWorkspaceSnapshot(
                    sessions: [],
                    selectedSessionID: nil,
                    archivedSessions: [
                        archivedSession(
                            sourceSessionID: sessionID,
                            gitSnapshot: gitSnapshot(branch: branch)
                        ),
                    ]
                )
                try persist(workspace, in: database)
            }

            #expect(try database.scalarInt64("SELECT COUNT(*) FROM git_snapshots;") == 5)

            let result = try HolyWorkspaceRetentionMaintenance.prune(
                in: database,
                gitSnapshotBatchSize: 100,
                sessionBatchSize: 0
            )

            #expect(result.deletedGitSnapshots == 4)
            #expect(try database.scalarInt64("SELECT COUNT(*) FROM git_snapshots;") == 1)
            #expect(try database.scalarText("SELECT branch FROM git_snapshots;") == "five")
        }
    }

    @MainActor
    @Test func interruptedSessionDrainStaysHiddenAndFinishesLater() throws {
        try withTemporaryDatabase { database, _ in
            let sessionID = UUID()
            for branch in ["one", "two", "three"] {
                let workspace = HolyWorkspaceSnapshot(
                    sessions: [],
                    selectedSessionID: nil,
                    archivedSessions: [
                        archivedSession(
                            sourceSessionID: sessionID,
                            gitSnapshot: gitSnapshot(branch: branch)
                        ),
                    ]
                )
                try persist(workspace, in: database)
            }

            try persist(.empty, in: database)

            #expect(try database.scalarInt64("SELECT COUNT(*) FROM sessions;") == 1)
            #expect(try database.scalarInt64("SELECT COUNT(*) FROM agent_sessions_sessions_v1;") == 0)
            #expect(try HolyWorkspaceDatabasePersistence.load(from: database)?.archivedSessions.isEmpty == true)

            let interrupted = try HolyWorkspaceRetentionMaintenance.prune(
                in: database,
                gitSnapshotBatchSize: 1,
                sessionBatchSize: 8
            )
            #expect(interrupted.deletedGitSnapshots == 1)
            #expect(interrupted.deletedSessions == 0)
            #expect(try database.scalarInt64("SELECT COUNT(*) FROM sessions;") == 1)
            #expect(try HolyWorkspaceDatabasePersistence.load(from: database)?.archivedSessions.isEmpty == true)

            let completed = try HolyWorkspaceRetentionMaintenance.prune(
                in: database,
                gitSnapshotBatchSize: 100,
                sessionBatchSize: 8
            )
            #expect(completed.deletedGitSnapshots == 1)
            #expect(completed.deletedSessions == 1)
            #expect(try database.scalarInt64("SELECT COUNT(*) FROM sessions;") == 0)
            #expect(try database.scalarInt64("SELECT COUNT(*) FROM git_snapshots;") == 0)
        }
    }

    @MainActor
    @Test func tombstonedSessionIsExcludedFromBudgetIntelligenceBeforePhysicalDrain() throws {
        try withTemporaryDatabase { database, _ in
            let sessionID = UUID()
            let workspace = HolyWorkspaceSnapshot(
                sessions: [],
                selectedSessionID: nil,
                archivedSessions: [
                    archivedSession(sourceSessionID: sessionID, gitSnapshot: nil),
                ]
            )
            try persist(workspace, in: database)
            try database.execute(
                """
                INSERT INTO budget_samples (
                    session_id, captured_at, runtime, total_tokens, estimated_cost_usd,
                    budget_status, token_limit, cost_limit_usd
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                """,
                bindings: [
                    .text(sessionID.uuidString),
                    .text(HolyPersistenceCoders.string(from: .now)),
                    .text(HolySessionRuntime.codex.rawValue),
                    .int64(100),
                    .double(0.25),
                    .text(HolySessionBudgetStatus.healthy.rawValue),
                    .int64(1_000),
                    .double(5),
                ]
            )
            let budget = HolySessionBudget(tokenLimit: 1_000, costLimitUSD: 5)

            let before = try HolyBudgetIntelligenceRepository.loadSessionIntelligence(
                sessionID: sessionID,
                runtime: .codex,
                budget: budget,
                in: database
            )
            #expect(before?.sampleCount == 1)
            #expect(before?.runtimeRollup?.sessionCount == 1)

            try persist(.empty, in: database)

            let whileDraining = try HolyBudgetIntelligenceRepository.loadSessionIntelligence(
                sessionID: sessionID,
                runtime: .codex,
                budget: budget,
                in: database
            )
            #expect(whileDraining == nil)
            // Raw child rows remain transactionally intact until the bounded
            // maintenance pass deletes the parent and cascades them.
            #expect(try database.scalarInt64("SELECT COUNT(*) FROM budget_samples;") == 1)

            _ = try HolyWorkspaceRetentionMaintenance.prune(
                in: database,
                gitSnapshotBatchSize: 0,
                sessionBatchSize: 8
            )
            #expect(try database.scalarInt64("SELECT COUNT(*) FROM budget_samples;") == 0)
        }
    }

    @MainActor
    @Test func boundedLegacyPruneUsesRetentionIndexes() throws {
        try withTemporaryDatabase { database, _ in
            let sessionID = UUID()
            let workspace = HolyWorkspaceSnapshot(
                sessions: [],
                selectedSessionID: nil,
                archivedSessions: [
                    archivedSession(
                        sourceSessionID: sessionID,
                        gitSnapshot: gitSnapshot(branch: "latest")
                    ),
                ]
            )
            try persist(workspace, in: database)

            try database.execute(
                """
                WITH RECURSIVE counter(value) AS (
                    VALUES(1)
                    UNION ALL
                    SELECT value + 1 FROM counter WHERE value < 100000
                )
                INSERT INTO git_snapshots (
                    session_id, captured_at, repository_root, worktree_path,
                    common_git_directory, branch, upstream_branch, is_detached_head,
                    ahead_count, behind_count, staged_count, unstaged_count,
                    untracked_count, conflicted_count, changed_files_json
                )
                SELECT ?, ?, '/tmp/repository', '/tmp/repository', '/tmp/repository/.git',
                       'legacy', NULL, 0, 0, 0, 0, 0, 0, 0, '[]'
                FROM counter;
                """,
                bindings: [
                    .text(sessionID.uuidString),
                    .text(HolyPersistenceCoders.string(from: Date(timeIntervalSince1970: 0))),
                ]
            )

            let latestLookupPlan = try queryPlan(
                "EXPLAIN QUERY PLAN SELECT 1 FROM sessions WHERE latest_git_snapshot_id = 1;",
                in: database
            )
            let historyLookupPlan = try queryPlan(
                "EXPLAIN QUERY PLAN SELECT 1 FROM git_snapshots WHERE session_id = 'x' ORDER BY captured_at;",
                in: database
            )
            #expect(latestLookupPlan.contains("sessions_latest_git_snapshot_id_idx"))
            #expect(historyLookupPlan.contains("git_snapshots_session_captured_at_idx"))

            let startedAt = Date()
            let result = try HolyWorkspaceRetentionMaintenance.prune(
                in: database,
                sessionBatchSize: 0
            )
            let elapsed = Date().timeIntervalSince(startedAt)

            #expect(result.deletedGitSnapshots == 1_000)
            #expect(elapsed < 2)
            #expect(try database.scalarInt64("SELECT COUNT(*) FROM git_snapshots;") == 99_001)
        }
    }

    @Test func archivePolicyCapsRecentHistoryAndProtectsDiscoveredTruth() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let protectedArchiveID = UUID()
        let activeSessionID = UUID()
        var archives: [HolyArchivedSession] = []

        for index in 0..<300 {
            let sourceSessionID = index == 0 ? activeSessionID : UUID()
            archives.append(
                archivedSession(
                    id: index == 299 ? protectedArchiveID : UUID(),
                    sourceSessionID: sourceSessionID,
                    archivedAt: now.addingTimeInterval(-TimeInterval(index * 60)),
                    gitSnapshot: nil
                )
            )
        }

        let retained = HolyWorkspaceRetentionPolicy.retainedArchivedSessions(
            archives,
            activeSessionIDs: [activeSessionID],
            protectedArchiveIDs: [protectedArchiveID],
            now: now
        )

        #expect(retained.count == HolyWorkspaceRetentionPolicy.maximumArchivedSessionCount)
        #expect(retained.contains(where: { $0.id == protectedArchiveID }))
        #expect(!retained.contains(where: { $0.sourceSessionID == activeSessionID }))
        #expect(retained == retained.sorted { $0.archivedAt > $1.archivedAt })
    }

    @Test func archivePolicyAppliesAgeCeilingButKeepsRelaunchFloor() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let archives = (0..<300).map { index in
            archivedSession(
                sourceSessionID: UUID(),
                archivedAt: now.addingTimeInterval(-TimeInterval(index * 24 * 60 * 60)),
                gitSnapshot: nil
            )
        }

        let retained = HolyWorkspaceRetentionPolicy.retainedArchivedSessions(archives, now: now)

        // Days 0...90 are inside the inclusive 90-day window.
        #expect(retained.count == 91)
        #expect(retained.last?.archivedAt == now.addingTimeInterval(-90 * 24 * 60 * 60))
    }

    @Test func versionSevenUpgradePreservesRowsAndHidesTombstonesEverywhere() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-v7-migration-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = try HolyDatabase.open(at: directory.appendingPathComponent("version7.sqlite3"))
        try database.execute(
            """
            CREATE TABLE sessions (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                runtime TEXT NOT NULL,
                mission TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                archived_at TEXT,
                launch_spec_json TEXT NOT NULL,
                ownership_json TEXT,
                working_directory TEXT,
                repository_root TEXT,
                worktree_path TEXT,
                branch_name TEXT,
                latest_preview_text TEXT,
                resume_metadata_json TEXT,
                preferred_command TEXT,
                latest_phase TEXT,
                latest_attention TEXT,
                latest_signal_json TEXT,
                latest_git_snapshot_id INTEGER,
                latest_command_telemetry_json TEXT,
                latest_budget_json TEXT,
                latest_runtime_telemetry_json TEXT
            );
            CREATE TABLE git_snapshots (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                captured_at TEXT NOT NULL,
                repository_root TEXT,
                worktree_path TEXT,
                common_git_directory TEXT,
                branch TEXT,
                upstream_branch TEXT,
                is_detached_head INTEGER NOT NULL,
                ahead_count INTEGER NOT NULL,
                behind_count INTEGER NOT NULL,
                staged_count INTEGER NOT NULL,
                unstaged_count INTEGER NOT NULL,
                untracked_count INTEGER NOT NULL,
                conflicted_count INTEGER NOT NULL,
                changed_files_json TEXT NOT NULL
            );
            CREATE INDEX git_snapshots_session_captured_at_idx
            ON git_snapshots(session_id, captured_at);
            CREATE TABLE session_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                sequence INTEGER NOT NULL,
                occurred_at TEXT NOT NULL,
                event_type TEXT NOT NULL,
                phase TEXT,
                attention TEXT,
                payload_json TEXT
            );
            CREATE TABLE annotations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                created_at TEXT NOT NULL,
                annotation_type TEXT NOT NULL,
                value TEXT NOT NULL,
                source TEXT NOT NULL,
                payload_json TEXT
            );
            INSERT INTO sessions (
                id, title, runtime, created_at, updated_at, launch_spec_json,
                working_directory, latest_phase, latest_attention
            ) VALUES (
                'session-v7', 'Preserved', 'codex', '2026-07-01T00:00:00.000Z',
                '2026-07-02T00:00:00.000Z', '{}', '/tmp', 'active', 'none'
            );
            INSERT INTO git_snapshots (
                session_id, captured_at, repository_root, worktree_path,
                common_git_directory, branch, is_detached_head, ahead_count,
                behind_count, staged_count, unstaged_count, untracked_count,
                conflicted_count, changed_files_json
            ) VALUES (
                'session-v7', '2026-07-02T00:00:00.000Z', '/tmp', '/tmp', '/tmp/.git',
                'main', 0, 0, 0, 0, 0, 0, 0, '[]'
            );
            UPDATE sessions SET latest_git_snapshot_id = last_insert_rowid()
            WHERE id = 'session-v7';
            INSERT INTO session_events (
                session_id, sequence, occurred_at, event_type
            ) VALUES ('session-v7', 1, '2026-07-02T00:00:00.000Z', 'created');
            INSERT INTO annotations (
                session_id, created_at, annotation_type, value, source
            ) VALUES ('session-v7', '2026-07-02T00:00:00.000Z', 'note', 'keep', 'test');
            PRAGMA user_version = 7;
            """
        )

        try HolyDatabaseMigrator.migrate(database)

        #expect(try database.userVersion() == HolyDatabaseSchema.currentUserVersion)
        #expect(try database.scalarText("SELECT title FROM sessions;") == "Preserved")
        #expect(try database.scalarInt64("SELECT latest_git_snapshot_id FROM sessions;") == 1)
        #expect(try database.scalarInt64("SELECT COUNT(*) FROM agent_sessions_sessions_v1;") == 1)
        #expect(try database.scalarInt64("SELECT COUNT(*) FROM agent_sessions_resume_targets_v1;") == 1)
        #expect(try database.scalarInt64("SELECT COUNT(*) FROM agent_sessions_events_v1;") == 1)
        #expect(try database.scalarInt64("SELECT COUNT(*) FROM agent_sessions_annotations_v1;") == 1)

        let latestLookupPlan = try queryPlan(
            "EXPLAIN QUERY PLAN SELECT 1 FROM sessions WHERE latest_git_snapshot_id = 1;",
            in: database
        )
        let historyLookupPlan = try queryPlan(
            "EXPLAIN QUERY PLAN SELECT 1 FROM git_snapshots WHERE session_id = 'session-v7' ORDER BY captured_at;",
            in: database
        )
        #expect(latestLookupPlan.contains("sessions_latest_git_snapshot_id_idx"))
        #expect(historyLookupPlan.contains("git_snapshots_session_captured_at_idx"))

        try database.execute(
            "UPDATE sessions SET purge_pending_at = '2026-07-10T00:00:00.000Z' WHERE id = 'session-v7';"
        )
        #expect(try database.scalarInt64("SELECT COUNT(*) FROM sessions;") == 1)
        #expect(try database.scalarInt64("SELECT COUNT(*) FROM agent_sessions_sessions_v1;") == 0)
        #expect(try database.scalarInt64("SELECT COUNT(*) FROM agent_sessions_resume_targets_v1;") == 0)
        #expect(try database.scalarInt64("SELECT COUNT(*) FROM agent_sessions_events_v1;") == 0)
        #expect(try database.scalarInt64("SELECT COUNT(*) FROM agent_sessions_annotations_v1;") == 0)
    }

    @MainActor
    @Test func compactedCopyPreservesSchemaSessionsEventsAndSnapshots() throws {
        try withTemporaryDatabase { database, directory in
            let sessionID = UUID()
            let workspace = HolyWorkspaceSnapshot(
                sessions: [],
                selectedSessionID: nil,
                archivedSessions: [
                    archivedSession(
                        sourceSessionID: sessionID,
                        gitSnapshot: gitSnapshot(branch: "main")
                    ),
                ]
            )
            try persist(workspace, in: database)
            try database.execute(
                """
                INSERT INTO session_events (
                    session_id, sequence, occurred_at, event_type, phase, attention, payload_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?);
                """,
                bindings: [
                    .text(sessionID.uuidString),
                    .int64(1),
                    .text(HolyPersistenceCoders.string(from: .now)),
                    .text("test_event"),
                    .text("active"),
                    .text("none"),
                    .text("{}"),
                ]
            )

            let sourceCounts = try databaseRowCounts(in: database)
            let destination = directory.appendingPathComponent("compacted.sqlite3")
            let report = try HolyDatabaseMaintenance.createCompactedCopy(
                of: database,
                at: destination
            )

            #expect(report.schemaVersion == HolyDatabaseSchema.currentUserVersion)
            #expect(report.rowCounts == sourceCounts)

            let compactedDatabase = try HolyDatabase.open(at: destination, readOnly: true)
            #expect(try compactedDatabase.scalarText("PRAGMA integrity_check;") == "ok")
            #expect(try foreignKeyViolationCount(in: compactedDatabase) == 0)
            #expect(try compactedDatabase.scalarText("SELECT event_type FROM session_events;") == "test_event")
        }
    }

    @MainActor
    @Test func failedCompactionValidationDoesNotBlockRetry() throws {
        try withTemporaryDatabase { database, directory in
            try database.execute("PRAGMA foreign_keys = OFF;")
            try database.execute(
                """
                INSERT INTO session_events (
                    session_id, sequence, occurred_at, event_type
                ) VALUES ('missing-session', 1, '2026-01-01T00:00:00.000Z', 'invalid');
                """
            )
            try database.execute("PRAGMA foreign_keys = ON;")

            let destination = directory.appendingPathComponent("retry.sqlite3")
            var validationFailed = false
            do {
                _ = try HolyDatabaseMaintenance.createCompactedCopy(of: database, at: destination)
            } catch HolyDatabaseMaintenanceError.foreignKeyCheckFailed(_, _) {
                validationFailed = true
            }
            #expect(validationFailed)
            #expect(!FileManager.default.fileExists(atPath: destination.path))
            #expect(
                try FileManager.default.contentsOfDirectory(atPath: directory.path)
                    .allSatisfy { !$0.contains(".building-") }
            )

            try database.execute("DELETE FROM session_events WHERE session_id = 'missing-session';")
            let report = try HolyDatabaseMaintenance.createCompactedCopy(of: database, at: destination)
            #expect(report.rowCounts[.sessionEvents] == 0)
            #expect(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    @MainActor
    private func persist(
        _ snapshot: HolyWorkspaceSnapshot,
        in database: HolyDatabase
    ) throws {
        try HolyWorkspaceDatabasePersistence.save(
            snapshot,
            activeSessions: [],
            attentionBySessionID: [:],
            pendingEvents: [],
            in: database
        )
    }

    @MainActor
    private func withTemporaryDatabase<T>(
        _ body: (HolyDatabase, URL) throws -> T
    ) throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-retention-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = try HolyDatabase.open(at: directory.appendingPathComponent("source.sqlite3"))
        try HolyDatabaseMigrator.migrate(database)
        return try body(database, directory)
    }

    private func archivedSession(
        id: UUID = UUID(),
        sourceSessionID: UUID,
        archivedAt: Date = .now,
        gitSnapshot: HolyGitSnapshot?
    ) -> HolyArchivedSession {
        var launchSpec = HolySessionLaunchSpec.interactiveTmuxShell(title: "Retention test")
        launchSpec.tmux = .init(
            socketName: HolySessionTmuxSpec.defaultSocketName,
            sessionName: "retention-\(sourceSessionID.uuidString)",
            createIfMissing: true
        )
        let record = HolySessionRecord(
            id: sourceSessionID,
            launchSpec: launchSpec,
            createdAt: archivedAt.addingTimeInterval(-60),
            updatedAt: archivedAt
        )
        return HolyArchivedSession(
            id: id,
            sourceSessionID: sourceSessionID,
            record: record,
            phase: .completed,
            preview: "",
            signals: [],
            commandTelemetry: .empty,
            budgetTelemetry: .empty,
            runtimeTelemetry: .empty,
            gitSnapshot: gitSnapshot,
            lastKnownWorkingDirectory: "/tmp",
            lastActivityAt: archivedAt,
            archivedAt: archivedAt
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
                .init(
                    path: "README.md",
                    category: .modified,
                    stagedStatus: " ",
                    unstagedStatus: "M"
                ),
            ]
        )
    }

    private func queryPlan(_ sql: String, in database: HolyDatabase) throws -> String {
        var details: [String] = []
        try database.query(sql) { statement in
            guard let bytes = sqlite3_column_text(statement, 3) else { return }
            details.append(String(cString: bytes))
        }
        return details.joined(separator: "\n")
    }

    private func databaseRowCounts(
        in database: HolyDatabase
    ) throws -> [HolyDatabaseTable: Int64] {
        try Dictionary(uniqueKeysWithValues: HolyDatabaseTable.allCases.map { table in
            (table, try database.scalarInt64("SELECT COUNT(*) FROM \(table.rawValue);"))
        })
    }

    private func foreignKeyViolationCount(in database: HolyDatabase) throws -> Int {
        var count = 0
        try database.query("PRAGMA foreign_key_check;") { _ in count += 1 }
        return count
    }
}
