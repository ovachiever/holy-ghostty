import Foundation
import OSLog
import SQLite3

enum HolyWorkspaceDatabasePersistence {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mitchellh.ghostty",
        category: "HolyWorkspaceDatabasePersistence"
    )

    private static let workspaceInitializedKey = "workspace_initialized"
    private static let selectedSessionIDKey = "selected_session_id"
    private static let activeSessionOrderKey = "active_session_order"
    private static let archivedSessionOrderKey = "archived_session_order"
    private static let templateOrderKey = "template_order"
    private static let legacyImportCompletedAtKey = "legacy_json_imported_at"

    private struct HolySessionRowProjection {
        let sessionID: UUID
        let title: String
        let runtime: HolySessionRuntime
        let mission: String?
        let createdAt: Date
        let updatedAt: Date
        let archivedAt: Date?
        let launchSpec: HolySessionLaunchSpec
        let ownershipJSON: String?
        let workingDirectory: String?
        let repositoryRoot: String?
        let worktreePath: String?
        let branchName: String?
        let latestPreviewText: String?
        let resumeMetadataJSON: String?
        let preferredCommand: String?
        let latestPhase: String?
        let latestAttention: String?
        let latestSignalJSON: String?
        let latestBudgetJSON: String?
        let latestCommandTelemetryJSON: String?
        let latestRuntimeTelemetryJSON: String?
    }

    static func load() -> HolyWorkspaceSnapshot? {
        do {
            let database = try HolyDatabase.openAppDatabase(readOnly: true)
            return try load(from: database)
        } catch {
            logger.error("Failed to load Holy workspace state from database: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    @MainActor
    static func save(
        _ snapshot: HolyWorkspaceSnapshot,
        activeSessions: [HolySession] = [],
        attentionBySessionID: [UUID: HolySessionAttention] = [:],
        pendingEvents: [HolySessionEventDraft] = []
    ) {
        do {
            let database = try HolyDatabase.openAppDatabase()
            try save(
                snapshot,
                activeSessions: activeSessions,
                attentionBySessionID: attentionBySessionID,
                pendingEvents: pendingEvents,
                in: database
            )
        } catch {
            logger.error("Failed to save Holy workspace state to database: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func hasInitializedWorkspace() throws -> Bool {
        let database = try HolyDatabase.openAppDatabase(readOnly: true)
        return try isWorkspaceInitialized(in: database)
    }

    static func markLegacyImportCompleted(at date: Date = .now) {
        do {
            let database = try HolyDatabase.openAppDatabase()
            try database.withTransaction {
                try upsertAppStateValue(date, forKey: legacyImportCompletedAtKey, in: database)
            }
        } catch {
            logger.error("Failed to record Holy legacy import marker: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from database: HolyDatabase) throws -> HolyWorkspaceSnapshot? {
        guard try isWorkspaceInitialized(in: database) else {
            return nil
        }

        let records = try loadActiveSessionRecords(from: database)
        let archivedSessions = try loadArchivedSessions(from: database)
        let templates = try loadTemplates(from: database)
        let selectedSessionID: UUID? = try appStateValue(forKey: selectedSessionIDKey, in: database)
        let activeSessionOrder: [UUID] = try appStateValue(forKey: activeSessionOrderKey, in: database) ?? []
        let archivedSessionOrder: [UUID] = try appStateValue(forKey: archivedSessionOrderKey, in: database) ?? []
        let templateOrder: [UUID] = try appStateValue(forKey: templateOrderKey, in: database) ?? []

        return HolyWorkspaceSnapshot(
            sessions: reorder(records, by: activeSessionOrder, id: \.id),
            selectedSessionID: selectedSessionID,
            templates: reorder(templates, by: templateOrder, id: \.id),
            archivedSessions: reorder(archivedSessions, by: archivedSessionOrder, id: \.id)
        )
    }

    @MainActor
    private static func save(
        _ snapshot: HolyWorkspaceSnapshot,
        activeSessions: [HolySession],
        attentionBySessionID: [UUID: HolySessionAttention],
        pendingEvents: [HolySessionEventDraft],
        in database: HolyDatabase
    ) throws {
        let activeSessionIndex = Dictionary(uniqueKeysWithValues: activeSessions.map { ($0.id, $0) })
        let desiredSessionIDs = Set(snapshot.sessions.map(\.id) + snapshot.archivedSessions.map(\.sourceSessionID))

        try database.withTransaction {
            for record in snapshot.sessions {
                let liveSession = activeSessionIndex[record.id]
                try upsertActiveSession(
                    record: record,
                    liveSession: liveSession,
                    attention: attentionBySessionID[record.id],
                    in: database
                )
            }

            for archivedSession in snapshot.archivedSessions {
                try upsertArchivedSession(archivedSession, in: database)
            }

            try deleteMissingSessions(keeping: desiredSessionIDs, in: database)

            try database.execute("DELETE FROM templates;")
            for template in snapshot.templates {
                try insertTemplate(template, in: database)
            }

            try upsertAppStateValue(true, forKey: workspaceInitializedKey, in: database)
            try upsertOptionalAppStateValue(snapshot.selectedSessionID, forKey: selectedSessionIDKey, in: database)
            try upsertAppStateValue(snapshot.sessions.map(\.id), forKey: activeSessionOrderKey, in: database)
            try upsertAppStateValue(snapshot.archivedSessions.map(\.id), forKey: archivedSessionOrderKey, in: database)
            try upsertAppStateValue(snapshot.templates.map(\.id), forKey: templateOrderKey, in: database)
            try HolyBudgetIntelligenceRepository.appendSamples(
                activeSessions: activeSessions,
                archivedSessions: snapshot.archivedSessions,
                in: database
            )
            try HolySessionEventRepository.append(pendingEvents, in: database)
        }
    }

    private static func isWorkspaceInitialized(in database: HolyDatabase) throws -> Bool {
        let value: Bool? = try appStateValue(forKey: workspaceInitializedKey, in: database)
        return value == true
    }

    private static func loadActiveSessionRecords(from database: HolyDatabase) throws -> [HolySessionRecord] {
        let sql = """
        SELECT id, launch_spec_json, created_at, updated_at
        FROM sessions
        WHERE archived_at IS NULL
        ORDER BY updated_at DESC;
        """

        var rows: [HolySessionRecord] = []
        try database.query(sql) { statement in
            let id = try uuidColumn(statement, index: 0)
            let launchSpecJSON = try requiredTextColumn(statement, index: 1)
            let createdAt = try dateColumn(statement, index: 2)
            let updatedAt = try dateColumn(statement, index: 3)
            let launchSpec = try HolyPersistenceCoders.decodeJSON(HolySessionLaunchSpec.self, from: launchSpecJSON)

            rows.append(.init(
                id: id,
                launchSpec: launchSpec,
                createdAt: createdAt,
                updatedAt: updatedAt
            ))
        }

        return rows
    }

    private static func loadArchivedSessions(from database: HolyDatabase) throws -> [HolyArchivedSession] {
        let sql = """
        SELECT
            sessions.id,
            sessions.title,
            sessions.runtime,
            sessions.mission,
            sessions.created_at,
            sessions.updated_at,
            sessions.archived_at,
            sessions.launch_spec_json,
            sessions.working_directory,
            sessions.latest_preview_text,
            sessions.resume_metadata_json,
            sessions.latest_phase,
            sessions.latest_signal_json,
            sessions.latest_command_telemetry_json,
            sessions.latest_budget_json,
            sessions.latest_runtime_telemetry_json,
            git_snapshots.repository_root,
            git_snapshots.worktree_path,
            git_snapshots.common_git_directory,
            git_snapshots.branch,
            git_snapshots.upstream_branch,
            git_snapshots.is_detached_head,
            git_snapshots.ahead_count,
            git_snapshots.behind_count,
            git_snapshots.staged_count,
            git_snapshots.unstaged_count,
            git_snapshots.untracked_count,
            git_snapshots.conflicted_count,
            git_snapshots.changed_files_json
        FROM sessions
        LEFT JOIN git_snapshots ON git_snapshots.id = sessions.latest_git_snapshot_id
        WHERE sessions.archived_at IS NOT NULL
        ORDER BY sessions.archived_at DESC;
        """

        var rows: [HolyArchivedSession] = []
        try database.query(sql) { statement in
            let sourceSessionID = try uuidColumn(statement, index: 0)
            let createdAt = try dateColumn(statement, index: 4)
            let updatedAt = try dateColumn(statement, index: 5)
            let archivedAt = try dateColumn(statement, index: 6)
            let launchSpecJSON = try requiredTextColumn(statement, index: 7)
            let launchSpec = try HolyPersistenceCoders.decodeJSON(HolySessionLaunchSpec.self, from: launchSpecJSON)
            let resumeMetadataJSON = textColumn(statement, index: 10)
            let resumeMetadata = try decodeResumeMetadata(from: resumeMetadataJSON, sourceSessionID: sourceSessionID)
            let phaseRaw = textColumn(statement, index: 11) ?? HolySessionPhase.active.rawValue
            let phase = HolySessionPhase(rawValue: phaseRaw) ?? .active
            let signals: [HolySessionSignal] = try decodeOptionalJSON(
                [HolySessionSignal].self,
                from: textColumn(statement, index: 12)
            ) ?? []
            let commandTelemetry: HolySessionCommandTelemetry = try decodeOptionalJSON(
                HolySessionCommandTelemetry.self,
                from: textColumn(statement, index: 13)
            ) ?? .empty
            let budgetTelemetry: HolySessionBudgetTelemetry = try decodeOptionalJSON(
                HolySessionBudgetTelemetry.self,
                from: textColumn(statement, index: 14)
            ) ?? .empty
            let runtimeTelemetry: HolySessionRuntimeTelemetry = try decodeOptionalJSON(
                HolySessionRuntimeTelemetry.self,
                from: textColumn(statement, index: 15)
            ) ?? .empty
            let gitSnapshot = try decodeGitSnapshot(from: statement, startingAt: 16)

            let record = HolySessionRecord(
                id: sourceSessionID,
                launchSpec: launchSpec,
                createdAt: createdAt,
                updatedAt: updatedAt
            )

            rows.append(.init(
                id: resumeMetadata.archiveID ?? sourceSessionID,
                sourceSessionID: sourceSessionID,
                record: record,
                phase: phase,
                preview: textColumn(statement, index: 9) ?? "",
                signals: signals,
                commandTelemetry: commandTelemetry,
                budgetTelemetry: budgetTelemetry,
                runtimeTelemetry: runtimeTelemetry,
                gitSnapshot: gitSnapshot,
                lastKnownWorkingDirectory: resumeMetadata.lastKnownWorkingDirectory ?? textColumn(statement, index: 8),
                lastActivityAt: resumeMetadata.lastActivityAt ?? updatedAt,
                archivedAt: archivedAt,
                recoveryReason: resumeMetadata.recoveryReason,
                recoveryCleanupSummary: resumeMetadata.recoveryCleanupSummary
            ))
        }

        return rows
    }

    private static func loadTemplates(from database: HolyDatabase) throws -> [HolySessionTemplate] {
        let sql = """
        SELECT id, name, summary, launch_spec_json, created_at, updated_at
        FROM templates
        ORDER BY updated_at DESC;
        """

        var rows: [HolySessionTemplate] = []
        try database.query(sql) { statement in
            let id = try uuidColumn(statement, index: 0)
            let name = try requiredTextColumn(statement, index: 1)
            let summary = textColumn(statement, index: 2) ?? ""
            let launchSpecJSON = try requiredTextColumn(statement, index: 3)
            let createdAt = try dateColumn(statement, index: 4)
            let updatedAt = try dateColumn(statement, index: 5)
            let launchSpec = try HolyPersistenceCoders.decodeJSON(HolySessionLaunchSpec.self, from: launchSpecJSON)

            rows.append(.init(
                id: id,
                name: name,
                summary: summary,
                launchSpec: launchSpec,
                createdAt: createdAt,
                updatedAt: updatedAt
            ))
        }

        return rows
    }

    @MainActor
    private static func upsertActiveSession(
        record: HolySessionRecord,
        liveSession: HolySession?,
        attention: HolySessionAttention?,
        in database: HolyDatabase
    ) throws {
        let livePreview = liveSession?.preview
        let livePhase = liveSession?.phase.rawValue
        let liveSignalsJSON = try encodeOptionalJSON(liveSession?.signals)
        let liveTelemetryJSON = try encodeOptionalJSON(liveSession?.commandTelemetry)
        let liveBudgetJSON = try encodeOptionalJSON(liveSession?.budgetTelemetry)
        let liveRuntimeTelemetryJSON = try encodeOptionalJSON(liveSession?.runtimeTelemetry)
        let resumeMetadataJSON = try encodeOptionalJSON(
            HolyResumeMetadata.active(
                sourceSessionID: record.id,
                runtime: record.launchSpec.runtime,
                launchSpec: record.launchSpec
            )
        )

        try upsertSessionRow(
            .init(
                sessionID: record.id,
                title: record.launchSpec.resolvedTitle,
                runtime: record.launchSpec.runtime,
                mission: record.launchSpec.objective,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                archivedAt: nil,
                launchSpec: record.launchSpec,
                ownershipJSON: nil,
                workingDirectory: liveSession?.workingDirectory ?? record.launchSpec.workingDirectory,
                repositoryRoot: liveSession?.ownership.repositoryRoot ?? record.launchSpec.workspace?.repositoryRoot,
                worktreePath: liveSession?.ownership.worktreePath,
                branchName: liveSession?.ownership.branchName ?? record.launchSpec.workspace?.branchName,
                latestPreviewText: livePreview,
                resumeMetadataJSON: resumeMetadataJSON,
                preferredCommand: record.launchSpec.command,
                latestPhase: livePhase,
                latestAttention: attention?.rawValue,
                latestSignalJSON: liveSignalsJSON,
                latestBudgetJSON: liveBudgetJSON,
                latestCommandTelemetryJSON: liveTelemetryJSON,
                latestRuntimeTelemetryJSON: liveRuntimeTelemetryJSON
            ),
            in: database
        )

        if let gitSnapshot = liveSession?.gitSnapshot {
            let gitSnapshotID = try insertGitSnapshot(gitSnapshot, sessionID: record.id, in: database)
            try updateLatestGitSnapshotID(gitSnapshotID, sessionID: record.id, in: database)
        } else {
            try updateLatestGitSnapshotID(nil, sessionID: record.id, in: database)
        }
    }

    private static func upsertArchivedSession(
        _ archivedSession: HolyArchivedSession,
        in database: HolyDatabase
    ) throws {
        let signalsJSON = try encodeOptionalJSON(archivedSession.signals)
        let telemetryJSON = try encodeOptionalJSON(archivedSession.commandTelemetry)
        let budgetJSON = try encodeOptionalJSON(archivedSession.budgetTelemetry)
        let runtimeTelemetryJSON = try encodeOptionalJSON(archivedSession.runtimeTelemetry)
        let resumeMetadataJSON = try encodeOptionalJSON(
            HolyResumeMetadata.archived(archivedSession)
        )

        try upsertSessionRow(
            .init(
                sessionID: archivedSession.sourceSessionID,
                title: archivedSession.title,
                runtime: archivedSession.runtime,
                mission: archivedSession.record.launchSpec.objective,
                createdAt: archivedSession.record.createdAt,
                updatedAt: archivedSession.record.updatedAt,
                archivedAt: archivedSession.archivedAt,
                launchSpec: archivedSession.record.launchSpec,
                ownershipJSON: nil,
                workingDirectory: archivedSession.lastKnownWorkingDirectory ?? archivedSession.record.launchSpec.workingDirectory,
                repositoryRoot: archivedSession.ownership.repositoryRoot,
                worktreePath: archivedSession.ownership.worktreePath,
                branchName: archivedSession.ownership.branchName,
                latestPreviewText: archivedSession.preview,
                resumeMetadataJSON: resumeMetadataJSON,
                preferredCommand: archivedSession.record.launchSpec.command,
                latestPhase: archivedSession.phase.rawValue,
                latestAttention: attention(for: archivedSession.phase).rawValue,
                latestSignalJSON: signalsJSON,
                latestBudgetJSON: budgetJSON,
                latestCommandTelemetryJSON: telemetryJSON,
                latestRuntimeTelemetryJSON: runtimeTelemetryJSON
            ),
            in: database
        )

        if let gitSnapshot = archivedSession.gitSnapshot {
            let gitSnapshotID = try insertGitSnapshot(gitSnapshot, sessionID: archivedSession.sourceSessionID, in: database)
            try updateLatestGitSnapshotID(gitSnapshotID, sessionID: archivedSession.sourceSessionID, in: database)
        } else {
            try updateLatestGitSnapshotID(nil, sessionID: archivedSession.sourceSessionID, in: database)
        }
    }

    private static func insertTemplate(_ template: HolySessionTemplate, in database: HolyDatabase) throws {
        let sql = """
        INSERT INTO templates (
            id, name, summary, launch_spec_json, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?);
        """

        try database.execute(sql, bindings: [
            .text(template.id.uuidString),
            .text(template.name),
            .text(template.summary),
            .text(try HolyPersistenceCoders.encodeJSON(template.launchSpec)),
            .text(HolyPersistenceCoders.string(from: template.createdAt)),
            .text(HolyPersistenceCoders.string(from: template.updatedAt)),
        ])
    }

    private static func upsertSessionRow(
        _ projection: HolySessionRowProjection,
        in database: HolyDatabase
    ) throws {
        let sql = """
        INSERT INTO sessions (
            id, title, runtime, mission, created_at, updated_at, archived_at,
            launch_spec_json, ownership_json, working_directory, repository_root, worktree_path,
            branch_name, latest_preview_text, resume_metadata_json, preferred_command,
            latest_phase, latest_attention, latest_signal_json, latest_budget_json, latest_command_telemetry_json,
            latest_runtime_telemetry_json, latest_git_snapshot_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            title = excluded.title,
            runtime = excluded.runtime,
            mission = excluded.mission,
            created_at = excluded.created_at,
            updated_at = excluded.updated_at,
            archived_at = excluded.archived_at,
            launch_spec_json = excluded.launch_spec_json,
            ownership_json = excluded.ownership_json,
            working_directory = excluded.working_directory,
            repository_root = excluded.repository_root,
            worktree_path = excluded.worktree_path,
            branch_name = excluded.branch_name,
            latest_preview_text = excluded.latest_preview_text,
            resume_metadata_json = excluded.resume_metadata_json,
            preferred_command = excluded.preferred_command,
            latest_phase = excluded.latest_phase,
            latest_attention = excluded.latest_attention,
            latest_signal_json = excluded.latest_signal_json,
            latest_budget_json = excluded.latest_budget_json,
            latest_command_telemetry_json = excluded.latest_command_telemetry_json,
            latest_runtime_telemetry_json = excluded.latest_runtime_telemetry_json,
            latest_git_snapshot_id = excluded.latest_git_snapshot_id;
        """

        try database.execute(sql, bindings: [
            .text(projection.sessionID.uuidString),
            .text(projection.title),
            .text(projection.runtime.rawValue),
            binding(for: projection.mission),
            .text(HolyPersistenceCoders.string(from: projection.createdAt)),
            .text(HolyPersistenceCoders.string(from: projection.updatedAt)),
            binding(for: projection.archivedAt.map(HolyPersistenceCoders.string(from:))),
            .text(try HolyPersistenceCoders.encodeJSON(projection.launchSpec)),
            binding(for: projection.ownershipJSON),
            binding(for: projection.workingDirectory),
            binding(for: projection.repositoryRoot),
            binding(for: projection.worktreePath),
            binding(for: projection.branchName),
            binding(for: projection.latestPreviewText),
            binding(for: projection.resumeMetadataJSON),
            binding(for: projection.preferredCommand),
            binding(for: projection.latestPhase),
            binding(for: projection.latestAttention),
            binding(for: projection.latestSignalJSON),
            binding(for: projection.latestBudgetJSON),
            binding(for: projection.latestCommandTelemetryJSON),
            binding(for: projection.latestRuntimeTelemetryJSON),
            .null,
        ])
    }

    private static func insertGitSnapshot(
        _ snapshot: HolyGitSnapshot,
        sessionID: UUID,
        in database: HolyDatabase
    ) throws -> Int64 {
        let sql = """
        INSERT INTO git_snapshots (
            session_id, captured_at, repository_root, worktree_path, common_git_directory,
            branch, upstream_branch, is_detached_head, ahead_count, behind_count,
            staged_count, unstaged_count, untracked_count, conflicted_count, changed_files_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        try database.execute(sql, bindings: [
            .text(sessionID.uuidString),
            .text(HolyPersistenceCoders.string(from: .now)),
            .text(snapshot.repositoryRoot),
            .text(snapshot.worktreePath),
            .text(snapshot.commonGitDirectory),
            .text(snapshot.branch),
            binding(for: snapshot.upstreamBranch),
            .bool(snapshot.isDetachedHead),
            .int(Int32(snapshot.aheadCount)),
            .int(Int32(snapshot.behindCount)),
            .int(Int32(snapshot.stagedCount)),
            .int(Int32(snapshot.unstagedCount)),
            .int(Int32(snapshot.untrackedCount)),
            .int(Int32(snapshot.conflictedCount)),
            .text(try HolyPersistenceCoders.encodeJSON(snapshot.changedFiles)),
        ])

        return database.lastInsertedRowID
    }

    private static func updateLatestGitSnapshotID(
        _ gitSnapshotID: Int64?,
        sessionID: UUID,
        in database: HolyDatabase
    ) throws {
        let sql = """
        UPDATE sessions
        SET latest_git_snapshot_id = ?
        WHERE id = ?;
        """

        try database.execute(sql, bindings: [
            gitSnapshotID.map(HolyDatabaseBinding.int64) ?? .null,
            .text(sessionID.uuidString),
        ])
    }

    private static func deleteMissingSessions(
        keeping sessionIDs: Set<UUID>,
        in database: HolyDatabase
    ) throws {
        guard !sessionIDs.isEmpty else {
            try database.execute("DELETE FROM sessions;")
            return
        }

        let placeholders = Array(repeating: "?", count: sessionIDs.count).joined(separator: ", ")
        let sql = "DELETE FROM sessions WHERE id NOT IN (\(placeholders));"
        let bindings = sessionIDs
            .sorted { $0.uuidString < $1.uuidString }
            .map { HolyDatabaseBinding.text($0.uuidString) }
        try database.execute(sql, bindings: bindings)
    }

    private static func upsertAppStateValue<T: Encodable>(
        _ value: T,
        forKey key: String,
        in database: HolyDatabase
    ) throws {
        let sql = """
        INSERT INTO app_state (key, value_json, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET
            value_json = excluded.value_json,
            updated_at = excluded.updated_at;
        """

        try database.execute(sql, bindings: [
            .text(key),
            .text(try HolyPersistenceCoders.encodeJSON(value)),
            .text(HolyPersistenceCoders.string(from: .now)),
        ])
    }

    private static func upsertOptionalAppStateValue<T: Encodable>(
        _ value: T?,
        forKey key: String,
        in database: HolyDatabase
    ) throws {
        if let value {
            try upsertAppStateValue(value, forKey: key, in: database)
            return
        }

        try database.execute(
            "DELETE FROM app_state WHERE key = ?;",
            bindings: [.text(key)]
        )
    }

    private static func appStateValue<T: Decodable>(
        forKey key: String,
        in database: HolyDatabase
    ) throws -> T? {
        let sql = """
        SELECT value_json
        FROM app_state
        WHERE key = ?
        LIMIT 1;
        """

        var value: T?
        try database.query(sql, bindings: [.text(key)]) { statement in
            guard let json = textColumn(statement, index: 0) else { return }
            value = try HolyPersistenceCoders.decodeJSON(T.self, from: json)
        }
        return value
    }

    private static func decodeGitSnapshot(
        from statement: OpaquePointer,
        startingAt baseIndex: Int32
    ) throws -> HolyGitSnapshot? {
        guard let repositoryRoot = textColumn(statement, index: baseIndex) else {
            return nil
        }

        let changedFilesJSON = try requiredTextColumn(statement, index: baseIndex + 12)
        let changedFiles = try HolyPersistenceCoders.decodeJSON([HolyGitFileChange].self, from: changedFilesJSON)

        return HolyGitSnapshot(
            repositoryRoot: repositoryRoot,
            worktreePath: try requiredTextColumn(statement, index: baseIndex + 1),
            commonGitDirectory: try requiredTextColumn(statement, index: baseIndex + 2),
            branch: try requiredTextColumn(statement, index: baseIndex + 3),
            upstreamBranch: textColumn(statement, index: baseIndex + 4),
            isDetachedHead: intColumn(statement, index: baseIndex + 5) != 0,
            aheadCount: Int(intColumn(statement, index: baseIndex + 6)),
            behindCount: Int(intColumn(statement, index: baseIndex + 7)),
            stagedCount: Int(intColumn(statement, index: baseIndex + 8)),
            unstagedCount: Int(intColumn(statement, index: baseIndex + 9)),
            untrackedCount: Int(intColumn(statement, index: baseIndex + 10)),
            conflictedCount: Int(intColumn(statement, index: baseIndex + 11)),
            changedFiles: changedFiles
        )
    }

    private static func decodeResumeMetadata(
        from json: String?,
        sourceSessionID: UUID
    ) throws -> HolyResumeMetadata {
        if let json,
           let metadata = try decodeOptionalJSON(HolyResumeMetadata.self, from: json) {
            return metadata
        }

        return .init(
            archiveID: sourceSessionID,
            sourceSessionID: sourceSessionID,
            runtime: .shell,
            workingDirectory: nil,
            preferredCommand: nil,
            resumeKind: "archived_session",
            lastKnownWorkingDirectory: nil,
            lastActivityAt: nil,
            recoveryReason: nil,
            recoveryCleanupSummary: nil
        )
    }

    private static func decodeOptionalJSON<T: Decodable>(_ type: T.Type, from json: String?) throws -> T? {
        guard let json else { return nil }
        return try HolyPersistenceCoders.decodeJSON(T.self, from: json)
    }

    private static func encodeOptionalJSON<T: Encodable>(_ value: T?) throws -> String? {
        guard let value else { return nil }
        return try HolyPersistenceCoders.encodeJSON(value)
    }

    private static func binding(for string: String?) -> HolyDatabaseBinding {
        guard let string else { return .null }
        return .text(string)
    }

    private static func attention(for phase: HolySessionPhase) -> HolySessionAttention {
        switch phase {
        case .active:
            return .none
        case .working:
            return .watch
        case .waitingInput:
            return .needsInput
        case .completed:
            return .done
        case .failed:
            return .failure
        }
    }

    private static func textColumn(_ statement: OpaquePointer, index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, index) else {
            return nil
        }

        return String(cString: value)
    }

    private static func requiredTextColumn(_ statement: OpaquePointer, index: Int32) throws -> String {
        guard let value = textColumn(statement, index: index) else {
            throw CocoaError(.coderValueNotFound)
        }

        return value
    }

    private static func uuidColumn(_ statement: OpaquePointer, index: Int32) throws -> UUID {
        let string = try requiredTextColumn(statement, index: index)
        guard let uuid = UUID(uuidString: string) else {
            throw CocoaError(.coderInvalidValue)
        }
        return uuid
    }

    private static func dateColumn(_ statement: OpaquePointer, index: Int32) throws -> Date {
        try HolyPersistenceCoders.date(from: requiredTextColumn(statement, index: index))
    }

    private static func intColumn(_ statement: OpaquePointer, index: Int32) -> Int32 {
        sqlite3_column_int(statement, index)
    }

    private static func reorder<Element>(
        _ elements: [Element],
        by order: [UUID],
        id keyPath: KeyPath<Element, UUID>
    ) -> [Element] {
        guard !order.isEmpty else { return elements }

        let positions = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return elements.sorted { lhs, rhs in
            let lhsPosition = positions[lhs[keyPath: keyPath]] ?? .max
            let rhsPosition = positions[rhs[keyPath: keyPath]] ?? .max
            return lhsPosition < rhsPosition
        }
    }
}

private struct HolyResumeMetadata: Codable {
    let archiveID: UUID?
    let sourceSessionID: UUID
    let runtime: HolySessionRuntime
    let workingDirectory: String?
    let preferredCommand: String?
    let resumeKind: String
    let lastKnownWorkingDirectory: String?
    let lastActivityAt: Date?
    let recoveryReason: String?
    let recoveryCleanupSummary: String?

    static func active(
        sourceSessionID: UUID,
        runtime: HolySessionRuntime,
        launchSpec: HolySessionLaunchSpec
    ) -> Self {
        .init(
            archiveID: nil,
            sourceSessionID: sourceSessionID,
            runtime: runtime,
            workingDirectory: launchSpec.workingDirectory,
            preferredCommand: launchSpec.command,
            resumeKind: "active_session",
            lastKnownWorkingDirectory: nil,
            lastActivityAt: nil,
            recoveryReason: nil,
            recoveryCleanupSummary: nil
        )
    }

    static func archived(_ archivedSession: HolyArchivedSession) -> Self {
        .init(
            archiveID: archivedSession.id,
            sourceSessionID: archivedSession.sourceSessionID,
            runtime: archivedSession.runtime,
            workingDirectory: archivedSession.record.launchSpec.workingDirectory,
            preferredCommand: archivedSession.record.launchSpec.command,
            resumeKind: "archived_session",
            lastKnownWorkingDirectory: archivedSession.lastKnownWorkingDirectory,
            lastActivityAt: archivedSession.lastActivityAt,
            recoveryReason: archivedSession.recoveryReason,
            recoveryCleanupSummary: archivedSession.recoveryCleanupSummary
        )
    }
}
