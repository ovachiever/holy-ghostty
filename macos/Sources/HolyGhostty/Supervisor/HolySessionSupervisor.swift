import AppKit
import Foundation
import UserNotifications

struct HolyWorkspaceRestoreResult {
    let state: HolySessionStoreState
    let pendingEvents: [HolySessionEventDraft]

    static let empty = Self(
        state: .init(
            sessions: [],
            savedTemplates: [],
            archivedSessions: [],
            selectedSessionID: nil,
            selectedArchivedSessionID: nil
        ),
        pendingEvents: []
    )
}

struct HolySessionCreationResult {
    let state: HolySessionStoreState
    let sessionID: UUID
    let pendingEvents: [HolySessionEventDraft]
}

struct HolySessionArchiveResult {
    let state: HolySessionStoreState
    let archivedSessionID: UUID
    let pendingEvents: [HolySessionEventDraft]
}

@MainActor
final class HolySessionSupervisor {
    private let ghostty: Ghostty.App
    private let seedDefaultSession: Bool
    private let alertCoordinator = HolySessionAlertCoordinator()
    private var scheduledPersistTask: Task<Void, Never>?
    private var bufferedMutationEvents: [HolySessionEventDraft] = []
    private var observedRuntimeStatesBySessionID: [UUID: HolyObservedRuntimeState] = [:]

    init(ghostty: Ghostty.App, seedDefaultSession: Bool) {
        self.ghostty = ghostty
        self.seedDefaultSession = seedDefaultSession
    }

    func restoreWorkspace() -> HolyWorkspaceRestoreResult {
        guard let app = ghostty.app else { return .empty }

        let snapshot = HolyWorkspaceRepository.loadSnapshot()
        let orphanCleanupSummaries = HolyWorktreeManager.cleanupOrphanedManagedWorktrees(
            referencedPaths: referencedManagedWorktreePaths(in: snapshot)
        )
        for summary in orphanCleanupSummaries {
            AppDelegate.logger.notice("Holy Ghostty recovery cleanup: \(summary, privacy: .public)")
        }
        let recovery = recoverActiveRecords(snapshot.sessions)
        let restoredSessions = recovery.restorableRecords.map { HolySession(record: $0, app: app) }
        let archivedSessions = (snapshot.archivedSessions + recovery.recoveredArchivedSessions)
            .sorted { $0.archivedAt > $1.archivedAt }

        if restoredSessions.isEmpty {
            guard seedDefaultSession else {
                return .init(
                    state: .init(
                        sessions: [],
                        savedTemplates: snapshot.templates,
                        archivedSessions: archivedSessions,
                        selectedSessionID: nil,
                        selectedArchivedSessionID: archivedSessions.first?.id
                    ),
                    pendingEvents: recovery.pendingEvents
                )
            }

            let session = HolySession(
                record: .init(launchSpec: .interactiveShell()),
                app: app
            )

            return .init(
                state: .init(
                    sessions: [session],
                    savedTemplates: snapshot.templates,
                    archivedSessions: archivedSessions,
                    selectedSessionID: session.id,
                    selectedArchivedSessionID: archivedSessions.first?.id
                ),
                pendingEvents: recovery.pendingEvents + [
                    .created(session: session, origin: .defaultSeed, attention: nil),
                ]
            )
        }

        let selectedSessionID = snapshot.selectedSessionID
            .flatMap { desiredID in
                restoredSessions.contains(where: { $0.id == desiredID }) ? desiredID : nil
            }
            ?? restoredSessions.first?.id

        return .init(
            state: .init(
                sessions: restoredSessions,
                savedTemplates: snapshot.templates,
                archivedSessions: archivedSessions,
                selectedSessionID: selectedSessionID,
                selectedArchivedSessionID: archivedSessions.first?.id
            ),
            pendingEvents: recovery.pendingEvents + restoredSessions.map {
                .restored(session: $0, attention: nil)
            }
        )
    }

    func createSession(
        with launchSpec: HolySessionLaunchSpec,
        in state: HolySessionStoreState,
        origin: HolySessionEventOrigin,
        sourceTemplateID: UUID? = nil,
        relaunchedFrom archivedSession: HolyArchivedSession? = nil
    ) -> HolySessionCreationResult? {
        guard let app = ghostty.app else { return nil }
        let realizedLaunchSpec = HolyTmuxCommandBuilder.realizedLaunchSpec(launchSpec)
        let session = HolySession(record: .init(launchSpec: realizedLaunchSpec), app: app)

        var nextState = state
        nextState.sessions.append(session)
        nextState.selectedSessionID = session.id

        let pendingEvents: [HolySessionEventDraft]
        if let archivedSession {
            pendingEvents = [
                .relaunched(session: session, archivedSession: archivedSession, attention: nil),
            ]
        } else {
            pendingEvents = [
                .created(
                    session: session,
                    origin: origin,
                    sourceTemplateID: sourceTemplateID,
                    attention: nil
                ),
            ]
        }

        return .init(
            state: nextState,
            sessionID: session.id,
            pendingEvents: pendingEvents
        )
    }

    func archive(_ session: HolySession, in state: HolySessionStoreState) -> HolySessionArchiveResult {
        let archivedSession = session.archiveSnapshot()
        var nextState = state
        nextState.archivedSessions.removeAll { $0.sourceSessionID == session.id }
        nextState.archivedSessions.insert(archivedSession, at: 0)
        nextState.selectedArchivedSessionID = archivedSession.id
        nextState.sessions.removeAll { $0.id == session.id }
        if nextState.selectedSessionID == session.id {
            nextState.selectedSessionID = nextState.sessions.first?.id
        }

        return .init(
            state: nextState,
            archivedSessionID: archivedSession.id,
            pendingEvents: [.archived(archivedSession)]
        )
    }

    func deleteArchive(
        _ archivedSession: HolyArchivedSession,
        in state: HolySessionStoreState
    ) -> HolySessionStoreMutationResult {
        var nextState = state
        nextState.archivedSessions.removeAll { $0.id == archivedSession.id }
        if nextState.selectedArchivedSessionID == archivedSession.id {
            nextState.selectedArchivedSessionID = nextState.archivedSessions.first?.id
        }

        return .init(state: nextState, pendingEvents: [])
    }

    func saveTemplate(
        from draft: HolySessionDraft,
        in state: HolySessionStoreState
    ) -> HolySessionStoreMutationResult {
        let templateLaunchSpec = draft.launchSpec.normalizedForTemplate
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = title.isEmpty ? draft.runtime.displayName : title
        let summary = draft.objective.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            ?? "Reusable \(draft.runtime.displayName) session template."

        let template = HolySessionTemplate(
            name: name,
            summary: summary,
            launchSpec: templateLaunchSpec
        )

        var nextState = state
        nextState.savedTemplates.append(template)
        nextState.savedTemplates.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        return .init(state: nextState, pendingEvents: [])
    }

    func persist(
        state: HolySessionStoreState,
        attentionBySessionID: [UUID: HolySessionAttention],
        pendingEvents: [HolySessionEventDraft] = []
    ) {
        flushScheduledPersistence(
            state: state,
            attentionBySessionID: attentionBySessionID,
            additionalEvents: pendingEvents
        )
    }

    func schedulePersistence(
        state: HolySessionStoreState,
        attentionBySessionID: [UUID: HolySessionAttention],
        pendingEvents: [HolySessionEventDraft] = []
    ) {
        if !pendingEvents.isEmpty {
            bufferedMutationEvents.append(contentsOf: pendingEvents)
        }

        scheduledPersistTask?.cancel()
        scheduledPersistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self?.flushScheduledPersistence(
                    state: state,
                    attentionBySessionID: attentionBySessionID
                )
            }
        }
    }

    func sessionBindingsDidChange(for state: HolySessionStoreState) {
        let activeSessionIDs = Set(state.sessions.map(\.id))
        observedRuntimeStatesBySessionID = observedRuntimeStatesBySessionID.filter { activeSessionIDs.contains($0.key) }

        for session in state.sessions {
            observedRuntimeStatesBySessionID[session.id] = observedRuntimeState(for: session)
        }
    }

    func sessionDidMutate(
        _ session: HolySession,
        in state: HolySessionStoreState,
        attentionBySessionID: [UUID: HolySessionAttention]
    ) {
        let pendingEvents = runtimeEvents(
            for: session,
            attention: attentionBySessionID[session.id]
        )
        schedulePersistence(
            state: state,
            attentionBySessionID: attentionBySessionID,
            pendingEvents: pendingEvents
        )
    }

    func reconcileAlerts(
        sessions: [HolySession],
        coordinationBySessionID: [UUID: HolySessionCoordination]
    ) {
        alertCoordinator.reconcile(
            sessions: sessions,
            coordinationBySessionID: coordinationBySessionID
        )
    }

    private func flushScheduledPersistence(
        state: HolySessionStoreState,
        attentionBySessionID: [UUID: HolySessionAttention],
        additionalEvents: [HolySessionEventDraft] = []
    ) {
        scheduledPersistTask?.cancel()
        scheduledPersistTask = nil

        let combinedEvents = bufferedMutationEvents + additionalEvents
        bufferedMutationEvents.removeAll()
        HolyWorkspaceRepository.save(
            snapshot: state.snapshot,
            activeSessions: state.sessions,
            attentionBySessionID: attentionBySessionID,
            pendingEvents: combinedEvents
        )
    }

    private func recoverActiveRecords(_ records: [HolySessionRecord]) -> HolyActiveRecoveryResult {
        var restorableRecords: [HolySessionRecord] = []
        var recoveredArchivedSessions: [HolyArchivedSession] = []
        var pendingEvents: [HolySessionEventDraft] = []

        for record in records {
            let evaluation = recoveryEvaluation(for: record)
            guard let reason = evaluation.issue else {
                restorableRecords.append(record)
                continue
            }

            let archivedSession = recoveredArchivedSession(
                for: record,
                reason: reason,
                cleanupSummary: evaluation.cleanupSummary
            )
            recoveredArchivedSessions.append(archivedSession)
            pendingEvents.append(.recovered(record: record, archivedSession: archivedSession, reason: reason))
        }

        return .init(
            restorableRecords: restorableRecords,
            recoveredArchivedSessions: recoveredArchivedSessions,
            pendingEvents: pendingEvents
        )
    }

    private func recoveryEvaluation(for record: HolySessionRecord) -> HolyWorktreeRecoveryEvaluation {
        HolyWorktreeManager.recoveryEvaluation(for: record.launchSpec)
    }

    private func recoveredArchivedSession(
        for record: HolySessionRecord,
        reason: String,
        cleanupSummary: String?
    ) -> HolyArchivedSession {
        let signal = HolySessionSignal(
            kind: .failure,
            headline: "Restore recovery archived this session",
            detail: reason
        )
        let runtimeTelemetry = HolySessionRuntimeTelemetry(
            activityKind: .failure,
            headline: "Session recovery archived this session",
            detail: reason,
            command: nil,
            filePath: record.launchSpec.workingDirectory,
            nextStepHint: "Review the archived session and relaunch after fixing the workspace.",
            artifactSummary: nil,
            artifactPath: nil,
            progressPercent: nil,
            stagnantSeconds: nil,
            repeatedEvidenceCount: nil,
            lastUpdatedAt: .now,
            evidence: reason
        )

        return .init(
            sourceSessionID: record.id,
            record: record,
            phase: .failed,
            preview: reason,
            signals: [signal],
            commandTelemetry: .empty,
            budgetTelemetry: .empty,
            runtimeTelemetry: runtimeTelemetry,
            gitSnapshot: nil,
            lastKnownWorkingDirectory: record.launchSpec.workingDirectory,
            lastActivityAt: record.updatedAt,
            archivedAt: .now,
            recoveryReason: reason,
            recoveryCleanupSummary: cleanupSummary
        )
    }

    private func referencedManagedWorktreePaths(in snapshot: HolyWorkspaceSnapshot) -> [String] {
        let activePaths = snapshot.sessions.compactMap { record -> String? in
            guard record.launchSpec.workspace?.strategy == .createManagedWorktree,
                  let workingDirectory = record.launchSpec.workingDirectory else {
                return nil
            }

            return URL(fileURLWithPath: workingDirectory).standardizedFileURL.path
        }

        let archivedPaths = snapshot.archivedSessions.compactMap { archivedSession -> String? in
            guard archivedSession.record.launchSpec.workspace?.strategy == .createManagedWorktree,
                  let workingDirectory = archivedSession.lastKnownWorkingDirectory ?? archivedSession.record.launchSpec.workingDirectory else {
                return nil
            }

            return URL(fileURLWithPath: workingDirectory).standardizedFileURL.path
        }

        return activePaths + archivedPaths
    }

    private func runtimeEvents(
        for session: HolySession,
        attention: HolySessionAttention?
    ) -> [HolySessionEventDraft] {
        let current = observedRuntimeState(for: session)
        defer { observedRuntimeStatesBySessionID[session.id] = current }

        guard let previous = observedRuntimeStatesBySessionID[session.id],
              previous != current else {
            return []
        }

        var events: [HolySessionEventDraft] = []

        if session.runtimeTelemetry.isMeaningful {
            events.append(.runtimeUpdated(session: session, attention: attention))
        }

        if current.artifactSignature != previous.artifactSignature,
           current.artifactSignature != nil {
            events.append(.artifactDetected(session: session, attention: attention))
        }

        return events
    }

    private func observedRuntimeState(for session: HolySession) -> HolyObservedRuntimeState {
        .init(
            phase: session.phase,
            runtimeTelemetry: session.runtimeTelemetry
        )
    }
}

private struct HolyActiveRecoveryResult {
    let restorableRecords: [HolySessionRecord]
    let recoveredArchivedSessions: [HolyArchivedSession]
    let pendingEvents: [HolySessionEventDraft]
}

private struct HolyObservedRuntimeState: Equatable {
    let phase: HolySessionPhase
    let runtimeTelemetry: HolySessionRuntimeTelemetry

    var artifactSignature: String? {
        let summary = runtimeTelemetry.artifactSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = runtimeTelemetry.artifactPath?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard summary?.isEmpty == false || path?.isEmpty == false else {
            return nil
        }

        return [summary, path]
            .compactMap { $0?.isEmpty == true ? nil : $0 }
            .joined(separator: "::")
    }
}

@MainActor
private final class HolySessionAlertCoordinator {
    private var authorizationRequested = false
    private var hasEstablishedBaseline = false
    private var previousStates: [UUID: HolySessionAlertState] = [:]

    func reconcile(
        sessions: [HolySession],
        coordinationBySessionID: [UUID: HolySessionCoordination]
    ) {
        requestAuthorizationIfNeeded()

        let nextStates = Dictionary(
            uniqueKeysWithValues: sessions.map { session in
                (
                    session.id,
                    HolySessionAlertState(
                        phase: session.phase,
                        hasBlockingConflict: coordinationBySessionID[session.id]?.hasBlockingConflict == true,
                        hasBranchOwnershipDrift: session.hasBranchOwnershipDrift,
                        budgetStatus: session.budgetStatus,
                        runtimeActivityKind: session.runtimeTelemetry.activityKind
                    )
                )
            }
        )

        guard hasEstablishedBaseline else {
            previousStates = nextStates
            hasEstablishedBaseline = true
            return
        }

        for session in sessions {
            guard let previous = previousStates[session.id],
                  let current = nextStates[session.id] else {
                continue
            }

            let coordination = coordinationBySessionID[session.id] ?? .empty
            notifyIfNeeded(
                for: session,
                previous: previous,
                current: current,
                coordination: coordination
            )
        }

        previousStates = nextStates
    }

    private func requestAuthorizationIfNeeded() {
        guard !authorizationRequested else { return }
        authorizationRequested = true

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                AppDelegate.logger.error("Holy Ghostty notification authorization failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func notifyIfNeeded(
        for session: HolySession,
        previous: HolySessionAlertState,
        current: HolySessionAlertState,
        coordination: HolySessionCoordination
    ) {
        if !previous.hasBlockingConflict && current.hasBlockingConflict {
            deliver(
                for: session,
                title: "Session collision detected",
                body: coordination.summary,
                requestAttention: true
            )
            return
        }

        if previous.phase != .failed && current.phase == .failed {
            deliver(
                for: session,
                title: "Agent failed",
                body: session.primarySignalDetail,
                requestAttention: true
            )
            return
        }

        if previous.phase != .waitingInput && current.phase == .waitingInput {
            deliver(
                for: session,
                title: "Agent needs input",
                body: session.primarySignalDetail,
                requestAttention: true
            )
            return
        }

        if !previous.hasBranchOwnershipDrift && current.hasBranchOwnershipDrift {
            deliver(
                for: session,
                title: "Branch ownership drift",
                body: session.ownershipStatusText,
                requestAttention: true
            )
            return
        }

        if previous.runtimeActivityKind != .stalled && current.runtimeActivityKind == .stalled {
            deliver(
                for: session,
                title: "Agent may be stalled",
                body: session.runtimeTelemetrySummaryText ?? session.primarySignalDetail,
                requestAttention: true
            )
            return
        }

        if previous.runtimeActivityKind != .looping && current.runtimeActivityKind == .looping {
            deliver(
                for: session,
                title: "Agent may be looping",
                body: session.runtimeTelemetrySummaryText ?? session.primarySignalDetail,
                requestAttention: true
            )
            return
        }

        if previous.budgetStatus != .warning && current.budgetStatus == .warning {
            deliver(
                for: session,
                title: "Budget nearing limit",
                body: session.budgetRemainingText,
                requestAttention: false
            )
            return
        }

        if previous.budgetStatus != .exceeded && current.budgetStatus == .exceeded {
            deliver(
                for: session,
                title: "Budget exceeded",
                body: session.budgetSummaryText,
                requestAttention: true
            )
            return
        }

        if previous.phase != .completed && current.phase == .completed {
            deliver(
                for: session,
                title: "Agent completed",
                body: session.primarySignalDetail,
                requestAttention: false
            )
        }
    }

    private func deliver(
        for session: HolySession,
        title: String,
        body: String,
        requestAttention: Bool
    ) {
        if requestAttention {
            NSApplication.shared.requestUserAttention(.criticalRequest)
        }

        let content = UNMutableNotificationContent()
        content.title = "\(title): \(session.title)"
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "holy-alert-\(session.id.uuidString)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AppDelegate.logger.error("Holy Ghostty notification delivery failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

private struct HolySessionAlertState: Equatable {
    let phase: HolySessionPhase
    let hasBlockingConflict: Bool
    let hasBranchOwnershipDrift: Bool
    let budgetStatus: HolySessionBudgetStatus
    let runtimeActivityKind: HolySessionActivityKind
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
