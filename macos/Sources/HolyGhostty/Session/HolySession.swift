import AppKit
import Combine
import Foundation
import GhosttyKit

@MainActor
final class HolySession: ObservableObject, Identifiable {
    let id: UUID
    let surfaceView: Ghostty.SurfaceView

    @Published private(set) var record: HolySessionRecord
    @Published private(set) var phase: HolySessionPhase = .active
    @Published private(set) var preview: String = ""
    @Published private(set) var signals: [HolySessionSignal] = []
    @Published private(set) var commandTelemetry: HolySessionCommandTelemetry = .empty
    @Published private(set) var budgetTelemetry: HolySessionBudgetTelemetry = .empty
    @Published private(set) var runtimeTelemetry: HolySessionRuntimeTelemetry = .empty
    @Published private(set) var gitSnapshot: HolyGitSnapshot?
    @Published private(set) var activityAt: Date
    @Published private(set) var inferredRuntime: HolySessionRuntime?

    private var cancellables: Set<AnyCancellable> = []
    private var gitRefreshTask: Task<Void, Never>?
    private var lastGitRefreshDirectory: String?
    private var lastGitRefreshAt: Date = .distantPast
    private var previewEvidenceSignature: String?
    private var previewEvidenceFirstObservedAt: Date = .now
    private var repeatedPreviewEvidenceCount = 0
    private var visibleActivitySignature: String?
    private var visibleActivityChangedAt: Date = .distantPast
    private var isPresentedInWorkspace = false
    private var surfaceOcclusionVisible: Bool?
    private var lastDerivedStateRefreshAt: Date = .distantPast

    private static let visibleDerivedStateRefreshInterval: TimeInterval = 1.25
    private static let backgroundDerivedStateRefreshInterval: TimeInterval = 15
    private static let activeProgressActivityRefreshInterval: TimeInterval = 10
    private static let visibleGitRefreshInterval: TimeInterval = 10
    private static let backgroundGitRefreshInterval: TimeInterval = 120

    init(record: HolySessionRecord, app: ghostty_app_t) {
        self.id = record.id
        self.record = record
        self.surfaceView = Ghostty.SurfaceView(app, baseConfig: record.launchSpec.surfaceConfiguration, uuid: record.id)
        self.activityAt = record.updatedAt
        surfaceView.setFrameSize(Self.detachedSurfaceFallbackSize)
        surfaceView.sizeDidChange(Self.detachedSurfaceFallbackSize)
        setSurfaceOcclusionVisible(false)
        bind()
        refreshDerivedState(forceGitRefresh: true)
    }

    private static let detachedSurfaceFallbackSize = CGSize(width: 1_240, height: 820)

    var title: String {
        let configured = record.launchSpec.resolvedTitle
        if configured != "Shell" || surfaceView.title.isEmpty {
            return configured
        }

        return surfaceView.title.isEmpty ? configured : surfaceView.title
    }

    var runtime: HolySessionRuntime {
        record.launchSpec.runtime
    }

    var displayRuntime: HolySessionRuntime {
        inferredRuntime ?? runtime
    }

    var displayTitle: String {
        let configured = record.launchSpec.resolvedTitle
        guard Self.isDefaultTitle(configured, for: runtime) else {
            return configured
        }

        // Placeholder/default title. Derive a STABLE name from the session's
        // identity — its repository or working directory — and fall back to the
        // runtime name. Never the live terminal title: agents such as Claude
        // Code rewrite the OSC title to a per-task summary that churns as they
        // work (and produced garbage roster names like "Lives" scraped from
        // on-screen prose).
        if let project = displayProjectName {
            return project
        }

        return displayRuntime.displayName
    }

    var displayLineTitle: String {
        guard let project = displayProjectName,
              !displayTitle.localizedCaseInsensitiveContains(project) else {
            return displayTitle
        }

        return "\(displayTitle) — \(project)"
    }

    var rosterTitleOverride: String? {
        Self.rosterTitleOverride(
            from: record.launchSpec.title,
            runtime: runtime,
            transport: record.launchSpec.transport
        )
    }

    var displayProjectName: String? {
        // Stable identity only — repository name, then working directory.
        // Deliberately NOT inferred from live screen content (it produced
        // churning, wrong names like a word scraped from chat prose).
        if let repositoryName = gitSnapshot?.repositoryName {
            return Self.displayName(fromPathComponent: repositoryName)
        }

        if let directory = workingDirectory {
            return Self.displayName(fromPathComponent: URL(fileURLWithPath: directory).lastPathComponent)
        }

        return nil
    }

    var budget: HolySessionBudget {
        record.launchSpec.budget ?? .none
    }

    var workingDirectory: String? {
        let recordedWorkingDirectory = Self.normalizedMetadataString(record.launchSpec.workingDirectory)
        if prefersTmuxWorkingDirectory,
           let recordedWorkingDirectory {
            return recordedWorkingDirectory
        }

        return surfaceView.pwd ?? recordedWorkingDirectory
    }

    var repositoryName: String? {
        gitSnapshot?.repositoryName
    }

    var branchDisplayName: String {
        gitSnapshot?.branchDisplayName ?? "No Repository"
    }

    var observedBranchName: String? {
        guard let gitSnapshot,
              !gitSnapshot.isDetachedHead else {
            return nil
        }

        let trimmed = gitSnapshot.branch.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var ownership: HolySessionOwnership {
        HolySessionOwnership.derived(
            workspace: record.launchSpec.workspace,
            gitSnapshot: gitSnapshot,
            fallbackWorktreePath: workingDirectory
        )
    }

    var hasBranchOwnershipDrift: Bool {
        ownership.hasDrift(
            observedBranchName: observedBranchName,
            isDetachedHead: gitSnapshot?.isDetachedHead == true
        )
    }

    private var prefersTmuxWorkingDirectory: Bool {
        guard let tmux = record.launchSpec.tmux?.normalized else {
            return false
        }

        return tmux.createIfMissing == false
    }

    var ownershipStatusText: String {
        ownership.branchStatusText(
            observedBranchName: observedBranchName,
            observedBranchDisplayName: branchDisplayName,
            isDetachedHead: gitSnapshot?.isDetachedHead == true
        )
    }

    var changeSummaryText: String {
        gitSnapshot?.changeSummaryText ?? "No git context"
    }

    var commandDisplay: String {
        if let command = record.launchSpec.command, !command.isEmpty {
            return command
        }
        return record.launchSpec.runtime.displayName
    }

    var statusText: String {
        phase.displayName
    }

    var compactStatusText: String {
        switch phase {
        case .active:
            return phase.displayName
        case .working:
            switch runtimeTelemetry.activityKind {
            case .planningQuestion:
                return "Planning"
            case .swarming:
                return "Swarming"
            case .reading:
                return "Reading"
            case .editing:
                return "Editing"
            case .command:
                return "Running"
            case .stalled:
                return "Stalled"
            case .looping:
                return "Looping"
            default:
                return "Working"
            }
        case .waitingInput:
            if runtimeTelemetry.activityKind == .planningQuestion {
                return "Planning"
            }
            return "Needs Input"
        case .completed:
            return "Done"
        case .failed:
            return "Issue"
        }
    }

    var activityHelpText: String {
        guard phase != .active else {
            return "\(displayRuntime.displayName): Ready"
        }

        if phase == .working, runtimeTelemetry.activityKind == .failure {
            return "\(displayRuntime.displayName): Working"
        }

        return Self.normalizedMetadataString(runtimeTelemetry.headline)
            ?? Self.normalizedMetadataString(runtimeTelemetry.detail)
            ?? "\(displayRuntime.displayName): \(compactStatusText)"
    }

    var missionDisplay: String {
        record.launchSpec.objective ?? "No mission defined"
    }

    var budgetStatus: HolySessionBudgetStatus {
        guard budget.isConfigured else { return .none }

        let tokenUtilization = utilization(used: budgetTelemetry.resolvedTotalTokens, limit: budget.tokenLimit)
        let costUtilization = utilization(used: budgetTelemetry.estimatedCostUSD, limit: budget.costLimitUSD)
        let utilization = max(tokenUtilization ?? 0, costUtilization ?? 0)

        if utilization >= 1 {
            return .exceeded
        }

        if utilization >= budget.warningThreshold {
            return .warning
        }

        return .healthy
    }

    var budgetSummaryText: String {
        let parts = [
            budgetTelemetry.resolvedTotalTokens.map(Self.tokenCountText),
            budgetTelemetry.estimatedCostUSD.map(Self.currencyText),
        ].compactMap { $0 }

        if !parts.isEmpty {
            return parts.joined(separator: " · ")
        }

        if budget.isConfigured {
            return "Budget configured, no usage detected yet"
        }

        return "No budget configured"
    }

    var budgetRemainingText: String {
        guard budget.isConfigured else { return "No limit" }

        var parts: [String] = []
        if let tokenLimit = budget.tokenLimit {
            let used = budgetTelemetry.resolvedTotalTokens ?? 0
            let remaining = max(0, tokenLimit - used)
            parts.append("\(Self.tokenCountText(remaining)) left")
        }

        if let costLimitUSD = budget.costLimitUSD {
            let used = budgetTelemetry.estimatedCostUSD ?? 0
            let remaining = max(0, costLimitUSD - used)
            parts.append("\(Self.currencyText(remaining)) left")
        }

        return parts.isEmpty ? "No limit" : parts.joined(separator: " · ")
    }

    var budgetBurnRateText: String {
        let elapsedMinutes = max(1 / 60, activityAt.timeIntervalSince(record.createdAt) / 60)
        var parts: [String] = []

        if let totalTokens = budgetTelemetry.resolvedTotalTokens, totalTokens > 0 {
            parts.append("\(Self.tokenCountText(Int(Double(totalTokens) / elapsedMinutes)))/min")
        }

        if let estimatedCostUSD = budgetTelemetry.estimatedCostUSD, estimatedCostUSD > 0 {
            let hourly = estimatedCostUSD / max(1 / 3600, activityAt.timeIntervalSince(record.createdAt) / 3600)
            parts.append("\(Self.currencyText(hourly))/hr")
        }

        return parts.isEmpty ? "Unknown" : parts.joined(separator: " · ")
    }

    var runtimeTelemetrySummaryText: String? {
        guard runtimeTelemetry.isMeaningful else { return nil }

        var segments: [String] = []
        if let headline = runtimeTelemetry.headline, !headline.isEmpty {
            segments.append(headline)
        }
        if segments.isEmpty, let artifactSummary = runtimeTelemetry.artifactSummary, !artifactSummary.isEmpty {
            segments.append(artifactSummary)
        }
        if segments.isEmpty, let progressPercent = runtimeTelemetry.progressPercent {
            segments.append("\(progressPercent)%")
        }

        if segments.isEmpty, let command = runtimeTelemetry.command, !command.isEmpty {
            segments.append(command)
        }

        if segments.isEmpty,
           let filePath = runtimeTelemetry.filePath,
           !filePath.isEmpty {
            segments.append(filePath)
        }

        if segments.isEmpty,
           let nextStepHint = runtimeTelemetry.nextStepHint,
           !nextStepHint.isEmpty {
            segments.append(nextStepHint)
        }

        return segments.isEmpty ? nil : segments.joined(separator: " · ")
    }

    var primarySignal: HolySessionSignal? {
        signals.first ?? commandTelemetry.recentSignal
    }

    var primarySignalHeadline: String {
        primarySignal?.headline ?? HolySessionAdapterRegistry.adapter(for: displayRuntime).idleHeadline
    }

    var primarySignalDetail: String {
        if let primarySignal {
            return primarySignal.detail
        }

        if preview == "Interactive shell ready." {
            return HolySessionAdapterRegistry.adapter(for: displayRuntime).idleDetail
        }

        return preview
    }

    func rename(to title: String) {
        record.launchSpec.title = title
        markUpdated()
        objectWillChange.send()
    }

    @discardableResult
    func applyDiscoveredLaunchMetadata(
        from launchSpec: HolySessionLaunchSpec,
        refreshGitSnapshot: Bool = true
    ) -> Bool {
        let discoveredLaunchSpec = HolyTmuxCommandBuilder.realizedLaunchSpec(launchSpec)
        var changed = false

        if record.launchSpec.runtime == .shell,
           discoveredLaunchSpec.runtime != .shell {
            record.launchSpec.runtime = discoveredLaunchSpec.runtime
            changed = true
        }

        if let workingDirectory = Self.normalizedMetadataString(discoveredLaunchSpec.workingDirectory),
           Self.normalizedMetadataString(record.launchSpec.workingDirectory) != workingDirectory {
            record.launchSpec.workingDirectory = workingDirectory
            changed = true
        }

        if let title = Self.normalizedMetadataString(discoveredLaunchSpec.title),
           shouldApplyDiscoveredTitle(title) {
            record.launchSpec.title = title
            changed = true
        }

        if let objective = Self.normalizedMetadataString(discoveredLaunchSpec.objective),
           Self.normalizedMetadataString(record.launchSpec.objective) == nil {
            record.launchSpec.objective = objective
            changed = true
        }

        if let command = Self.normalizedMetadataString(discoveredLaunchSpec.command),
           Self.normalizedMetadataString(record.launchSpec.command) == nil {
            record.launchSpec.command = command
            changed = true
        }

        guard changed else { return false }

        markUpdated()
        if refreshGitSnapshot {
            refreshGitSnapshotIfNeeded(force: true)
        }
        objectWillChange.send()
        return true
    }

    private func shouldApplyDiscoveredTitle(_ discoveredTitle: String) -> Bool {
        guard Self.normalizedMetadataString(record.launchSpec.title) != discoveredTitle else {
            return false
        }

        // Never adopt a live agent status line (e.g. "✱ Verify auto-commit") as
        // the persistent session title.
        if Self.isLiveAgentStatusTitle(discoveredTitle) {
            return false
        }

        if Self.isGenericLocalTitle(discoveredTitle, transport: record.launchSpec.transport) {
            return false
        }

        if Self.isDefaultTitle(record.launchSpec.title, for: runtime) ||
            Self.isGenericLocalTitle(record.launchSpec.title, transport: record.launchSpec.transport) {
            return true
        }

        guard let tmux = record.launchSpec.tmux?.normalized,
              tmux.createIfMissing == false else {
            return false
        }

        let currentTitle = record.launchSpec.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentTitle == tmux.sessionName {
            return true
        }

        return currentTitle.contains("/")
    }

    func archiveSnapshot(at archivedAt: Date = .init()) -> HolyArchivedSession {
        HolyArchivedSession(
            sourceSessionID: id,
            record: record,
            phase: phase,
            preview: preview,
            signals: signals,
            commandTelemetry: commandTelemetry,
            budgetTelemetry: budgetTelemetry,
            runtimeTelemetry: runtimeTelemetry,
            gitSnapshot: gitSnapshot,
            lastKnownWorkingDirectory: workingDirectory,
            lastActivityAt: activityAt,
            archivedAt: archivedAt
        )
    }

    func refreshDerivedState(forceGitRefresh: Bool = false) {
        lastDerivedStateRefreshAt = Date()
        let previousPreview = preview
        let previousPhase = phase
        let previousInferredRuntime = inferredRuntime
        let nextPreview = Self.previewText(from: surfaceView.cachedVisibleContents.get())
        if let nextInferredRuntime = Self.inferredRuntime(
            launchRuntime: runtime,
            surfaceTitle: surfaceView.title,
            preview: nextPreview,
            command: record.launchSpec.command,
            initialInput: record.launchSpec.initialInput,
            launchTitle: record.launchSpec.resolvedTitle,
            tmuxSessionName: record.launchSpec.tmux?.sessionName,
            tmuxSocketName: record.launchSpec.tmux?.socketName,
            objective: record.launchSpec.objective
        ),
           inferredRuntime != nextInferredRuntime {
            inferredRuntime = nextInferredRuntime
        }

        let effectiveRuntime = inferredRuntime ?? runtime
        let previewChangedRecently = updateVisibleActivity(for: nextPreview, surfaceTitle: surfaceView.title)
        var nextSignals = Self.detectSignals(
            runtime: effectiveRuntime,
            surfaceView: surfaceView,
            preview: nextPreview,
            previewChangedRecently: previewChangedRecently
        )
        let previewStability = updatePreviewStability(for: nextPreview)
        let nextBudgetTelemetry = HolySessionBudgetParser.updatedTelemetry(
            from: nextPreview,
            current: budgetTelemetry
        )
        let effectiveBudgetTelemetry = nextBudgetTelemetry ?? budgetTelemetry
        if let budgetSignal = Self.budgetSignal(for: budget, telemetry: effectiveBudgetTelemetry) {
            nextSignals.insert(budgetSignal, at: 0)
        }
        let nextPhase = Self.classifyPhase(
            surfaceView: surfaceView,
            signals: nextSignals,
            stability: previewStability
        )
        let nextRuntimeTelemetry = HolySessionRuntimeTelemetryParser.telemetry(
            from: .init(
                runtime: effectiveRuntime,
                surfaceView: surfaceView,
                preview: nextPreview,
                signals: nextSignals,
                phase: nextPhase,
                stability: previewStability
            ),
            current: runtimeTelemetry
        )
        let budgetTelemetryChanged = nextBudgetTelemetry.map { $0 != budgetTelemetry } ?? false
        let runtimeTelemetryChanged = nextRuntimeTelemetry.map { $0 != runtimeTelemetry } ?? false

        if preview != nextPreview {
            preview = nextPreview
        }
        if signals != nextSignals {
            signals = nextSignals
        }
        if phase != nextPhase {
            phase = nextPhase
        }
        if let nextBudgetTelemetry,
           budgetTelemetry != nextBudgetTelemetry {
            budgetTelemetry = nextBudgetTelemetry
        }
        if let nextRuntimeTelemetry,
           runtimeTelemetry != nextRuntimeTelemetry {
            runtimeTelemetry = nextRuntimeTelemetry
        }

        let activeProgressReport = Self.activeProgressReport(from: surfaceView.progressReport)
        let shouldRefreshProgressActivity = activeProgressReport != nil
            && Date().timeIntervalSince(activityAt) >= Self.activeProgressActivityRefreshInterval

        if previousPreview != nextPreview
            || previousPhase != nextPhase
            || previousInferredRuntime != inferredRuntime
            || budgetTelemetryChanged
            || runtimeTelemetryChanged
            || shouldRefreshProgressActivity {
            markUpdated()
        }

        refreshGitSnapshotIfNeeded(force: forceGitRefresh)
    }

    func setPresentedInWorkspace(_ isPresented: Bool) {
        guard isPresentedInWorkspace != isPresented else { return }

        isPresentedInWorkspace = isPresented
        setSurfaceOcclusionVisible(isPresented)
        if isPresented {
            refreshDerivedStateIfNeeded(force: true, forceGitRefresh: true)
        }
    }

    private func bind() {
        surfaceView.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.refreshDerivedState()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .ghosttyCommandDidFinish, object: surfaceView)
            .sink { [weak self] notification in
                self?.recordCommandFinished(from: notification)
            }
            .store(in: &cancellables)

        Timer.publish(every: 1.25, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshDerivedState()
            }
            .store(in: &cancellables)
    }

    private func refreshDerivedStateIfNeeded(force: Bool = false, forceGitRefresh: Bool = false) {
        if !force {
            let minimumInterval = isPresentedInWorkspace
                ? Self.visibleDerivedStateRefreshInterval
                : Self.backgroundDerivedStateRefreshInterval

            guard Date().timeIntervalSince(lastDerivedStateRefreshAt) >= minimumInterval else {
                return
            }
        }

        refreshDerivedState(forceGitRefresh: forceGitRefresh)
    }

    private func setSurfaceOcclusionVisible(_ visible: Bool) {
        guard surfaceOcclusionVisible != visible,
              let surface = surfaceView.surface else {
            return
        }

        ghostty_surface_set_occlusion(surface, visible)
        surfaceOcclusionVisible = visible
    }

    private func recordCommandFinished(from notification: Notification) {
        guard let duration = notification.userInfo?[Notification.Name.CommandDurationKey] as? UInt64 else {
            return
        }

        let exitCodeRaw = notification.userInfo?[Notification.Name.CommandExitCodeKey] as? Int
        let exitCode = exitCodeRaw.flatMap { $0 >= 0 ? $0 : nil }

        commandTelemetry.recordCompletion(
            exitCode: exitCode,
            durationNanoseconds: duration,
            completedAt: .now
        )
        markUpdated()
        objectWillChange.send()
    }

    private func refreshGitSnapshotIfNeeded(force: Bool = false) {
        let currentDirectory = workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines)
        let directoryChanged = currentDirectory != lastGitRefreshDirectory

        if directoryChanged {
            lastGitRefreshDirectory = currentDirectory
            markUpdated()
        }

        let gitRefreshInterval = isPresentedInWorkspace
            ? Self.visibleGitRefreshInterval
            : Self.backgroundGitRefreshInterval

        guard force
            || directoryChanged
            || Date().timeIntervalSince(lastGitRefreshAt) >= gitRefreshInterval else {
            return
        }

        lastGitRefreshAt = .init()
        let transport = record.launchSpec.transport
        gitRefreshTask?.cancel()
        gitRefreshTask = Task { [weak self, currentDirectory, transport] in
            let snapshot = await HolyGitClient.shared.snapshot(for: currentDirectory, transport: transport)
            guard !Task.isCancelled else { return }
            self?.applyGitSnapshot(snapshot)
        }
    }

    private func applyGitSnapshot(_ snapshot: HolyGitSnapshot?) {
        if gitSnapshot != snapshot {
            gitSnapshot = snapshot
            markUpdated()
        }
    }

    private func markUpdated(at date: Date = .init()) {
        activityAt = date
        record.updatedAt = date
    }

    private func updateVisibleActivity(for preview: String, surfaceTitle: String) -> Bool {
        let signature = Self.normalizedVisibleActivitySignature(from: preview, surfaceTitle: surfaceTitle)
        let now = Date()

        guard visibleActivitySignature != nil else {
            visibleActivitySignature = signature
            return false
        }

        if visibleActivitySignature != signature {
            visibleActivitySignature = signature
            visibleActivityChangedAt = now
            return true
        }

        return now.timeIntervalSince(visibleActivityChangedAt) <= Self.agentScreenActivityFreshnessInterval
    }

    private func updatePreviewStability(for preview: String) -> HolySessionPreviewStability {
        let evidence = Self.lastMeaningfulLine(from: preview) ?? preview
        let signature = Self.normalizedEvidenceSignature(from: evidence)

        guard let signature else {
            previewEvidenceSignature = nil
            previewEvidenceFirstObservedAt = .now
            repeatedPreviewEvidenceCount = 0
            return .init(repeatedEvidenceCount: 0, stagnantDuration: 0)
        }

        if previewEvidenceSignature == signature {
            repeatedPreviewEvidenceCount += 1
        } else {
            previewEvidenceSignature = signature
            previewEvidenceFirstObservedAt = .now
            repeatedPreviewEvidenceCount = 1
        }

        return .init(
            repeatedEvidenceCount: repeatedPreviewEvidenceCount,
            stagnantDuration: Date().timeIntervalSince(previewEvidenceFirstObservedAt)
        )
    }

    private func utilization(used: Int?, limit: Int?) -> Double? {
        guard let used, let limit, limit > 0 else { return nil }
        return Double(used) / Double(limit)
    }

    private func utilization(used: Double?, limit: Double?) -> Double? {
        guard let used, let limit, limit > 0 else { return nil }
        return used / limit
    }

    private static func utilization(used: Int?, limit: Int?) -> Double? {
        guard let used, let limit, limit > 0 else { return nil }
        return Double(used) / Double(limit)
    }

    private static func utilization(used: Double?, limit: Double?) -> Double? {
        guard let used, let limit, limit > 0 else { return nil }
        return used / limit
    }

    private static func previewText(from content: String) -> String {
        let trimmed = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .suffix(8)
            .joined(separator: "\n")
        return trimmed.isEmpty ? "Interactive shell ready." : trimmed
    }

    private static func classifyPhase(
        surfaceView: Ghostty.SurfaceView,
        signals: [HolySessionSignal],
        stability: HolySessionPreviewStability
    ) -> HolySessionPhase {
        if surfaceView.processExited {
            if signals.contains(where: { $0.kind == .failure }) {
                return .failed
            }
            return .completed
        }

        if activeProgressReport(from: surfaceView.progressReport) != nil {
            return .working
        }

        if signals.contains(where: { $0.kind == .progress }) {
            return .working
        }

        if signals.contains(where: { $0.kind == .failure }) {
            return .failed
        }

        if signals.contains(where: { $0.kind == .approval }) {
            return .waitingInput
        }

        if signals.contains(where: {
            switch $0.kind {
            case .reading, .editing, .command:
                return true
            default:
                return false
            }
        }) {
            if stability.repeatedEvidenceCount <= 2 || stability.stagnantDuration < 8 {
                return .working
            }
        }

        if signals.contains(where: { $0.kind == .completion }) {
            return .completed
        }

        return .active
    }

    private static func detectSignals(
        runtime: HolySessionRuntime,
        surfaceView: Ghostty.SurfaceView,
        preview: String,
        previewChangedRecently: Bool = false
    ) -> [HolySessionSignal] {
        let adapter = HolySessionAdapterRegistry.adapter(for: runtime)
        let evidence = lastMeaningfulLine(from: preview) ?? preview
        let activePreview = recentMeaningfulLines(from: preview, maxCount: 3).joined(separator: "\n")
        let lowerActivePreview = activePreview.lowercased()
        let evidenceLooksReady = isReadyLine(evidence)
        let meaningfulLines = recentMeaningfulLines(from: preview, maxCount: 14)
        let swarmEvidence = agentSwarmEvidence(
            runtime: runtime,
            lines: meaningfulLines,
            previewChangedRecently: previewChangedRecently
        )
        let liveAgentWorkingEvidence = agentWorkingEvidence(
            runtime: runtime,
            surfaceTitle: surfaceView.title,
            lines: meaningfulLines,
            previewChangedRecently: previewChangedRecently
        )
        let activeProgressReport = activeProgressReport(from: surfaceView.progressReport)
        let hasFreshTerminalActivity = liveAgentWorkingEvidence != nil
            || swarmEvidence != nil
            || activeProgressReport != nil
        var results: [HolySessionSignal] = []

        func append(_ signal: HolySessionSignal) {
            guard !signal.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            guard !results.contains(where: { $0.kind == signal.kind && $0.headline == signal.headline }) else { return }
            results.append(signal)
        }

        if activeProgressReport != nil {
            append(.init(
                kind: .progress,
                headline: progressHeadline(for: activeProgressReport),
                detail: evidence
            ))
        }

        if let swarmEvidence {
            append(.init(
                kind: .progress,
                headline: "\(runtime.displayName) is coordinating a swarm",
                detail: swarmEvidence
            ))
        }

        if let liveAgentWorkingEvidence {
            append(.init(
                kind: .progress,
                headline: "\(runtime.displayName) is working",
                detail: liveAgentWorkingEvidence
            ))
        } else if let planningQuestionEvidence = agentPlanningQuestionEvidence(runtime: runtime, lines: meaningfulLines) {
            append(.init(
                kind: .approval,
                headline: "\(runtime.displayName) has planning questions",
                detail: planningQuestionEvidence
            ))
        } else if let waitingEvidence = agentWaitingEvidence(runtime: runtime, lines: meaningfulLines) {
            append(.init(
                kind: .approval,
                headline: "\(runtime.displayName) is waiting on you",
                detail: waitingEvidence
            ))
        }

        let approvalMarkers = [
            "waiting for input",
            "waiting on your input",
            "needs approval",
            "awaiting approval",
            "press enter",
            "continue?",
            "approve",
            "approval",
            "allow",
            "confirm",
            "[y/n]",
            "(y/n)",
        ] + adapter.approvalMarkers
        if liveAgentWorkingEvidence == nil, approvalMarkers.contains(where: lowerActivePreview.contains) {
            append(.init(
                kind: .approval,
                headline: "\(adapter.runtime.displayName) needs approval or confirmation",
                detail: evidence
            ))
        }

        let failureHeadlines: [(String, String)] = [
            ("build failed", "Build failed"),
            ("test failed", "Tests failed"),
            ("tests failed", "Tests failed"),
            ("failing test", "Tests failed"),
            ("traceback", "Runtime exception reported"),
            ("exception", "Runtime exception reported"),
            ("fatal:", "Fatal error reported"),
            ("error:", "Command reported an error"),
            ("failed with exit code", "Command exited with failure"),
            ("ssh: could not resolve hostname", "SSH host resolution failed"),
            ("host key verification failed", "SSH host verification failed"),
            ("permission denied (publickey", "SSH authentication failed"),
            ("connection timed out", "SSH connection timed out"),
            ("connection refused", "SSH connection refused"),
            ("no server running", "Tmux server not running"),
            ("can't find session", "Tmux session not found"),
            ("no sessions", "Tmux has no sessions"),
        ] + adapter.failureHeadlines
        if liveAgentWorkingEvidence == nil || surfaceView.processExited,
           let failure = failureHeadlines.first(where: { lowerActivePreview.contains($0.0) }) {
            append(.init(kind: .failure, headline: failure.1, detail: evidence))
        }

        let readingMarkers = [
            "reading ",
            "read file",
            "inspecting ",
            "reviewing ",
            "scanning ",
            "searching ",
            "doodling",
        ] + adapter.readingMarkers
        if !evidenceLooksReady,
           hasFreshTerminalActivity,
           readingMarkers.contains(where: lowerActivePreview.contains) {
            append(.init(kind: .reading, headline: "\(adapter.runtime.displayName) is reading code and context", detail: evidence))
        }

        let editingMarkers = [
            "editing ",
            "writing ",
            "apply_patch",
            "patching ",
            "updated ",
            "modifying ",
        ] + adapter.editingMarkers
        if !evidenceLooksReady,
           hasFreshTerminalActivity,
           editingMarkers.contains(where: lowerActivePreview.contains) {
            append(.init(kind: .editing, headline: "\(adapter.runtime.displayName) is editing project files", detail: evidence))
        }

        let commandMarkers = [
            "running ",
            "executing ",
            "xcodebuild",
            "zig build",
            "pytest",
            "npm ",
            "pnpm ",
            "yarn ",
            "git ",
            "bash(",
        ] + adapter.commandMarkers
        if !evidenceLooksReady,
           hasFreshTerminalActivity,
           commandMarkers.contains(where: lowerActivePreview.contains) {
            append(.init(kind: .command, headline: "\(adapter.runtime.displayName) is running commands", detail: evidence))
        }

        let completionMarkers = [
            "task complete",
            "task completed",
            "completed successfully",
            "finished successfully",
            "done",
        ] + adapter.completionMarkers
        if (!evidenceLooksReady && completionMarkers.contains(where: lowerActivePreview.contains)) || surfaceView.processExited {
            append(.init(kind: .completion, headline: "\(adapter.runtime.displayName) session completed", detail: evidence))
        }

        return results.sorted { lhs, rhs in
            rank(for: lhs.kind) < rank(for: rhs.kind)
        }
    }

    private static func budgetSignal(
        for budget: HolySessionBudget,
        telemetry: HolySessionBudgetTelemetry
    ) -> HolySessionSignal? {
        guard budget.isConfigured,
              budget.enforcementPolicy == .requireApproval,
              budgetStatus(for: budget, telemetry: telemetry) == .exceeded else {
            return nil
        }

        let detailParts = [
            telemetry.resolvedTotalTokens.map(tokenCountText),
            telemetry.estimatedCostUSD.map(currencyText),
        ].compactMap { $0 }

        let detail = detailParts.isEmpty
            ? "Budget exceeded. Operator approval is required to continue."
            : "\(detailParts.joined(separator: " · ")) used. Operator approval is required to continue."

        return .init(
            kind: .approval,
            headline: "Budget approval required",
            detail: detail
        )
    }

    private static func progressHeadline(for report: Ghostty.Action.ProgressReport?) -> String {
        guard let report else { return "Progress reported" }

        switch report.state {
        case .remove:
            return "Progress finished"
        case .set:
            if let progress = report.progress {
                return "Progress \(progress)%"
            }
            return "Progress updated"
        case .error:
            return "Progress reported an error"
        case .indeterminate:
            return "Working"
        case .pause:
            return "Progress paused"
        }
    }

    private static func activeProgressReport(
        from report: Ghostty.Action.ProgressReport?
    ) -> Ghostty.Action.ProgressReport? {
        guard let report else { return nil }
        switch report.state {
        case .set, .indeterminate:
            return report
        case .remove, .error, .pause:
            return nil
        }
    }

    private static let agentScreenActivityFreshnessInterval: TimeInterval = 4

    private static let agentSpinnerTitlePrefixes: Set<Character> = [
        "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏",
        "◐", "◓", "◑", "◒"
    ]

    private static func isAgentRuntime(_ runtime: HolySessionRuntime) -> Bool {
        switch runtime {
        case .claude, .codex, .opencode:
            return true
        case .shell:
            return false
        }
    }

    private static func agentWorkingEvidence(
        runtime: HolySessionRuntime,
        surfaceTitle: String,
        lines: [String],
        previewChangedRecently: Bool
    ) -> String? {
        guard isAgentRuntime(runtime), previewChangedRecently else { return nil }

        if let liveStatusEvidence = lines.suffix(8).reversed().first(where: isLiveAgentStatusLine) {
            return liveStatusEvidence
        }

        if previewChangedRecently, isBusyAgentTitle(surfaceTitle) {
            return normalizedTerminalTitle(surfaceTitle) ?? surfaceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard previewChangedRecently else { return nil }

        for line in lines.reversed() where isAgentBusyStatusLine(line) {
            return line
        }

        return nil
    }

    private static func agentSwarmEvidence(
        runtime: HolySessionRuntime,
        lines: [String],
        previewChangedRecently: Bool
    ) -> String? {
        guard isAgentRuntime(runtime), previewChangedRecently else { return nil }

        let recent = Array(lines.suffix(18))
        if let liveLine = recent.reversed().first(where: isLiveAgentSwarmLine) {
            return liveLine
        }

        return recent.reversed().first(where: isAgentSwarmLine)
    }

    private static func isLiveAgentSwarmLine(_ line: String) -> Bool {
        let lower = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.contains("teammates running")
            || lower.contains("show teammates")
            || lower.range(of: #"\b[2-9][0-9]*\s+teammates?\b"#, options: .regularExpression) != nil
    }

    private static func isAgentSwarmLine(_ line: String) -> Bool {
        let lower = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.contains("background agents launched")
            || lower.contains("agents working in parallel")
            || lower.contains("build swarm")
            || lower.contains("agent swarm")
            || lower.range(
                of: #"\b[2-9][0-9]*\s+(background\s+)?agents?\s+(launched|running|working)\b"#,
                options: .regularExpression
            ) != nil
    }

    private static func agentWaitingEvidence(runtime: HolySessionRuntime, lines: [String]) -> String? {
        guard isAgentRuntime(runtime) else { return nil }

        return lines.suffix(8).reversed().first(where: isAgentPromptLine)
    }

    private static func agentPlanningQuestionEvidence(runtime: HolySessionRuntime, lines: [String]) -> String? {
        guard isAgentRuntime(runtime) else { return nil }

        let recent = Array(lines.suffix(16))
        let joined = recent.joined(separator: "\n")
        let lower = joined.lowercased()
        guard lower.contains("planning:")
            || lower.contains("plan mode")
            || lower.contains("enter to select")
            || lower.contains("how should ")
            || lower.contains("questions i need from you") else {
            return nil
        }

        if let questionLine = recent.reversed().first(where: isPlanningQuestionLine) {
            return questionLine
        }

        return recent.reversed().first(where: isPlanningPromptLine)
    }

    private static func isPlanningQuestionLine(_ line: String) -> Bool {
        let lower = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.hasSuffix("?")
            || lower.hasPrefix("how should ")
            || lower.contains("questions i need from you")
    }

    private static func isPlanningPromptLine(_ line: String) -> Bool {
        let lower = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.contains("planning:")
            || lower.contains("plan mode")
            || lower.contains("enter to select")
    }

    private static func isBusyAgentTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if let first = trimmed.first, agentSpinnerTitlePrefixes.contains(first) {
            return true
        }

        let lower = trimmed.lowercased()
        return lower.range(
            of: #"\b(working|thinking|reasoning|running|searching|editing|writing|doodling|tooling)\b"#,
            options: .regularExpression
        ) != nil
    }

    private static func isLiveAgentStatusLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let lower = trimmed.lowercased()
        if lower.contains("esc to interrupt") || lower.contains("ctrl-c to interrupt") || lower.contains("ctrl+c to interrupt") {
            return true
        }

        if lower.contains("thinking with high effort")
            || lower.contains("thinking with medium effort")
            || lower.contains("thinking with low effort")
            || lower.contains("almost done thinking") {
            return true
        }

        return lower.range(
            of: #"\([0-9]+(?:h|m|s)(?:\s+[0-9]+s)?[^)]*\b(thinking|reasoning|working|running|reading|searching|executing|editing|writing|applying|patching|tooling|scaffolding|implementing|installing|creating|fixing)\b"#,
            options: .regularExpression
        ) != nil
    }

    private static func isAgentBusyStatusLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if isLiveAgentStatusLine(trimmed) {
            return true
        }

        let lower = trimmed.lowercased()
        if lower.range(of: #"\bworking\s*\([0-9]"#, options: .regularExpression) != nil {
            return true
        }

        let statusBody = agentStatusBody(from: trimmed)

        return statusBody.range(
            of: #"^\s*(working|thinking|reasoning|reading|searching|running|executing|editing|writing|applying|patching|doodling|tooling|scaffolding|implementing|installing|creating|fixing)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func agentStatusBody(from line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first,
              "•·✻✢⏺●○◐◓◑◒".contains(first) || agentSpinnerTitlePrefixes.contains(first) else {
            return trimmed
        }

        return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isAgentRecentOutputLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 1,
              !isAgentPromptLine(trimmed),
              !isAgentFooterLine(trimmed),
              !isTerminalChromeLine(trimmed) else {
            return false
        }

        return true
    }

    private static func isAgentPromptLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if lower.hasPrefix("? for shortcuts") || lower.contains("new task?") {
            return true
        }

        if trimmed == "›" || trimmed.hasPrefix("› ") {
            return true
        }

        if trimmed == ">" || trimmed.hasPrefix("> ") || trimmed.contains("│ >") {
            return true
        }

        return lower.contains("type a message") || lower.contains("send a message")
    }

    private static func isAgentFooterLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.range(of: #"\bgpt-[0-9a-z][0-9a-z.\-]*\b"#, options: .regularExpression) != nil
            || lower.contains("tokens")
            || lower.contains("context left")
    }

    private static func normalizedVisibleActivitySignature(from preview: String, surfaceTitle: String) -> String? {
        var lines = recentMeaningfulLines(from: preview, maxCount: 16)
        if let title = normalizedTerminalTitle(surfaceTitle) {
            lines.append("title: \(title)")
        }
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }

    private static func lastMeaningfulLine(from preview: String) -> String? {
        recentMeaningfulLines(from: preview, maxCount: .max).last
    }

    private static func recentMeaningfulLines(from preview: String, maxCount: Int) -> [String] {
        preview
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isTerminalChromeLine($0) }
            .suffix(maxCount)
            .map { $0 }
    }

    private static func isTerminalChromeLine(_ line: String) -> Bool {
        isTmuxStatusLine(line) || isSeparatorLine(line)
    }

    private static func isTmuxStatusLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[") else { return false }
        return trimmed.range(
            of: #"\b\d{1,2}:\d{2}\s+\d{2}-[A-Za-z]{3}-\d{2}\b"#,
            options: .regularExpression
        ) != nil
    }

    private static func isSeparatorLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return false }
        return trimmed.allSatisfy { "─━═- ".contains($0) }
    }

    private static func isReadyLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("? for shortcuts") || lower.contains("new task?") {
            return true
        }

        return trimmed.range(
            of: #"(^|\s)[^\n]*[%$#]\s*$"#,
            options: .regularExpression
        ) != nil
    }

    private static func normalizedEvidenceSignature(from evidence: String) -> String? {
        let normalized = evidence
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty,
              normalized != "interactive shell ready." else {
            return nil
        }

        return normalized
    }

    private static func normalizedMetadataString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    private static func isDefaultTitle(_ title: String, for runtime: HolySessionRuntime) -> Bool {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.range(
            of: #"^Shell\s+\d+$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return true
        }

        return normalized.isEmpty
            || normalized == "Shell"
            || normalized == runtime.displayName
    }

    private static func normalizedTerminalTitle(_ title: String) -> String? {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized != "Shell" else {
            return nil
        }

        return normalized
    }

    private static func rosterTitleOverride(
        from title: String,
        runtime: HolySessionRuntime,
        transport: HolySessionTransportSpec
    ) -> String? {
        guard let normalized = normalizedMetadataString(title),
              !isDefaultTitle(normalized, for: runtime),
              !isGenericLocalTitle(normalized, transport: transport),
              !isInternalHolyTmuxTitle(normalized),
              !isLiveAgentStatusTitle(normalized) else {
            return nil
        }

        return displayName(fromPathComponent: normalized) ?? normalized
    }

    /// True when a title is actually an agent's live status line (a Claude/Codex
    /// task summary prefixed with a status glyph like ✱ ✻ ⏺). These churn per
    /// task and must never become a session's persistent name.
    private static func isLiveAgentStatusTitle(_ title: String) -> Bool {
        guard let first = title.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return false
        }
        return "✱✳✻✽✢⏺●○◐◓◑◒•·⠂⠄⠆⠇⠋⠐⠴⠼⠿".contains(first)
    }

    private static func isGenericLocalTitle(_ title: String, transport: HolySessionTransportSpec) -> Bool {
        guard !transport.isRemote else { return false }

        let titleKey = normalizedLocalMachineTitleKey(title)
        guard !titleKey.isEmpty else { return true }

        if genericLocalTitleKeys.contains(titleKey) {
            return true
        }

        return localMachineTitleCandidateKeys.contains(titleKey)
    }

    private static let genericLocalTitleKeys: Set<String> = [
        "local",
        "local mac",
        "mac",
        "machine",
        "this mac",
        "localhost",
    ]

    private static let localMachineTitleCandidateKeys: Set<String> = {
        let processInfo = ProcessInfo.processInfo
        let candidates = [
            Host.current().localizedName,
            processInfo.hostName,
            processInfo.environment["HOSTNAME"],
        ].compactMap { value -> String? in
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty else {
                return nil
            }
            return normalizedLocalMachineTitleKey(trimmed)
        }
        return Set(candidates.filter { !$0.isEmpty })
    }()

    private static func normalizedLocalMachineTitleKey(_ value: String) -> String {
        let scalars = value
            .lowercased()
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }

        return String(scalars)
            .split(separator: " ")
            .joined(separator: " ")
    }

    private static func isInternalHolyTmuxTitle(_ title: String) -> Bool {
        title.range(
            of: #"^holy-[a-z0-9-]+-[0-9A-Fa-f]{8}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func displayName(fromPathComponent component: String) -> String? {
        let normalized = component
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let words = normalized
            .split(separator: " ")
            .map(String.init)
        guard !words.isEmpty else { return nil }

        return words.map { word in
            if word.contains(".") || word == word.uppercased() {
                return word
            }

            return word.prefix(1).uppercased() + String(word.dropFirst())
        }
        .joined(separator: " ")
    }

    private static func inferredAgentProjectName(
        runtime: HolySessionRuntime,
        surfaceTitle: String,
        preview: String
    ) -> String? {
        switch runtime {
        case .claude, .codex, .opencode:
            break
        case .shell:
            return nil
        }

        let evidence = [surfaceTitle, preview]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard !evidence.isEmpty else { return nil }

        var seen: Set<String> = []
        for candidate in inferredAgentProjectCandidates(from: evidence) {
            guard let projectName = normalizedAgentProjectCandidate(candidate) else { continue }
            let key = projectName.lowercased()
            guard seen.insert(key).inserted else { continue }
            return projectName
        }

        return nil
    }

    private static func inferredAgentProjectCandidates(from evidence: String) -> [String] {
        let patterns = [
            #"/Custom[-_]Coding/([A-Za-z][A-Za-z0-9._-]{1,47})(?:[/\s]|$)"#,
            #"(?i)\bon\s+`?([A-Z][A-Za-z0-9._-]{2,47})`?\s+itself\b"#,
            #"(?i)\b(?:in|inside|within|for|on)\s+`?([A-Z][A-Za-z0-9._-]{2,47})`?\s+(?:repo|repository|project|app|codebase|workspace)\b"#,
            #"(?i)\b(?:project|repo|repository|workspace|app)\s+(?:called|named|is|for|on|to)?\s*`?([A-Z][A-Za-z0-9._-]{2,47})`?"#,
            #"`([A-Za-z][A-Za-z0-9._-]{2,47})`\s+(?:repo|repository|project|app|codebase|workspace)\b"#,
        ]

        return patterns.flatMap { capturedMatches(in: evidence, pattern: $0) }
    }

    private static func capturedMatches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let captureRange = match.range(at: 1)
            guard captureRange.location != NSNotFound else { return nil }
            return nsText.substring(with: captureRange)
        }
    }

    private static func normalizedAgentProjectCandidate(_ candidate: String) -> String? {
        var trimCharacters = CharacterSet.whitespacesAndNewlines
        trimCharacters.insert(charactersIn: "`'\".,;:()[]{}<>")

        let trimmed = candidate.trimmingCharacters(in: trimCharacters)
        guard trimmed.count >= 3,
              trimmed.count <= 48,
              trimmed.range(of: #"^[A-Za-z][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil else {
            return nil
        }

        let lower = trimmed.lowercased()
        let ignoredNames: Set<String> = [
            "app",
            "claude",
            "claude.md",
            "codebase",
            "codex",
            "custom",
            "custom_coding",
            "docs",
            "documentation",
            "firebase",
            "ghostty",
            "holy",
            "opencode",
            "project",
            "readme",
            "readme.md",
            "repo",
            "repository",
            "root",
            "shell",
            "supabase",
            "swift",
            "workspace",
        ]
        guard !ignoredNames.contains(lower),
              !lower.hasSuffix(".md"),
              !lower.hasSuffix(".json"),
              !lower.hasSuffix(".swift"),
              !lower.hasSuffix(".txt") else {
            return nil
        }

        return displayName(fromPathComponent: trimmed)
    }

    private static func inferredRuntime(
        launchRuntime: HolySessionRuntime,
        surfaceTitle: String,
        preview: String,
        command: String?,
        initialInput: String?,
        launchTitle: String?,
        tmuxSessionName: String?,
        tmuxSocketName: String?,
        objective: String?
    ) -> HolySessionRuntime? {
        guard launchRuntime == .shell else { return nil }

        let title = surfaceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let launchMetadata = [launchTitle, tmuxSessionName, tmuxSocketName, objective]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n")
        let commandText = [command, initialInput]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n")

        // Launch intent (what was actually started) is authoritative. Screen
        // scrollback is NOT — agents constantly discuss each other by name, so
        // a bare "opencode"/"codex"/"claude" in the chat body must never decide
        // the runtime.
        let launchEvidence = [title, launchMetadata, commandText]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .lowercased()
        let previewEvidence = preview.lowercased()

        if containsOpenCodeMarker(launchEvidence) { return .opencode }
        if containsCodexMarker(launchEvidence) { return .codex }
        if containsClaudeMarker(launchEvidence) { return .claude }

        // Live, structural screen signals (not prose). The Codex model/effort
        // status footer (e.g. "gpt-5.5 xhigh fast") is unambiguous.
        if containsCodexStatusFooter(previewEvidence) { return .codex }

        // Last resort: looser content markers — but never opencode, whose only
        // reliable signal is the launch command.
        if containsClaudeMarker(previewEvidence) { return .claude }
        if containsCodexMarker(previewEvidence) { return .codex }

        return nil
    }

    private static func containsCodexStatusFooter(_ evidence: String) -> Bool {
        evidence.range(
            of: #"\bgpt-[0-9a-z][0-9a-z.\-]*\s+(fast\s+)?(low|medium|high|xhigh)\b"#,
            options: .regularExpression
        ) != nil
    }

    private static func containsClaudeMarker(_ evidence: String) -> Bool {
        evidence.contains("claude code")
            || evidence.contains("claude max")
            || evidence.contains("claude.exe")
            || evidence.contains("claude.md")
            || evidence.contains(".claude")
            || evidence.range(
                of: #"(^|[^a-z])claude([^a-z]|$)"#,
                options: .regularExpression
            ) != nil
    }

    private static func containsCodexMarker(_ evidence: String) -> Bool {
        evidence.contains("openai codex")
            || evidence.contains(" codex ")
            || evidence.hasPrefix("codex ")
            || evidence.hasPrefix("codex-")
            || evidence.range(
                of: #"(^|[^a-z])codex([0-9_-]|[^a-z]|$)"#,
                options: .regularExpression
            ) != nil
            || evidence.range(
                of: #"\bgpt-[0-9a-z][0-9a-z.\-]*\s+(fast\s+)?(low|medium|high|xhigh)\b"#,
                options: .regularExpression
            ) != nil
    }

    private static func containsOpenCodeMarker(_ evidence: String) -> Bool {
        evidence.contains("opencode")
            || evidence.contains("open code")
    }

    private static func budgetStatus(
        for budget: HolySessionBudget,
        telemetry: HolySessionBudgetTelemetry
    ) -> HolySessionBudgetStatus {
        guard budget.isConfigured else { return .none }

        let tokenUtilization = utilization(used: telemetry.resolvedTotalTokens, limit: budget.tokenLimit)
        let costUtilization = utilization(used: telemetry.estimatedCostUSD, limit: budget.costLimitUSD)
        let utilization = max(tokenUtilization ?? 0, costUtilization ?? 0)

        if utilization >= 1 {
            return .exceeded
        }

        if utilization >= budget.warningThreshold {
            return .warning
        }

        return .healthy
    }

    private static func rank(for kind: HolySessionSignalKind) -> Int {
        switch kind {
        case .approval: return 0
        case .progress: return 1
        case .failure: return 2
        case .editing: return 3
        case .command: return 4
        case .reading: return 5
        case .completion: return 6
        case .coordination: return 7
        }
    }

    private static func tokenCountText(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM tokens", Double(value) / 1_000_000)
        }

        if value >= 1_000 {
            return String(format: "%.1fK tokens", Double(value) / 1_000)
        }

        return "\(value) tokens"
    }

    private static func currencyText(_ value: Double) -> String {
        if value >= 100 {
            return String(format: "$%.0f", value)
        }

        if value >= 10 {
            return String(format: "$%.1f", value)
        }

        return String(format: "$%.2f", value)
    }
}
