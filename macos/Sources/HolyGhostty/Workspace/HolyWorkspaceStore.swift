import Combine
import Darwin
import Foundation
import SwiftUI

enum HolySessionCycleDirection {
    case next
    case previous
}

enum HolyConvergeReason: String {
    case manual
    case wake
    case paneExit
    case periodic
}

private struct PaneLayoutMemoKey: Equatable {
    let sessionIDs: [UUID]
    let paneLayout: HolyPaneLayout
    let selectedSessionID: UUID?
}

private struct HolyConvergeRosterSnapshot {
    let sessionID: UUID
    let launchSpec: HolySessionLaunchSpec
    let title: String
    let localProcessExited: Bool
}

@MainActor
final class HolyWorkspaceStore: ObservableObject {
    @Published private(set) var sessions: [HolySession] = []
    @Published private(set) var savedTemplates: [HolySessionTemplate] = []
    @Published private(set) var archivedSessions: [HolyArchivedSession] = []
    @Published private(set) var externalTasks: [HolyExternalTaskRecord] = []
    @Published private(set) var remoteHosts: [HolyRemoteHostRecord] = []
    @Published private(set) var launchProfiles: [HolyLaunchProfile] = []
    @Published private(set) var defaultLaunchProfileID: UUID?
    @Published private(set) var discoveredLocalTmuxSessions: [HolyDiscoveredTmuxSession] = []
    @Published private(set) var discoveredRemoteSessionsByHostID: [UUID: [HolyDiscoveredTmuxSession]] = [:]
    @Published private(set) var localTmuxDiscoveryError: String?
    @Published private(set) var remoteDiscoveryErrorsByHostID: [UUID: String] = [:]
    @Published private(set) var localTmuxDiscoveryBusy: Bool = false
    @Published private(set) var remoteDiscoveryBusyHostIDs: Set<UUID> = []
    @Published private(set) var remoteHostImportMessage: String?
    @Published private(set) var coordinationBySessionID: [UUID: HolySessionCoordination] = [:]
    @Published private(set) var attentionMetadataBySessionID: [UUID: HolySessionAttentionMetadata] = [:]
    @Published private(set) var draftLaunchGuardrail: HolyLaunchGuardrail = .clear
    @Published private(set) var draftOwnershipPreview: HolySessionOwnership?
    @Published private(set) var draftLaunchGuardrailRefreshing: Bool = false
    @Published private(set) var attentionClock: Date = .now
    @Published private(set) var isConverging = false
    private var lastConvergeStartedAt: Date?
    /// Per-host wall-clock cap on the converge discovery sweep (spec's 5s/host).
    /// Applied only at the converge call sites so the Hosts panel and metadata
    /// refresh keep answering slow-but-alive hosts uncapped.
    private static let convergeDiscoveryTimeoutSeconds: TimeInterval = 5
    /// Kill preflight uses a constant-time identity inventory rather than rich
    /// discovery. Keep it bounded independently from converge so a wedged local
    /// server or SSH hop fails closed without inheriting converge-only policy.
    private static let terminationDiscoveryTimeoutSeconds: TimeInterval = 10
    @Published var paneLayout: HolyPaneLayout = .single {
        didSet {
            refreshSessionPresentationState()
            guard !suppressAutomaticSelectionPersistence,
                  oldValue != paneLayout else { return }
            persist()
        }
    }
    @Published var selectedSessionID: UUID? {
        didSet {
            guard !suppressAutomaticSelectionPersistence,
                  oldValue != selectedSessionID else { return }
            refreshSessionPresentationState()
            scheduleSelectedSessionSeenMark()
            persist(pendingEvents: selectionEvents(from: oldValue, to: selectedSessionID))
        }
    }
    @Published var soloSessionID: UUID? {
        didSet {
            guard oldValue != soloSessionID else { return }
            refreshSessionPresentationState()
        }
    }
    @Published private(set) var focusedPaneSlot: Int?
    @Published var selectedArchivedSessionID: UUID?
    @Published var selectedTaskID: UUID?
    @Published var selectedRemoteHostID: UUID?
    @Published var commandPaletteIsShowing: Bool = false
    @Published var composerPresented: Bool = false
    @Published var composerBusy: Bool = false
    @Published var composerErrorMessage: String?
    @Published var tmuxSessionTerminationError: String?
    @Published var historyPresented: Bool = false
    @Published var tasksPresented: Bool = false
    @Published var remoteHostsPresented: Bool = false
    @Published var draft: HolySessionDraft = .init()
    @Published var keepAwakeWhileRemoteAttached: Bool = UserDefaults.standard.object(
        forKey: HolyWorkspaceStore.keepAwakeDefaultsKey
    ) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(keepAwakeWhileRemoteAttached, forKey: Self.keepAwakeDefaultsKey)
            updatePowerAssertion()
        }
    }

    private let sessionSupervisor: HolySessionSupervisor
    private let powerAssertionManager = HolyPowerAssertionManager()
    private var refreshCoordinator: HolySessionRefreshCoordinator?
    private var paneLayoutMemo: (key: PaneLayoutMemoKey, layout: HolyPaneLayout, labels: [UUID: String])?
    private var sessionObservationCancellables: Set<AnyCancellable> = []
    private var cancellables: Set<AnyCancellable> = []
    private var repairBackoff = HolyRepairBackoff()
    private var activeTmuxMetadataRefreshCancellable: AnyCancellable?
    private var localTmuxMetadataRefreshCancellable: AnyCancellable?
    private var attentionClockCancellable: AnyCancellable?
    private var draftLaunchGuardrailTask: Task<Void, Never>?
    private var selectedSessionReadTask: Task<Void, Never>?
    private var selectedSessionReadTaskKey: String?
    private var suppressAutomaticSelectionPersistence = false
    private static let selectedSessionReadDelay: TimeInterval = 3
    private static let keepAwakeDefaultsKey = "HolyKeepAwakeWhileRemoteAttached"
    private static let freshReplyInterval: TimeInterval = 10 * 60
    private static let overdueReplyInterval: TimeInterval = 2 * 60 * 60
    private static let staleReplyInterval: TimeInterval = 24 * 60 * 60

    init(ghostty: Ghostty.App, seedDefaultSession: Bool = true) {
        self.sessionSupervisor = HolySessionSupervisor(
            ghostty: ghostty,
            seedDefaultSession: seedDefaultSession
        )
        restore()
        let coordinator = HolySessionRefreshCoordinator { [weak self] in
            self?.sessions ?? []
        }
        self.refreshCoordinator = coordinator
        coordinator.start()

        NotificationCenter.default.publisher(for: .holyRemoteSessionPaneDied)
            .compactMap { $0.userInfo?["sessionID"] as? UUID }
            .sink { [weak self] sessionID in
                self?.scheduleRepair(sessionID: sessionID)
            }
            .store(in: &cancellables)
    }

    var selectedSession: HolySession? {
        guard let selectedSessionID else { return sessions.first }
        return sessions.first(where: { $0.id == selectedSessionID }) ?? sessions.first
    }

    var soloSession: HolySession? {
        guard let soloSessionID else { return nil }
        return session(withID: soloSessionID)
    }

    var visiblePaneLayoutKind: HolyPaneLayoutKind {
        soloSession == nil ? normalizedPaneLayout.kind : .single
    }

    var isShowingLinkedSplit: Bool {
        soloSession == nil && normalizedPaneLayout.kind.isSplit
    }

    var visiblePaneSlots: [HolySession?] {
        if let soloSession {
            return [soloSession]
        }

        let layout = normalizedPaneLayout
        return layout.renderedSlotSessionIDs.map { sessionID in
            sessionID.flatMap(session(withID:))
        }
    }

    var visiblePaneSessions: [HolySession] {
        visiblePaneSlots.compactMap(\.self)
    }

    var normalizedPaneLayout: HolyPaneLayout {
        paneLayoutMemoEntry().layout
    }

    var paneLabelsBySessionID: [UUID: String] {
        paneLayoutMemoEntry().labels
    }

    var paneSlotsBySessionID: [UUID: Int] {
        guard normalizedPaneLayout.kind.isSplit else { return [:] }

        return Dictionary(
            uniqueKeysWithValues: normalizedPaneLayout.sessionIDs.compactMap { id in
                normalizedPaneLayout.slot(for: id).map { (id, $0) }
            }
        )
    }

    /// Memoized normalized pane layout + per-session labels.
    ///
    /// Both values are O(sessions) to derive and were previously recomputed for
    /// every roster row on every layout pass — O(rows²) per frame, which froze
    /// the main thread while scrolling a large roster. They only change when the
    /// session id list, the pane layout, or the selection changes, so cache them
    /// keyed on exactly those inputs and rebuild only when one of them moves.
    private func paneLayoutMemoEntry() -> (layout: HolyPaneLayout, labels: [UUID: String]) {
        let key = PaneLayoutMemoKey(
            sessionIDs: sessions.map(\.id),
            paneLayout: paneLayout,
            selectedSessionID: selectedSessionID
        )

        if let memo = paneLayoutMemo, memo.key == key {
            return (memo.layout, memo.labels)
        }

        let layout = paneLayout.normalized(
            availableSessionIDs: key.sessionIDs,
            selectedSessionID: selectedSessionID
        )
        let labels = Dictionary(
            uniqueKeysWithValues: layout.sessionIDs.compactMap { id in
                layout.label(for: id).map { (id, $0) }
            }
        )

        paneLayoutMemo = (key, layout, labels)
        return (layout, labels)
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

    var defaultLaunchProfile: HolyLaunchProfile? {
        guard let defaultLaunchProfileID else { return launchProfiles.first }
        return launchProfiles.first(where: { $0.id == defaultLaunchProfileID }) ?? launchProfiles.first
    }

    var defaultLaunchProfileName: String {
        defaultLaunchProfile?.name ?? "Local Mac"
    }

    var localMachineDisplayName: String {
        HolyLocalMachineIdentity.current.displayName
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

    func attentionPresentation(for session: HolySession) -> HolySessionAttentionPresentation {
        attentionPresentation(for: session, coordination: coordination(for: session))
    }

    func session(withID id: UUID) -> HolySession? {
        sessions.first(where: { $0.id == id })
    }

    func selectSession(_ sessionID: UUID) {
        selectedSessionID = sessionID
        if soloSessionID == nil,
           let slot = normalizedPaneLayout.slot(for: sessionID) {
            focusedPaneSlot = slot
        }
        clearUnreadAttentionIfNeeded(for: sessionID)
    }

    func handleRosterSelect(_ sessionID: UUID) {
        selectSession(sessionID)

        let layout = normalizedPaneLayout
        if layout.kind.isSplit,
           let slot = layout.slot(for: sessionID) {
            enterSplit(focusedSlot: slot)
        } else if layout.kind.isSplit {
            soloSessionID = sessionID
            focusedPaneSlot = nil
        } else {
            soloSessionID = nil
            focusedPaneSlot = nil
            paneLayout = HolyPaneLayout(kind: .single, sessionIDs: [sessionID])
        }
    }

    @discardableResult
    func cycleSelectedSession(_ direction: HolySessionCycleDirection) -> Bool {
        let orderedSessions = HolySessionRosterOrdering.orderedSessions(sessions)
        guard orderedSessions.count > 1 else { return false }

        let selectedIndex = selectedSessionID.flatMap { selectedID in
            orderedSessions.firstIndex { $0.id == selectedID }
        }

        let nextIndex: Int
        if let selectedIndex {
            switch direction {
            case .next:
                nextIndex = (selectedIndex + 1) % orderedSessions.count
            case .previous:
                nextIndex = (selectedIndex - 1 + orderedSessions.count) % orderedSessions.count
            }
        } else {
            nextIndex = direction == .next ? 0 : orderedSessions.count - 1
        }

        handleRosterSelect(orderedSessions[nextIndex].id)
        return true
    }

    func showSinglePane() {
        let selectedID = selectedSession?.id ?? sessions.first?.id
        if normalizedPaneLayout.kind.isSplit,
           let selectedID {
            soloSessionID = selectedID
            focusedPaneSlot = nil
        } else {
            paneLayout = .init(kind: .single, sessionIDs: selectedID.map { [$0] } ?? [])
            soloSessionID = nil
            focusedPaneSlot = nil
        }
    }

    func splitPaneRight(
        cloning baseConfig: Ghostty.SurfaceConfiguration? = nil,
        from sourceSessionID: UUID? = nil
    ) {
        applyPaneLayout(
            kind: .splitRight,
            sourceSessionID: sourceSessionID,
            cloneConfig: baseConfig
        )
    }

    func splitPaneDown(
        cloning baseConfig: Ghostty.SurfaceConfiguration? = nil,
        from sourceSessionID: UUID? = nil
    ) {
        applyPaneLayout(
            kind: .splitDown,
            sourceSessionID: sourceSessionID,
            cloneConfig: baseConfig
        )
    }

    func showTriplePaneLayout() {
        applyPaneLayout(kind: .triple)
    }

    func showQuadPaneLayout() {
        applyPaneLayout(kind: .quad)
    }

    func assignCurrentSessionToSlot(_ slot: Int) {
        guard let selectedSessionID else { return }
        assignSession(selectedSessionID, toSlot: slot)
    }

    func assignSession(_ sessionID: UUID, toSlot slot: Int) {
        guard sessions.contains(where: { $0.id == sessionID }),
              (1...HolyPaneLayout.maxSlotCount).contains(slot) else {
            return
        }

        selectedSessionID = sessionID
        paneLayout = normalizedPaneLayout
            .assigning(sessionID, toSlot: slot)
            .normalized(
                availableSessionIDs: sessions.map(\.id),
                selectedSessionID: sessionID
            )
        soloSessionID = nil
        focusedPaneSlot = slot
        clearUnreadAttentionIfNeeded(for: sessionID)
    }

    func removeFromLinkage(_ sessionID: UUID) {
        guard normalizedPaneLayout.slot(for: sessionID) != nil else { return }

        let shouldSoloRemovedSession = selectedSessionID == sessionID || soloSessionID == sessionID
        paneLayout = normalizedPaneLayout
            .removingSession(sessionID)
            .normalized(
                availableSessionIDs: sessions.map(\.id),
                selectedSessionID: selectedSessionID,
                fillsEmptySlots: false
            )

        if shouldSoloRemovedSession,
           sessions.contains(where: { $0.id == sessionID }) {
            soloSessionID = sessionID
            focusedPaneSlot = nil
        } else if focusedPaneSlot.flatMap({ paneLayout.sessionID(atSlot: $0) }) == nil {
            focusedPaneSlot = paneLayout.highestOccupiedSlot
        }
    }

    func breakLinkage() {
        let selectedID = selectedSession?.id ?? sessions.first?.id
        paneLayout = HolyPaneLayout(kind: .single, sessionIDs: selectedID.map { [$0] } ?? [])
        soloSessionID = nil
        focusedPaneSlot = nil
    }

    func maximize(_ sessionID: UUID) {
        guard normalizedPaneLayout.slot(for: sessionID) != nil,
              sessions.contains(where: { $0.id == sessionID }) else {
            return
        }

        selectedSessionID = sessionID
        soloSessionID = sessionID
        focusedPaneSlot = nil
        clearUnreadAttentionIfNeeded(for: sessionID)
    }

    func togglePaneZoom(_ sessionID: UUID) {
        guard let slot = normalizedPaneLayout.slot(for: sessionID) else { return }

        if soloSessionID == sessionID {
            enterSplit(focusedSlot: slot)
        } else {
            maximize(sessionID)
        }
    }

    func enterSplit(focusedSlot: Int? = nil) {
        guard normalizedPaneLayout.kind.isSplit else { return }
        soloSessionID = nil

        if let focusedSlot,
           let focusedSessionID = normalizedPaneLayout.sessionID(atSlot: focusedSlot) {
            selectedSessionID = focusedSessionID
            self.focusedPaneSlot = focusedSlot
            clearUnreadAttentionIfNeeded(for: focusedSessionID)
        } else if let selectedSessionID,
                  let slot = normalizedPaneLayout.slot(for: selectedSessionID) {
            self.focusedPaneSlot = slot
        } else if let firstSessionID = normalizedPaneLayout.sessionIDs.first,
                  let slot = normalizedPaneLayout.slot(for: firstSessionID) {
            selectedSessionID = firstSessionID
            self.focusedPaneSlot = slot
            clearUnreadAttentionIfNeeded(for: firstSessionID)
        }
    }

    func restore() {
        let restoration = sessionSupervisor.restoreWorkspace()
        applySessionStoreState(restoration.state)
        loadTasks()
        loadRemoteHosts()
        loadLaunchProfiles()
        refreshLocalTmuxSessions()
        refreshActiveRemoteTmuxSessionMetadata()
        startActiveTmuxMetadataRefresh()
        startAttentionClock()
        persist(pendingEvents: restoration.pendingEvents)
        convergeRoster(reason: .periodic)
    }

    @discardableResult
    func createSession(
        with launchSpec: HolySessionLaunchSpec,
        origin: HolySessionEventOrigin = .directLaunch,
        sourceTemplateID: UUID? = nil,
        relaunchedFrom archivedSession: HolyArchivedSession? = nil
    ) -> HolySession? {
        if shouldBootstrapDefaultTmuxServer(for: launchSpec) {
            HolyLocalTmuxDefaults.ensureDefaultServerStartedIfNeeded()
        }

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
        if normalizedPaneLayout.kind.isSplit {
            soloSessionID = result.sessionID
            focusedPaneSlot = nil
        }
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
            newDefaultLaunchProfileSpec()
        }

        return createSession(
            with: launchSpec,
            origin: baseConfig == nil ? .directLaunch : .surfaceClone
        )
    }

    func close(_ session: HolySession) {
        archive(session)
    }

    func detachAllSessions() {
        guard !sessions.isEmpty else { return }

        let previousSelectedSessionID = selectedSessionID
        var nextState = currentSessionStoreState
        var pendingEvents: [HolySessionEventDraft] = []

        for session in sessions.reversed() {
            let result = sessionSupervisor.archive(session, in: nextState)
            nextState = result.state
            pendingEvents.append(contentsOf: result.pendingEvents)
        }

        nextState.selectedSessionID = nil
        applySessionStoreState(nextState)
        pendingEvents.append(contentsOf: selectionEvents(from: previousSelectedSessionID, to: selectedSessionID))
        persist(pendingEvents: pendingEvents)
        refreshDraftLaunchGuardrail()
    }

    func canReattachSession(_ session: HolySession) -> Bool {
        Self.canReattachLaunchSpec(session.record.launchSpec)
    }

    nonisolated private static func canReattachLaunchSpec(_ launchSpec: HolySessionLaunchSpec) -> Bool {
        HolyLocalTmuxSessionKey(launchSpec: launchSpec) != nil
            || HolyRemoteTmuxSessionKey(launchSpec: launchSpec) != nil
    }

    private func updatePowerAssertion() {
        let hasRemoteSessions = sessions.contains {
            HolyRemoteTmuxSessionKey(launchSpec: $0.record.launchSpec) != nil
        }
        powerAssertionManager.setActive(keepAwakeWhileRemoteAttached && hasRemoteSessions)
    }

    func reattach(_ session: HolySession) {
        guard canReattachSession(session) else {
            return
        }

        let sessionID = session.id
        let detachCommand = HolyTmuxClientDetachCommand.command(for: session.record.launchSpec)

        Task {
            if let detachCommand {
                _ = await Task.detached(priority: .utility) {
                    detachCommand.run()
                }.value
            }

            guard let currentSession = sessions.first(where: { $0.id == sessionID }),
                  let result = sessionSupervisor.reattach(currentSession, in: currentSessionStoreState) else {
                return
            }

            applySessionStoreState(result.state)
            persist(pendingEvents: result.pendingEvents)
            refreshActiveRemoteTmuxSessionMetadata()
        }
    }

    func reattachAllSessions() {
        convergeRoster(reason: .manual)
    }

    private func scheduleRepair(sessionID: UUID) {
        guard let delay = repairBackoff.nextDelay(for: sessionID) else { return }

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await MainActor.run {
                guard let self,
                      let session = self.sessions.first(where: { $0.id == sessionID }),
                      session.surfaceView.processExited,
                      self.canReattachSession(session) else { return }
                self.reattach(session)
            }
        }
    }

    func convergeOnSystemWake() {
        repairBackoff.resetAll()
        convergeRoster(reason: .wake)
    }

    static func shouldStartConverge(
        now: Date,
        lastStartedAt: Date?,
        isRunning: Bool,
        reason: HolyConvergeReason
    ) -> Bool {
        if isRunning { return false }
        if reason == .manual { return true }
        guard let lastStartedAt else { return true }
        return now.timeIntervalSince(lastStartedAt) >= 10
    }

    func convergeRoster(reason: HolyConvergeReason) {
        if reason == .manual { repairBackoff.resetAll() }

        guard Self.shouldStartConverge(
            now: Date(),
            lastStartedAt: lastConvergeStartedAt,
            isRunning: isConverging,
            reason: reason
        ) else { return }

        isConverging = true
        lastConvergeStartedAt = Date()

        // Keep incomplete legacy specs intact until the live inventory exists.
        // Building identity here would re-realize a missing name and recreate
        // the phantom-target bug. The task below resolves each snapshot only
        // against sessions discovery actually observed.
        let rosterSnapshots = sessions.map { session in
            HolyConvergeRosterSnapshot(
                sessionID: session.id,
                launchSpec: session.record.launchSpec,
                title: session.title,
                localProcessExited: session.surfaceView.processExited
            )
        }
        let archivedSnapshots = archivedSessions

        // Hosts to sweep: every saved remote host plus hosts inferable from
        // live roster records (covers sessions on unsaved hosts).
        var hostsByKey: [String: HolyRemoteHostRecord] = [:]
        for host in remoteHosts + activeRemoteTmuxDiscoveryHosts() {
            let normalized = host.normalized()
            let key = Self.convergeHostKey(
                destination: normalized.sshDestination,
                socketName: normalized.tmuxSocketName?.nilIfBlank
            )
            if hostsByKey[key] == nil { hostsByKey[key] = host }
        }
        for archived in archivedSnapshots {
            let spec = archived.record.launchSpec
            guard spec.transport.kind == .ssh,
                  spec.tmux != nil,
                  let destination = spec.transport.normalized.sshDestination?.nilIfBlank else {
                continue
            }

            let socketName = spec.tmux?.normalized.socketName?.nilIfBlank
            let host = remoteDiscoveryHost(
                destination: destination,
                label: spec.transport.hostLabel,
                socketName: socketName
            )
            let key = Self.convergeHostKey(destination: destination, socketName: socketName)
            if hostsByKey[key] == nil { hostsByKey[key] = host }
        }
        let remoteSweep = hostsByKey

        Task { [weak self] in
            var discoveredEntries: [HolyConvergeDiscoveredEntry] = []
            var reachable: Set<String> = []
            var discoveredByMatchKey: [String: (session: HolyDiscoveredTmuxSession, host: HolyRemoteHostRecord?)] = [:]
            var successfulRemoteHostIDs: Set<UUID> = []
            var localDiscoverySucceeded = false

            await withTaskGroup(of: (HolyRemoteHostRecord?, [HolyDiscoveredTmuxSession])?.self) { group in
                // Every child (remote and local) runs under the per-host
                // wall-clock cap. Discovery is now genuinely async (no blocking
                // waitUntilExit), so the actor services all children
                // concurrently: sweep wall-clock is max(per-host), not the sum.
                // A host that exceeds the cap is treated exactly like an
                // unreachable one - the child yields nil and its records are left
                // untouched - so isConverging always returns to false in bounded
                // time no matter what any discovery process does.
                let timeout = Self.convergeDiscoveryTimeoutSeconds
                for host in remoteSweep.values {
                    group.addTask {
                        do {
                            let sessions = try await HolyRemoteTmuxDiscoveryService.shared.discoverSessionsThrowing(
                                for: host,
                                timeout: timeout,
                                includeHiddenSessions: true
                            )
                            return (host, sessions)
                        } catch {
                            return nil // unreachable: leave its records untouched
                        }
                    }
                }
                group.addTask {
                    do {
                        let sessions = try await HolyRemoteTmuxDiscoveryService.shared.discoverLocalSessionsThrowing(
                            hostID: UUID(),
                            hostLabel: "This Mac",
                            timeout: timeout,
                            includeHiddenSessions: true
                        )
                        return (nil, sessions)
                    } catch {
                        return nil
                    }
                }

                for await result in group {
                    guard let (host, sessions) = result else { continue }
                    if let host {
                        successfulRemoteHostIDs.insert(host.id)
                    } else {
                        localDiscoverySucceeded = true
                    }

                    // Reachability = probe coverage, not the sockets we happened
                    // to find sessions on. A vanished session may only be
                    // archived when discovery actually inspected its socket
                    // namespace, so mark reachable every socket the service
                    // probes on this host. The probe list is owned by the
                    // discovery service (single source of truth).
                    let discoveryService = HolyRemoteTmuxDiscoveryService.shared
                    let reachableDestination: String
                    let probedSockets: [String?]
                    if let host {
                        reachableDestination = host.normalized().sshDestination
                        probedSockets = discoveryService.probedSocketNames(for: host)
                    } else {
                        reachableDestination = "local"
                        probedSockets = discoveryService.localProbedSocketNames
                    }
                    for socketName in probedSockets {
                        reachable.insert(Self.convergeHostKey(destination: reachableDestination, socketName: socketName))
                    }

                    for discovered in sessions {
                        // Key the discovered entry from the SESSION's own socket
                        // (mirrors the roster snapshot). Keying from the sweep
                        // host's recorded socket would let a live "holy"-socket
                        // session look "new" and get duplicated.
                        let entryHostKey = Self.convergeHostKey(
                            destination: host == nil ? "local" : discovered.hostDestination,
                            socketName: discovered.tmuxSocketName
                        )
                        let matchKey = Self.convergeMatchKey(hostKey: entryHostKey, sessionName: discovered.sessionName)
                        discoveredEntries.append(HolyConvergeDiscoveredEntry(
                            matchKey: matchKey,
                            hostKey: entryHostKey,
                            attachedClientCount: discovered.attachedClientCount
                        ))
                        if discoveredByMatchKey[matchKey] == nil {
                            discoveredByMatchKey[matchKey] = (discovered, host)
                        }
                    }
                }
            }

            let allDiscoveredSessions = discoveredByMatchKey.values.map(\.session)
            let activeMatches = HolyTmuxIdentityResolver.resolveOneToOne(
                launchSpecsByID: Dictionary(
                    uniqueKeysWithValues: rosterSnapshots.map { ($0.sessionID, $0.launchSpec) }
                ),
                among: allDiscoveredSessions
            )
            var reconciledIdentityBySessionID: [UUID: HolyDiscoveredTmuxSession] = [:]
            var unresolvedRosterSnapshots: [HolyConvergeRosterSnapshot] = []
            let rosterEntries = rosterSnapshots.map { snapshot -> HolyConvergeRosterEntry in
                guard let discovered = activeMatches[snapshot.sessionID] else {
                    if snapshot.launchSpec.tmux != nil {
                        unresolvedRosterSnapshots.append(snapshot)
                    }
                    return Self.storedConvergeRosterEntry(snapshot)
                }

                let destination = snapshot.launchSpec.transport.isRemote
                    ? discovered.hostDestination
                    : "local"
                reconciledIdentityBySessionID[snapshot.sessionID] = discovered
                return Self.convergeRosterEntry(
                    sessionID: snapshot.sessionID,
                    destination: destination,
                    socketName: discovered.tmuxSocketName,
                    sessionName: discovered.sessionName,
                    couldBeHidden: false,
                    localProcessExited: snapshot.localProcessExited
                )
            }

            let activeMatchKeys = Set(rosterEntries.compactMap(\.matchKey))
            var protectedArchiveIDs: Set<UUID> = []
            var archivedCandidatesByMatchKey: [String: [(archive: HolyArchivedSession, discovered: HolyDiscoveredTmuxSession)]] = [:]
            for archived in archivedSnapshots {
                let resolution = HolyTmuxIdentityResolver.resolve(
                    launchSpec: archived.record.launchSpec,
                    among: allDiscoveredSessions
                )
                guard case let .matched(discovered) = resolution else {
                    if resolution == .ambiguous,
                       allDiscoveredSessions.contains(where: {
                           HolyTmuxIdentityResolver.couldRefer(
                               launchSpec: archived.record.launchSpec,
                               to: $0
                           )
                       }) {
                        // Ambiguity blocks adoption, but it is still positive
                        // evidence that this archive may reference a live
                        // session. Keep it until identity becomes unique.
                        protectedArchiveIDs.insert(archived.id)
                    }
                    continue
                }

                let hostKey = Self.convergeHostKey(
                    destination: archived.record.launchSpec.transport.isRemote
                        ? discovered.hostDestination
                        : "local",
                    socketName: discovered.tmuxSocketName
                )
                let matchKey = Self.convergeMatchKey(
                    hostKey: hostKey,
                    sessionName: discovered.sessionName
                )
                protectedArchiveIDs.insert(archived.id)
                guard !activeMatchKeys.contains(matchKey) else { continue }
                archivedCandidatesByMatchKey[matchKey, default: []].append((archived, discovered))
            }

            var archivedSessionIDByMatchKey: [String: UUID] = [:]
            for (matchKey, candidates) in archivedCandidatesByMatchKey {
                guard candidates.count == 1, let candidate = candidates.first else { continue }
                let conflictsWithUnresolvedRoster = unresolvedRosterSnapshots.contains {
                    HolyTmuxIdentityResolver.couldRefer(
                        launchSpec: $0.launchSpec,
                        to: candidate.discovered
                    )
                }
                guard !conflictsWithUnresolvedRoster else { continue }
                archivedSessionIDByMatchKey[matchKey] = candidate.archive.id
            }
            let uncoveredArchiveIDs = Set(archivedSnapshots.compactMap { archived -> UUID? in
                Self.archiveDiscoveryCovered(archived, reachableHostKeys: reachable)
                    ? nil
                    : archived.id
            })

            let actions = HolyConvergePlanner.plan(
                roster: rosterEntries,
                discovered: discoveredEntries,
                reachableHostKeys: reachable,
                adoptableMatchKeys: Set(archivedSessionIDByMatchKey.keys)
            )

            await MainActor.run {
                guard let self else { return }
                self.publishConvergeDiscoveries(
                    discoveredByMatchKey,
                    localDiscoverySucceeded: localDiscoverySucceeded,
                    successfulRemoteHostIDs: successfulRemoteHostIDs
                )
                var identityChanged = false
                for (sessionID, discovered) in reconciledIdentityBySessionID {
                    if let session = self.sessions.first(where: { $0.id == sessionID }) {
                        identityChanged = session.applyDiscoveredTmuxIdentity(discovered) || identityChanged
                        let discoveredSpec: HolySessionLaunchSpec
                        if session.record.launchSpec.transport.isRemote,
                           let host = discoveredByMatchKey.values.first(where: {
                               $0.session.id == discovered.id
                           })?.host {
                            discoveredSpec = self.remoteTmuxLaunchSpec(for: discovered, on: host)
                        } else {
                            discoveredSpec = self.localTmuxLaunchSpec(for: discovered)
                        }
                        identityChanged = session.applyDiscoveredLaunchMetadata(
                            from: discoveredSpec,
                            refreshGitSnapshot: false
                        ) || identityChanged
                    }
                }
                self.applyConvergeActions(
                    actions,
                    discoveredByMatchKey: discoveredByMatchKey,
                    archivedSessionIDByMatchKey: archivedSessionIDByMatchKey
                )
                let retentionChanged = self.applyArchiveRetention(
                    protectedArchiveIDs: protectedArchiveIDs.union(uncoveredArchiveIDs)
                )
                if identityChanged || retentionChanged {
                    self.persist()
                }
                self.isConverging = false
            }
        }
    }

    private func applyConvergeActions(
        _ actions: [HolyConvergeAction],
        discoveredByMatchKey: [String: (session: HolyDiscoveredTmuxSession, host: HolyRemoteHostRecord?)],
        archivedSessionIDByMatchKey: [String: UUID]
    ) {
        for action in actions {
            switch action {
            case let .adoptArchived(matchKey):
                guard let found = discoveredByMatchKey[matchKey],
                      let archivedSessionID = archivedSessionIDByMatchKey[matchKey],
                      let archivedSession = archivedSessions.first(where: { $0.id == archivedSessionID }) else {
                    break
                }

                let launchSpec = reconciledArchivedLaunchSpec(
                    archivedSession,
                    discovered: found.session,
                    host: found.host
                )
                if let result = sessionSupervisor.readoptArchivedSession(
                    archivedSession,
                    with: launchSpec,
                    in: currentSessionStoreState
                ) {
                    applySessionStoreState(result.state)
                    persist(pendingEvents: result.pendingEvents)
                }
            case .surfaceOrphan:
                // Unknown live sessions remain discovery-only. Hosts now shows
                // them with its existing explicit Attach and confirmed Kill
                // controls; converge never creates a pane or reaps them itself.
                break
            case let .repair(sessionID):
                if let session = sessions.first(where: { $0.id == sessionID }),
                   canReattachSession(session) {
                    // Discovery confirmed that the backing tmux session is live.
                    // Recreate the local Ghostty surface for both local and remote
                    // transports, mirroring the working app-restore path.
                    reattach(session)
                }
            case let .archive(sessionID):
                if let session = sessions.first(where: { $0.id == sessionID }) {
                    archive(session)
                }
            }
        }
        updatePowerAssertion()
    }

    private func publishConvergeDiscoveries(
        _ discoveredByMatchKey: [String: (session: HolyDiscoveredTmuxSession, host: HolyRemoteHostRecord?)],
        localDiscoverySucceeded: Bool,
        successfulRemoteHostIDs: Set<UUID>
    ) {
        let discoveries = Array(discoveredByMatchKey.values)
        if localDiscoverySucceeded {
            discoveredLocalTmuxSessions = discoveries
                .filter { $0.host == nil }
                .map(\.session)
                .sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
            localTmuxDiscoveryError = nil
        }

        for hostID in successfulRemoteHostIDs {
            discoveredRemoteSessionsByHostID[hostID] = discoveries
                .filter { $0.host?.id == hostID }
                .map(\.session)
                .sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
            remoteDiscoveryErrorsByHostID.removeValue(forKey: hostID)
        }
    }

    @discardableResult
    private func applyArchiveRetention(
        protectedArchiveIDs: Set<UUID>
    ) -> Bool {
        let retained = HolyWorkspaceRetentionPolicy.retainedArchivedSessions(
            archivedSessions,
            activeSessionIDs: Set(sessions.map(\.id)),
            protectedArchiveIDs: protectedArchiveIDs
        )
        guard retained.map(\.id) != archivedSessions.map(\.id) else {
            return false
        }

        archivedSessions = retained
        if let selectedArchivedSessionID,
           !retained.contains(where: { $0.id == selectedArchivedSessionID }) {
            self.selectedArchivedSessionID = retained.first?.id
        }
        return true
    }

    private func reconciledArchivedLaunchSpec(
        _ archivedSession: HolyArchivedSession,
        discovered: HolyDiscoveredTmuxSession,
        host: HolyRemoteHostRecord?
    ) -> HolySessionLaunchSpec {
        let discoveredSpec = if let host {
            remoteTmuxLaunchSpec(for: discovered, on: host)
        } else {
            localTmuxLaunchSpec(for: discovered)
        }

        return reconciledArchivedLaunchSpec(
            archivedSession,
            discoveredLaunchSpec: discoveredSpec
        )
    }

    private func reconciledArchivedLaunchSpec(
        _ archivedSession: HolyArchivedSession,
        discoveredLaunchSpec discoveredSpec: HolySessionLaunchSpec
    ) -> HolySessionLaunchSpec {
        var launchSpec = archivedSession.record.launchSpec
        launchSpec.transport = discoveredSpec.transport
        launchSpec.tmux = discoveredSpec.tmux
        if launchSpec.runtime == .shell, discoveredSpec.runtime != .shell {
            launchSpec.runtime = discoveredSpec.runtime
        }
        if launchSpec.workingDirectory?.nilIfBlank == nil {
            launchSpec.workingDirectory = discoveredSpec.workingDirectory
        }
        if launchSpec.objective?.nilIfBlank == nil {
            launchSpec.objective = discoveredSpec.objective
        }
        if launchSpec.command?.nilIfBlank == nil {
            launchSpec.command = discoveredSpec.command
        }
        return launchSpec
    }

    // MARK: - Converge key construction (single source of truth)
    //
    // Both the roster snapshot and the discovery loop build identity keys here
    // so a session is keyed identically on both sides. The identity socket is
    // always the SESSION's own socket, normalized the same way everywhere:
    // blank -> nil -> "auto", with named socket case preserved.

    nonisolated private static func convergeHostKey(destination: String, socketName: String?) -> String {
        let scheme = destination == "local" ? "local" : "ssh"
        let normalizedSocket = socketName?.nilIfBlank ?? "auto"
        return [scheme, destination.lowercased(), normalizedSocket].joined(separator: "|")
    }

    nonisolated private static func convergeMatchKey(hostKey: String, sessionName: String) -> String {
        "\(hostKey)|\(sessionName)"
    }

    /// Builds a roster entry from a session's own identity. Any session that
    /// discovery could hide - a generated bare shell, a symbol-only shell title,
    /// or a Holy-managed shell whose only identity is a generic workspace name -
    /// is filtered out of discovery, so it can never be matched. Keep its
    /// matchKey so a discovered twin can never duplicate it, but drop its hostKey
    /// so the planner never archives or repairs a session discovery cannot see.
    /// A hidden session is by definition absent from discovery, so its repair
    /// path is never reachable regardless of host. Dropping its hostKey also
    /// prevents convergence from archiving it as missing.
    nonisolated private static func convergeRosterEntry(
        sessionID: UUID,
        destination: String,
        socketName: String?,
        sessionName: String,
        couldBeHidden: Bool,
        localProcessExited: Bool
    ) -> HolyConvergeRosterEntry {
        let hostKey = convergeHostKey(destination: destination, socketName: socketName)
        let matchKey = convergeMatchKey(hostKey: hostKey, sessionName: sessionName)
        return HolyConvergeRosterEntry(
            sessionID: sessionID,
            matchKey: matchKey,
            hostKey: couldBeHidden ? nil : hostKey,
            localProcessExited: localProcessExited
        )
    }

    /// Fallback used only when discovery could not resolve a roster snapshot.
    /// A nil socket is treated as incomplete legacy identity and therefore has
    /// no hostKey: it may prevent a duplicate default-socket attach by matchKey,
    /// but it can never authorize archival as "missing".
    nonisolated private static func storedConvergeRosterEntry(
        _ snapshot: HolyConvergeRosterSnapshot
    ) -> HolyConvergeRosterEntry {
        let spec = snapshot.launchSpec
        guard let tmux = spec.tmux?.normalized,
              let sessionName = tmux.sessionName?.nilIfBlank else {
            return .init(
                sessionID: snapshot.sessionID,
                matchKey: nil,
                hostKey: nil,
                localProcessExited: snapshot.localProcessExited
            )
        }

        let destination: String
        if spec.transport.isRemote {
            guard let sshDestination = spec.transport.normalized.sshDestination?.nilIfBlank else {
                return .init(
                    sessionID: snapshot.sessionID,
                    matchKey: nil,
                    hostKey: nil,
                    localProcessExited: snapshot.localProcessExited
                )
            }
            destination = sshDestination
        } else {
            destination = "local"
        }

        let socketName = tmux.socketName?.nilIfBlank
        let couldBeHidden = socketName == nil || HolyDiscoveredTmuxSession.rosterEntryCouldBeHiddenFromDiscovery(
            sessionName: sessionName,
            title: snapshot.title,
            workingDirectory: spec.workingDirectory,
            runtime: spec.runtime
        )
        return convergeRosterEntry(
            sessionID: snapshot.sessionID,
            destination: destination,
            socketName: socketName,
            sessionName: sessionName,
            couldBeHidden: couldBeHidden,
            localProcessExited: snapshot.localProcessExited
        )
    }

    /// Whether converge positively inspected every socket namespace an archive
    /// could refer to. Uncovered archives are protected from retention, while
    /// covered hosts still compact even when an unrelated host is offline.
    nonisolated private static func archiveDiscoveryCovered(
        _ archivedSession: HolyArchivedSession,
        reachableHostKeys: Set<String>
    ) -> Bool {
        let launchSpec = archivedSession.record.launchSpec
        guard let tmux = launchSpec.tmux?.normalized else { return true }

        let destination: String
        if launchSpec.transport.isRemote {
            guard let sshDestination = launchSpec.transport.normalized.sshDestination?.nilIfBlank else {
                return true
            }
            destination = sshDestination
        } else {
            destination = "local"
        }

        if let socketName = tmux.socketName?.nilIfBlank {
            return reachableHostKeys.contains(
                convergeHostKey(destination: destination, socketName: socketName)
            )
        }

        // Nil is an incomplete legacy socket, not permission to assume the
        // default server. The standard unconstrained probe inspects both.
        return [nil, HolySessionTmuxSpec.defaultSocketName].allSatisfy { socketName in
            reachableHostKeys.contains(
                convergeHostKey(destination: destination, socketName: socketName)
            )
        }
    }

    func canKillTmuxSession(_ session: HolySession) -> Bool {
        let launchSpec = session.record.launchSpec
        guard launchSpec.tmux != nil else { return false }
        return !launchSpec.transport.isRemote
            || launchSpec.transport.sshDestination?.holyTerminatorTrimmed.nilIfEmpty != nil
    }

    func killTmuxSession(_ session: HolySession) {
        let sessionID = session.id
        let sessionTitle = session.displayTitle
        let launchSpec = session.record.launchSpec
        tmuxSessionTerminationError = nil

        Task { [weak self] in
            guard let self else { return }

            let identity: HolyTmuxLiveIdentity
            if let exactIdentity = HolyTmuxLiveIdentity(exactLaunchSpec: launchSpec) {
                identity = exactIdentity
            } else {
                let discoveredSessions: [HolyDiscoveredTmuxSession]
                do {
                    discoveredSessions = try await self.discoverLiveTmuxSessions(for: launchSpec)
                } catch {
                    AppDelegate.logger.error(
                        "Holy Ghostty could not inspect tmux before killing \(sessionTitle, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                    self.tmuxSessionTerminationError = "Holy Ghostty left \(sessionTitle) in the roster because its saved tmux identity is incomplete and the app could not inspect the server. \(error.localizedDescription)"
                    return
                }

                let discoveredSession: HolyDiscoveredTmuxSession
                switch HolyTmuxIdentityResolver.resolve(
                    launchSpec: launchSpec,
                    among: discoveredSessions
                ) {
                case let .matched(match):
                    discoveredSession = match
                case .notFound:
                    self.tmuxSessionTerminationError = "Holy Ghostty did not kill \(sessionTitle) because no live tmux session could be matched safely. Refresh Hosts and attach or kill the exact discovered session there."
                    return
                case .ambiguous:
                    self.tmuxSessionTerminationError = "Holy Ghostty did not kill \(sessionTitle) because more than one live tmux session matched its saved metadata. Use Hosts to choose the exact session."
                    return
                }

                let activeMatches = HolyTmuxIdentityResolver.resolveOneToOne(
                    launchSpecsByID: Dictionary(
                        uniqueKeysWithValues: self.sessions.compactMap { activeSession in
                            guard activeSession.record.launchSpec.tmux != nil else { return nil }
                            return (activeSession.id, activeSession.record.launchSpec)
                        }
                    ),
                    among: discoveredSessions
                )
                guard activeMatches[sessionID] == discoveredSession else {
                    self.tmuxSessionTerminationError = "Holy Ghostty did not kill \(sessionTitle) because another roster record resolves to the same live tmux session. Resolve the duplicate in Hosts before killing it."
                    return
                }

                guard let discoveredIdentity = HolyTmuxLiveIdentity(
                    transport: launchSpec.transport,
                    discoveredSession: discoveredSession
                ) else {
                    self.tmuxSessionTerminationError = "Holy Ghostty did not kill \(sessionTitle) because the discovered tmux identity did not match its transport."
                    return
                }
                identity = discoveredIdentity

                if let currentSession = self.sessions.first(where: { $0.id == sessionID }),
                   currentSession.applyDiscoveredTmuxIdentity(discoveredSession) {
                    self.persist()
                }
            }

            let command = HolyTmuxSessionTerminationCommand.command(for: identity)
            let result = await Task.detached(priority: .utility) {
                command.run()
            }.value

            guard case .success = result else {
                if case let .failure(failure) = result {
                    AppDelegate.logger.error(
                        "Holy Ghostty failed to kill tmux session \(sessionTitle, privacy: .public): \(failure.message, privacy: .public)"
                    )
                    self.tmuxSessionTerminationError = "Holy Ghostty left \(sessionTitle) in the roster because tmux still reported it after the kill attempt. \(failure.message)"
                }
                return
            }

            guard let currentSession = self.sessions.first(where: { $0.id == sessionID }) else {
                return
            }

            self.archive(currentSession)
        }
    }

    private func discoverLiveTmuxSessions(
        for launchSpec: HolySessionLaunchSpec
    ) async throws -> [HolyDiscoveredTmuxSession] {
        if launchSpec.transport.isRemote {
            let transport = launchSpec.transport.normalized
            guard let destination = transport.sshDestination?.holyTerminatorTrimmed.nilIfEmpty else {
                return []
            }

            let savedHost = remoteHosts.first {
                $0.sshDestination.holyTerminatorTrimmed.caseInsensitiveCompare(destination) == .orderedSame
            }
            let host = HolyRemoteHostRecord(
                id: savedHost?.id ?? UUID(),
                label: savedHost?.displayTitle ?? transport.hostLabel ?? destination,
                sshDestination: destination,
                // A missing stored socket is exactly what this probe must
                // recover, so leave it unconstrained and inspect both default
                // and holy. Never inherit a saved host's preferred socket here.
                tmuxSocketName: launchSpec.tmux?.normalized.socketName
            )
            return try await HolyRemoteTmuxDiscoveryService.shared.discoverIdentitySessionsThrowing(
                for: host,
                timeout: Self.terminationDiscoveryTimeoutSeconds,
                includeHiddenSessions: true
            )
        }

        return try await HolyRemoteTmuxDiscoveryService.shared.discoverLocalIdentitySessionsThrowing(
            hostID: HolyLocalMachineIdentity.localHostID,
            hostLabel: HolyLocalMachineIdentity.current.displayName,
            tmuxSocketName: launchSpec.tmux?.normalized.socketName,
            timeout: Self.terminationDiscoveryTimeoutSeconds,
            includeHiddenSessions: true
        )
    }

    func killDiscoveredLocalTmuxSession(_ session: HolyDiscoveredTmuxSession) {
        let launchSpec = localTmuxLaunchSpec(for: session)
        killDiscoveredTmuxSession(launchSpec: launchSpec) { [weak self] in
            self?.refreshLocalTmuxSessions()
        }
    }

    func killDiscoveredRemoteTmuxSession(_ session: HolyDiscoveredTmuxSession, on host: HolyRemoteHostRecord) {
        let launchSpec = remoteTmuxLaunchSpec(for: session, on: host)
        killDiscoveredTmuxSession(launchSpec: launchSpec) { [weak self] in
            self?.refreshRemoteSessions(for: host)
        }
    }

    private func killDiscoveredTmuxSession(
        launchSpec: HolySessionLaunchSpec,
        onCompletion: @escaping @MainActor () -> Void
    ) {
        guard let tmux = launchSpec.tmux?.normalized,
              let sessionName = tmux.sessionName?.holyTerminatorTrimmed.nilIfEmpty else {
            return
        }
        guard let identity = HolyTmuxLiveIdentity(
            transport: launchSpec.transport.normalized,
            socketName: tmux.socketName?.holyTerminatorTrimmed.nilIfEmpty,
            sessionName: sessionName
        ) else { return }
        let command = HolyTmuxSessionTerminationCommand.command(for: identity)

        tmuxSessionTerminationError = nil

        Task {
            let result = await Task.detached(priority: .utility) {
                command.run()
            }.value

            switch result {
            case .success:
                onCompletion()
            case let .failure(failure):
                AppDelegate.logger.error(
                    "Holy Ghostty failed to kill discovered tmux session: \(failure.message, privacy: .public)"
                )
                tmuxSessionTerminationError = "Holy Ghostty left the tmux session running because tmux still reported it after the kill attempt. \(failure.message)"
            }
        }
    }

    func moveSession(_ sessionID: UUID, to targetSessionID: UUID) {
        guard sessionID != targetSessionID,
              let sourceIndex = sessions.firstIndex(where: { $0.id == sessionID }),
              let targetIndex = sessions.firstIndex(where: { $0.id == targetSessionID }) else {
            return
        }

        let session = sessions.remove(at: sourceIndex)
        sessions.insert(session, at: min(targetIndex, sessions.count))
    }

    func moveSessionToEnd(_ sessionID: UUID) {
        guard let sourceIndex = sessions.firstIndex(where: { $0.id == sessionID }),
              sourceIndex != sessions.index(before: sessions.endIndex) else {
            return
        }

        let session = sessions.remove(at: sourceIndex)
        sessions.append(session)
    }

    func persistSessionOrder() {
        persist()
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

        guard let command = HolyTmuxSessionTitleUpdateCommand.command(
            for: session.record.launchSpec,
            title: newTitle
        ) else {
            return
        }

        Task.detached(priority: .utility) {
            _ = command.run()
        }
    }

    func setNote(_ session: HolySession, to note: String?) {
        session.setNote(note)
        persist()
    }

    func setFocus(_ session: HolySession, _ focused: Bool) {
        session.setFocused(focused)
        // The roster's Focus layout groups by session.isFocused, but that lives on
        // the session, not a @Published store property — so toggling it does not by
        // itself re-run the roster body. Republish the store so the session moves
        // into/out of the Today section immediately, instead of only after the next
        // unrelated store change (e.g. selecting another session).
        objectWillChange.send()
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

    func duplicate(_ sessionID: UUID) {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return }
        duplicate(session)
    }

    func presentComposer() {
        presentComposer(with: draftForNewSession())
    }

    @discardableResult
    func createSessionFromDefaultLaunchProfile() -> HolySession? {
        guard let session = createSession(with: newDefaultLaunchProfileSpec(), origin: .directLaunch) else {
            return nil
        }
        revealAndFocusNewSession(session)
        return session
    }

    @discardableResult
    func createSession(using profile: HolyLaunchProfile) -> HolySession? {
        guard let session = createSession(with: launchSpec(for: profile), origin: .directLaunch) else {
            return nil
        }
        revealAndFocusNewSession(session)
        return session
    }

    /// Bring a user-created session fully to the foreground: switch the visible
    /// pane to it (identical to clicking its roster row) and move keyboard focus
    /// into its terminal. Only explicit "New" actions call this; bulk creation
    /// (restore, converge attach, duplicate) must not steal the pane or focus.
    private func revealAndFocusNewSession(_ session: HolySession) {
        handleRosterSelect(session.id)
        Ghostty.moveFocus(to: session.surfaceView)
    }

    @discardableResult
    func createLocalSession() -> HolySession? {
        createSession(with: launchSpec(for: HolyLaunchProfile.localDefault()), origin: .directLaunch)
    }

    func setDefaultLaunchProfile(_ profile: HolyLaunchProfile) {
        guard launchProfiles.contains(where: { $0.id == profile.id }) else { return }
        defaultLaunchProfileID = profile.id
        persistLaunchProfiles()
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
        refreshConnectionOverview()
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
        reconcileLaunchProfiles()
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
        reconcileLaunchProfiles()
    }

    func refreshConnectionOverview() {
        refreshLocalTmuxSessions()

        for host in remoteHosts where !host.sshDestination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            refreshRemoteSessions(for: host)
        }
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

    func refreshLocalTmuxSessions() {
        guard !localTmuxDiscoveryBusy else { return }

        localTmuxDiscoveryBusy = true
        localTmuxDiscoveryError = nil

        Task { [weak self] in
            do {
                let sessions = try await HolyRemoteTmuxDiscoveryService.shared.discoverLocalSessionsThrowing(
                    hostID: HolyLocalMachineIdentity.localHostID,
                    hostLabel: HolyLocalMachineIdentity.current.displayName
                )
                await MainActor.run {
                    guard let self else { return }
                    // Runs every 15s now — skip the publish when nothing moved.
                    if self.discoveredLocalTmuxSessions != sessions {
                        self.discoveredLocalTmuxSessions = sessions
                    }
                    if self.applyDiscoveredLocalSessionMetadata(sessions) {
                        self.persist()
                    }
                    self.localTmuxDiscoveryBusy = false
                    self.localTmuxDiscoveryError = nil
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.discoveredLocalTmuxSessions = []
                    self.localTmuxDiscoveryBusy = false
                    self.localTmuxDiscoveryError = error.localizedDescription
                }
            }
        }
    }

    func refreshRemoteSessions(for host: HolyRemoteHostRecord) {
        guard !remoteDiscoveryBusyHostIDs.contains(host.id) else { return }

        remoteDiscoveryBusyHostIDs.insert(host.id)
        remoteDiscoveryErrorsByHostID.removeValue(forKey: host.id)

        Task { [weak self] in
            do {
                let sessions = try await HolyRemoteTmuxDiscoveryService.shared.discoverSessionsThrowing(for: host)
                await MainActor.run {
                    guard let self else { return }
                    self.discoveredRemoteSessionsByHostID[host.id] = sessions
                    let changed = self.applyDiscoveredRemoteSessionMetadata(sessions, on: host)
                    self.remoteDiscoveryBusyHostIDs.remove(host.id)
                    self.remoteDiscoveryErrorsByHostID.removeValue(forKey: host.id)
                    self.markRemoteHostDiscovered(host.id)
                    if changed {
                        self.persist()
                    }
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

    func launchLocalTmuxSession(_ session: HolyDiscoveredTmuxSession, keepHostsOpen: Bool = false) {
        _ = attachDiscoveredTmuxSession(with: localTmuxLaunchSpec(for: session))
        if !keepHostsOpen {
            remoteHostsPresented = false
        }
    }

    func launchLocalTmuxSessions(_ sessions: [HolyDiscoveredTmuxSession], keepHostsOpen: Bool = false) {
        guard !sessions.isEmpty else { return }

        for session in sessions {
            _ = attachDiscoveredTmuxSession(with: localTmuxLaunchSpec(for: session))
        }

        if !keepHostsOpen {
            remoteHostsPresented = false
        }
    }

    func launchRemoteTmuxSession(_ session: HolyDiscoveredTmuxSession, on host: HolyRemoteHostRecord, keepHostsOpen: Bool = false) {
        let launchSpec = remoteTmuxLaunchSpec(for: session, on: host)

        _ = attachDiscoveredTmuxSession(with: launchSpec)
        if !keepHostsOpen {
            remoteHostsPresented = false
        }
    }

    func launchRemoteTmuxSessions(_ sessions: [HolyDiscoveredTmuxSession], on host: HolyRemoteHostRecord, keepHostsOpen: Bool = false) {
        guard !sessions.isEmpty else { return }

        for session in sessions {
            let launchSpec = remoteTmuxLaunchSpec(for: session, on: host)

            _ = attachDiscoveredTmuxSession(with: launchSpec)
        }

        if !keepHostsOpen {
            remoteHostsPresented = false
        }
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
            selectedArchivedSessionID: selectedArchivedSessionID,
            paneLayout: normalizedPaneLayout,
            attentionMetadata: attentionMetadataForPersistence()
        )
    }

    private func attentionMetadataForPersistence() -> [HolySessionAttentionMetadata] {
        let activeIDs = Set(sessions.map(\.id))
        return attentionMetadataBySessionID.values
            .filter { activeIDs.contains($0.sessionID) }
            .sorted { $0.sessionID.uuidString < $1.sessionID.uuidString }
    }

    private func clearUnreadAttentionIfNeeded(for sessionID: UUID) {
        guard markSessionSeenIfNeeded(sessionID) else { return }
        cancelSelectedSessionSeenMark()
        persist()
    }

    @discardableResult
    private func markSelectedSessionSeenIfNeeded(at date: Date = .init()) -> Bool {
        guard let selectedSessionID else { return false }
        return markSessionSeenIfNeeded(selectedSessionID, at: date)
    }

    @discardableResult
    private func markSessionSeenIfNeeded(_ sessionID: UUID, at date: Date = .init()) -> Bool {
        guard let session = session(withID: sessionID) else {
            return false
        }

        return updateAttentionMetadata(
            for: session,
            markSeen: true,
            existing: &attentionMetadataBySessionID,
            at: date
        )
    }

    private func scheduleSelectedSessionSeenMark() {
        // No-op: the "new reply" (blue) state is now purely a function of how
        // long ago the agent reply arrived, so viewing a session no longer needs
        // to mark it seen. Kept as a stub so existing call sites stay simple.
        cancelSelectedSessionSeenMark()
    }

    private func cancelSelectedSessionSeenMark() {
        selectedSessionReadTask?.cancel()
        selectedSessionReadTask = nil
        selectedSessionReadTaskKey = nil
    }

    private func reconcileAttentionMetadata(
        markSelectedSeen: Bool,
        seedMissingAsSeen: Bool = false,
        at date: Date = .init()
    ) {
        let activeIDs = Set(sessions.map(\.id))
        var next = attentionMetadataBySessionID.filter { activeIDs.contains($0.key) }
        var changed = next.count != attentionMetadataBySessionID.count

        for session in sessions {
            let shouldMarkSeen = (markSelectedSeen && session.id == selectedSessionID)
                || (seedMissingAsSeen && next[session.id] == nil)
            if updateAttentionMetadata(for: session, markSeen: shouldMarkSeen, existing: &next, at: date) {
                changed = true
            }
        }

        if changed {
            attentionMetadataBySessionID = next
        }
    }

    @discardableResult
    private func updateAttentionMetadata(
        for session: HolySession,
        markSeen: Bool,
        existing: inout [UUID: HolySessionAttentionMetadata],
        at date: Date = .init()
    ) -> Bool {
        let isActiveWork = session.phase == .working || session.runtimeTelemetry.activityKind.isActiveWork
        var metadata = existing[session.id] ?? HolySessionAttentionMetadata(sessionID: session.id)
        var changed = false

        if metadata.lastAttentionWasActiveWork == true && !isActiveWork {
            metadata.lastAgentFinishedAt = date
            changed = true
        }

        if metadata.lastAttentionWasActiveWork != isActiveWork {
            metadata.lastAttentionWasActiveWork = isActiveWork
            changed = true
        }

        if changed {
            metadata.updatedAt = date
            existing[session.id] = metadata
        } else if existing[session.id] == nil {
            existing[session.id] = metadata
            changed = true
        }

        return changed
    }

    /// Whether persisted attention metadata says this session's last reply had
    /// already been seen before the previous quit. Used to decide which restored
    /// sessions get their seen verdict carried across relaunch.
    private func isWaitingAttention(_ session: HolySession) -> Bool {
        session.phase == .waitingInput || session.runtimeTelemetry.activityKind == .approval
    }

    private func normalizedAttentionText(_ text: String?) -> String? {
        guard let text else { return nil }
        let collapsed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    private func attentionPresentation(
        for session: HolySession,
        coordination: HolySessionCoordination
    ) -> HolySessionAttentionPresentation {
        let metadata = attentionMetadataBySessionID[session.id]
        let finishedAt = metadata?.lastAgentFinishedAt
        let becameAvailableAt = finishedAt ?? session.activityAt
        let detail = attentionDetail(for: session)

        if session.phase == .failed || session.runtimeTelemetry.activityKind == .failure {
            return .init(
                kind: .failed,
                symbolName: "xmark.octagon.fill",
                title: "Issue",
                detail: detail,
                isProminent: true,
                becameAvailableAt: becameAvailableAt
            )
        }

        if session.runtimeTelemetry.activityKind == .planningQuestion {
            return .init(
                kind: .planningQuestion,
                symbolName: "questionmark.bubble.fill",
                title: "Planning questions",
                detail: detail,
                isProminent: true,
                becameAvailableAt: becameAvailableAt
            )
        }

        if approvalLooksExplicit(for: session) {
            return .init(
                kind: .approvalNeeded,
                symbolName: "hand.raised.fill",
                title: "Approval needed",
                detail: detail,
                isProminent: true,
                becameAvailableAt: becameAvailableAt
            )
        }

        if session.runtimeTelemetry.activityKind == .swarming {
            return .init(
                kind: .swarming,
                symbolName: "sparkles",
                title: "Swarming",
                detail: detail,
                isProminent: true,
                becameAvailableAt: becameAvailableAt
            )
        }

        if session.runtimeTelemetry.activityKind == .stalled || session.runtimeTelemetry.activityKind == .looping {
            let isLooping = session.runtimeTelemetry.activityKind == .looping
            return .init(
                kind: .stalled,
                symbolName: isLooping ? "arrow.triangle.2.circlepath" : "hourglass",
                title: isLooping ? "Looping" : "Stalled",
                detail: detail,
                isProminent: true,
                becameAvailableAt: becameAvailableAt
            )
        }

        if session.phase == .working || session.runtimeTelemetry.activityKind.isActiveWork {
            return .init(
                kind: .working,
                symbolName: "circle.dotted",
                title: session.compactStatusText,
                detail: detail,
                isProminent: true,
                becameAvailableAt: becameAvailableAt
            )
        }

        if let finishedAt,
           attentionClock.timeIntervalSince(finishedAt) < Self.freshReplyInterval {
            return .init(
                kind: .newReply,
                symbolName: "circle.fill",
                title: "Recent reply",
                detail: detail,
                isProminent: true,
                becameAvailableAt: finishedAt
            )
        }

        if session.phase == .waitingInput || session.runtimeTelemetry.activityKind == .approval {
            let age = attentionClock.timeIntervalSince(becameAvailableAt)
            if age >= Self.staleReplyInterval {
                return .init(
                    kind: .dormantReply,
                    symbolName: "moon.fill",
                    title: "Dormant",
                    detail: detail,
                    isProminent: false,
                    becameAvailableAt: becameAvailableAt
                )
            }

            if age >= Self.overdueReplyInterval {
                return .init(
                    kind: .sleepingReply,
                    symbolName: "moon.zzz.fill",
                    title: "Sleeping",
                    detail: detail,
                    isProminent: false,
                    becameAvailableAt: becameAvailableAt
                )
            }

            return .init(
                kind: .waitingQuiet,
                symbolName: "circle",
                title: "Waiting quietly",
                detail: detail,
                isProminent: false,
                becameAvailableAt: becameAvailableAt
            )
        }

        if session.phase == .completed || session.runtimeTelemetry.activityKind == .completion {
            return .init(
                kind: .done,
                symbolName: "checkmark.circle.fill",
                title: "Complete",
                detail: detail,
                isProminent: false,
                becameAvailableAt: becameAvailableAt
            )
        }

        return .init(
            kind: .quiet,
            symbolName: "circle",
            title: "Ready",
            detail: detail,
            isProminent: false,
            becameAvailableAt: becameAvailableAt
        )
    }

    private func approvalLooksExplicit(for session: HolySession) -> Bool {
        guard session.runtimeTelemetry.activityKind == .approval else { return false }

        let evidence = [
            session.runtimeTelemetry.headline,
            session.runtimeTelemetry.detail,
            session.runtimeTelemetry.nextStepHint,
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: "\n")

        return [
            "approval",
            "approve",
            "confirm",
            "allow",
            "permission",
            "continue?",
            "[y/n]",
            "(y/n)",
        ].contains { evidence.contains($0) }
    }

    private func attentionDetail(for session: HolySession) -> String? {
        [
            session.runtimeTelemetry.detail,
            session.runtimeTelemetry.nextStepHint,
            session.runtimeTelemetry.headline,
            session.primarySignal?.detail,
            session.primarySignal?.headline,
        ]
        .compactMap(normalizedAttentionText)
        .first
    }

    private func applySessionStoreState(_ state: HolySessionStoreState) {
        suppressAutomaticSelectionPersistence = true
        sessions = state.sessions
        savedTemplates = state.savedTemplates
        archivedSessions = state.archivedSessions
        attentionMetadataBySessionID = Dictionary(uniqueKeysWithValues: state.attentionMetadata.map { ($0.sessionID, $0) })
        selectedArchivedSessionID = state.selectedArchivedSessionID
        selectedSessionID = state.selectedSessionID
        paneLayout = state.paneLayout.normalized(
            availableSessionIDs: state.sessions.map(\.id),
            selectedSessionID: state.selectedSessionID
        )
        soloSessionID = nil
        focusedPaneSlot = state.selectedSessionID.flatMap { paneLayout.slot(for: $0) }
        suppressAutomaticSelectionPersistence = false
        refreshSessionPresentationState()
        bindSessions(seedMissingAsSeen: true)
        reconcileExternalTasks()
        scheduleSelectedSessionSeenMark()
        updatePowerAssertion()
    }

    private func refreshSessionPresentationState() {
        var presentedIDs = Set(visiblePaneSessions.map(\.id))
        if presentedIDs.isEmpty, let selectedSessionID = selectedSession?.id {
            presentedIDs.insert(selectedSessionID)
        }

        for session in sessions {
            session.setPresentedInWorkspace(presentedIDs.contains(session.id))
        }
    }

    private func applyPaneLayout(
        kind: HolyPaneLayoutKind,
        sourceSessionID: UUID? = nil,
        cloneConfig: Ghostty.SurfaceConfiguration? = nil
    ) {
        var layout = normalizedPaneLayout

        if let cloneConfig,
           kind.maxPaneCount > 1,
           let session = createSession(from: cloneConfig) {
            let targetSlot = sourceSessionID.flatMap { layout.slot(for: $0).map { min($0 + 1, kind.maxPaneCount) } }
                ?? min(max(layout.highestOccupiedSlot ?? 0, 1) + 1, kind.maxPaneCount)
            layout = layout.assigning(session.id, toSlot: targetSlot)
        }

        if layout.sessionIDs.isEmpty,
           let selectedID = selectedSession?.id ?? sessions.first?.id {
            layout = layout.assigning(selectedID, toSlot: 1)
        }

        paneLayout = layout
            .normalized(
                availableSessionIDs: sessions.map(\.id),
                selectedSessionID: selectedSessionID
            )
            .oriented(kind)
        let focusedSlot = selectedSessionID.flatMap { paneLayout.slot(for: $0) }
            ?? paneLayout.highestOccupiedSlot
        enterSplit(focusedSlot: focusedSlot)
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
            reusableSession.applyDiscoveredLaunchMetadata(from: launchSpec)
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

    /// Hosts attach actions reconnect to an existing tmux identity. Reuse the
    /// current roster record when present, or re-adopt its archive after Clear,
    /// so user-owned metadata (notes, focus pins, task context) follows the
    /// session instead of being replaced by a blank discovery-built record.
    @discardableResult
    private func attachDiscoveredTmuxSession(
        with launchSpec: HolySessionLaunchSpec
    ) -> HolySession? {
        guard let launchKey = HolyTmuxSessionKey(launchSpec: launchSpec),
              launchSpec.tmux?.normalized.createIfMissing == false else {
            return createSession(with: launchSpec, origin: .directLaunch)
        }

        if let existingSession = sessions.first(where: {
            HolyTmuxSessionKey(launchSpec: $0.record.launchSpec) == launchKey
        }) {
            existingSession.applyDiscoveredLaunchMetadata(from: launchSpec)
            selectedSessionID = existingSession.id
            persist()
            return existingSession
        }

        guard let archivedSession = archivedSessions.first(where: {
            HolyTmuxSessionKey(launchSpec: $0.record.launchSpec) == launchKey
        }) else {
            return createSession(with: launchSpec, origin: .directLaunch)
        }

        let reconciledLaunchSpec = reconciledArchivedLaunchSpec(
            archivedSession,
            discoveredLaunchSpec: launchSpec
        )
        let previousSelectedSessionID = selectedSessionID
        guard let result = sessionSupervisor.readoptArchivedSession(
            archivedSession,
            with: reconciledLaunchSpec,
            in: currentSessionStoreState
        ) else {
            return nil
        }

        applySessionStoreState(result.state)
        selectedSessionID = result.sessionID
        var pendingEvents = result.pendingEvents
        pendingEvents.append(contentsOf: selectionEvents(
            from: previousSelectedSessionID,
            to: selectedSessionID
        ))
        persist(pendingEvents: pendingEvents)
        return sessions.first(where: { $0.id == result.sessionID })
    }

    private func startActiveTmuxMetadataRefresh() {
        guard activeTmuxMetadataRefreshCancellable == nil else { return }

        activeTmuxMetadataRefreshCancellable = Timer.publish(every: 300, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.convergeRoster(reason: .periodic)
            }

        // A resumed-but-idle agent pane emits no OSC 7 until its next turn,
        // so tmux pane_current_path is the only prompt source for the
        // cwd-derived sidebar name. Local discovery is one cheap subprocess;
        // don't make the name wait on the 300s converge.
        localTmuxMetadataRefreshCancellable = Timer.publish(every: 15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.hasActiveLocalTmuxSessions else { return }
                self.refreshLocalTmuxSessions()
            }
    }

    private func refreshActiveTmuxSessionMetadata() {
        if hasActiveLocalTmuxSessions {
            refreshLocalTmuxSessions()
        }

        refreshActiveRemoteTmuxSessionMetadata()
    }

    private func startAttentionClock() {
        guard attentionClockCancellable == nil else { return }

        attentionClockCancellable = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                self?.attentionClock = date
            }
    }

    private var hasActiveLocalTmuxSessions: Bool {
        sessions.contains { session in
            HolyLocalTmuxSessionKey(launchSpec: session.record.launchSpec) != nil
        }
    }

    private func refreshActiveRemoteTmuxSessionMetadata() {
        for host in activeRemoteTmuxDiscoveryHosts() {
            refreshRemoteSessions(for: host)
        }
    }

    private func activeRemoteTmuxDiscoveryHosts() -> [HolyRemoteHostRecord] {
        var hosts: [HolyRemoteHostRecord] = []
        var seenKeys: Set<String> = []

        for session in sessions {
            let launchSpec = session.record.launchSpec
            guard launchSpec.transport.kind == .ssh,
                  let destination = launchSpec.transport.sshDestination?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
                  let tmux = launchSpec.tmux?.normalized else {
                continue
            }

            let socketName = tmux.socketName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            let host = remoteDiscoveryHost(
                destination: destination,
                label: launchSpec.transport.hostLabel,
                socketName: socketName
            )
            let normalizedHost = host.normalized()
            let key = [
                normalizedHost.sshDestination.lowercased(),
                normalizedHost.tmuxSocketName ?? "auto",
            ].joined(separator: "|")

            guard seenKeys.insert(key).inserted else { continue }
            hosts.append(host)
        }

        return hosts
    }

    private func remoteDiscoveryHost(
        destination: String,
        label: String?,
        socketName: String?
    ) -> HolyRemoteHostRecord {
        if let exact = remoteHosts.first(where: { host in
            let normalized = host.normalized()
            return normalized.sshDestination.caseInsensitiveCompare(destination) == .orderedSame
                && normalized.tmuxSocketName == socketName
        }) {
            return exact
        }

        // A saved "automatic" host is useful for its stable ID/label, but an
        // exact record socket must still drive probe coverage. Copy rather than
        // returning the auto host, or a custom-socket record would be marked
        // covered after probing only default+holy.
        if let automatic = remoteHosts.first(where: { host in
            let normalized = host.normalized()
            return normalized.sshDestination.caseInsensitiveCompare(destination) == .orderedSame
                && normalized.tmuxSocketName == nil
        }) {
            return HolyRemoteHostRecord(
                id: automatic.id,
                label: automatic.displayTitle,
                sshDestination: destination,
                tmuxSocketName: socketName,
                createdAt: automatic.createdAt,
                updatedAt: automatic.updatedAt,
                lastDiscoveredAt: automatic.lastDiscoveredAt
            )
        }

        return HolyRemoteHostRecord(
            label: label ?? destination,
            sshDestination: destination,
            tmuxSocketName: socketName
        )
    }

    private func localTmuxLaunchSpec(for session: HolyDiscoveredTmuxSession) -> HolySessionLaunchSpec {
        HolySessionLaunchSpec(
            runtime: session.runtime ?? .shell,
            title: session.displayTitle,
            objective: session.objective,
            budget: nil,
            transport: .local,
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
    }

    private func remoteTmuxLaunchSpec(
        for session: HolyDiscoveredTmuxSession,
        on host: HolyRemoteHostRecord
    ) -> HolySessionLaunchSpec {
        HolySessionLaunchSpec(
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
    }

    private func applyDiscoveredLocalSessionMetadata(_ discoveredSessions: [HolyDiscoveredTmuxSession]) -> Bool {
        var changed = false

        for session in sessions where session.record.launchSpec.transport.kind == .local {
            guard case let .matched(discoveredSession) = HolyTmuxIdentityResolver.resolve(
                launchSpec: session.record.launchSpec,
                among: discoveredSessions
            ) else { continue }

            let launchSpec = localTmuxLaunchSpec(for: discoveredSession)
            changed = session.applyDiscoveredTmuxIdentity(discoveredSession) || changed
            changed = session.applyDiscoveredLaunchMetadata(from: launchSpec, refreshGitSnapshot: false) || changed
        }

        return changed
    }

    private func applyDiscoveredRemoteSessionMetadata(
        _ discoveredSessions: [HolyDiscoveredTmuxSession],
        on host: HolyRemoteHostRecord
    ) -> Bool {
        var changed = false

        for session in sessions where session.record.launchSpec.transport.kind == .ssh {
            guard case let .matched(discoveredSession) = HolyTmuxIdentityResolver.resolve(
                launchSpec: session.record.launchSpec,
                among: discoveredSessions
            ) else { continue }

            let launchSpec = remoteTmuxLaunchSpec(for: discoveredSession, on: host)
            changed = session.applyDiscoveredTmuxIdentity(discoveredSession) || changed
            changed = session.applyDiscoveredLaunchMetadata(from: launchSpec) || changed
        }

        return changed
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
            launchSpec: newDefaultLaunchProfileSpec(),
            contextualWorkingDirectory: contextualWorkingDirectory,
            contextualRepositoryRoot: contextualRepositoryRoot
        )
    }

    private func newDefaultLaunchProfileSpec() -> HolySessionLaunchSpec {
        let profile = defaultLaunchProfile ?? HolyLaunchProfile.localDefault()
        return launchSpec(for: profile)
    }

    private func launchSpec(for profile: HolyLaunchProfile) -> HolySessionLaunchSpec {
        contextualizedLaunchSpec(from: profile.launchSpecForNewSession(fallbackTitle: nextShellTitle()))
    }

    private func shouldBootstrapDefaultTmuxServer(for launchSpec: HolySessionLaunchSpec) -> Bool {
        guard launchSpec.transport.kind == .local,
              launchSpec.tmux == nil,
              launchSpec.command?.trimmingCharacters(in: .whitespacesAndNewlines) == "tmux" else {
            return false
        }

        return true
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
        let reconciledHosts = reconcileRemoteHosts(migratedHosts)
        remoteHosts = reconciledHosts
        if let selectedRemoteHostID,
           remoteHosts.contains(where: { $0.id == selectedRemoteHostID }) {
            self.selectedRemoteHostID = selectedRemoteHostID
        } else {
            self.selectedRemoteHostID = remoteHosts.first?.id
        }

        if reconciledHosts != loadedHosts {
            persistRemoteHosts()
        }
    }

    private func loadLaunchProfiles() {
        let state = HolyLaunchProfileRepository.loadState(remoteHosts: remoteHosts)
        launchProfiles = state.profiles
        defaultLaunchProfileID = state.defaultProfileID
    }

    private func persistTasks() {
        HolyTaskRepository.save(externalTasks)
    }

    private func persistRemoteHosts() {
        HolyRemoteHostRepository.save(remoteHosts)
    }

    private func persistLaunchProfiles() {
        HolyLaunchProfileRepository.save(
            .init(
                profiles: launchProfiles,
                defaultProfileID: defaultLaunchProfileID
            )
        )
    }

    private func reconcileLaunchProfiles(persistIfChanged: Bool = true) {
        let nextState = HolyLaunchProfileRepository.reconciledState(
            loadedProfiles: launchProfiles,
            loadedDefaultID: defaultLaunchProfileID,
            remoteHosts: remoteHosts
        )

        guard nextState.profiles != launchProfiles || nextState.defaultProfileID != defaultLaunchProfileID else {
            return
        }

        launchProfiles = nextState.profiles
        defaultLaunchProfileID = nextState.defaultProfileID
        if persistIfChanged {
            persistLaunchProfiles()
        }
    }

    private func mergeImportedRemoteHosts(_ importedHosts: [HolyRemoteHostRecord], sourceLabel: String) {
        guard !importedHosts.isEmpty else {
            remoteHostImportMessage = "No machines found in \(sourceLabel.lowercased())."
            return
        }

        let previousHostCount = remoteHosts.count
        var existingHostsByDestination: [String: HolyRemoteHostRecord] = [:]
        for host in remoteHosts {
            existingHostsByDestination[host.sshDestination.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = host
        }

        for importedHost in importedHosts {
            let normalizedHost = importedHost.normalized()
            let key = normalizedHost.sshDestination.lowercased()

            guard existingHostsByDestination[key] == nil else { continue }
            remoteHosts.append(normalizedHost)
            existingHostsByDestination[key] = normalizedHost
        }

        remoteHosts = reconcileRemoteHosts(remoteHosts)
        remoteHosts.sort { lhs, rhs in
            lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
        }

        if let selectedRemoteHostID,
           remoteHosts.contains(where: { $0.id == selectedRemoteHostID }) {
            self.selectedRemoteHostID = selectedRemoteHostID
        } else {
            self.selectedRemoteHostID = remoteHosts.first?.id
        }

        persistRemoteHosts()
        reconcileLaunchProfiles()

        let addedHosts = max(0, remoteHosts.count - previousHostCount)
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
        reconcileLaunchProfiles()
    }

    private func migrateRemoteHostIfNeeded(_ host: HolyRemoteHostRecord) -> HolyRemoteHostRecord {
        var normalizedHost = host.normalized()

        if normalizedHost.tmuxSocketName?.trimmingCharacters(in: .whitespacesAndNewlines) == HolySessionTmuxSpec.defaultSocketName {
            normalizedHost.tmuxSocketName = nil
            normalizedHost.updatedAt = .now
        }

        return normalizedHost
    }

    private func reconcileRemoteHosts(_ hosts: [HolyRemoteHostRecord]) -> [HolyRemoteHostRecord] {
        var hostsByConnectionKey: [String: HolyRemoteHostRecord] = [:]

        for host in hosts.map(migrateRemoteHostIfNeeded(_:)) {
            let normalizedHost = host.normalized()
            guard !HolyLocalMachineIdentity.current.shouldHideAsRemote(normalizedHost) else { continue }

            let connectionKey = remoteHostConnectionKey(for: normalizedHost)
            if let existingHost = hostsByConnectionKey[connectionKey] {
                hostsByConnectionKey[connectionKey] = mergedRemoteHost(existingHost, normalizedHost, connectionKey: connectionKey)
            } else {
                hostsByConnectionKey[connectionKey] = canonicalRemoteHost(normalizedHost, connectionKey: connectionKey)
            }
        }

        return hostsByConnectionKey.values.sorted { lhs, rhs in
            lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
        }
    }

    private func remoteHostConnectionKey(for host: HolyRemoteHostRecord) -> String {
        let destination = host.sshDestination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destination.isEmpty else { return "manual:\(host.id.uuidString)" }

        let candidates = [
            host.label,
            destination,
            destination.components(separatedBy: ".").first ?? destination,
        ]

        if let firstUsefulToken = candidates
            .flatMap(\.holyConnectionTokenSet)
            .first(where: { !Self.remoteHostIgnoredConnectionTokens.contains($0) }) {
            return firstUsefulToken
        }

        return destination.holyMachineIdentityKey.nilIfBlank ?? destination.lowercased()
    }

    private func mergedRemoteHost(
        _ lhs: HolyRemoteHostRecord,
        _ rhs: HolyRemoteHostRecord,
        connectionKey: String
    ) -> HolyRemoteHostRecord {
        let preferred = preferredRemoteHost(lhs, rhs)
        let fallback = preferred.id == lhs.id ? rhs : lhs

        return canonicalRemoteHost(
            HolyRemoteHostRecord(
                id: preferred.id,
                label: preferred.label,
                sshDestination: preferred.sshDestination,
                tmuxSocketName: preferred.tmuxSocketName ?? fallback.tmuxSocketName,
                createdAt: min(lhs.createdAt, rhs.createdAt),
                updatedAt: max(lhs.updatedAt, rhs.updatedAt),
                lastDiscoveredAt: latestDate(lhs.lastDiscoveredAt, rhs.lastDiscoveredAt)
            ),
            connectionKey: connectionKey
        )
    }

    private func canonicalRemoteHost(
        _ host: HolyRemoteHostRecord,
        connectionKey: String
    ) -> HolyRemoteHostRecord {
        host.normalized()
    }

    private func preferredRemoteHost(
        _ lhs: HolyRemoteHostRecord,
        _ rhs: HolyRemoteHostRecord
    ) -> HolyRemoteHostRecord {
        remoteHostPreferenceScore(lhs) >= remoteHostPreferenceScore(rhs) ? lhs : rhs
    }

    private func remoteHostPreferenceScore(_ host: HolyRemoteHostRecord) -> Int {
        let destination = host.sshDestination.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let label = host.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var score = 0

        if !destination.contains(".tail") { score += 40 }
        if destination == label { score += 30 }
        if !destination.contains("-lan") && !label.contains("-lan") { score += 20 }
        if host.lastDiscoveredAt != nil { score += 10 }
        return score
    }

    private func latestDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return max(lhs, rhs)
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
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

    private func filesystemNamespaceKey(for session: HolySession) -> String? {
        filesystemNamespaceKey(for: session.record.launchSpec)
    }

    private func filesystemNamespaceKey(for launchSpec: HolySessionLaunchSpec) -> String? {
        let transport = launchSpec.transport.normalized
        switch transport.kind {
        case .local:
            return "local"
        case .ssh:
            guard let destination = transport.sshDestination?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfBlank else {
                return nil
            }

            return "ssh:\(destination.lowercased())"
        }
    }

    private func bindSessions(seedMissingAsSeen: Bool = false) {
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
        reconcileAttentionMetadata(markSelectedSeen: false, seedMissingAsSeen: seedMissingAsSeen)
        sessionSupervisor.sessionBindingsDidChange(for: currentSessionStoreState)
    }

    private func handleSessionMutation(for session: HolySession) {
        recomputeCoordination()
        reconcileAttentionMetadata(markSelectedSeen: false)
        if session.id == selectedSessionID {
            scheduleSelectedSessionSeenMark()
        }
        sessionSupervisor.sessionDidMutate(
            session,
            in: currentSessionStoreState,
            attentionBySessionID: coordinationBySessionID.mapValues(\.attention)
        )
    }

    /// Cheap fingerprint of every input `makeCoordination` reads. Terminal
    /// output (scrolling, redraws) churns `HolySession` constantly but never
    /// touches these fields, so when the fingerprint is unchanged we skip the
    /// O(N^2) coordination recompute entirely.
    private var lastCoordinationInputSignature: [String]?

    private func coordinationInputSignature(for session: HolySession) -> String {
        let ownership = session.ownership
        let snapshot = session.gitSnapshot
        return [
            session.id.uuidString,
            String(describing: session.displayRuntime),
            String(describing: ownership.repositoryRoot),
            String(describing: ownership.worktreePath),
            String(describing: ownership.branchName),
            String(describing: snapshot?.repositoryRoot),
            String(describing: snapshot?.changedFiles.map(\.path)),
            String(describing: session.phase),
            title(forSessionID: session.id),
        ].joined(separator: "\u{1E}")
    }

    private func recomputeCoordination() {
        let signature = sessions.map { coordinationInputSignature(for: $0) }
        if let lastCoordinationInputSignature,
           lastCoordinationInputSignature == signature {
            return
        }
        lastCoordinationInputSignature = signature

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
        if session.displayRuntime == .shell {
            return coordinationWithoutOwnershipConflict(for: session)
        }

        let ownership = session.ownership
        let sessionRepositoryRoot = normalizedPath(ownership.repositoryRoot)
        let sessionWorktreePath = normalizedPath(ownership.worktreePath)
        let sessionBranchName = ownership.branchName
        let sessionNamespaceKey = filesystemNamespaceKey(for: session)

        if sessionRepositoryRoot == nil,
           sessionWorktreePath == nil,
           session.gitSnapshot == nil {
            return coordinationWithoutOwnershipConflict(for: session)
        }

        var sharedWorktreeSessionIDs: Set<UUID> = []
        var sharedBranchSessionIDs: Set<UUID> = []
        var overlappingSessionIDs: Set<UUID> = []
        var overlappingFiles: Set<String> = []

        let sessionFiles = Set(session.gitSnapshot?.changedFiles.map(\.path) ?? [])

        for other in sessions where other.id != session.id {
            guard let sessionNamespaceKey,
                  filesystemNamespaceKey(for: other) == sessionNamespaceKey else {
                continue
            }

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

    private func coordinationWithoutOwnershipConflict(for session: HolySession) -> HolySessionCoordination {
        .init(
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

        if context.runtimeActivityKind == .swarming {
            return "Agent swarm is running."
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

private struct HolyLocalTmuxSessionKey: Equatable {
    let tmuxSocketName: String?
    let tmuxSessionName: String

    init?(launchSpec: HolySessionLaunchSpec) {
        guard launchSpec.transport.normalized.kind == .local,
              let tmux = launchSpec.tmux?.normalized,
              let tmuxSessionName = tmux.sessionName?.nilIfBlank else {
            return nil
        }

        self.tmuxSocketName = tmux.socketName?.nilIfBlank
        self.tmuxSessionName = tmuxSessionName
    }
}

private struct HolyRemoteTmuxSessionKey: Equatable {
    let sshDestination: String
    let tmuxSocketName: String?
    let tmuxSessionName: String

    init?(launchSpec: HolySessionLaunchSpec) {
        let transport = launchSpec.transport.normalized
        guard transport.kind == .ssh,
              let sshDestination = transport.sshDestination?.nilIfBlank,
              let tmux = launchSpec.tmux?.normalized,
              let tmuxSessionName = tmux.sessionName?.nilIfBlank else {
            return nil
        }

        self.sshDestination = sshDestination
        self.tmuxSocketName = tmux.socketName?.nilIfBlank
        self.tmuxSessionName = tmuxSessionName
    }
}

private enum HolyTmuxSessionKey: Equatable {
    case local(HolyLocalTmuxSessionKey)
    case remote(HolyRemoteTmuxSessionKey)

    init?(launchSpec: HolySessionLaunchSpec) {
        if let remoteKey = HolyRemoteTmuxSessionKey(launchSpec: launchSpec) {
            self = .remote(remoteKey)
        } else if let localKey = HolyLocalTmuxSessionKey(launchSpec: launchSpec) {
            self = .local(localKey)
        } else {
            return nil
        }
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

private struct HolyTmuxClientDetachCommand: Sendable {
    let executableURL: URL
    let arguments: [String]

    static func command(for launchSpec: HolySessionLaunchSpec) -> Self? {
        let realizedLaunchSpec = HolyTmuxCommandBuilder.realizedLaunchSpec(launchSpec)
        guard realizedLaunchSpec.transport.isRemote,
              let destination = realizedLaunchSpec.transport.sshDestination?.holyTerminatorTrimmed.nilIfEmpty,
              let tmux = realizedLaunchSpec.tmux?.normalized,
              let sessionName = tmux.sessionName?.holyTerminatorTrimmed.nilIfEmpty else {
            return nil
        }

        return make(destination: destination, socketName: tmux.socketName?.holyTerminatorTrimmed.nilIfEmpty, sessionName: sessionName)
    }

    static func make(destination: String, socketName: String?, sessionName: String) -> Self {
        var tmuxArguments = ["tmux"]
        if let socketName {
            tmuxArguments += ["-L", socketName]
        }
        tmuxArguments += ["detach-client", "-s", sessionName]

        return Self(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "ssh",
                "-o", "ConnectTimeout=5",
                "-o", "BatchMode=yes",
                destination,
                "zsh", "-lc", shellCommand(tmuxArguments),
            ]
        )
    }

    func run() -> Bool {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func shellCommand(_ arguments: [String]) -> String {
        arguments.map(posixQuote).joined(separator: " ")
    }

    private static func posixQuote(_ value: String) -> String {
        if value.isEmpty {
            return "''"
        }

        let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }
}

private struct HolyTmuxSessionTitleUpdateCommand: Sendable {
    let executableURL: URL
    let arguments: [String]

    static func command(for launchSpec: HolySessionLaunchSpec, title: String) -> Self? {
        let realizedLaunchSpec = HolyTmuxCommandBuilder.realizedLaunchSpec(launchSpec)
        guard let tmux = realizedLaunchSpec.tmux?.normalized,
              let sessionName = tmux.sessionName?.holyTerminatorTrimmed.nilIfEmpty,
              let title = title.holyTerminatorTrimmed.nilIfEmpty else {
            return nil
        }

        var tmuxArguments = ["tmux"]
        if let socketName = tmux.socketName?.holyTerminatorTrimmed.nilIfEmpty {
            tmuxArguments += ["-L", socketName]
        }
        tmuxArguments += ["set-option", "-q", "-t", sessionName, "@holy_title", title]

        if realizedLaunchSpec.transport.isRemote {
            guard let destination = realizedLaunchSpec.transport.sshDestination?.holyTerminatorTrimmed.nilIfEmpty else {
                return nil
            }

            return Self(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["ssh", destination, "zsh", "-lc", shellCommand(tmuxArguments)]
            )
        }

        return Self(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: tmuxArguments
        )
    }

    func run() -> Bool {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func shellCommand(_ arguments: [String]) -> String {
        arguments.map(posixQuote).joined(separator: " ")
    }

    private static func posixQuote(_ value: String) -> String {
        if value.isEmpty {
            return "''"
        }

        let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }
}

private struct HolyTmuxSessionTerminationCommand: Sendable {
    struct Failure: Error, Sendable {
        let message: String
    }

    let executableURL: URL
    let arguments: [String]

    static func command(for identity: HolyTmuxLiveIdentity) -> Self {
        var tmuxArguments = ["tmux"]
        if let socketName = identity.socketName?.holyTerminatorTrimmed.nilIfEmpty {
            tmuxArguments += ["-L", socketName]
        }
        let exactTarget = "=\(identity.sessionName)"
        let killCommand = shellCommand(tmuxArguments + ["kill-session", "-t", exactTarget])
        let probeCommand = shellCommand(tmuxArguments + ["has-session", "-t", exactTarget])
        let script = verificationScript(killCommand: killCommand, probeCommand: probeCommand)

        if identity.transport.isRemote {
            let destination = identity.transport.sshDestination?.holyTerminatorTrimmed.nilIfEmpty ?? ""

            return Self(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: [
                    "ssh",
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    destination,
                    "zsh", "-lc", posixQuote(script),
                ]
            )
        }

        return Self(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lc", script]
        )
    }

    func run() -> Result<Void, Failure> {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.environment = Self.scrubbedTmuxEnvironment(ProcessInfo.processInfo.environment)
        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminated.signal() }

        do {
            try process.run()
            guard terminated.wait(timeout: .now() + 12) == .success else {
                process.terminate()
                if terminated.wait(timeout: .now() + 1) == .timedOut {
                    Darwin.kill(process.processIdentifier, SIGKILL)
                    _ = terminated.wait(timeout: .now() + 1)
                }
                return .failure(.init(message: "tmux termination timed out after 12 seconds."))
            }
            guard process.terminationStatus == 0 else {
                let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
                let detail = String(data: errorData, encoding: .utf8)?.holyTerminatorTrimmed.nilIfEmpty
                    ?? String(data: outputData, encoding: .utf8)?.holyTerminatorTrimmed.nilIfEmpty
                    ?? "tmux exited with status \(process.terminationStatus)."
                return .failure(.init(message: detail))
            }
            return .success(())
        } catch {
            return .failure(.init(message: error.localizedDescription))
        }
    }

    fileprivate static func scrubbedTmuxEnvironment(_ environment: [String: String]) -> [String: String] {
        var environment = environment
        environment.removeValue(forKey: "TMUX")
        environment.removeValue(forKey: "TMUX_PANE")
        environment.removeValue(forKey: "TMUX_TMPDIR")
        return environment
    }

    private static func shellCommand(_ arguments: [String]) -> String {
        arguments.map(posixQuote).joined(separator: " ")
    }

    private static func verificationScript(killCommand: String, probeCommand: String) -> String {
        """
        unset TMUX TMUX_PANE
        kill_output=$(\(killCommand) 2>&1)
        kill_status=$?
        if (( kill_status != 0 )); then
          if [[ -n "$kill_output" ]]; then printf '%s\n' "$kill_output" >&2; fi
          exit "$kill_status"
        fi
        attempt=0
        while \(probeCommand) >/dev/null 2>&1; do
          attempt=$((attempt + 1))
          if (( attempt >= 20 )); then
            if [[ -n "$kill_output" ]]; then printf '%s\n' "$kill_output" >&2; fi
            printf '%s\n' 'tmux still reports the session after kill verification.' >&2
            exit 1
          fi
          sleep 0.1
        done
        exit 0
        """
    }

    private static func posixQuote(_ value: String) -> String {
        if value.isEmpty {
            return "''"
        }

        let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }
}

private extension String {
    var holyTerminatorTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension HolyWorkspaceStore {
    static let remoteHostIgnoredConnectionTokens: Set<String> = [
        "lan",
        "local",
        "mac",
        "pro",
        "tail",
        "tailscale",
        "ts",
    ]
}

private struct HolyLocalMachineIdentity {
    static let localHostID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let current = HolyLocalMachineIdentity()

    let displayName: String
    private let localKeys: Set<String>

    private init() {
        let processInfo = ProcessInfo.processInfo
        let candidateNames = [
            Self.scutilValue("ComputerName"),
            Self.scutilValue("LocalHostName"),
            Host.current().localizedName,
            processInfo.hostName,
            processInfo.environment["HOSTNAME"],
        ]
        .compactMap { $0?.nilIfBlank }

        displayName = candidateNames.first ?? "This Mac"
        localKeys = Set(candidateNames.compactMap { $0.holyMachineIdentityKey.nilIfBlank })
    }

    func shouldHideAsRemote(_ host: HolyRemoteHostRecord) -> Bool {
        let label = host.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = host.sshDestination.trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredLabel = label.lowercased()
        let loweredDestination = destination.lowercased()

        if loweredLabel == "localhost" || loweredDestination == "localhost" {
            return true
        }

        if ["127.0.0.1", "::1"].contains(loweredDestination) {
            return true
        }

        let isMobileTailnetHost = loweredDestination.contains("iphone") || loweredDestination.contains("ipad")
        if loweredDestination.contains(".tail"),
           isMobileTailnetHost {
            return true
        }

        let hostKeys = [
            label,
            destination,
            destination.components(separatedBy: ".").first ?? destination,
        ]
        .compactMap { $0.holyMachineIdentityKey.nilIfBlank }

        if hostKeys.contains(where: { localKeys.contains($0) }) {
            return true
        }

        return false
    }

    private static func scutilValue(_ key: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
        process.arguments = ["--get", key]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.nilIfBlank
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var nilIfAttentionBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var holyConnectionTokenSet: [String] {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !$0.allSatisfy(\.isNumber) }
    }

    var holyMachineIdentityKey: String {
        holyConnectionTokenSet.joined()
    }
}

private extension HolySessionActivityKind {
    var isActiveWork: Bool {
        switch self {
        case .progress, .swarming, .reading, .editing, .command:
            return true
        case .idle, .approval, .planningQuestion, .stalled, .looping, .failure, .completion:
            return false
        }
    }
}

#if DEBUG
extension HolyWorkspaceStore {
    static func detachCommandArgumentsForTesting(
        destination: String,
        socketName: String?,
        sessionName: String
    ) -> [String] {
        HolyTmuxClientDetachCommand.make(
            destination: destination,
            socketName: socketName,
            sessionName: sessionName
        ).arguments
    }

    static func terminationCommandForTesting(
        launchSpec: HolySessionLaunchSpec
    ) -> (executablePath: String, arguments: [String])? {
        let transport = launchSpec.transport.normalized
        guard let tmux = launchSpec.tmux?.normalized,
              let socketName = tmux.socketName?.holyTerminatorTrimmed.nilIfEmpty,
              let sessionName = tmux.sessionName?.holyTerminatorTrimmed.nilIfEmpty,
              let identity = HolyTmuxLiveIdentity(
                transport: transport,
                socketName: socketName,
                sessionName: sessionName
              ) else {
            return nil
        }
        let command = HolyTmuxSessionTerminationCommand.command(for: identity)
        return (command.executableURL.path, command.arguments)
    }

    static func discoveredTerminationCommandForTesting(
        transport: HolySessionTransportSpec,
        socketName: String?,
        sessionName: String
    ) -> (executablePath: String, arguments: [String])? {
        guard let identity = HolyTmuxLiveIdentity(
            transport: transport,
            socketName: socketName,
            sessionName: sessionName
        ) else { return nil }
        let command = HolyTmuxSessionTerminationCommand.command(for: identity)
        return (command.executableURL.path, command.arguments)
    }

    static func scrubbedTerminationEnvironmentForTesting(
        _ environment: [String: String]
    ) -> [String: String] {
        HolyTmuxSessionTerminationCommand.scrubbedTmuxEnvironment(environment)
    }

    static func canReattachLaunchSpecForTesting(_ launchSpec: HolySessionLaunchSpec) -> Bool {
        canReattachLaunchSpec(launchSpec)
    }

    static func convergeHostKeyForTesting(destination: String, socketName: String?) -> String {
        convergeHostKey(destination: destination, socketName: socketName)
    }

    static func convergeMatchKeyForTesting(hostKey: String, sessionName: String) -> String {
        convergeMatchKey(hostKey: hostKey, sessionName: sessionName)
    }

    static func convergeRosterEntryForTesting(
        sessionID: UUID,
        destination: String,
        socketName: String?,
        sessionName: String,
        title: String? = nil,
        workingDirectory: String? = nil,
        runtime: HolySessionRuntime = .shell,
        localProcessExited: Bool
    ) -> HolyConvergeRosterEntry {
        convergeRosterEntry(
            sessionID: sessionID,
            destination: destination,
            socketName: socketName,
            sessionName: sessionName,
            couldBeHidden: HolyDiscoveredTmuxSession.rosterEntryCouldBeHiddenFromDiscovery(
                sessionName: sessionName,
                title: title,
                workingDirectory: workingDirectory,
                runtime: runtime
            ),
            localProcessExited: localProcessExited
        )
    }

    static func archiveDiscoveryCoveredForTesting(
        _ archivedSession: HolyArchivedSession,
        reachableHostKeys: Set<String>
    ) -> Bool {
        archiveDiscoveryCovered(archivedSession, reachableHostKeys: reachableHostKeys)
    }
}
#endif
