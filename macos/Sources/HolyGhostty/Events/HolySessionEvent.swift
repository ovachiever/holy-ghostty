import Foundation

enum HolySessionEventType: String, Codable {
    case imported = "session_imported"
    case restored = "session_restored"
    case recovered = "session_recovered"
    case created = "session_created"
    case archived = "session_archived"
    case relaunched = "session_relaunched"
    case selected = "session_selected"
    case runtimeUpdated = "session_runtime_updated"
    case artifactDetected = "session_artifact_detected"
}

extension HolySessionEventType {
    var displayName: String {
        switch self {
        case .imported:
            return "Imported"
        case .restored:
            return "Restored"
        case .recovered:
            return "Recovered"
        case .created:
            return "Created"
        case .archived:
            return "Archived"
        case .relaunched:
            return "Relaunched"
        case .selected:
            return "Selected"
        case .runtimeUpdated:
            return "Runtime"
        case .artifactDetected:
            return "Artifact"
        }
    }
}

enum HolySessionEventOrigin: String, Codable {
    case legacyJSON = "legacy_json"
    case workspaceRestore = "workspace_restore"
    case directLaunch = "direct_launch"
    case templateLaunch = "template_launch"
    case archiveRelaunch = "archive_relaunch"
    case duplicate = "duplicate"
    case surfaceClone = "surface_clone"
    case defaultSeed = "default_seed"
}

struct HolySessionEventPayload: Codable, Equatable {
    var origin: HolySessionEventOrigin?
    var runtime: HolySessionRuntime?
    var title: String?
    var mission: String?
    var workingDirectory: String?
    var repositoryRoot: String?
    var worktreePath: String?
    var branchName: String?
    var previousSessionID: UUID?
    var sourceArchiveID: UUID?
    var sourceTemplateID: UUID?
    var archivedSessionID: UUID?
    var preview: String?
    var archived: Bool?
    var activityKind: HolySessionActivityKind?
    var command: String?
    var filePath: String?
    var nextStepHint: String?
    var artifactSummary: String?
    var artifactPath: String?
    var stagnantSeconds: Int?
    var repeatedEvidenceCount: Int?
    var evidence: String?
    var recoveryReason: String?
}

struct HolySessionEventDraft: Equatable {
    let sessionID: UUID
    let occurredAt: Date
    let eventType: HolySessionEventType
    let phase: HolySessionPhase?
    let attention: HolySessionAttention?
    let payload: HolySessionEventPayload?

    static func imported(record: HolySessionRecord) -> Self {
        let ownership = HolySessionOwnership.derived(
            workspace: record.launchSpec.workspace,
            gitSnapshot: nil,
            fallbackWorktreePath: record.launchSpec.workingDirectory
        )

        return .init(
            sessionID: record.id,
            occurredAt: .now,
            eventType: .imported,
            phase: nil,
            attention: nil,
            payload: .init(
                origin: .legacyJSON,
                runtime: record.launchSpec.runtime,
                title: record.launchSpec.resolvedTitle,
                mission: record.launchSpec.objective,
                workingDirectory: record.launchSpec.workingDirectory,
                repositoryRoot: ownership.repositoryRoot,
                worktreePath: ownership.worktreePath,
                branchName: ownership.branchName,
                previousSessionID: nil,
                sourceArchiveID: nil,
                sourceTemplateID: nil,
                archivedSessionID: nil,
                preview: nil,
                archived: false,
                activityKind: nil,
                command: nil,
                filePath: nil,
                nextStepHint: nil,
                artifactSummary: nil,
                artifactPath: nil,
                stagnantSeconds: nil,
                repeatedEvidenceCount: nil,
                evidence: nil,
                recoveryReason: nil
            )
        )
    }

    static func imported(archivedSession: HolyArchivedSession) -> Self {
        .init(
            sessionID: archivedSession.sourceSessionID,
            occurredAt: .now,
            eventType: .imported,
            phase: archivedSession.phase,
            attention: attention(for: archivedSession.phase),
            payload: .init(
                origin: .legacyJSON,
                runtime: archivedSession.runtime,
                title: archivedSession.title,
                mission: archivedSession.record.launchSpec.objective,
                workingDirectory: archivedSession.lastKnownWorkingDirectory ?? archivedSession.record.launchSpec.workingDirectory,
                repositoryRoot: archivedSession.ownership.repositoryRoot,
                worktreePath: archivedSession.ownership.worktreePath,
                branchName: archivedSession.ownership.branchName,
                previousSessionID: nil,
                sourceArchiveID: archivedSession.id,
                sourceTemplateID: nil,
                archivedSessionID: archivedSession.id,
                preview: archivedSession.preview,
                archived: true,
                activityKind: archivedSession.runtimeTelemetry.activityKind,
                command: archivedSession.runtimeTelemetry.command,
                filePath: archivedSession.runtimeTelemetry.filePath,
                nextStepHint: archivedSession.runtimeTelemetry.nextStepHint,
                artifactSummary: archivedSession.runtimeTelemetry.artifactSummary,
                artifactPath: archivedSession.runtimeTelemetry.artifactPath,
                stagnantSeconds: archivedSession.runtimeTelemetry.stagnantSeconds,
                repeatedEvidenceCount: archivedSession.runtimeTelemetry.repeatedEvidenceCount,
                evidence: archivedSession.runtimeTelemetry.evidence,
                recoveryReason: nil
            )
        )
    }

    @MainActor
    static func restored(session: HolySession, attention: HolySessionAttention?) -> Self {
        .init(
            sessionID: session.id,
            occurredAt: .now,
            eventType: .restored,
            phase: session.phase,
            attention: attention,
            payload: .init(
                origin: .workspaceRestore,
                runtime: session.runtime,
                title: session.title,
                mission: session.record.launchSpec.objective,
                workingDirectory: session.workingDirectory,
                repositoryRoot: session.ownership.repositoryRoot,
                worktreePath: session.ownership.worktreePath,
                branchName: session.ownership.branchName,
                previousSessionID: nil,
                sourceArchiveID: nil,
                sourceTemplateID: nil,
                archivedSessionID: nil,
                preview: session.preview,
                archived: false,
                activityKind: session.runtimeTelemetry.activityKind,
                command: session.runtimeTelemetry.command,
                filePath: session.runtimeTelemetry.filePath,
                nextStepHint: session.runtimeTelemetry.nextStepHint,
                artifactSummary: session.runtimeTelemetry.artifactSummary,
                artifactPath: session.runtimeTelemetry.artifactPath,
                stagnantSeconds: session.runtimeTelemetry.stagnantSeconds,
                repeatedEvidenceCount: session.runtimeTelemetry.repeatedEvidenceCount,
                evidence: session.runtimeTelemetry.evidence,
                recoveryReason: nil
            )
        )
    }

    static func recovered(
        record: HolySessionRecord,
        archivedSession: HolyArchivedSession,
        reason: String
    ) -> Self {
        .init(
            sessionID: record.id,
            occurredAt: archivedSession.archivedAt,
            eventType: .recovered,
            phase: .failed,
            attention: .failure,
            payload: .init(
                origin: .workspaceRestore,
                runtime: record.launchSpec.runtime,
                title: record.launchSpec.resolvedTitle,
                mission: record.launchSpec.objective,
                workingDirectory: record.launchSpec.workingDirectory,
                repositoryRoot: archivedSession.ownership.repositoryRoot,
                worktreePath: archivedSession.ownership.worktreePath,
                branchName: archivedSession.ownership.branchName,
                previousSessionID: nil,
                sourceArchiveID: archivedSession.id,
                sourceTemplateID: nil,
                archivedSessionID: archivedSession.id,
                preview: archivedSession.preview,
                archived: true,
                activityKind: archivedSession.runtimeTelemetry.activityKind,
                command: archivedSession.runtimeTelemetry.command,
                filePath: archivedSession.runtimeTelemetry.filePath,
                nextStepHint: archivedSession.runtimeTelemetry.nextStepHint,
                artifactSummary: archivedSession.runtimeTelemetry.artifactSummary,
                artifactPath: archivedSession.runtimeTelemetry.artifactPath,
                stagnantSeconds: archivedSession.runtimeTelemetry.stagnantSeconds,
                repeatedEvidenceCount: archivedSession.runtimeTelemetry.repeatedEvidenceCount,
                evidence: archivedSession.runtimeTelemetry.evidence,
                recoveryReason: reason
            )
        )
    }

    @MainActor
    static func created(
        session: HolySession,
        origin: HolySessionEventOrigin,
        sourceTemplateID: UUID? = nil,
        attention: HolySessionAttention?
    ) -> Self {
        .init(
            sessionID: session.id,
            occurredAt: .now,
            eventType: .created,
            phase: session.phase,
            attention: attention,
            payload: .init(
                origin: origin,
                runtime: session.runtime,
                title: session.title,
                mission: session.record.launchSpec.objective,
                workingDirectory: session.workingDirectory,
                repositoryRoot: session.ownership.repositoryRoot,
                worktreePath: session.ownership.worktreePath,
                branchName: session.ownership.branchName,
                previousSessionID: nil,
                sourceArchiveID: nil,
                sourceTemplateID: sourceTemplateID,
                archivedSessionID: nil,
                preview: session.preview,
                archived: false,
                activityKind: session.runtimeTelemetry.activityKind,
                command: session.runtimeTelemetry.command,
                filePath: session.runtimeTelemetry.filePath,
                nextStepHint: session.runtimeTelemetry.nextStepHint,
                artifactSummary: session.runtimeTelemetry.artifactSummary,
                artifactPath: session.runtimeTelemetry.artifactPath,
                stagnantSeconds: session.runtimeTelemetry.stagnantSeconds,
                repeatedEvidenceCount: session.runtimeTelemetry.repeatedEvidenceCount,
                evidence: session.runtimeTelemetry.evidence,
                recoveryReason: nil
            )
        )
    }

    @MainActor
    static func relaunched(
        session: HolySession,
        archivedSession: HolyArchivedSession,
        attention: HolySessionAttention?
    ) -> Self {
        .init(
            sessionID: session.id,
            occurredAt: .now,
            eventType: .relaunched,
            phase: session.phase,
            attention: attention,
            payload: .init(
                origin: .archiveRelaunch,
                runtime: session.runtime,
                title: session.title,
                mission: session.record.launchSpec.objective,
                workingDirectory: session.workingDirectory,
                repositoryRoot: session.ownership.repositoryRoot,
                worktreePath: session.ownership.worktreePath,
                branchName: session.ownership.branchName,
                previousSessionID: nil,
                sourceArchiveID: archivedSession.id,
                sourceTemplateID: nil,
                archivedSessionID: archivedSession.id,
                preview: session.preview,
                archived: false,
                activityKind: session.runtimeTelemetry.activityKind,
                command: session.runtimeTelemetry.command,
                filePath: session.runtimeTelemetry.filePath,
                nextStepHint: session.runtimeTelemetry.nextStepHint,
                artifactSummary: session.runtimeTelemetry.artifactSummary,
                artifactPath: session.runtimeTelemetry.artifactPath,
                stagnantSeconds: session.runtimeTelemetry.stagnantSeconds,
                repeatedEvidenceCount: session.runtimeTelemetry.repeatedEvidenceCount,
                evidence: session.runtimeTelemetry.evidence,
                recoveryReason: nil
            )
        )
    }

    static func archived(_ archivedSession: HolyArchivedSession) -> Self {
        .init(
            sessionID: archivedSession.sourceSessionID,
            occurredAt: archivedSession.archivedAt,
            eventType: .archived,
            phase: archivedSession.phase,
            attention: attention(for: archivedSession.phase),
            payload: .init(
                origin: nil,
                runtime: archivedSession.runtime,
                title: archivedSession.title,
                mission: archivedSession.record.launchSpec.objective,
                workingDirectory: archivedSession.lastKnownWorkingDirectory ?? archivedSession.record.launchSpec.workingDirectory,
                repositoryRoot: archivedSession.ownership.repositoryRoot,
                worktreePath: archivedSession.ownership.worktreePath,
                branchName: archivedSession.ownership.branchName,
                previousSessionID: nil,
                sourceArchiveID: archivedSession.id,
                sourceTemplateID: nil,
                archivedSessionID: archivedSession.id,
                preview: archivedSession.preview,
                archived: true,
                activityKind: archivedSession.runtimeTelemetry.activityKind,
                command: archivedSession.runtimeTelemetry.command,
                filePath: archivedSession.runtimeTelemetry.filePath,
                nextStepHint: archivedSession.runtimeTelemetry.nextStepHint,
                artifactSummary: archivedSession.runtimeTelemetry.artifactSummary,
                artifactPath: archivedSession.runtimeTelemetry.artifactPath,
                stagnantSeconds: archivedSession.runtimeTelemetry.stagnantSeconds,
                repeatedEvidenceCount: archivedSession.runtimeTelemetry.repeatedEvidenceCount,
                evidence: archivedSession.runtimeTelemetry.evidence,
                recoveryReason: nil
            )
        )
    }

    @MainActor
    static func selected(
        session: HolySession,
        previousSessionID: UUID?,
        attention: HolySessionAttention?
    ) -> Self {
        .init(
            sessionID: session.id,
            occurredAt: .now,
            eventType: .selected,
            phase: session.phase,
            attention: attention,
            payload: .init(
                origin: nil,
                runtime: session.runtime,
                title: session.title,
                mission: session.record.launchSpec.objective,
                workingDirectory: session.workingDirectory,
                repositoryRoot: session.ownership.repositoryRoot,
                worktreePath: session.ownership.worktreePath,
                branchName: session.ownership.branchName,
                previousSessionID: previousSessionID,
                sourceArchiveID: nil,
                sourceTemplateID: nil,
                archivedSessionID: nil,
                preview: session.preview,
                archived: false,
                activityKind: session.runtimeTelemetry.activityKind,
                command: session.runtimeTelemetry.command,
                filePath: session.runtimeTelemetry.filePath,
                nextStepHint: session.runtimeTelemetry.nextStepHint,
                artifactSummary: session.runtimeTelemetry.artifactSummary,
                artifactPath: session.runtimeTelemetry.artifactPath,
                stagnantSeconds: session.runtimeTelemetry.stagnantSeconds,
                repeatedEvidenceCount: session.runtimeTelemetry.repeatedEvidenceCount,
                evidence: session.runtimeTelemetry.evidence,
                recoveryReason: nil
            )
        )
    }

    @MainActor
    static func runtimeUpdated(
        session: HolySession,
        attention: HolySessionAttention?
    ) -> Self {
        .init(
            sessionID: session.id,
            occurredAt: .now,
            eventType: .runtimeUpdated,
            phase: session.phase,
            attention: attention,
            payload: .init(
                origin: nil,
                runtime: session.runtime,
                title: session.title,
                mission: session.record.launchSpec.objective,
                workingDirectory: session.workingDirectory,
                repositoryRoot: session.ownership.repositoryRoot,
                worktreePath: session.ownership.worktreePath,
                branchName: session.ownership.branchName,
                previousSessionID: nil,
                sourceArchiveID: nil,
                sourceTemplateID: nil,
                archivedSessionID: nil,
                preview: session.preview,
                archived: false,
                activityKind: session.runtimeTelemetry.activityKind,
                command: session.runtimeTelemetry.command,
                filePath: session.runtimeTelemetry.filePath,
                nextStepHint: session.runtimeTelemetry.nextStepHint,
                artifactSummary: session.runtimeTelemetry.artifactSummary,
                artifactPath: session.runtimeTelemetry.artifactPath,
                stagnantSeconds: session.runtimeTelemetry.stagnantSeconds,
                repeatedEvidenceCount: session.runtimeTelemetry.repeatedEvidenceCount,
                evidence: session.runtimeTelemetry.evidence,
                recoveryReason: nil
            )
        )
    }

    @MainActor
    static func artifactDetected(
        session: HolySession,
        attention: HolySessionAttention?
    ) -> Self {
        .init(
            sessionID: session.id,
            occurredAt: .now,
            eventType: .artifactDetected,
            phase: session.phase,
            attention: attention,
            payload: .init(
                origin: nil,
                runtime: session.runtime,
                title: session.title,
                mission: session.record.launchSpec.objective,
                workingDirectory: session.workingDirectory,
                repositoryRoot: session.ownership.repositoryRoot,
                worktreePath: session.ownership.worktreePath,
                branchName: session.ownership.branchName,
                previousSessionID: nil,
                sourceArchiveID: nil,
                sourceTemplateID: nil,
                archivedSessionID: nil,
                preview: session.preview,
                archived: false,
                activityKind: session.runtimeTelemetry.activityKind,
                command: session.runtimeTelemetry.command,
                filePath: session.runtimeTelemetry.filePath,
                nextStepHint: session.runtimeTelemetry.nextStepHint,
                artifactSummary: session.runtimeTelemetry.artifactSummary,
                artifactPath: session.runtimeTelemetry.artifactPath,
                stagnantSeconds: session.runtimeTelemetry.stagnantSeconds,
                repeatedEvidenceCount: session.runtimeTelemetry.repeatedEvidenceCount,
                evidence: session.runtimeTelemetry.evidence,
                recoveryReason: nil
            )
        )
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
}

struct HolySessionTimelineEvent: Identifiable, Equatable {
    let sessionID: UUID
    let sequence: Int64
    let occurredAt: Date
    let eventType: HolySessionEventType
    let phase: HolySessionPhase?
    let attention: HolySessionAttention?
    let payload: HolySessionEventPayload?

    var id: String {
        "\(sessionID.uuidString)-\(sequence)"
    }

    var badgeText: String {
        eventType.displayName.uppercased()
    }

    var title: String {
        switch eventType {
        case .imported:
            return "Imported session state"
        case .restored:
            return "Restored session"
        case .recovered:
            return "Recovered into archive"
        case .created:
            if payload?.origin == .defaultSeed {
                return "Seeded default session"
            }
            return "Created session"
        case .archived:
            return "Archived session"
        case .relaunched:
            return "Relaunched archived session"
        case .selected:
            return "Selected session"
        case .runtimeUpdated:
            return payload?.artifactSummary?.nilIfBlank
                ?? payload?.nextStepHint?.nilIfBlank
                ?? payload?.activityKind?.displayName
                ?? "Runtime updated"
        case .artifactDetected:
            return payload?.artifactSummary?.nilIfBlank ?? "Artifact detected"
        }
    }

    var detail: String? {
        switch eventType {
        case .imported:
            return compacted(payload?.workingDirectory ?? payload?.mission ?? payload?.title)
        case .restored:
            return compacted(payload?.preview ?? payload?.workingDirectory ?? payload?.mission)
        case .recovered:
            return compacted(payload?.recoveryReason ?? payload?.preview)
        case .created:
            return compacted(payload?.mission ?? payload?.workingDirectory ?? payload?.title)
        case .archived:
            return compacted(payload?.preview ?? payload?.workingDirectory)
        case .relaunched:
            return compacted(payload?.workingDirectory ?? payload?.mission)
        case .selected:
            guard let previousSessionID = payload?.previousSessionID else {
                return "Session became the active operator surface."
            }
            return "Previous selection: \(previousSessionID.uuidString.prefix(8))"
        case .runtimeUpdated:
            return compacted(
                payload?.evidence
                ?? payload?.command
                ?? payload?.filePath
                ?? payload?.preview
            )
        case .artifactDetected:
            return compacted(payload?.artifactPath ?? payload?.filePath ?? payload?.evidence)
        }
    }

    private func compacted(_ value: String?) -> String? {
        value?.compactedSingleLine.nilIfBlank
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var compactedSingleLine: String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
