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
    @Published private(set) var gitSnapshot: HolyGitSnapshot?
    @Published private(set) var activityAt: Date

    private var cancellables: Set<AnyCancellable> = []
    private var gitRefreshTask: Task<Void, Never>?
    private var lastGitRefreshDirectory: String?
    private var lastGitRefreshAt: Date = .distantPast

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

    var primarySignal: HolySessionSignal? {
        signals.first ?? commandTelemetry.recentSignal
    }

    var primarySignalHeadline: String {
        primarySignal?.headline ?? HolySessionAdapterRegistry.adapter(for: runtime).idleHeadline
    }

    var primarySignalDetail: String {
        if let primarySignal {
            return primarySignal.detail
        }

        if preview == "Interactive shell ready." {
            return HolySessionAdapterRegistry.adapter(for: runtime).idleDetail
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
            gitSnapshot: gitSnapshot,
            lastKnownWorkingDirectory: workingDirectory,
            lastActivityAt: activityAt,
            archivedAt: archivedAt
        )
    }

    func refreshDerivedState(forceGitRefresh: Bool = false) {
        let previousPreview = preview
        let previousPhase = phase
        let nextPreview = Self.previewText(from: surfaceView.cachedVisibleContents.get())
        let nextSignals = Self.detectSignals(runtime: runtime, surfaceView: surfaceView, preview: nextPreview)
        let nextPhase = Self.classifyPhase(surfaceView: surfaceView, signals: nextSignals)

        preview = nextPreview
        signals = nextSignals
        phase = nextPhase

        if previousPreview != nextPreview || previousPhase != nextPhase || surfaceView.progressReport != nil {
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
        gitRefreshTask?.cancel()
        gitRefreshTask = Task { [weak self, currentDirectory] in
            let snapshot = await HolyGitClient.shared.snapshot(for: currentDirectory)
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
}
