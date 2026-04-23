import Combine
import Foundation

@MainActor
final class HolyWorkspaceStore: ObservableObject {
    @Published private(set) var sessions: [HolySession] = []
    @Published private(set) var savedTemplates: [HolySessionTemplate] = []
    @Published private(set) var archivedSessions: [HolyArchivedSession] = []
    @Published private(set) var externalTasks: [HolyExternalTaskRecord] = []
    @Published private(set) var remoteHosts: [HolyRemoteHostRecord] = []
    @Published private(set) var discoveredRemoteSessionsByHostID: [UUID: [HolyDiscoveredTmuxSession]] = [:]
    @Published private(set) var remoteDiscoveryErrorsByHostID: [UUID: String] = [:]
    @Published private(set) var remoteDiscoveryBusyHostIDs: Set<UUID> = []
    @Published private(set) var remoteHostImportMessage: String?
    @Published private(set) var coordinationBySessionID: [UUID: HolySessionCoordination] = [:]
    @Published private(set) var draftLaunchGuardrail: HolyLaunchGuardrail = .clear
    @Published private(set) var draftOwnershipPreview: HolySessionOwnership?
    @Published private(set) var draftLaunchGuardrailRefreshing: Bool = false
    @Published var selectedSessionID: UUID? {
        didSet {
            guard !suppressAutomaticSelectionPersistence,
                  oldValue != selectedSessionID else { return }
            persist(pendingEvents: selectionEvents(from: oldValue, to: selectedSessionID))
        }
    }
    @Published var selectedArchivedSessionID: UUID?
    @Published var selectedTaskID: UUID?
    @Published var selectedRemoteHostID: UUID?
    @Published var composerPresented: Bool = false
    @Published var composerBusy: Bool = false
    @Published var composerErrorMessage: String?
    @Published var historyPresented: Bool = false
    @Published var tasksPresented: Bool = false
    @Published var remoteHostsPresented: Bool = false
    @Published var draft: HolySessionDraft = .init()

    private let sessionSupervisor: HolySessionSupervisor
    private var sessionObservationCancellables: Set<AnyCancellable> = []
    private var draftLaunchGuardrailTask: Task<Void, Never>?
    private var suppressAutomaticSelectionPersistence = false

    init(ghostty: Ghostty.App, seedDefaultSession: Bool = true) {
        self.sessionSupervisor = HolySessionSupervisor(
            ghostty: ghostty,
            seedDefaultSession: seedDefaultSession
        )
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

    var selectedTask: HolyExternalTaskRecord? {
        guard let selectedTaskID else { return externalTasks.first }
        return externalTasks.first(where: { $0.id == selectedTaskID }) ?? externalTasks.first
    }

    var selectedRemoteHost: HolyRemoteHostRecord? {
        guard let selectedRemoteHostID else { return remoteHosts.first }
        return remoteHosts.first(where: { $0.id == selectedRemoteHostID }) ?? remoteHosts.first
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

    var taskCountText: String {
        let count = externalTasks.count
        return count == 1 ? "1 task" : "\(count) tasks"
    }

    func coordination(for session: HolySession) -> HolySessionCoordination {
        coordinationBySessionID[session.id] ?? .empty
    }

    func restore() {
        let restoration = sessionSupervisor.restoreWorkspace()
        applySessionStoreState(restoration.state)
        loadTasks()
        loadRemoteHosts()
        persist(pendingEvents: restoration.pendingEvents)
    }

    @discardableResult
    func createSession(
        with launchSpec: HolySessionLaunchSpec,
        origin: HolySessionEventOrigin = .directLaunch,
        sourceTemplateID: UUID? = nil,
        relaunchedFrom archivedSession: HolyArchivedSession? = nil
    ) -> HolySession? {
        if let existingRemoteSession = prepareRemoteTmuxLaunch(for: launchSpec) {
            return existingRemoteSession
        }

        guard let result = sessionSupervisor.createSession(
            with: launchSpec,
            in: currentSessionStoreState,
            origin: origin,
            sourceTemplateID: sourceTemplateID,
            relaunchedFrom: archivedSession
        ) else {
            return nil
        }

        let previousSelectedSessionID = selectedSessionID
        applySessionStoreState(result.state)
        composerBusy = false
        composerErrorMessage = nil
        composerPresented = false
        draftLaunchGuardrail = .clear
        draftOwnershipPreview = nil
        draft = .init()
        var pendingEvents = result.pendingEvents
        pendingEvents.append(contentsOf: selectionEvents(from: previousSelectedSessionID, to: result.sessionID))
        persist(pendingEvents: pendingEvents)
        refreshDraftLaunchGuardrail()
        return sessions.first(where: { $0.id == result.sessionID })
    }

    @discardableResult
    func createSession(from baseConfig: Ghostty.SurfaceConfiguration?) -> HolySession? {
        let launchSpec = if let baseConfig {
            HolySessionLaunchSpec(config: baseConfig)
        } else {
            HolySessionLaunchSpec.interactiveShell(title: nextShellTitle())
        }

        return createSession(
            with: launchSpec,
            origin: baseConfig == nil ? .directLaunch : .surfaceClone
        )
    }

    func close(_ session: HolySession) {
        archive(session)
    }

    func archive(_ session: HolySession) {
        let previousSelectedSessionID = selectedSessionID
        let result = sessionSupervisor.archive(session, in: currentSessionStoreState)
        applySessionStoreState(result.state)
        var pendingEvents = result.pendingEvents
        pendingEvents.append(contentsOf: selectionEvents(from: previousSelectedSessionID, to: selectedSessionID))
        persist(pendingEvents: pendingEvents)
        refreshDraftLaunchGuardrail()
    }

    func rename(_ session: HolySession, to newTitle: String) {
        session.rename(to: newTitle)
        persist()
    }

    func duplicate(_ session: HolySession) {
        var launchSpec = session.record.launchSpec
        launchSpec.title = "\(session.title) Copy"
        launchSpec.tmux?.sessionName = nil

        if var workspace = launchSpec.workspace,
           workspace.strategy == .createManagedWorktree {
            workspace.branchName = HolyWorktreeManager.suggestedBranchName(
                for: launchSpec.title,
                runtime: launchSpec.runtime
            )
            launchSpec.workspace = workspace
            launchSpec.workingDirectory = nil
            resolveAndCreateSession(with: launchSpec, origin: .duplicate)
            return
        }

        _ = createSession(with: launchSpec, origin: .duplicate)
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

    func presentComposer(using task: HolyExternalTaskRecord) {
        presentComposer(with: makeDraft(from: task))
    }

    func applyTemplateToDraft(_ template: HolySessionTemplate) {
        draft = makeDraft(from: template.launchSpec)
        composerErrorMessage = nil
        refreshDraftLaunchGuardrail()
    }

    func launchTemplate(_ template: HolySessionTemplate) {
        attemptLaunch(
            using: makeDraft(from: template.launchSpec),
            origin: .templateLaunch,
            sourceTemplateID: template.id
        )
    }

    func relaunch(_ archivedSession: HolyArchivedSession) {
        attemptLaunch(
            using: makeDraft(from: archivedSession.record.launchSpec),
            origin: .archiveRelaunch,
            relaunchedFrom: archivedSession
        )
    }

    func deleteArchive(_ archivedSession: HolyArchivedSession) {
        let result = sessionSupervisor.deleteArchive(archivedSession, in: currentSessionStoreState)
        applySessionStoreState(result.state)
        persist()
        refreshDraftLaunchGuardrail()
    }

    func presentHistory() {
        selectedArchivedSessionID = selectedArchivedSession?.id ?? archivedSessions.first?.id
        historyPresented = true
    }

    func presentTasks() {
        selectedTaskID = selectedTask?.id ?? externalTasks.first?.id
        tasksPresented = true
    }

    func presentRemoteHosts() {
        selectedRemoteHostID = selectedRemoteHost?.id ?? remoteHosts.first?.id
        remoteHostsPresented = true

        if let host = selectedRemoteHost,
           remoteSessions(for: host).isEmpty,
           !isRemoteDiscoveryBusy(for: host) {
            refreshRemoteSessions(for: host)
        }
    }

    func createTask() {
        let task = HolyExternalTaskRecord(
            preferredWorkingDirectory: contextualWorkingDirectory,
            preferredRepositoryRoot: contextualRepositoryRoot
        )
        externalTasks.insert(task, at: 0)
        selectedTaskID = task.id
        persistTasks()
    }

    func createRemoteHost() {
        let host = HolyRemoteHostRecord()
        remoteHosts.insert(host, at: 0)
        selectedRemoteHostID = host.id
        persistRemoteHosts()
    }

    func importRemoteHostsFromSSHConfig() {
        Task { [weak self] in
            let importedHosts = await HolyRemoteHostImportService.shared.importSSHConfigHosts()
            await MainActor.run {
                self?.mergeImportedRemoteHosts(importedHosts, sourceLabel: "SSH Config")
            }
        }
    }

    func importRemoteHostsFromTailscale() {
        Task { [weak self] in
            let importedHosts = await HolyRemoteHostImportService.shared.importTailscaleHosts()
            await MainActor.run {
                self?.mergeImportedRemoteHosts(importedHosts, sourceLabel: "Tailscale")
            }
        }
    }

    func upsertTask(_ task: HolyExternalTaskRecord) {
        let normalizedTask = task.normalized()
        var updatedTask = normalizedTask
        updatedTask = HolyExternalTaskRecord(
            id: normalizedTask.id,
            sourceKind: normalizedTask.sourceKind,
            sourceLabel: normalizedTask.sourceLabel,
            externalID: normalizedTask.externalID,
            canonicalURL: normalizedTask.canonicalURL,
            title: normalizedTask.title,
            summary: normalizedTask.summary,
            preferredRuntime: normalizedTask.preferredRuntime,
            preferredWorkingDirectory: normalizedTask.preferredWorkingDirectory,
            preferredRepositoryRoot: normalizedTask.preferredRepositoryRoot,
            preferredCommand: normalizedTask.preferredCommand,
            preferredInitialInput: normalizedTask.preferredInitialInput,
            status: normalizedTask.status,
            linkedSessionID: normalizedTask.linkedSessionID,
            linkedSessionTitle: normalizedTask.linkedSessionTitle,
            linkedSessionPhase: normalizedTask.linkedSessionPhase,
            createdAt: normalizedTask.createdAt,
            updatedAt: .now,
            lastImportedAt: normalizedTask.lastImportedAt
        )

        if let index = externalTasks.firstIndex(where: { $0.id == updatedTask.id }) {
            externalTasks[index] = updatedTask
        } else {
            externalTasks.insert(updatedTask, at: 0)
        }

        selectedTaskID = updatedTask.id
        reconcileExternalTasks()
    }

    func deleteTask(_ task: HolyExternalTaskRecord) {
        externalTasks.removeAll { $0.id == task.id }
        if selectedTaskID == task.id {
            selectedTaskID = externalTasks.first?.id
        }
        persistTasks()
    }

    func upsertRemoteHost(_ host: HolyRemoteHostRecord) {
        let normalized = host.normalized()
        let normalizedHost = HolyRemoteHostRecord(
            id: host.id,
            label: normalized.label,
            sshDestination: normalized.sshDestination,
            tmuxSocketName: normalized.tmuxSocketName,
            createdAt: host.createdAt,
            updatedAt: .now,
            lastDiscoveredAt: host.lastDiscoveredAt
        )

        if let index = remoteHosts.firstIndex(where: { $0.id == normalizedHost.id }) {
            remoteHosts[index] = normalizedHost
        } else {
            remoteHosts.insert(normalizedHost, at: 0)
        }

        selectedRemoteHostID = normalizedHost.id
        persistRemoteHosts()
    }

    func deleteRemoteHost(_ host: HolyRemoteHostRecord) {
        remoteHosts.removeAll { $0.id == host.id }
        discoveredRemoteSessionsByHostID.removeValue(forKey: host.id)
        remoteDiscoveryErrorsByHostID.removeValue(forKey: host.id)
        remoteDiscoveryBusyHostIDs.remove(host.id)

        if selectedRemoteHostID == host.id {
            selectedRemoteHostID = remoteHosts.first?.id
        }

        persistRemoteHosts()
    }

    func launchTask(_ task: HolyExternalTaskRecord) {
        attemptLaunch(using: makeDraft(from: task), origin: .directLaunch)
    }

    func remoteSessions(for host: HolyRemoteHostRecord) -> [HolyDiscoveredTmuxSession] {
        discoveredRemoteSessionsByHostID[host.id] ?? []
    }

    func remoteDiscoveryError(for host: HolyRemoteHostRecord) -> String? {
        remoteDiscoveryErrorsByHostID[host.id]
    }

    func isRemoteDiscoveryBusy(for host: HolyRemoteHostRecord) -> Bool {
        remoteDiscoveryBusyHostIDs.contains(host.id)
    }

    func refreshRemoteSessions(for host: HolyRemoteHostRecord) {
        remoteDiscoveryBusyHostIDs.insert(host.id)
        remoteDiscoveryErrorsByHostID.removeValue(forKey: host.id)

        Task { [weak self] in
            do {
                let sessions = try await HolyRemoteTmuxDiscoveryService.shared.discoverSessionsThrowing(for: host)
                await MainActor.run {
                    guard let self else { return }
                    self.discoveredRemoteSessionsByHostID[host.id] = sessions
                    self.remoteDiscoveryBusyHostIDs.remove(host.id)
                    self.remoteDiscoveryErrorsByHostID.removeValue(forKey: host.id)
                    self.markRemoteHostDiscovered(host.id)
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.discoveredRemoteSessionsByHostID[host.id] = []
                    self.remoteDiscoveryBusyHostIDs.remove(host.id)
                    self.remoteDiscoveryErrorsByHostID[host.id] = error.localizedDescription
                }
            }
        }
    }

    func launchRemoteTmuxSession(_ session: HolyDiscoveredTmuxSession, on host: HolyRemoteHostRecord) {
        let launchSpec = HolySessionLaunchSpec(
            runtime: session.runtime ?? .shell,
            title: session.displayTitle,
            objective: session.objective,
            budget: nil,
            transport: .init(
                kind: .ssh,
                hostLabel: host.displayTitle,
                sshDestination: host.sshDestination
            ),
            tmux: .init(
                socketName: session.tmuxSocketName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
                sessionName: session.sessionName,
                createIfMissing: false
            ),
            workingDirectory: session.workingDirectory,
            command: session.bootstrapCommand,
            initialInput: nil,
            waitAfterCommand: false,
            environment: [:],
            workspace: nil
        )

        _ = createSession(with: launchSpec, origin: .directLaunch)
        remoteHostsPresented = false
    }

    func launchRemoteTmuxSessions(_ sessions: [HolyDiscoveredTmuxSession], on host: HolyRemoteHostRecord) {
        guard !sessions.isEmpty else { return }

        for session in sessions {
            let launchSpec = HolySessionLaunchSpec(
                runtime: session.runtime ?? .shell,
                title: session.displayTitle,
                objective: session.objective,
                budget: nil,
                transport: .init(
                    kind: .ssh,
                    hostLabel: host.displayTitle,
                    sshDestination: host.sshDestination
                ),
                tmux: .init(
                    socketName: session.tmuxSocketName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
                    sessionName: session.sessionName,
                    createIfMissing: false
                ),
                workingDirectory: session.workingDirectory,
                command: session.bootstrapCommand,
                initialInput: nil,
                waitAfterCommand: false,
                environment: [:],
                workspace: nil
            )

            _ = createSession(with: launchSpec, origin: .directLaunch)
        }

        remoteHostsPresented = false
    }

    func saveDraftAsTemplate() {
        let result = sessionSupervisor.saveTemplate(from: draft, in: currentSessionStoreState)
        applySessionStoreState(result.state)
        persist()
    }

    func createFromDraft() {
        attemptLaunch(using: draft, origin: .directLaunch)
    }

    func refreshDraftLaunchGuardrail() {
        refreshDraftLaunchGuardrail(for: draft)
    }

    func resolveAndCreateSession(
        with launchSpec: HolySessionLaunchSpec,
        origin: HolySessionEventOrigin = .directLaunch,
        sourceTemplateID: UUID? = nil,
        relaunchedFrom archivedSession: HolyArchivedSession? = nil
    ) {
        guard !composerBusy else { return }
        composerBusy = true
        composerErrorMessage = nil

        Task { [weak self] in
            do {
                let resolved = try await HolyWorktreeManager.shared.prepareLaunchSpec(launchSpec)
                await MainActor.run {
                    guard let self else { return }
                    _ = self.createSession(
                        with: resolved,
                        origin: origin,
                        sourceTemplateID: sourceTemplateID,
                        relaunchedFrom: archivedSession
                    )
                }
            } catch {
                await MainActor.run {
                    self?.composerBusy = false
                    self?.composerErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func attemptLaunch(
        using draft: HolySessionDraft,
        origin: HolySessionEventOrigin,
        sourceTemplateID: UUID? = nil,
        relaunchedFrom archivedSession: HolyArchivedSession? = nil
    ) {
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
                    _ = self.createSession(
                        with: resolved,
                        origin: origin,
                        sourceTemplateID: sourceTemplateID,
                        relaunchedFrom: archivedSession
                    )
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

    private func persist(pendingEvents: [HolySessionEventDraft] = []) {
        sessionSupervisor.persist(
            state: currentSessionStoreState,
            attentionBySessionID: coordinationBySessionID.mapValues(\.attention),
            pendingEvents: pendingEvents
        )
    }

    private var currentSessionStoreState: HolySessionStoreState {
        .init(
            sessions: sessions,
            savedTemplates: savedTemplates,
            archivedSessions: archivedSessions,
            selectedSessionID: selectedSessionID,
            selectedArchivedSessionID: selectedArchivedSessionID
        )
    }

    private func applySessionStoreState(_ state: HolySessionStoreState) {
        suppressAutomaticSelectionPersistence = true
        sessions = state.sessions
        savedTemplates = state.savedTemplates
        archivedSessions = state.archivedSessions
        selectedArchivedSessionID = state.selectedArchivedSessionID
        selectedSessionID = state.selectedSessionID
        suppressAutomaticSelectionPersistence = false
        bindSessions()
        reconcileExternalTasks()
    }

    private func prepareRemoteTmuxLaunch(for launchSpec: HolySessionLaunchSpec) -> HolySession? {
        guard let launchKey = HolyRemoteTmuxSessionKey(launchSpec: launchSpec) else { return nil }

        let matchingSessions = sessions.filter {
            HolyRemoteTmuxSessionKey(launchSpec: $0.record.launchSpec) == launchKey
        }

        if let reusableSession = matchingSessions.first(where: { session in
            switch session.phase {
            case .active, .working, .waitingInput:
                return true
            case .completed, .failed:
                return false
            }
        }) {
            selectedSessionID = reusableSession.id
            composerBusy = false
            composerErrorMessage = nil
            composerPresented = false
            remoteHostsPresented = false
            return reusableSession
        }

        for staleSession in matchingSessions where staleSession.phase == .completed || staleSession.phase == .failed {
            archive(staleSession)
        }

        return nil
    }

    private func selectionEvents(from previousSessionID: UUID?, to nextSessionID: UUID?) -> [HolySessionEventDraft] {
        guard previousSessionID != nextSessionID,
              let nextSessionID,
              let session = sessions.first(where: { $0.id == nextSessionID }) else {
            return []
        }

        return [
            .selected(
                session: session,
                previousSessionID: previousSessionID,
                attention: coordinationBySessionID[nextSessionID]?.attention
            ),
        ]
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

    private func makeDraft(from task: HolyExternalTaskRecord) -> HolySessionDraft {
        let workingDirectory = task.preferredWorkingDirectory
            ?? task.preferredRepositoryRoot
            ?? contextualWorkingDirectory

        let launchSpec = HolySessionLaunchSpec(
            runtime: task.preferredRuntime,
            title: task.title,
            objective: task.summary.nilIfBlank,
            task: task.reference,
            budget: nil,
            workingDirectory: workingDirectory,
            command: task.preferredCommand,
            initialInput: task.preferredInitialInput,
            waitAfterCommand: false,
            environment: [:],
            workspace: nil
        )

        return HolySessionDraft(
            launchSpec: launchSpec,
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

    private func loadTasks() {
        externalTasks = HolyTaskRepository.load()
        selectedTaskID = selectedTask?.id ?? externalTasks.first?.id
        reconcileExternalTasks(persistIfChanged: false)
    }

    private func loadRemoteHosts() {
        let loadedHosts = HolyRemoteHostRepository.load()
        let migratedHosts = loadedHosts.map(migrateRemoteHostIfNeeded(_:))
        remoteHosts = migratedHosts
        selectedRemoteHostID = selectedRemoteHost?.id ?? remoteHosts.first?.id

        if migratedHosts != loadedHosts {
            persistRemoteHosts()
        }
    }

    private func persistTasks() {
        HolyTaskRepository.save(externalTasks)
    }

    private func persistRemoteHosts() {
        HolyRemoteHostRepository.save(remoteHosts)
    }

    private func mergeImportedRemoteHosts(_ importedHosts: [HolyRemoteHostRecord], sourceLabel: String) {
        guard !importedHosts.isEmpty else {
            remoteHostImportMessage = "No machines found in \(sourceLabel.lowercased())."
            return
        }

        var existingHostsByDestination: [String: HolyRemoteHostRecord] = [:]
        for host in remoteHosts {
            existingHostsByDestination[host.sshDestination.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = host
        }

        var addedHosts = 0
        for importedHost in importedHosts {
            let normalizedHost = importedHost.normalized()
            let key = normalizedHost.sshDestination.lowercased()

            guard existingHostsByDestination[key] == nil else { continue }
            remoteHosts.append(normalizedHost)
            existingHostsByDestination[key] = normalizedHost
            addedHosts += 1
        }

        remoteHosts.sort { lhs, rhs in
            lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
        }

        if selectedRemoteHostID == nil {
            selectedRemoteHostID = remoteHosts.first?.id
        }

        persistRemoteHosts()

        if addedHosts == 0 {
            remoteHostImportMessage = "No new machines found in \(sourceLabel.lowercased())."
        } else if addedHosts == 1 {
            remoteHostImportMessage = "Added 1 machine from \(sourceLabel)."
        } else {
            remoteHostImportMessage = "Added \(addedHosts) machines from \(sourceLabel)."
        }
    }

    private func markRemoteHostDiscovered(_ hostID: UUID) {
        guard let index = remoteHosts.firstIndex(where: { $0.id == hostID }) else { return }

        remoteHosts[index] = HolyRemoteHostRecord(
            id: remoteHosts[index].id,
            label: remoteHosts[index].label,
            sshDestination: remoteHosts[index].sshDestination,
            tmuxSocketName: remoteHosts[index].tmuxSocketName,
            createdAt: remoteHosts[index].createdAt,
            updatedAt: .now,
            lastDiscoveredAt: .now
        )

        persistRemoteHosts()
    }

    private func migrateRemoteHostIfNeeded(_ host: HolyRemoteHostRecord) -> HolyRemoteHostRecord {
        var normalizedHost = host.normalized()

        if normalizedHost.tmuxSocketName?.trimmingCharacters(in: .whitespacesAndNewlines) == HolySessionTmuxSpec.defaultSocketName {
            normalizedHost.tmuxSocketName = nil
            normalizedHost.updatedAt = .now
        }

        return normalizedHost
    }

    private func reconcileExternalTasks(persistIfChanged: Bool = true) {
        guard !externalTasks.isEmpty else { return }

        var nextTasks: [HolyExternalTaskRecord] = []
        nextTasks.reserveCapacity(externalTasks.count)

        for task in externalTasks {
            var nextTask = task.normalized()

            if let session = sessions.first(where: { $0.record.launchSpec.task?.id == task.id }) {
                nextTask.linkedSessionID = session.id
                nextTask.linkedSessionTitle = session.title
                nextTask.linkedSessionPhase = session.phase
                nextTask.status = taskStatus(for: session.phase)
            } else if let archivedSession = archivedSessions.first(where: { $0.record.launchSpec.task?.id == task.id }) {
                nextTask.linkedSessionID = archivedSession.sourceSessionID
                nextTask.linkedSessionTitle = archivedSession.title
                nextTask.linkedSessionPhase = archivedSession.phase
                nextTask.status = taskStatus(for: archivedSession.phase)
            } else {
                nextTask.linkedSessionID = nil
                nextTask.linkedSessionTitle = nil
                nextTask.linkedSessionPhase = nil
            }

            if nextTask != task {
                nextTask = HolyExternalTaskRecord(
                    id: nextTask.id,
                    sourceKind: nextTask.sourceKind,
                    sourceLabel: nextTask.sourceLabel,
                    externalID: nextTask.externalID,
                    canonicalURL: nextTask.canonicalURL,
                    title: nextTask.title,
                    summary: nextTask.summary,
                    preferredRuntime: nextTask.preferredRuntime,
                    preferredWorkingDirectory: nextTask.preferredWorkingDirectory,
                    preferredRepositoryRoot: nextTask.preferredRepositoryRoot,
                    preferredCommand: nextTask.preferredCommand,
                    preferredInitialInput: nextTask.preferredInitialInput,
                    status: nextTask.status,
                    linkedSessionID: nextTask.linkedSessionID,
                    linkedSessionTitle: nextTask.linkedSessionTitle,
                    linkedSessionPhase: nextTask.linkedSessionPhase,
                    createdAt: nextTask.createdAt,
                    updatedAt: .now,
                    lastImportedAt: nextTask.lastImportedAt
                )
            }

            nextTasks.append(nextTask)
        }

        guard nextTasks != externalTasks else { return }
        externalTasks = nextTasks
        if persistIfChanged {
            persistTasks()
        }
    }

    private func taskStatus(for phase: HolySessionPhase) -> HolyExternalTaskStatus {
        switch phase {
        case .active, .working:
            return .active
        case .waitingInput:
            return .waitingInput
        case .completed:
            return .done
        case .failed:
            return .failed
        }
    }

    private func makeDraftOwnershipPreview(
        for draft: HolySessionDraft,
        intent: HolyDraftLaunchIntent
    ) -> HolySessionOwnership? {
        guard draft.transportKind == .local else {
            return nil
        }

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

        if spec.transport.isRemote {
            spec.workspace = nil
            return spec
        }

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

        guard draft.transportKind == .local else {
            return .empty
        }

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
                .sink { [weak self, weak session] _ in
                    Task { @MainActor [weak self] in
                        guard let self, let session else { return }
                        self.handleSessionMutation(for: session)
                    }
                }
                .store(in: &sessionObservationCancellables)
        }

        recomputeCoordination()
        sessionSupervisor.sessionBindingsDidChange(for: currentSessionStoreState)
    }

    private func handleSessionMutation(for session: HolySession) {
        recomputeCoordination()
        sessionSupervisor.sessionDidMutate(
            session,
            in: currentSessionStoreState,
            attentionBySessionID: coordinationBySessionID.mapValues(\.attention)
        )
    }

    private func recomputeCoordination() {
        var next: [UUID: HolySessionCoordination] = [:]
        for session in sessions {
            next[session.id] = makeCoordination(for: session)
        }

        sessionSupervisor.reconcileAlerts(
            sessions: sessions,
            coordinationBySessionID: next
        )

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
                    hasOwnershipDrift: session.hasBranchOwnershipDrift,
                    runtimeActivityKind: session.runtimeTelemetry.activityKind
                ),
                summary: summary(
                    for: session.phase,
                    hasOwnershipDrift: session.hasBranchOwnershipDrift,
                    ownershipStatusText: session.ownershipStatusText,
                    runtimeActivityKind: session.runtimeTelemetry.activityKind
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
                hasOwnershipDrift: session.hasBranchOwnershipDrift,
                runtimeActivityKind: session.runtimeTelemetry.activityKind
            ),
            summary: summary(
                .init(
                    phase: session.phase,
                    sharedWorktreeCount: orderedSharedWorktreeIDs.count,
                    sharedBranchCount: orderedSharedBranchIDs.count,
                    overlappingFileCount: orderedOverlapFiles.count,
                    overlappingSessionCount: orderedOverlapIDs.count,
                    hasOwnershipDrift: session.hasBranchOwnershipDrift,
                    ownershipStatusText: session.ownershipStatusText,
                    runtimeActivityKind: session.runtimeTelemetry.activityKind
                )
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
        hasOwnershipDrift: Bool,
        runtimeActivityKind: HolySessionActivityKind
    ) -> HolySessionAttention {
        if phase == .failed { return .failure }
        if hasBlockingConflict { return .conflict }
        if phase == .waitingInput { return .needsInput }
        if runtimeActivityKind == .stalled || runtimeActivityKind == .looping { return .watch }
        if hasOwnershipDrift || hasSharedBranch || phase == .working { return .watch }
        if phase == .completed { return .done }
        return .none
    }

    private func summary(
        for phase: HolySessionPhase,
        hasOwnershipDrift: Bool,
        ownershipStatusText: String,
        runtimeActivityKind: HolySessionActivityKind
    ) -> String {
        summary(
            .init(
                phase: phase,
                sharedWorktreeCount: 0,
                sharedBranchCount: 0,
                overlappingFileCount: 0,
                overlappingSessionCount: 0,
                hasOwnershipDrift: hasOwnershipDrift,
                ownershipStatusText: ownershipStatusText,
                runtimeActivityKind: runtimeActivityKind
            )
        )
    }

    private func summary(_ context: HolyCoordinationSummaryContext) -> String {
        if context.overlappingFileCount > 0 {
            return context.overlappingFileCount == 1
                ? "1 overlapping file across \(context.overlappingSessionCount) session"
                : "\(context.overlappingFileCount) overlapping files across \(context.overlappingSessionCount) sessions"
        }

        if context.sharedWorktreeCount > 0 {
            return context.sharedWorktreeCount == 1
                ? "Shared worktree with 1 session"
                : "Shared worktree with \(context.sharedWorktreeCount) sessions"
        }

        if context.sharedBranchCount > 0 {
            return context.sharedBranchCount == 1
                ? "Shared branch ownership with 1 session"
                : "Shared branch ownership with \(context.sharedBranchCount) sessions"
        }

        if context.hasOwnershipDrift {
            return context.ownershipStatusText
        }

        if context.runtimeActivityKind == .looping {
            return "Session appears to be repeating the same work."
        }

        if context.runtimeActivityKind == .stalled {
            return "Session has not made visible progress recently."
        }

        switch context.phase {
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

private struct HolyRemoteTmuxSessionKey: Equatable {
    let sshDestination: String
    let tmuxSocketName: String?
    let tmuxSessionName: String

    init?(launchSpec: HolySessionLaunchSpec) {
        let realizedLaunchSpec = HolyTmuxCommandBuilder.realizedLaunchSpec(launchSpec)
        guard realizedLaunchSpec.transport.kind == .ssh,
              let sshDestination = realizedLaunchSpec.transport.sshDestination?.nilIfBlank,
              let tmuxSessionName = realizedLaunchSpec.tmux?.normalized.sessionName?.nilIfBlank else {
            return nil
        }

        self.sshDestination = sshDestination
        self.tmuxSocketName = realizedLaunchSpec.tmux?.normalized.socketName?.nilIfBlank
        self.tmuxSessionName = tmuxSessionName
    }
}

private struct HolyCoordinationSummaryContext {
    let phase: HolySessionPhase
    let sharedWorktreeCount: Int
    let sharedBranchCount: Int
    let overlappingFileCount: Int
    let overlappingSessionCount: Int
    let hasOwnershipDrift: Bool
    let ownershipStatusText: String
    let runtimeActivityKind: HolySessionActivityKind
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
