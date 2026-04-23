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

    init(record: HolySessionRecord, app: ghostty_app_t) {
        self.id = record.id
        self.record = record
        self.surfaceView = Ghostty.SurfaceView(app, baseConfig: record.launchSpec.surfaceConfiguration, uuid: record.id)
        self.activityAt = record.updatedAt
        bind()
        refreshDerivedState(forceGitRefresh: true)
    }

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

        if let terminalTitle = Self.normalizedTerminalTitle(surfaceView.title),
           Self.inferredRuntime(
               launchRuntime: runtime,
               surfaceTitle: terminalTitle,
               preview: "",
               command: nil,
               initialInput: nil
           ) == displayRuntime {
            return terminalTitle
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

    var displayProjectName: String? {
        if let repositoryName = gitSnapshot?.repositoryName {
            return repositoryName
        }

        if let directory = workingDirectory {
            return URL(fileURLWithPath: directory).lastPathComponent
        }

        return nil
    }

    var budget: HolySessionBudget {
        record.launchSpec.budget ?? .none
    }

    var workingDirectory: String? {
        surfaceView.pwd ?? record.launchSpec.workingDirectory
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
        let previousPreview = preview
        let previousPhase = phase
        let previousInferredRuntime = inferredRuntime
        let nextPreview = Self.previewText(from: surfaceView.cachedVisibleContents.get())
        if let nextInferredRuntime = Self.inferredRuntime(
            launchRuntime: runtime,
            surfaceTitle: surfaceView.title,
            preview: nextPreview,
            command: record.launchSpec.command,
            initialInput: record.launchSpec.initialInput
        ) {
            inferredRuntime = nextInferredRuntime
        }

        let effectiveRuntime = inferredRuntime ?? runtime
        var nextSignals = Self.detectSignals(runtime: effectiveRuntime, surfaceView: surfaceView, preview: nextPreview)
        let previewStability = updatePreviewStability(for: nextPreview)
        let nextBudgetTelemetry = HolySessionBudgetParser.updatedTelemetry(
            from: nextPreview,
            current: budgetTelemetry
        )
        let effectiveBudgetTelemetry = nextBudgetTelemetry ?? budgetTelemetry
        if let budgetSignal = Self.budgetSignal(for: budget, telemetry: effectiveBudgetTelemetry) {
            nextSignals.insert(budgetSignal, at: 0)
        }
        let nextPhase = Self.classifyPhase(surfaceView: surfaceView, signals: nextSignals)
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

        preview = nextPreview
        signals = nextSignals
        phase = nextPhase
        if let nextBudgetTelemetry {
            budgetTelemetry = nextBudgetTelemetry
        }
        if let nextRuntimeTelemetry {
            runtimeTelemetry = nextRuntimeTelemetry
        }

        if previousPreview != nextPreview
            || previousPhase != nextPhase
            || previousInferredRuntime != inferredRuntime
            || nextBudgetTelemetry != nil
            || nextRuntimeTelemetry != nil
            || surfaceView.progressReport != nil {
            markUpdated()
        }

        refreshGitSnapshotIfNeeded(force: forceGitRefresh)
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

        guard force
            || directoryChanged
            || Date().timeIntervalSince(lastGitRefreshAt) >= 2.5 else {
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
        signals: [HolySessionSignal]
    ) -> HolySessionPhase {
        if surfaceView.processExited {
            if signals.contains(where: { $0.kind == .failure }) {
                return .failed
            }
            return .completed
        }

        if signals.contains(where: { $0.kind == .failure }) {
            return .failed
        }

        if signals.contains(where: { $0.kind == .approval }) {
            return .waitingInput
        }

        if surfaceView.progressReport != nil {
            return .working
        }

        if signals.contains(where: {
            switch $0.kind {
            case .progress, .reading, .editing, .command:
                return true
            default:
                return false
            }
        }) {
            return .working
        }

        if signals.contains(where: { $0.kind == .completion }) {
            return .completed
        }

        return .active
    }

    private static func detectSignals(
        runtime: HolySessionRuntime,
        surfaceView: Ghostty.SurfaceView,
        preview: String
    ) -> [HolySessionSignal] {
        let adapter = HolySessionAdapterRegistry.adapter(for: runtime)
        let lowerPreview = preview.lowercased()
        let evidence = lastMeaningfulLine(from: preview) ?? preview
        var results: [HolySessionSignal] = []

        func append(_ signal: HolySessionSignal) {
            guard !signal.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            guard !results.contains(where: { $0.kind == signal.kind && $0.headline == signal.headline }) else { return }
            results.append(signal)
        }

        if surfaceView.progressReport != nil {
            append(.init(
                kind: .progress,
                headline: progressHeadline(for: surfaceView.progressReport),
                detail: evidence
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
        if approvalMarkers.contains(where: lowerPreview.contains) {
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
        if let failure = failureHeadlines.first(where: { lowerPreview.contains($0.0) }) {
            append(.init(kind: .failure, headline: failure.1, detail: evidence))
        }

        let readingMarkers = [
            "reading ",
            "read file",
            "inspecting ",
            "reviewing ",
            "scanning ",
            "searching ",
        ] + adapter.readingMarkers
        if readingMarkers.contains(where: lowerPreview.contains) {
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
        if editingMarkers.contains(where: lowerPreview.contains) {
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
        ] + adapter.commandMarkers
        if commandMarkers.contains(where: lowerPreview.contains) {
            append(.init(kind: .command, headline: "\(adapter.runtime.displayName) is running commands", detail: evidence))
        }

        let completionMarkers = [
            "task complete",
            "task completed",
            "completed successfully",
            "finished successfully",
            "done",
        ] + adapter.completionMarkers
        if completionMarkers.contains(where: lowerPreview.contains) || surfaceView.processExited {
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

    private static func lastMeaningfulLine(from preview: String) -> String? {
        preview
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .last(where: { !$0.isEmpty })
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

    private static func isDefaultTitle(_ title: String, for runtime: HolySessionRuntime) -> Bool {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private static func inferredRuntime(
        launchRuntime: HolySessionRuntime,
        surfaceTitle: String,
        preview: String,
        command: String?,
        initialInput: String?
    ) -> HolySessionRuntime? {
        guard launchRuntime == .shell else { return nil }

        let title = surfaceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let commandText = [command, initialInput]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n")
        let evidence = [title, preview, commandText]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .lowercased()

        guard !evidence.isEmpty else { return nil }

        if containsOpenCodeMarker(evidence) {
            return .opencode
        }

        if containsCodexMarker(evidence) {
            return .codex
        }

        if containsClaudeMarker(evidence) {
            return .claude
        }

        return nil
    }

    private static func containsClaudeMarker(_ evidence: String) -> Bool {
        evidence.contains("claude code")
            || evidence.contains("claude max")
            || evidence.contains(" claude ")
            || evidence.hasPrefix("claude ")
            || evidence.hasPrefix("claude-")
    }

    private static func containsCodexMarker(_ evidence: String) -> Bool {
        evidence.contains("openai codex")
            || evidence.contains(" codex ")
            || evidence.hasPrefix("codex ")
            || evidence.hasPrefix("codex-")
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
        case .failure: return 1
        case .progress: return 2
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
