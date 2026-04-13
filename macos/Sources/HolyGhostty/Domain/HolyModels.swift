import Foundation
import GhosttyKit

enum HolySessionRuntime: String, Codable, CaseIterable, Identifiable {
    case shell
    case claude
    case codex
    case opencode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .shell: "Shell"
        case .claude: "Claude"
        case .codex: "Codex"
        case .opencode: "OpenCode"
        }
    }
}

enum HolySessionPhase: String, Codable, CaseIterable {
    case active
    case working
    case waitingInput
    case completed
    case failed

    var displayName: String {
        switch self {
        case .active: "Active"
        case .working: "Working"
        case .waitingInput: "Needs Input"
        case .completed: "Completed"
        case .failed: "Failed"
        }
    }
}

enum HolySessionAttention: String, CaseIterable {
    case none
    case watch
    case needsInput
    case failure
    case conflict
    case done

    var displayName: String {
        switch self {
        case .none: "Calm"
        case .watch: "Watch"
        case .needsInput: "Needs Input"
        case .failure: "Failure"
        case .conflict: "Conflict"
        case .done: "Done"
        }
    }
}

enum HolyLaunchConflictSeverity: String, Equatable {
    case warning
    case blocking

    var displayName: String {
        switch self {
        case .warning: "Warning"
        case .blocking: "Block"
        }
    }
}

enum HolyLaunchConflictKind: String, Equatable {
    case sharedWorktree
    case sharedBranch

    var displayName: String {
        switch self {
        case .sharedWorktree: "Shared Worktree"
        case .sharedBranch: "Shared Branch"
        }
    }
}

struct HolyLaunchConflict: Equatable, Identifiable {
    let kind: HolyLaunchConflictKind
    let severity: HolyLaunchConflictSeverity
    let headline: String
    let detail: String
    let relatedSessionTitles: [String]

    var id: String {
        "\(kind.rawValue):\(headline)"
    }
}

struct HolyLaunchGuardrail: Equatable {
    let conflicts: [HolyLaunchConflict]

    static let clear = Self(conflicts: [])

    var isClear: Bool {
        conflicts.isEmpty
    }

    var hasBlockingConflict: Bool {
        conflicts.contains(where: { $0.severity == .blocking })
    }

    var hasWarningConflict: Bool {
        conflicts.contains(where: { $0.severity == .warning })
    }

    var requiresOverride: Bool {
        !hasBlockingConflict && hasWarningConflict
    }

    var headline: String {
        if hasBlockingConflict {
            return "Launch blocked by active ownership"
        }

        if hasWarningConflict {
            return "Launch review required"
        }

        return "Launch is clear"
    }

    var detail: String {
        if hasBlockingConflict {
            return "This draft targets a worktree that is already active. Archive the current owner or choose a different worktree."
        }

        if hasWarningConflict {
            return "This draft would share branch ownership with an active session. Continue only if you want overlapping branch responsibility."
        }

        return "No active launch conflicts were detected."
    }

    var overrideLabel: String {
        "Allow launch despite shared branch ownership"
    }

    func allowsLaunch(allowOverride: Bool) -> Bool {
        if hasBlockingConflict {
            return false
        }

        if requiresOverride {
            return allowOverride
        }

        return true
    }
}

enum HolySessionSignalKind: String, Codable, CaseIterable {
    case coordination
    case approval
    case progress
    case reading
    case editing
    case command
    case failure
    case completion

    var displayName: String {
        switch self {
        case .coordination: "Coordination"
        case .approval: "Approval"
        case .progress: "Progress"
        case .reading: "Reading"
        case .editing: "Editing"
        case .command: "Command"
        case .failure: "Failure"
        case .completion: "Completion"
        }
    }
}

struct HolySessionSignal: Codable, Equatable, Identifiable {
    let kind: HolySessionSignalKind
    let headline: String
    let detail: String

    var id: String {
        "\(kind.rawValue):\(headline)"
    }
}

struct HolySessionCommandTelemetry: Codable, Equatable {
    var runCount: Int = 0
    var failureCount: Int = 0
    var lastExitCode: Int?
    var lastDurationNanoseconds: UInt64?
    var lastCompletedAt: Date?

    static let empty = Self()

    var successCount: Int {
        max(0, runCount - failureCount)
    }

    var lastOutcomeText: String {
        guard let lastExitCode else {
            return runCount == 0 ? "No commands finished yet" : "Last command finished"
        }

        if lastExitCode == 0 {
            return "Succeeded"
        }

        return "Failed (\(lastExitCode))"
    }

    var lastDurationText: String {
        guard let lastDurationNanoseconds else { return "Unknown" }

        let nanoseconds = Double(lastDurationNanoseconds)
        let milliseconds = nanoseconds / 1_000_000
        let seconds = nanoseconds / 1_000_000_000

        if seconds >= 60 {
            return String(format: "%.1f min", seconds / 60)
        }

        if seconds >= 1 {
            return String(format: "%.1f s", seconds)
        }

        return String(format: "%.0f ms", milliseconds)
    }

    var recentSignal: HolySessionSignal? {
        guard let lastCompletedAt else { return nil }
        guard Date().timeIntervalSince(lastCompletedAt) <= 30 else { return nil }

        return completionSignal
    }

    var historicalSignal: HolySessionSignal? {
        completionSignal
    }

    private var completionSignal: HolySessionSignal? {
        guard lastCompletedAt != nil else { return nil }

        let detail = "Last command completed in \(lastDurationText)."

        if let lastExitCode {
            if lastExitCode == 0 {
                return .init(
                    kind: .command,
                    headline: "Last command succeeded",
                    detail: detail
                )
            }

            return .init(
                kind: .failure,
                headline: "Last command failed with exit code \(lastExitCode)",
                detail: detail
            )
        }

        return .init(
            kind: .command,
            headline: "Last command finished",
            detail: detail
        )
    }

    mutating func recordCompletion(exitCode: Int?, durationNanoseconds: UInt64, completedAt: Date) {
        runCount += 1
        if let exitCode, exitCode != 0 {
            failureCount += 1
        }
        lastExitCode = exitCode
        lastDurationNanoseconds = durationNanoseconds
        lastCompletedAt = completedAt
    }
}

struct HolyArchivedSession: Codable, Identifiable, Equatable {
    let id: UUID
    let sourceSessionID: UUID
    var record: HolySessionRecord
    var phase: HolySessionPhase
    var preview: String
    var signals: [HolySessionSignal]
    var commandTelemetry: HolySessionCommandTelemetry
    var gitSnapshot: HolyGitSnapshot?
    var lastKnownWorkingDirectory: String?
    var lastActivityAt: Date
    var archivedAt: Date

    init(
        id: UUID = UUID(),
        sourceSessionID: UUID,
        record: HolySessionRecord,
        phase: HolySessionPhase,
        preview: String,
        signals: [HolySessionSignal],
        commandTelemetry: HolySessionCommandTelemetry,
        gitSnapshot: HolyGitSnapshot?,
        lastKnownWorkingDirectory: String?,
        lastActivityAt: Date,
        archivedAt: Date = .init()
    ) {
        self.id = id
        self.sourceSessionID = sourceSessionID
        self.record = record
        self.phase = phase
        self.preview = preview
        self.signals = signals
        self.commandTelemetry = commandTelemetry
        self.gitSnapshot = gitSnapshot
        self.lastKnownWorkingDirectory = lastKnownWorkingDirectory
        self.lastActivityAt = lastActivityAt
        self.archivedAt = archivedAt
    }

    var runtime: HolySessionRuntime {
        record.launchSpec.runtime
    }

    var title: String {
        record.launchSpec.resolvedTitle
    }

    var missionDisplay: String {
        record.launchSpec.objective ?? "No mission defined"
    }

    var workingDirectoryDisplay: String {
        lastKnownWorkingDirectory ?? record.launchSpec.workingDirectory ?? "Unassigned"
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
            fallbackWorktreePath: workingDirectoryDisplay
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

    var primarySignal: HolySessionSignal? {
        signals.first ?? commandTelemetry.historicalSignal
    }
}

enum HolySessionWorkspaceStrategy: String, Codable, CaseIterable, Identifiable {
    case directDirectory
    case attachExistingWorktree
    case createManagedWorktree

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .directDirectory: "Direct Directory"
        case .attachExistingWorktree: "Attach Worktree"
        case .createManagedWorktree: "Create Managed"
        }
    }

    var subtitle: String {
        switch self {
        case .directDirectory:
            return "Launch directly inside the provided working directory."
        case .attachExistingWorktree:
            return "Bind this session to an already existing git worktree."
        case .createManagedWorktree:
            return "Create and own a dedicated git worktree for this session."
        }
    }
}

struct HolySessionWorkspaceSpec: Codable, Equatable {
    var strategy: HolySessionWorkspaceStrategy
    var repositoryRoot: String?
    var branchName: String?
}

struct HolySessionCoordination: Equatable {
    let attention: HolySessionAttention
    let summary: String
    let sharedWorktreeSessionIDs: [UUID]
    let sharedWorktreeSessionTitles: [String]
    let sharedBranchSessionIDs: [UUID]
    let sharedBranchSessionTitles: [String]
    let overlappingSessionIDs: [UUID]
    let overlappingSessionTitles: [String]
    let overlappingFiles: [String]

    static let empty = Self(
        attention: .none,
        summary: "No active coordination issues.",
        sharedWorktreeSessionIDs: [],
        sharedWorktreeSessionTitles: [],
        sharedBranchSessionIDs: [],
        sharedBranchSessionTitles: [],
        overlappingSessionIDs: [],
        overlappingSessionTitles: [],
        overlappingFiles: []
    )

    var hasBlockingConflict: Bool {
        !sharedWorktreeSessionIDs.isEmpty || !overlappingFiles.isEmpty
    }

    var hasSharedBranch: Bool {
        !sharedBranchSessionIDs.isEmpty
    }
}

enum HolySessionOwnershipSource: String, Equatable {
    case directDirectory
    case attachedWorktree
    case managedWorktree

    var displayName: String {
        switch self {
        case .directDirectory: "Direct Directory"
        case .attachedWorktree: "Attached Worktree"
        case .managedWorktree: "Managed Worktree"
        }
    }

    var shortLabel: String {
        switch self {
        case .directDirectory: "Direct"
        case .attachedWorktree: "Attached"
        case .managedWorktree: "Managed"
        }
    }

    var provenanceTitle: String {
        switch self {
        case .directDirectory: "Direct Repository Session"
        case .attachedWorktree: "Attached External Worktree"
        case .managedWorktree: "Holy-Managed Worktree"
        }
    }

    var provenanceDetail: String {
        switch self {
        case .directDirectory:
            return "This session launched directly in a directory and infers ownership from the active repository state."
        case .attachedWorktree:
            return "This session adopted an existing git worktree and treats that worktree and branch as owned while active."
        case .managedWorktree:
            return "Holy Ghostty created this dedicated worktree and reserves its branch for this session while it remains active."
        }
    }

    init(strategy: HolySessionWorkspaceStrategy?) {
        switch strategy {
        case .attachExistingWorktree:
            self = .attachedWorktree
        case .createManagedWorktree:
            self = .managedWorktree
        case .directDirectory, .none:
            self = .directDirectory
        }
    }
}

struct HolySessionOwnership: Equatable {
    let source: HolySessionOwnershipSource
    let repositoryRoot: String?
    let worktreePath: String?
    let branchName: String?

    var label: String {
        source.shortLabel
    }

    var branchDisplayName: String {
        branchName ?? "No Reserved Branch"
    }

    var summary: String {
        if let branchName {
            switch source {
            case .managedWorktree:
                return "Managed branch \(branchName)"
            case .attachedWorktree:
                return "Attached on \(branchName)"
            case .directDirectory:
                return "Direct on \(branchName)"
            }
        }

        switch source {
        case .managedWorktree:
            return "Managed worktree"
        case .attachedWorktree:
            return "Attached worktree"
        case .directDirectory:
            return repositoryRoot == nil ? "Directory session" : "Direct repository session"
        }
    }

    var reservationText: String {
        if let branchName {
            switch source {
            case .managedWorktree:
                return "Branch `\(branchName)` is reserved through a Holy-managed worktree."
            case .attachedWorktree:
                return "Branch `\(branchName)` is treated as owned by this attached worktree while the session is active."
            case .directDirectory:
                return "Branch `\(branchName)` is treated as active ownership for this direct repository session."
            }
        }

        switch source {
        case .managedWorktree:
            return "No reserved branch was recorded for this managed worktree."
        case .attachedWorktree:
            return "No branch ownership could be inferred from the attached worktree."
        case .directDirectory:
            return "No branch ownership is currently visible for this directory session."
        }
    }

    func hasDrift(observedBranchName: String?, isDetachedHead: Bool) -> Bool {
        guard let branchName else { return false }
        if isDetachedHead { return true }
        guard let observedBranchName else { return false }
        return observedBranchName != branchName
    }

    func branchStatusText(
        observedBranchName: String?,
        observedBranchDisplayName: String,
        isDetachedHead: Bool
    ) -> String {
        guard let branchName else {
            return "No reserved branch is currently recorded for this session."
        }

        if isDetachedHead {
            return "Reserved branch `\(branchName)` but the live worktree is currently in Detached HEAD."
        }

        guard let observedBranchName else {
            return "Reserved branch `\(branchName)` is recorded, but no live branch observation is currently available."
        }

        if observedBranchName == branchName {
            return "Reserved branch `\(branchName)` matches the live worktree."
        }

        return "Reserved branch `\(branchName)` but the live worktree reports `\(observedBranchDisplayName)`."
    }

    static func derived(
        workspace: HolySessionWorkspaceSpec?,
        gitSnapshot: HolyGitSnapshot?,
        fallbackWorktreePath: String?
    ) -> Self {
        let observedBranchName: String?
        if let gitSnapshot,
           !gitSnapshot.isDetachedHead {
            let trimmed = gitSnapshot.branch.trimmingCharacters(in: .whitespacesAndNewlines)
            observedBranchName = trimmed.isEmpty ? nil : trimmed
        } else {
            observedBranchName = nil
        }

        return .init(
            source: .init(strategy: workspace?.strategy),
            repositoryRoot: workspace?.repositoryRoot ?? gitSnapshot?.repositoryRoot,
            worktreePath: gitSnapshot?.worktreePath ?? fallbackWorktreePath,
            branchName: workspace?.branchName ?? observedBranchName
        )
    }

    static func preview(
        strategy: HolySessionWorkspaceStrategy,
        repositoryRoot: String?,
        worktreePath: String?,
        branchName: String?
    ) -> Self {
        .init(
            source: .init(strategy: strategy),
            repositoryRoot: repositoryRoot,
            worktreePath: worktreePath,
            branchName: branchName
        )
    }
}

struct HolySessionLaunchSpec: Codable, Equatable {
    var runtime: HolySessionRuntime
    var title: String
    var objective: String?
    var workingDirectory: String?
    var command: String?
    var initialInput: String?
    var waitAfterCommand: Bool
    var environment: [String: String]
    var workspace: HolySessionWorkspaceSpec?

    static func interactiveShell(title: String = "Shell") -> Self {
        .init(
            runtime: .shell,
            title: title,
            objective: nil,
            workingDirectory: nil,
            command: nil,
            initialInput: nil,
            waitAfterCommand: false,
            environment: [:],
            workspace: nil
        )
    }

    init(
        runtime: HolySessionRuntime = .shell,
        title: String,
        objective: String? = nil,
        workingDirectory: String?,
        command: String?,
        initialInput: String?,
        waitAfterCommand: Bool,
        environment: [String: String],
        workspace: HolySessionWorkspaceSpec? = nil
    ) {
        self.runtime = runtime
        self.title = title
        self.objective = objective
        self.workingDirectory = workingDirectory
        self.command = command
        self.initialInput = initialInput
        self.waitAfterCommand = waitAfterCommand
        self.environment = environment
        self.workspace = workspace
    }

    init(config: Ghostty.SurfaceConfiguration, fallbackTitle: String = "Session") {
        self.runtime = .shell
        self.title = fallbackTitle
        self.objective = nil
        self.workingDirectory = config.workingDirectory
        self.command = config.command
        self.initialInput = config.initialInput
        self.waitAfterCommand = config.waitAfterCommand
        self.environment = config.environmentVariables
        self.workspace = nil
    }

    var surfaceConfiguration: Ghostty.SurfaceConfiguration {
        var config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = workingDirectory
        config.command = command
        config.initialInput = initialInput
        config.waitAfterCommand = waitAfterCommand
        config.environmentVariables = environment
        return config
    }

    var resolvedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let workingDirectory, !workingDirectory.isEmpty {
            return URL(fileURLWithPath: workingDirectory).lastPathComponent
        }
        return runtime.displayName
    }

    var normalizedForTemplate: Self {
        var copy = self
        copy.workingDirectory = nil
        if var workspace = copy.workspace {
            workspace.repositoryRoot = nil
            workspace.branchName = nil
            copy.workspace = workspace
        }
        return copy
    }
}

struct HolySessionRecord: Codable, Identifiable, Equatable {
    let id: UUID
    var launchSpec: HolySessionLaunchSpec
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        launchSpec: HolySessionLaunchSpec,
        createdAt: Date = .init(),
        updatedAt: Date = .init()
    ) {
        self.id = id
        self.launchSpec = launchSpec
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct HolySessionTemplate: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var summary: String
    var launchSpec: HolySessionLaunchSpec
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        summary: String,
        launchSpec: HolySessionLaunchSpec,
        createdAt: Date = .init(),
        updatedAt: Date = .init()
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.launchSpec = launchSpec
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var runtime: HolySessionRuntime {
        launchSpec.runtime
    }
}

struct HolyWorkspaceSnapshot: Codable {
    var sessions: [HolySessionRecord]
    var selectedSessionID: UUID?
    var templates: [HolySessionTemplate]
    var archivedSessions: [HolyArchivedSession]

    static let empty = Self(sessions: [], selectedSessionID: nil, templates: [], archivedSessions: [])

    init(
        sessions: [HolySessionRecord],
        selectedSessionID: UUID?,
        templates: [HolySessionTemplate] = [],
        archivedSessions: [HolyArchivedSession] = []
    ) {
        self.sessions = sessions
        self.selectedSessionID = selectedSessionID
        self.templates = templates
        self.archivedSessions = archivedSessions
    }

    private enum CodingKeys: String, CodingKey {
        case sessions
        case selectedSessionID
        case templates
        case archivedSessions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessions = try container.decodeIfPresent([HolySessionRecord].self, forKey: .sessions) ?? []
        selectedSessionID = try container.decodeIfPresent(UUID.self, forKey: .selectedSessionID)
        templates = try container.decodeIfPresent([HolySessionTemplate].self, forKey: .templates) ?? []
        archivedSessions = try container.decodeIfPresent([HolyArchivedSession].self, forKey: .archivedSessions) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessions, forKey: .sessions)
        try container.encode(selectedSessionID, forKey: .selectedSessionID)
        try container.encode(templates, forKey: .templates)
        try container.encode(archivedSessions, forKey: .archivedSessions)
    }
}

struct HolySessionDraft: Equatable {
    var runtime: HolySessionRuntime = .shell
    var title: String = ""
    var objective: String = ""
    var workspaceStrategy: HolySessionWorkspaceStrategy = .directDirectory
    var workingDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    var repositoryRoot: String = FileManager.default.homeDirectoryForCurrentUser.path
    var branchName: String = ""
    var command: String = ""
    var initialInput: String = ""
    var waitAfterCommand: Bool = false
    var environment: [String: String] = [:]
    var allowOwnershipCollision: Bool = false

    init() {}

    init(
        launchSpec: HolySessionLaunchSpec,
        contextualWorkingDirectory: String?,
        contextualRepositoryRoot: String?
    ) {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        let fallbackWorkingDirectory = contextualWorkingDirectory ?? homeDirectory

        runtime = launchSpec.runtime
        title = launchSpec.title
        objective = launchSpec.objective ?? ""
        workingDirectory = launchSpec.workingDirectory ?? fallbackWorkingDirectory
        command = launchSpec.command ?? ""
        initialInput = launchSpec.initialInput ?? ""
        waitAfterCommand = launchSpec.waitAfterCommand
        environment = launchSpec.environment

        if let workspace = launchSpec.workspace {
            workspaceStrategy = workspace.strategy
            repositoryRoot = workspace.repositoryRoot ?? contextualRepositoryRoot ?? fallbackWorkingDirectory
            branchName = workspace.branchName ?? ""
        } else {
            workspaceStrategy = .directDirectory
            repositoryRoot = contextualRepositoryRoot ?? fallbackWorkingDirectory
            branchName = ""
        }
    }

    var launchSpec: HolySessionLaunchSpec {
        .init(
            runtime: runtime,
            title: title.isEmpty ? runtime.displayName : title,
            objective: objective.nilIfBlank,
            workingDirectory: workingDirectory.nilIfBlank,
            command: command.nilIfBlank,
            initialInput: initialInput.nilIfBlank,
            waitAfterCommand: waitAfterCommand,
            environment: environment,
            workspace: workspaceSpec
        )
    }

    var workspaceSpec: HolySessionWorkspaceSpec? {
        switch workspaceStrategy {
        case .directDirectory:
            return nil
        case .attachExistingWorktree:
            return .init(strategy: .attachExistingWorktree, repositoryRoot: nil, branchName: nil)
        case .createManagedWorktree:
            return .init(
                strategy: .createManagedWorktree,
                repositoryRoot: repositoryRoot.nilIfBlank ?? workingDirectory.nilIfBlank,
                branchName: branchName.nilIfBlank
            )
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
