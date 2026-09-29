import AppKit
import Combine
import Foundation
import OSLog
import SQLite3

/// What one flush actually wrote to the workspace database. Every count is
/// zero when the durable state was already on disk: the transaction then
/// dirtied no page, SQLite appended no WAL frame, and no sync ran.
struct HolyWorkspaceSaveReceipt: Equatable {
    /// `sqlite3_total_changes` delta across the transaction: rows inserted,
    /// updated, or deleted, including cascades.
    var rowsChanged: Int64 = 0
    var sessionRowsWritten = 0
    var gitSnapshotsInserted = 0
    var templatesRewritten = false
    var appStateRowsWritten = 0
    var eventsAppended = 0

    var wroteAnything: Bool {
        rowsChanged > 0
    }
}

/// The live, per-poll fields a session row projects: preview text, phase,
/// telemetry, git state, and the working tree the pane sits in. A value,
/// read off `HolySession` on the main actor, so the save path and its tests
/// never need a terminal surface to feed runtime updates.
struct HolyWorkspaceLiveSessionState: Equatable {
    let sessionID: UUID
    var phase: HolySessionPhase
    var preview: String
    var signals: [HolySessionSignal]
    var commandTelemetry: HolySessionCommandTelemetry
    var budgetTelemetry: HolySessionBudgetTelemetry
    var runtimeTelemetry: HolySessionRuntimeTelemetry
    var gitSnapshot: HolyGitSnapshot?
    var workingDirectory: String?
    var repositoryRoot: String?
    var worktreePath: String?
    var branchName: String?

    init(
        sessionID: UUID,
        phase: HolySessionPhase = .active,
        preview: String = "",
        signals: [HolySessionSignal] = [],
        commandTelemetry: HolySessionCommandTelemetry = .empty,
        budgetTelemetry: HolySessionBudgetTelemetry = .empty,
        runtimeTelemetry: HolySessionRuntimeTelemetry = .empty,
        gitSnapshot: HolyGitSnapshot? = nil,
        workingDirectory: String? = nil,
        repositoryRoot: String? = nil,
        worktreePath: String? = nil,
        branchName: String? = nil
    ) {
        self.sessionID = sessionID
        self.phase = phase
        self.preview = preview
        self.signals = signals
        self.commandTelemetry = commandTelemetry
        self.budgetTelemetry = budgetTelemetry
        self.runtimeTelemetry = runtimeTelemetry
        self.gitSnapshot = gitSnapshot
        self.workingDirectory = workingDirectory
        self.repositoryRoot = repositoryRoot
        self.worktreePath = worktreePath
        self.branchName = branchName
    }

    @MainActor
    init(session: HolySession) {
        let ownership = session.ownership
        self.init(
            sessionID: session.id,
            phase: session.phase,
            preview: session.preview,
            signals: session.signals,
            commandTelemetry: session.commandTelemetry,
            budgetTelemetry: session.budgetTelemetry,
            runtimeTelemetry: session.runtimeTelemetry,
            gitSnapshot: session.gitSnapshot,
            workingDirectory: session.workingDirectory,
            repositoryRoot: ownership.repositoryRoot,
            worktreePath: ownership.worktreePath,
            branchName: ownership.branchName
        )
    }
}

/// Everything one flush carries into the database.
struct HolyWorkspaceSaveInput {
    var snapshot: HolyWorkspaceSnapshot
    var liveSessionStates: [HolyWorkspaceLiveSessionState] = []
    /// Live sessions for the budget ledger, which reads the budget and its
    /// status straight off the session. Empty in tests that feed live state
    /// as values.
    var budgetSampleSessions: [HolySession] = []
    var attentionBySessionID: [UUID: HolySessionAttention] = [:]
    var pendingEvents: [HolySessionEventDraft] = []
}

/// The one connection the workspace save loop writes through, kept open
/// across flushes.
///
/// Before this class every flush opened the app database, wrote, and let
/// the connection deinit; that close ran a WAL checkpoint with F_FULLFSYNC
/// into a 1.6 GB main file on the main thread, 83 times in 120 s on the
/// live fleet (lane mn-59bbbf, 2026-09-26). The connection now opens on
/// the first flush with `HolyDatabase.openDurableWriter(at:)` and stays
/// open; every commit that wrote a frame is F_FULLFSYNC'd by SQLite itself
/// (`synchronous = FULL`, `fullfsync = ON`), so a flush is on the platter
/// when `save` returns, exactly as promptly as the close checkpoint made
/// it. Checkpoints run on the library's own frame threshold, off-thread.
///
/// A failed flush drops the connection so the next flush reopens it: the
/// recovery the per-flush open used to give for free.
@MainActor
final class HolyWorkspaceDatabaseWriter {
    static let shared = HolyWorkspaceDatabaseWriter(databaseURL: HolyDatabasePaths.databaseURL)

    let databaseURL: URL
    private var connection: HolyDatabase?
    private(set) var connectionOpenCount = 0
    private(set) var flushCount = 0
    private(set) var lastReceipt: HolyWorkspaceSaveReceipt?

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    var isConnected: Bool {
        connection != nil
    }

    /// The open writer connection, opened on first use.
    func openConnection() throws -> HolyDatabase {
        if let connection {
            return connection
        }

        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let opened = try HolyDatabase.openDurableWriter(at: databaseURL)
        connection = opened
        connectionOpenCount += 1
        return opened
    }

    @discardableResult
    func save(_ input: HolyWorkspaceSaveInput) throws -> HolyWorkspaceSaveReceipt {
        let database = try openConnection()
        do {
            let receipt = try HolyWorkspaceDatabasePersistence.save(input, in: database)
            flushCount += 1
            lastReceipt = receipt
            return receipt
        } catch {
            // The transaction rolled back. Drop the connection so the next
            // flush reopens a fresh one, as the per-flush open used to.
            closeConnection()
            throw error
        }
    }

    /// Closes the connection without a checkpoint. The next flush reopens.
    func closeConnection() {
        connection?.close()
        connection = nil
    }

    /// Folds the WAL into the main file as far as readers allow and closes.
    /// Called at an orderly quit so the database is left the way the
    /// per-flush close used to leave it; a crash never reaches this and
    /// needs nothing from it, every commit is already synced.
    @discardableResult
    func checkpointAndClose() -> HolyDatabaseCheckpointReceipt? {
        guard let connection else { return nil }
        let receipt = try? connection.checkpoint(.passive)
        closeConnection()
        return receipt
    }
}

enum HolyWorkspaceDatabasePersistence {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mitchellh.ghostty",
        category: "HolyWorkspaceDatabasePersistence"
    )
    private static let retentionWorker = HolyWorkspaceRetentionWorker(databaseURL: HolyDatabasePaths.databaseURL)
    @MainActor private static var terminationObserver: AnyCancellable?

    private static let workspaceInitializedKey = "workspace_initialized"
    private static let selectedSessionIDKey = "selected_session_id"
    private static let paneLayoutKey = "pane_layout"
    private static let activeSessionOrderKey = "active_session_order"
    private static let archivedSessionOrderKey = "archived_session_order"
    private static let templateOrderKey = "template_order"
    private static let attentionMetadataKey = "attention_metadata"
    private static let legacyImportCompletedAtKey = "legacy_json_imported_at"

    private struct HolySessionRowProjection {
        let sessionID: UUID
        let harnessSessionID: String?
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
        startRetentionMaintenance()

        do {
            let receipt = try HolyWorkspaceDatabaseWriter.shared.save(
                .init(
                    snapshot: snapshot,
                    liveSessionStates: activeSessions.map(HolyWorkspaceLiveSessionState.init(session:)),
                    budgetSampleSessions: activeSessions,
                    attentionBySessionID: attentionBySessionID,
                    pendingEvents: pendingEvents
                )
            )

            if receipt.wroteAnything {
                retentionWorker.requestPass()
            }
        } catch {
            logger.error("Failed to save Holy workspace state to database: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Called at launch after migration, before the first save. Expiry and
    /// backlog draining must continue even in a completely quiet workspace.
    @MainActor
    static func startRetentionMaintenance() {
        installTerminationHandlerIfNeeded()
        retentionWorker.start()
    }

    /// At an orderly quit: write the legacy snapshot exactly as last handed
    /// over (its activity clocks included), fold the WAL into the main
    /// file, and close the writer. Registered on the first save; the
    /// notification is posted on the main thread.
    @MainActor
    private static func installTerminationHandlerIfNeeded() {
        guard terminationObserver == nil else { return }
        terminationObserver = NotificationCenter.default
            .publisher(for: NSApplication.willTerminateNotification)
            .sink { _ in
                HolyWorkspacePersistence.flushForTermination()
                retentionWorker.stop()
                HolyWorkspaceDatabaseWriter.shared.checkpointAndClose()
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

    static func load(from database: HolyDatabase) throws -> HolyWorkspaceSnapshot? {
        guard try isWorkspaceInitialized(in: database) else {
            return nil
        }

        let records = try loadActiveSessionRecords(from: database)
        let archivedSessions = try loadArchivedSessions(from: database)
        let templates = try loadTemplates(from: database)
        let selectedSessionID: UUID? = try appStateValue(forKey: selectedSessionIDKey, in: database)
        let paneLayout: HolyPaneLayout = try appStateValue(forKey: paneLayoutKey, in: database) ?? .single
        let activeSessionOrder: [UUID] = try appStateValue(forKey: activeSessionOrderKey, in: database) ?? []
        let archivedSessionOrder: [UUID] = try appStateValue(forKey: archivedSessionOrderKey, in: database) ?? []
        let templateOrder: [UUID] = try appStateValue(forKey: templateOrderKey, in: database) ?? []
        let attentionMetadata: [HolySessionAttentionMetadata] = try appStateValue(forKey: attentionMetadataKey, in: database) ?? []

        return HolyWorkspaceSnapshot(
            sessions: reorder(records, by: activeSessionOrder, id: \.id),
            selectedSessionID: selectedSessionID,
            templates: reorder(templates, by: templateOrder, id: \.id),
            archivedSessions: reorder(archivedSessions, by: archivedSessionOrder, id: \.id),
            paneLayout: paneLayout.normalized(
                availableSessionIDs: records.map(\.id),
                selectedSessionID: selectedSessionID
            ),
            attentionMetadata: attentionMetadata.filter { metadata in
                records.contains(where: { $0.id == metadata.sessionID })
            }
        )
    }

    @MainActor
    @discardableResult
    static func save(
        _ snapshot: HolyWorkspaceSnapshot,
        activeSessions: [HolySession],
        attentionBySessionID: [UUID: HolySessionAttention],
        pendingEvents: [HolySessionEventDraft],
        in database: HolyDatabase
    ) throws -> HolyWorkspaceSaveReceipt {
        try save(
            .init(
                snapshot: snapshot,
                liveSessionStates: activeSessions.map(HolyWorkspaceLiveSessionState.init(session:)),
                budgetSampleSessions: activeSessions,
                attentionBySessionID: attentionBySessionID,
                pendingEvents: pendingEvents
            ),
            in: database
        )
    }

    /// One flush, one transaction. Every statement is conditional on the row
    /// differing from what the table already holds (an UPSERT whose
    /// `DO UPDATE ... WHERE` compares each column, an UPDATE that names the
    /// value it would set, a template rewrite only when the set differs), so
    /// an unchanged row is never written and an unchanged workspace commits
    /// nothing: no dirty page, no WAL frame, no sync.
    @MainActor
    @discardableResult
    static func save(
        _ input: HolyWorkspaceSaveInput,
        in database: HolyDatabase
    ) throws -> HolyWorkspaceSaveReceipt {
        let snapshot = input.snapshot
        let liveStateIndex = Dictionary(
            input.liveSessionStates.map { ($0.sessionID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let activeSessionIDs = Set(snapshot.sessions.map(\.id))
        // An active record is the live source of truth if stale persisted input
        // happens to contain an archive for the same source session.
        let archivedSessions = snapshot.archivedSessions.filter {
            !activeSessionIDs.contains($0.sourceSessionID)
        }
        let desiredSessionIDs = activeSessionIDs.union(archivedSessions.map(\.sourceSessionID))

        var receipt = HolyWorkspaceSaveReceipt()
        let changesBefore = database.totalChangedRowCount

        try database.withTransaction {
            for record in snapshot.sessions {
                try upsertActiveSession(
                    record: record,
                    liveState: liveStateIndex[record.id],
                    attention: input.attentionBySessionID[record.id],
                    in: database,
                    receipt: &receipt
                )
            }

            for archivedSession in archivedSessions {
                try upsertArchivedSession(archivedSession, in: database, receipt: &receipt)
            }

            try markMissingSessionsForPruning(keeping: desiredSessionIDs, in: database)

            receipt.templatesRewritten = try replaceTemplatesIfChanged(snapshot.templates, in: database)

            try upsertAppStateValue(true, forKey: workspaceInitializedKey, in: database, receipt: &receipt)
            try upsertOptionalAppStateValue(
                snapshot.selectedSessionID,
                forKey: selectedSessionIDKey,
                in: database,
                receipt: &receipt
            )
            try upsertAppStateValue(snapshot.paneLayout, forKey: paneLayoutKey, in: database, receipt: &receipt)
            try upsertAppStateValue(
                snapshot.sessions.map(\.id),
                forKey: activeSessionOrderKey,
                in: database,
                receipt: &receipt
            )
            try upsertAppStateValue(
                archivedSessions.map(\.id),
                forKey: archivedSessionOrderKey,
                in: database,
                receipt: &receipt
            )
            try upsertAppStateValue(
                snapshot.templates.map(\.id),
                forKey: templateOrderKey,
                in: database,
                receipt: &receipt
            )
            try upsertAppStateValue(
                snapshot.attentionMetadata,
                forKey: attentionMetadataKey,
                in: database,
                receipt: &receipt
            )
            try HolyBudgetIntelligenceRepository.appendSamples(
                activeSessions: input.budgetSampleSessions,
                archivedSessions: archivedSessions,
                in: database
            )
            try HolySessionEventRepository.append(input.pendingEvents, in: database)
            receipt.eventsAppended = input.pendingEvents.count
        }

        receipt.rowsChanged = database.totalChangedRowCount - changesBefore
        return receipt
    }

    private static func isWorkspaceInitialized(in database: HolyDatabase) throws -> Bool {
        let value: Bool? = try appStateValue(forKey: workspaceInitializedKey, in: database)
        return value == true
    }

    private static func loadActiveSessionRecords(from database: HolyDatabase) throws -> [HolySessionRecord] {
        let sql = """
        SELECT id, launch_spec_json, created_at, updated_at, harness_session_id
        FROM sessions
        WHERE archived_at IS NULL
          AND purge_pending_at IS NULL
        ORDER BY created_at ASC;
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
                harnessSessionID: textColumn(statement, index: 4) ?? launchSpec.providerSessionID,
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
            git_snapshots.changed_files_json,
            sessions.harness_session_id
        FROM sessions
        LEFT JOIN git_snapshots ON git_snapshots.id = sessions.latest_git_snapshot_id
        WHERE sessions.archived_at IS NOT NULL
          AND sessions.purge_pending_at IS NULL
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
                harnessSessionID: textColumn(statement, index: 29) ?? launchSpec.providerSessionID,
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
                recoveryCleanupSummary: resumeMetadata.recoveryCleanupSummary,
                recoveryBootBatchID: resumeMetadata.recoveryBootBatchID
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

    private static func upsertActiveSession(
        record: HolySessionRecord,
        liveState: HolyWorkspaceLiveSessionState?,
        attention: HolySessionAttention?,
        in database: HolyDatabase,
        receipt: inout HolyWorkspaceSaveReceipt
    ) throws {
        let livePreview = liveState?.preview
        let livePhase = liveState?.phase.rawValue
        let liveSignalsJSON = try encodeOptionalJSON(liveState?.signals)
        let liveTelemetryJSON = try encodeOptionalJSON(liveState?.commandTelemetry)
        let liveBudgetJSON = try encodeOptionalJSON(liveState?.budgetTelemetry)
        let liveRuntimeTelemetryJSON = try encodeOptionalJSON(liveState?.runtimeTelemetry)
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
                harnessSessionID: record.effectiveHarnessSessionID,
                title: record.launchSpec.resolvedTitle,
                runtime: record.launchSpec.runtime,
                mission: record.launchSpec.objective,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                archivedAt: nil,
                launchSpec: record.launchSpec,
                ownershipJSON: nil,
                workingDirectory: liveState?.workingDirectory ?? record.launchSpec.workingDirectory,
                repositoryRoot: liveState?.repositoryRoot ?? record.launchSpec.workspace?.repositoryRoot,
                worktreePath: liveState?.worktreePath,
                branchName: liveState?.branchName ?? record.launchSpec.workspace?.branchName,
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
        receipt.sessionRowsWritten += Int(database.changedRowCount)

        try storeGitSnapshotReference(
            liveState?.gitSnapshot,
            sessionID: record.id,
            in: database,
            receipt: &receipt
        )
    }

    private static func upsertArchivedSession(
        _ archivedSession: HolyArchivedSession,
        in database: HolyDatabase,
        receipt: inout HolyWorkspaceSaveReceipt
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
                harnessSessionID: archivedSession.record.effectiveHarnessSessionID,
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
        receipt.sessionRowsWritten += Int(database.changedRowCount)

        try storeGitSnapshotReference(
            archivedSession.gitSnapshot,
            sessionID: archivedSession.sourceSessionID,
            in: database,
            receipt: &receipt
        )
    }

    /// Points the session at its latest git snapshot: a row is inserted only
    /// when the snapshot differs from the one already referenced, and the
    /// reference is rewritten only when it would change.
    private static func storeGitSnapshotReference(
        _ gitSnapshot: HolyGitSnapshot?,
        sessionID: UUID,
        in database: HolyDatabase,
        receipt: inout HolyWorkspaceSaveReceipt
    ) throws {
        var gitSnapshotID: Int64?
        if let gitSnapshot {
            let stored = try storeLatestGitSnapshot(gitSnapshot, sessionID: sessionID, in: database)
            gitSnapshotID = stored.id
            if stored.inserted {
                receipt.gitSnapshotsInserted += 1
            }
        }
        try updateLatestGitSnapshotID(gitSnapshotID, sessionID: sessionID, in: database)
    }

    private struct TemplateRow: Equatable {
        let id: String
        let name: String
        let summary: String
        let launchSpecJSON: String
        let createdAt: String
        let updatedAt: String
    }

    /// Rewrites the templates table only when the persisted set differs from
    /// the snapshot's. Returns whether it rewrote.
    private static func replaceTemplatesIfChanged(
        _ templates: [HolySessionTemplate],
        in database: HolyDatabase
    ) throws -> Bool {
        let desired = try templates.map { template in
            TemplateRow(
                id: template.id.uuidString,
                name: template.name,
                summary: template.summary,
                launchSpecJSON: try HolyPersistenceCoders.encodeJSON(template.launchSpec),
                createdAt: HolyPersistenceCoders.string(from: template.createdAt),
                updatedAt: HolyPersistenceCoders.string(from: template.updatedAt)
            )
        }
        .sorted { $0.id < $1.id }

        var existing: [TemplateRow] = []
        try database.query(
            "SELECT id, name, summary, launch_spec_json, created_at, updated_at FROM templates ORDER BY id;"
        ) { statement in
            existing.append(
                TemplateRow(
                    id: try requiredTextColumn(statement, index: 0),
                    name: try requiredTextColumn(statement, index: 1),
                    summary: textColumn(statement, index: 2) ?? "",
                    launchSpecJSON: try requiredTextColumn(statement, index: 3),
                    createdAt: try requiredTextColumn(statement, index: 4),
                    updatedAt: try requiredTextColumn(statement, index: 5)
                )
            )
        }

        guard existing != desired else { return false }

        try database.execute("DELETE FROM templates;")
        let sql = """
        INSERT INTO templates (
            id, name, summary, launch_spec_json, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?);
        """
        for row in desired {
            try database.execute(sql, bindings: [
                .text(row.id),
                .text(row.name),
                .text(row.summary),
                .text(row.launchSpecJSON),
                .text(row.createdAt),
                .text(row.updatedAt),
            ])
        }
        return true
    }

    private static func upsertSessionRow(
        _ projection: HolySessionRowProjection,
        in database: HolyDatabase
    ) throws {
        let sql = """
        INSERT INTO sessions (
            id, harness_session_id, title, runtime, mission, created_at, updated_at, archived_at,
            launch_spec_json, ownership_json, working_directory, repository_root, worktree_path,
            branch_name, latest_preview_text, resume_metadata_json, preferred_command,
            latest_phase, latest_attention, latest_signal_json, latest_budget_json, latest_command_telemetry_json,
            latest_runtime_telemetry_json, latest_git_snapshot_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            harness_session_id = excluded.harness_session_id,
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
            purge_pending_at = NULL
        WHERE sessions.purge_pending_at IS NOT NULL
           OR sessions.harness_session_id IS NOT excluded.harness_session_id
           OR sessions.title IS NOT excluded.title
           OR sessions.runtime IS NOT excluded.runtime
           OR sessions.mission IS NOT excluded.mission
           OR sessions.created_at IS NOT excluded.created_at
           OR sessions.updated_at IS NOT excluded.updated_at
           OR sessions.archived_at IS NOT excluded.archived_at
           OR sessions.launch_spec_json IS NOT excluded.launch_spec_json
           OR sessions.ownership_json IS NOT excluded.ownership_json
           OR sessions.working_directory IS NOT excluded.working_directory
           OR sessions.repository_root IS NOT excluded.repository_root
           OR sessions.worktree_path IS NOT excluded.worktree_path
           OR sessions.branch_name IS NOT excluded.branch_name
           OR sessions.latest_preview_text IS NOT excluded.latest_preview_text
           OR sessions.resume_metadata_json IS NOT excluded.resume_metadata_json
           OR sessions.preferred_command IS NOT excluded.preferred_command
           OR sessions.latest_phase IS NOT excluded.latest_phase
           OR sessions.latest_attention IS NOT excluded.latest_attention
           OR sessions.latest_signal_json IS NOT excluded.latest_signal_json
           OR sessions.latest_budget_json IS NOT excluded.latest_budget_json
           OR sessions.latest_command_telemetry_json IS NOT excluded.latest_command_telemetry_json
           OR sessions.latest_runtime_telemetry_json IS NOT excluded.latest_runtime_telemetry_json;
        """

        try database.execute(sql, bindings: [
            .text(projection.sessionID.uuidString),
            binding(for: projection.harnessSessionID),
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

    private static func storeLatestGitSnapshot(
        _ snapshot: HolyGitSnapshot,
        sessionID: UUID,
        in database: HolyDatabase
    ) throws -> (id: Int64, inserted: Bool) {
        if let latest = try latestGitSnapshot(sessionID: sessionID, in: database),
           latest.snapshot == snapshot {
            return (latest.id, false)
        }

        return (try insertGitSnapshot(snapshot, sessionID: sessionID, in: database), true)
    }

    private static func latestGitSnapshot(
        sessionID: UUID,
        in database: HolyDatabase
    ) throws -> (id: Int64, snapshot: HolyGitSnapshot)? {
        let sql = """
        SELECT
            git_snapshots.id,
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
        INNER JOIN git_snapshots ON git_snapshots.id = sessions.latest_git_snapshot_id
        WHERE sessions.id = ?
        LIMIT 1;
        """

        var latest: (id: Int64, snapshot: HolyGitSnapshot)?
        try database.query(sql, bindings: [.text(sessionID.uuidString)]) { statement in
            guard let snapshot = try decodeGitSnapshot(from: statement, startingAt: 1) else { return }
            latest = (sqlite3_column_int64(statement, 0), snapshot)
        }
        return latest
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
        // `IS NOT` is null-safe: an UPDATE whose WHERE excludes the row that
        // already holds the value dirties nothing.
        let sql = """
        UPDATE sessions
        SET latest_git_snapshot_id = ?
        WHERE id = ?
          AND latest_git_snapshot_id IS NOT ?;
        """
        let binding = gitSnapshotID.map(HolyDatabaseBinding.int64) ?? .null

        try database.execute(sql, bindings: [
            binding,
            .text(sessionID.uuidString),
            binding,
        ])
    }

    private static func markMissingSessionsForPruning(
        keeping sessionIDs: Set<UUID>,
        in database: HolyDatabase
    ) throws {
        // Only rows not yet tombstoned are touched; COALESCE kept the value
        // but still rewrote every already-marked row on every flush.
        let markedAt = HolyPersistenceCoders.string(from: .now)
        guard !sessionIDs.isEmpty else {
            try database.execute(
                "UPDATE sessions SET purge_pending_at = ? WHERE purge_pending_at IS NULL;",
                bindings: [.text(markedAt)]
            )
            return
        }

        let placeholders = Array(repeating: "?", count: sessionIDs.count).joined(separator: ", ")
        let sql = """
        UPDATE sessions
        SET purge_pending_at = ?
        WHERE purge_pending_at IS NULL
          AND id NOT IN (\(placeholders));
        """
        let bindings = [.text(markedAt)] + sessionIDs
            .sorted { $0.uuidString < $1.uuidString }
            .map { HolyDatabaseBinding.text($0.uuidString) }
        try database.execute(sql, bindings: bindings)
    }

    private static func upsertAppStateValue<T: Encodable>(
        _ value: T,
        forKey key: String,
        in database: HolyDatabase
    ) throws {
        // The row is rewritten, and its updated_at advanced, only when the
        // value differs from what is stored.
        let sql = """
        INSERT INTO app_state (key, value_json, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET
            value_json = excluded.value_json,
            updated_at = excluded.updated_at
        WHERE app_state.value_json IS NOT excluded.value_json;
        """

        try database.execute(sql, bindings: [
            .text(key),
            .text(try HolyPersistenceCoders.encodeJSON(value)),
            .text(HolyPersistenceCoders.string(from: .now)),
        ])
    }

    private static func upsertAppStateValue<T: Encodable>(
        _ value: T,
        forKey key: String,
        in database: HolyDatabase,
        receipt: inout HolyWorkspaceSaveReceipt
    ) throws {
        try upsertAppStateValue(value, forKey: key, in: database)
        receipt.appStateRowsWritten += Int(database.changedRowCount)
    }

    private static func upsertOptionalAppStateValue<T: Encodable>(
        _ value: T?,
        forKey key: String,
        in database: HolyDatabase,
        receipt: inout HolyWorkspaceSaveReceipt
    ) throws {
        if let value {
            try upsertAppStateValue(value, forKey: key, in: database, receipt: &receipt)
            return
        }

        try database.execute(
            "DELETE FROM app_state WHERE key = ?;",
            bindings: [.text(key)]
        )
        receipt.appStateRowsWritten += Int(database.changedRowCount)
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
            recoveryCleanupSummary: nil,
            recoveryBootBatchID: nil
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
    let recoveryBootBatchID: UUID?

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
            recoveryCleanupSummary: nil,
            recoveryBootBatchID: nil
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
            recoveryCleanupSummary: archivedSession.recoveryCleanupSummary,
            recoveryBootBatchID: archivedSession.recoveryBootBatchID
        )
    }
}
