import AppKit
import Combine
import Foundation
import UserNotifications

@MainActor
final class HolyWorkspaceStore: ObservableObject {
    @Published private(set) var sessions: [HolySession] = []
    @Published private(set) var savedTemplates: [HolySessionTemplate] = []
    @Published private(set) var archivedSessions: [HolyArchivedSession] = []
    @Published private(set) var coordinationBySessionID: [UUID: HolySessionCoordination] = [:]
    @Published private(set) var draftLaunchGuardrail: HolyLaunchGuardrail = .clear
    @Published private(set) var draftOwnershipPreview: HolySessionOwnership?
    @Published private(set) var draftLaunchGuardrailRefreshing: Bool = false
    @Published var selectedSessionID: UUID? {
        didSet { persist() }
    }
    @Published var selectedArchivedSessionID: UUID?
    @Published var composerPresented: Bool = false
    @Published var composerBusy: Bool = false
    @Published var composerErrorMessage: String?
    @Published var historyPresented: Bool = false
    @Published var draft: HolySessionDraft = .init()

    private let ghostty: Ghostty.App
    private let seedDefaultSession: Bool
    private let alertCoordinator = HolyWorkspaceAlertCoordinator()
    private var sessionObservationCancellables: Set<AnyCancellable> = []
    private var draftLaunchGuardrailTask: Task<Void, Never>?

    init(ghostty: Ghostty.App, seedDefaultSession: Bool = true) {
        self.ghostty = ghostty
        self.seedDefaultSession = seedDefaultSession
        restore()
    }

    var selectedSession: HolySession? {
        guard let selectedSessionID else { return sessions.first }
        return sessions.first(where: { $0.id == selectedSessionID }) ?? sessions.first
    }

    var selectedArchivedSession: HolyArchivedSession? {
        guard let selectedArchivedSessionID else { return archivedSessions.first }
        return archivedSessions.first(where: { $0.id == selectedArchivedSessionID }) ?? archivedSessions.first
    }

    var builtInTemplates: [HolySessionTemplate] {
        HolySessionTemplateCatalog.builtIns
    }

    var availableTemplates: [HolySessionTemplate] {
        builtInTemplates + savedTemplates
    }

    var sessionCountText: String {
        "\(sessions.count) session" + (sessions.count == 1 ? "" : "s")
    }

    var conflictCountText: String {
        let count = coordinationBySessionID.values.filter(\.hasBlockingConflict).count
        return count == 1 ? "1 collision" : "\(count) collisions"
    }

    var templateCountText: String {
        let count = availableTemplates.count
        return count == 1 ? "1 template" : "\(count) templates"
    }

    var archiveCountText: String {
        let count = archivedSessions.count
        return count == 1 ? "1 archived" : "\(count) archived"
    }

    func coordination(for session: HolySession) -> HolySessionCoordination {
        coordinationBySessionID[session.id] ?? .empty
    }

    func restore() {
        guard let app = ghostty.app else { return }

        let snapshot = HolyWorkspacePersistence.load()
        let restored = snapshot.sessions.map { HolySession(record: $0, app: app) }
        savedTemplates = snapshot.templates
        archivedSessions = snapshot.archivedSessions.sorted { $0.archivedAt > $1.archivedAt }
        selectedArchivedSessionID = archivedSessions.first?.id

        if restored.isEmpty {
            guard seedDefaultSession, archivedSessions.isEmpty else {
                sessions = []
                selectedSessionID = nil
                persist()
                return
            }

            let session = HolySession(
                record: .init(launchSpec: .interactiveShell()),
                app: app
            )
            sessions = [session]
            selectedSessionID = session.id
            bindSessions()
            persist()
            return
        }

        sessions = restored
        selectedSessionID = snapshot.selectedSessionID ?? restored.first?.id
        bindSessions()
        persist()
    }

    @discardableResult
    func createSession(with launchSpec: HolySessionLaunchSpec) -> HolySession? {
        guard let app = ghostty.app else { return nil }
        let session = HolySession(record: .init(launchSpec: launchSpec), app: app)
        sessions.append(session)
        bindSessions()
        selectedSessionID = session.id
        composerBusy = false
        composerErrorMessage = nil
        composerPresented = false
        draftLaunchGuardrail = .clear
        draftOwnershipPreview = nil
        draft = .init()
        persist()
        refreshDraftLaunchGuardrail()
        return session
    }

    @discardableResult
    func createSession(from baseConfig: Ghostty.SurfaceConfiguration?) -> HolySession? {
        let launchSpec = if let baseConfig {
            HolySessionLaunchSpec(config: baseConfig)
        } else {
            HolySessionLaunchSpec.interactiveShell(title: nextShellTitle())
        }

        return createSession(with: launchSpec)
    }

    func close(_ session: HolySession) {
        archive(session)
    }

    func archive(_ session: HolySession) {
        let archived = session.archiveSnapshot()
        archivedSessions.removeAll { $0.sourceSessionID == session.id }
        archivedSessions.insert(archived, at: 0)
        selectedArchivedSessionID = archived.id

        sessions.removeAll { $0.id == session.id }
        bindSessions()
        if selectedSessionID == session.id {
            selectedSessionID = sessions.first?.id
        }
        persist()
        refreshDraftLaunchGuardrail()
    }

    func duplicate(_ session: HolySession) {
        var launchSpec = session.record.launchSpec
        launchSpec.title = "\(session.title) Copy"

        if var workspace = launchSpec.workspace,
           workspace.strategy == .createManagedWorktree {
            workspace.branchName = HolyWorktreeManager.suggestedBranchName(
                for: launchSpec.title,
                runtime: launchSpec.runtime
            )
            launchSpec.workspace = workspace
            launchSpec.workingDirectory = nil
            resolveAndCreateSession(with: launchSpec)
            return
        }

        _ = createSession(with: launchSpec)
    }

    func presentComposer() {
        presentComposer(with: draftForNewSession())
    }

    func presentComposer(using template: HolySessionTemplate) {
        presentComposer(with: makeDraft(from: template.launchSpec))
    }

    func presentComposer(using archivedSession: HolyArchivedSession) {
        presentComposer(with: makeDraft(from: archivedSession.record.launchSpec))
    }

    func applyTemplateToDraft(_ template: HolySessionTemplate) {
        draft = makeDraft(from: template.launchSpec)
        composerErrorMessage = nil
        refreshDraftLaunchGuardrail()
    }

    func launchTemplate(_ template: HolySessionTemplate) {
        attemptLaunch(using: makeDraft(from: template.launchSpec))
    }

    func relaunch(_ archivedSession: HolyArchivedSession) {
        attemptLaunch(using: makeDraft(from: archivedSession.record.launchSpec))
    }

    func deleteArchive(_ archivedSession: HolyArchivedSession) {
        archivedSessions.removeAll { $0.id == archivedSession.id }
        if selectedArchivedSessionID == archivedSession.id {
            selectedArchivedSessionID = archivedSessions.first?.id
        }
        persist()
        refreshDraftLaunchGuardrail()
    }

    func presentHistory() {
        selectedArchivedSessionID = selectedArchivedSession?.id ?? archivedSessions.first?.id
        historyPresented = true
    }

    func saveDraftAsTemplate() {
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

        savedTemplates.append(template)
        savedTemplates.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        persist()
    }

    func createFromDraft() {
        attemptLaunch(using: draft)
    }

    func refreshDraftLaunchGuardrail() {
        refreshDraftLaunchGuardrail(for: draft)
    }

    func resolveAndCreateSession(with launchSpec: HolySessionLaunchSpec) {
        guard !composerBusy else { return }
        composerBusy = true
        composerErrorMessage = nil

        Task { [weak self] in
            do {
                let resolved = try await HolyWorktreeManager.shared.prepareLaunchSpec(launchSpec)
                await MainActor.run {
                    guard let self else { return }
                    _ = self.createSession(with: resolved)
                }
            } catch {
                await MainActor.run {
                    self?.composerBusy = false
                    self?.composerErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func attemptLaunch(using draft: HolySessionDraft) {
        guard !composerBusy else { return }

        draftLaunchGuardrailTask?.cancel()
        draftLaunchGuardrailRefreshing = false
        composerBusy = true
        composerErrorMessage = nil

        Task { [weak self] in
            guard let self else { return }
            let assessment = await self.evaluateLaunchAssessment(for: draft)

            await MainActor.run {
                self.draftLaunchGuardrail = assessment.guardrail
                self.draftOwnershipPreview = assessment.ownershipPreview
            }

            guard assessment.guardrail.allowsLaunch(allowOverride: draft.allowOwnershipCollision) else {
                await MainActor.run {
                    self.draft = draft
                    self.composerBusy = false
                    self.composerPresented = true
                }
                return
            }

            do {
                let resolved = try await HolyWorktreeManager.shared.prepareLaunchSpec(draft.launchSpec)
                await MainActor.run {
                    _ = self.createSession(with: resolved)
                }
            } catch {
                await MainActor.run {
                    self.draft = draft
                    self.composerBusy = false
                    self.composerPresented = true
                    self.composerErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func refreshDraftLaunchGuardrail(for draft: HolySessionDraft) {
        guard composerPresented else {
            draftLaunchGuardrailTask?.cancel()
            draftLaunchGuardrailRefreshing = false
            draftLaunchGuardrail = .clear
            draftOwnershipPreview = nil
            return
        }

        draftLaunchGuardrailTask?.cancel()
        draftLaunchGuardrailRefreshing = true

        draftLaunchGuardrailTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard let self else { return }
            let assessment = await self.evaluateLaunchAssessment(for: draft)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard self.composerPresented else {
                    self.draftLaunchGuardrailRefreshing = false
                    self.draftLaunchGuardrail = .clear
                    self.draftOwnershipPreview = nil
                    return
                }

                if self.draft == draft {
                    self.draftLaunchGuardrail = assessment.guardrail
                    self.draftOwnershipPreview = assessment.ownershipPreview
                }
                self.draftLaunchGuardrailRefreshing = false
            }
        }
    }

    private func evaluateLaunchAssessment(for draft: HolySessionDraft) async -> HolyDraftLaunchAssessment {
        let intent = await draftIntent(for: draft)
        let ownershipPreview = makeDraftOwnershipPreview(for: draft, intent: intent)
        guard let intendedWorktreePath = intent.worktreePath else {
            return .init(guardrail: .clear, ownershipPreview: ownershipPreview)
        }

        var conflicts: [HolyLaunchConflict] = []
        var sharedWorktreeTitles: [String] = []
        var sharedBranchTitles: [String] = []

        for session in sessions {
            let otherTitle = session.title
            let otherWorktreePath = normalizedPath(
                session.ownership.worktreePath
            )

            if let otherWorktreePath, otherWorktreePath == intendedWorktreePath {
                sharedWorktreeTitles.append(otherTitle)
                continue
            }

            guard let intendedRepositoryRoot = intent.repositoryRoot,
                  let intendedBranchName = intent.branchName,
                  let otherOwnershipRepositoryRoot = normalizedPath(session.ownership.repositoryRoot),
                  let otherOwnershipBranchName = session.ownership.branchName,
                  otherOwnershipRepositoryRoot == intendedRepositoryRoot,
                  otherOwnershipBranchName == intendedBranchName else {
                continue
            }

            sharedBranchTitles.append(otherTitle)
        }

        if !sharedWorktreeTitles.isEmpty {
            conflicts.append(
                .init(
                    kind: .sharedWorktree,
                    severity: .blocking,
                    headline: "Worktree already active",
                    detail: "The target worktree `\(intendedWorktreePath)` is already owned by \(sharedWorktreeTitles.joined(separator: ", ")). Choose a new worktree or archive the current owner first.",
                    relatedSessionTitles: sharedWorktreeTitles
                )
            )
        }

        if !sharedBranchTitles.isEmpty,
           let intendedBranchName = intent.branchName {
            conflicts.append(
                .init(
                    kind: .sharedBranch,
                    severity: .warning,
                    headline: "Branch ownership overlaps",
                    detail: "The branch `\(intendedBranchName)` is already active in \(sharedBranchTitles.joined(separator: ", ")). Continue only if you want multiple sessions sharing that branch.",
                    relatedSessionTitles: sharedBranchTitles
                )
            )
        }

        let guardrail = conflicts.isEmpty ? HolyLaunchGuardrail.clear : .init(conflicts: conflicts)
        return .init(guardrail: guardrail, ownershipPreview: ownershipPreview)
    }

    private func persist() {
        let snapshot = HolyWorkspaceSnapshot(
            sessions: sessions.map(\.record),
            selectedSessionID: selectedSessionID,
            templates: savedTemplates,
            archivedSessions: archivedSessions
        )
        HolyWorkspacePersistence.save(snapshot)
    }

    private func nextShellTitle() -> String {
        "Shell \(sessions.count + 1)"
    }

    private func draftForNewSession() -> HolySessionDraft {
        HolySessionDraft(
            launchSpec: .interactiveShell(title: nextShellTitle()),
            contextualWorkingDirectory: contextualWorkingDirectory,
            contextualRepositoryRoot: contextualRepositoryRoot
        )
    }

    private func makeDraft(from launchSpec: HolySessionLaunchSpec) -> HolySessionDraft {
        HolySessionDraft(
            launchSpec: contextualizedLaunchSpec(from: launchSpec),
            contextualWorkingDirectory: contextualWorkingDirectory,
            contextualRepositoryRoot: contextualRepositoryRoot
        )
    }

    private func presentComposer(with draft: HolySessionDraft) {
        self.draft = draft
        composerBusy = false
        composerErrorMessage = nil
        draftLaunchGuardrail = .clear
        draftOwnershipPreview = nil
        composerPresented = true
        refreshDraftLaunchGuardrail(for: draft)
    }

    private func makeDraftOwnershipPreview(
        for draft: HolySessionDraft,
        intent: HolyDraftLaunchIntent
    ) -> HolySessionOwnership? {
        let fallbackWorktreePath: String?
        switch draft.workspaceStrategy {
        case .createManagedWorktree:
            fallbackWorktreePath = HolyWorktreeManager.predictedManagedWorktreePath(
                repositoryRoot: draft.repositoryRoot.nilIfBlank,
                branchName: draft.branchName.nilIfBlank,
                runtime: draft.runtime,
                title: draft.launchSpec.title
            )
        case .directDirectory, .attachExistingWorktree:
            fallbackWorktreePath = normalizedPath(draft.workingDirectory.nilIfBlank)
        }

        let repositoryRoot = intent.repositoryRoot
            ?? normalizedPath(draft.repositoryRoot.nilIfBlank)
        let worktreePath = intent.worktreePath ?? fallbackWorktreePath
        let branchName = intent.branchName ?? draft.branchName.nilIfBlank

        guard repositoryRoot != nil || worktreePath != nil || branchName != nil else {
            return nil
        }

        return .preview(
            strategy: draft.workspaceStrategy,
            repositoryRoot: repositoryRoot,
            worktreePath: worktreePath,
            branchName: branchName
        )
    }

    private func contextualizedLaunchSpec(from templateLaunchSpec: HolySessionLaunchSpec) -> HolySessionLaunchSpec {
        var spec = templateLaunchSpec
        let defaultWorkingDirectory = contextualWorkingDirectory
        let defaultRepositoryRoot = contextualRepositoryRoot

        if spec.workingDirectory == nil,
           spec.workspace?.strategy != .createManagedWorktree {
            spec.workingDirectory = defaultWorkingDirectory
        }

        if spec.workspace == nil,
           spec.workingDirectory == nil {
            spec.workingDirectory = defaultWorkingDirectory
        }

        if var workspace = spec.workspace {
            switch workspace.strategy {
            case .directDirectory:
                spec.workingDirectory = spec.workingDirectory ?? defaultWorkingDirectory
            case .attachExistingWorktree:
                spec.workingDirectory = spec.workingDirectory ?? defaultWorkingDirectory
            case .createManagedWorktree:
                workspace.repositoryRoot = workspace.repositoryRoot ?? defaultRepositoryRoot ?? defaultWorkingDirectory
                if workspace.branchName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                    workspace.branchName = nil
                }
                spec.workspace = workspace
                spec.workingDirectory = nil
            }
        }

        return spec
    }

    private var contextualWorkingDirectory: String? {
        selectedSession?.workingDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path
    }

    private var contextualRepositoryRoot: String? {
        selectedSession?.gitSnapshot?.repositoryRoot
    }

    private func draftIntent(for draft: HolySessionDraft) async -> HolyDraftLaunchIntent {
        let launchSpec = contextualizedLaunchSpec(from: draft.launchSpec)

        switch draft.workspaceStrategy {
        case .createManagedWorktree:
            let repositoryRoot = normalizedPath(
                draft.repositoryRoot.nilIfBlank ?? launchSpec.workspace?.repositoryRoot
            )
            let branchName = draft.branchName.nilIfBlank
                ?? launchSpec.workspace?.branchName
                ?? HolyWorktreeManager.suggestedBranchName(for: launchSpec.title, runtime: launchSpec.runtime)
            let predictedPath = normalizedPath(
                HolyWorktreeManager.predictedManagedWorktreePath(
                    repositoryRoot: repositoryRoot,
                    branchName: branchName,
                    runtime: launchSpec.runtime,
                    title: launchSpec.title
                )
            )

            return .init(
                worktreePath: predictedPath,
                repositoryRoot: repositoryRoot,
                branchName: branchName
            )

        case .directDirectory, .attachExistingWorktree:
            let requestedDirectory = normalizedPath(launchSpec.workingDirectory)
            guard let requestedDirectory else {
                return .empty
            }

            guard let snapshot = await HolyGitClient.shared.snapshot(for: requestedDirectory) else {
                return .init(
                    worktreePath: requestedDirectory,
                    repositoryRoot: nil,
                    branchName: nil
                )
            }

            return .init(
                worktreePath: normalizedPath(snapshot.worktreePath),
                repositoryRoot: normalizedPath(snapshot.repositoryRoot),
                branchName: snapshot.isDetachedHead ? nil : snapshot.branch.nilIfBlank
            )
        }
    }

    private func normalizedPath(_ path: String?) -> String? {
        guard let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: trimmed).standardizedFileURL.path
    }

    private func bindSessions() {
        sessionObservationCancellables.removeAll()

        for session in sessions {
            session.objectWillChange
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.recomputeCoordination()
                    }
                }
                .store(in: &sessionObservationCancellables)
        }

        recomputeCoordination()
    }

    private func recomputeCoordination() {
        var next: [UUID: HolySessionCoordination] = [:]
        for session in sessions {
            next[session.id] = makeCoordination(for: session)
        }

        alertCoordinator.reconcile(sessions: sessions, coordinationBySessionID: next)

        if next != coordinationBySessionID {
            coordinationBySessionID = next
        }
    }

    private func makeCoordination(for session: HolySession) -> HolySessionCoordination {
        let ownership = session.ownership
        let sessionRepositoryRoot = normalizedPath(ownership.repositoryRoot)
        let sessionWorktreePath = normalizedPath(ownership.worktreePath)
        let sessionBranchName = ownership.branchName

        if sessionRepositoryRoot == nil,
           sessionWorktreePath == nil,
           session.gitSnapshot == nil {
            return .init(
                attention: attention(
                    for: session.phase,
                    hasBlockingConflict: false,
                    hasSharedBranch: false,
                    hasOwnershipDrift: session.hasBranchOwnershipDrift
                ),
                summary: summary(
                    for: session.phase,
                    hasOwnershipDrift: session.hasBranchOwnershipDrift,
                    ownershipStatusText: session.ownershipStatusText
                ),
                sharedWorktreeSessionIDs: [],
                sharedWorktreeSessionTitles: [],
                sharedBranchSessionIDs: [],
                sharedBranchSessionTitles: [],
                overlappingSessionIDs: [],
                overlappingSessionTitles: [],
                overlappingFiles: []
            )
        }

        var sharedWorktreeSessionIDs: Set<UUID> = []
        var sharedBranchSessionIDs: Set<UUID> = []
        var overlappingSessionIDs: Set<UUID> = []
        var overlappingFiles: Set<String> = []

        let sessionFiles = Set(session.gitSnapshot?.changedFiles.map(\.path) ?? [])

        for other in sessions where other.id != session.id {
            let otherOwnership = other.ownership
            let otherRepositoryRoot = normalizedPath(otherOwnership.repositoryRoot)
            let otherWorktreePath = normalizedPath(otherOwnership.worktreePath)
            let otherBranchName = otherOwnership.branchName

            if let sessionWorktreePath,
               let otherWorktreePath,
               otherWorktreePath == sessionWorktreePath {
                sharedWorktreeSessionIDs.insert(other.id)
            }

            if let sessionRepositoryRoot,
               let otherRepositoryRoot,
               sessionRepositoryRoot == otherRepositoryRoot,
               let sessionBranchName,
               let otherBranchName,
               sessionBranchName == otherBranchName {
                sharedBranchSessionIDs.insert(other.id)
            }

            guard let otherSnapshot = other.gitSnapshot,
                  let sessionRepositoryRoot,
                  normalizedPath(otherSnapshot.repositoryRoot) == sessionRepositoryRoot else {
                continue
            }

            let overlap = sessionFiles.intersection(otherSnapshot.changedFiles.map(\.path))
            if !sessionFiles.isEmpty, !overlap.isEmpty {
                overlappingSessionIDs.insert(other.id)
                overlappingFiles.formUnion(overlap)
            }
        }

        let orderedSharedWorktreeIDs = sharedWorktreeSessionIDs.sorted { lhs, rhs in
            title(forSessionID: lhs) < title(forSessionID: rhs)
        }
        let orderedSharedBranchIDs = sharedBranchSessionIDs.sorted { lhs, rhs in
            title(forSessionID: lhs) < title(forSessionID: rhs)
        }
        let orderedOverlapIDs = overlappingSessionIDs.sorted { lhs, rhs in
            title(forSessionID: lhs) < title(forSessionID: rhs)
        }
        let orderedOverlapFiles = overlappingFiles.sorted()

        return .init(
            attention: attention(
                for: session.phase,
                hasBlockingConflict: !orderedSharedWorktreeIDs.isEmpty || !orderedOverlapFiles.isEmpty,
                hasSharedBranch: !orderedSharedBranchIDs.isEmpty,
                hasOwnershipDrift: session.hasBranchOwnershipDrift
            ),
            summary: summary(
                for: session.phase,
                sharedWorktreeCount: orderedSharedWorktreeIDs.count,
                sharedBranchCount: orderedSharedBranchIDs.count,
                overlappingFileCount: orderedOverlapFiles.count,
                overlappingSessionCount: orderedOverlapIDs.count,
                hasOwnershipDrift: session.hasBranchOwnershipDrift,
                ownershipStatusText: session.ownershipStatusText
            ),
            sharedWorktreeSessionIDs: orderedSharedWorktreeIDs,
            sharedWorktreeSessionTitles: orderedSharedWorktreeIDs.map(title(forSessionID:)),
            sharedBranchSessionIDs: orderedSharedBranchIDs,
            sharedBranchSessionTitles: orderedSharedBranchIDs.map(title(forSessionID:)),
            overlappingSessionIDs: orderedOverlapIDs,
            overlappingSessionTitles: orderedOverlapIDs.map(title(forSessionID:)),
            overlappingFiles: orderedOverlapFiles
        )
    }

    private func attention(
        for phase: HolySessionPhase,
        hasBlockingConflict: Bool,
        hasSharedBranch: Bool,
        hasOwnershipDrift: Bool
    ) -> HolySessionAttention {
        if phase == .failed { return .failure }
        if hasBlockingConflict { return .conflict }
        if phase == .waitingInput { return .needsInput }
        if hasOwnershipDrift || hasSharedBranch || phase == .working { return .watch }
        if phase == .completed { return .done }
        return .none
    }

    private func summary(
        for phase: HolySessionPhase,
        hasOwnershipDrift: Bool,
        ownershipStatusText: String
    ) -> String {
        summary(
            for: phase,
            sharedWorktreeCount: 0,
            sharedBranchCount: 0,
            overlappingFileCount: 0,
            overlappingSessionCount: 0,
            hasOwnershipDrift: hasOwnershipDrift,
            ownershipStatusText: ownershipStatusText
        )
    }

    private func summary(
        for phase: HolySessionPhase,
        sharedWorktreeCount: Int,
        sharedBranchCount: Int,
        overlappingFileCount: Int,
        overlappingSessionCount: Int,
        hasOwnershipDrift: Bool,
        ownershipStatusText: String
    ) -> String {
        if overlappingFileCount > 0 {
            return overlappingFileCount == 1
                ? "1 overlapping file across \(overlappingSessionCount) session"
                : "\(overlappingFileCount) overlapping files across \(overlappingSessionCount) sessions"
        }

        if sharedWorktreeCount > 0 {
            return sharedWorktreeCount == 1
                ? "Shared worktree with 1 session"
                : "Shared worktree with \(sharedWorktreeCount) sessions"
        }

        if sharedBranchCount > 0 {
            return sharedBranchCount == 1
                ? "Shared branch ownership with 1 session"
                : "Shared branch ownership with \(sharedBranchCount) sessions"
        }

        if hasOwnershipDrift {
            return ownershipStatusText
        }

        switch phase {
        case .active:
            return "No active coordination issues."
        case .working:
            return "Session is actively working."
        case .waitingInput:
            return "Waiting for your input."
        case .completed:
            return "Completed and ready for review."
        case .failed:
            return "Session reported a failure."
        }
    }

    private func title(forSessionID id: UUID) -> String {
        sessions.first(where: { $0.id == id })?.title ?? id.uuidString
    }
}

private struct HolyDraftLaunchIntent {
    let worktreePath: String?
    let repositoryRoot: String?
    let branchName: String?

    static let empty = Self(
        worktreePath: nil,
        repositoryRoot: nil,
        branchName: nil
    )
}

private struct HolyDraftLaunchAssessment {
    let guardrail: HolyLaunchGuardrail
    let ownershipPreview: HolySessionOwnership?
}

@MainActor
private final class HolyWorkspaceAlertCoordinator {
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
                        hasBranchOwnershipDrift: session.hasBranchOwnershipDrift
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
        let message = body.trimmingCharacters(in: .whitespacesAndNewlines)
        session.surfaceView.showUserNotification(
            title: title,
            body: message.isEmpty ? session.missionDisplay : message,
            requireFocus: true
        )

        if requestAttention {
            NSApp.requestUserAttention(.informationalRequest)
        }
    }
}

private struct HolySessionAlertState {
    let phase: HolySessionPhase
    let hasBlockingConflict: Bool
    let hasBranchOwnershipDrift: Bool
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
