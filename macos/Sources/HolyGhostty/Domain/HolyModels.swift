import Foundation
import GhosttyKit

enum HolyLocalTmuxDefaults {
    static var workingDirectory: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Custom-Coding", isDirectory: true)
            .path
    }

    static func launchSpec(fallbackTitle: String = "Shell") -> HolySessionLaunchSpec {
        let title = URL(fileURLWithPath: workingDirectory).lastPathComponent.nilIfBlank ?? fallbackTitle
        return .localTmuxClientShell(title: title, workingDirectory: workingDirectory)
    }

    static func ensureDefaultServerStartedIfNeeded() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            "-lc",
            """
            if command -v tmux >/dev/null 2>&1; then
              tmux list-sessions >/dev/null 2>&1 || tmux start-server >/dev/null 2>&1 || true
            fi
            """,
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return
        }
    }
}

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
        case .active: "Ready"
        case .working: "Working"
        case .waitingInput: "Needs Input"
        case .completed: "Complete"
        case .failed: "Issue"
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

/// The complete, user-visible session indicator vocabulary.
///
/// Rich runtime telemetry deliberately does not leak into this enum. Every
/// case answers one question only: active work, human attention, unread work,
/// or age. Adding another glyph requires changing this contract and its tests.
enum HolySessionAttentionKind: String, Codable, Equatable, Hashable, CaseIterable {
    case working
    case needsUser
    case unread
    case usedToday
    case inactive
    case sleeping
}

struct HolySessionAttentionMetadata: Codable, Equatable, Identifiable {
    static let currentSeenTrackingVersion = 1
    static let currentNotificationTrackingVersion = 1

    let sessionID: UUID
    var lastSeenAt: Date?
    var seenEvidenceSignature: String?
    var lastAttentionEvidenceSignature: String?
    var lastAttentionBecameAvailableAt: Date?
    var lastAttentionWasWaiting: Bool?
    var lastAgentFinishedAt: Date?
    var lastAgentFinishedSource: String?
    var lastAgentFinishedReasonCode: String?
    var lastAttentionWasActiveWork: Bool?
    /// Nil identifies rows written while seen tracking was disabled. Restore
    /// baselines those rows once so the hook rollout cannot badge-storm every
    /// historical session.
    var seenTrackingVersion: Int?
    /// The last hook event incorporated into attention metadata. The token is
    /// opaque and contains no prompt or response text.
    var lastAuthoritativeEventID: String?
    var lastAuthoritativeFinishedEventID: String?
    /// Producer and receipt clocks stay separate. Operational leases use the
    /// producer occurrence (clamped against future clock skew); diagnostics
    /// can still explain when Holy actually observed the event.
    var lastAuthoritativeEventOccurredAt: Date?
    var lastAuthoritativeEventObservedAt: Date?
    /// Recency is advanced only by an operator seeing the session or by a
    /// structured harness event. Terminal redraws and screen prose cannot
    /// make an old session look newly used.
    var lastUsedAt: Date?
    /// Persists which actionable producer event has already scheduled an OS
    /// notification, preventing both restart duplicates and offline-event loss.
    var notificationTrackingVersion: Int?
    var notificationTrackingStartedAt: Date?
    var lastNotifiedAuthoritativeEventID: String?
    /// Monotonic producer-order watermark paired with the event ID above.
    /// This prevents an older durable finish register from replaying after a
    /// newer question or failure has already been handled.
    var lastNotifiedEventAtMilliseconds: Int64?
    var updatedAt: Date

    var id: UUID { sessionID }

    init(
        sessionID: UUID,
        lastSeenAt: Date? = nil,
        seenEvidenceSignature: String? = nil,
        lastAttentionEvidenceSignature: String? = nil,
        lastAttentionBecameAvailableAt: Date? = nil,
        lastAttentionWasWaiting: Bool? = nil,
        lastAgentFinishedAt: Date? = nil,
        lastAgentFinishedSource: String? = nil,
        lastAgentFinishedReasonCode: String? = nil,
        lastAttentionWasActiveWork: Bool? = nil,
        seenTrackingVersion: Int? = nil,
        lastAuthoritativeEventID: String? = nil,
        lastAuthoritativeFinishedEventID: String? = nil,
        lastAuthoritativeEventOccurredAt: Date? = nil,
        lastAuthoritativeEventObservedAt: Date? = nil,
        lastUsedAt: Date? = nil,
        notificationTrackingVersion: Int? = nil,
        notificationTrackingStartedAt: Date? = nil,
        lastNotifiedAuthoritativeEventID: String? = nil,
        lastNotifiedEventAtMilliseconds: Int64? = nil,
        updatedAt: Date = .init()
    ) {
        self.sessionID = sessionID
        self.lastSeenAt = lastSeenAt
        self.seenEvidenceSignature = seenEvidenceSignature
        self.lastAttentionEvidenceSignature = lastAttentionEvidenceSignature
        self.lastAttentionBecameAvailableAt = lastAttentionBecameAvailableAt
        self.lastAttentionWasWaiting = lastAttentionWasWaiting
        self.lastAgentFinishedAt = lastAgentFinishedAt
        self.lastAgentFinishedSource = lastAgentFinishedSource
        self.lastAgentFinishedReasonCode = lastAgentFinishedReasonCode
        self.lastAttentionWasActiveWork = lastAttentionWasActiveWork
        self.seenTrackingVersion = seenTrackingVersion
        self.lastAuthoritativeEventID = lastAuthoritativeEventID
        self.lastAuthoritativeFinishedEventID = lastAuthoritativeFinishedEventID
        self.lastAuthoritativeEventOccurredAt = lastAuthoritativeEventOccurredAt
        self.lastAuthoritativeEventObservedAt = lastAuthoritativeEventObservedAt
        self.lastUsedAt = lastUsedAt
        self.notificationTrackingVersion = notificationTrackingVersion
        self.notificationTrackingStartedAt = notificationTrackingStartedAt
        self.lastNotifiedAuthoritativeEventID = lastNotifiedAuthoritativeEventID
        self.lastNotifiedEventAtMilliseconds = lastNotifiedEventAtMilliseconds
        self.updatedAt = updatedAt
    }
}

extension HolySessionAttentionMetadata {
    @discardableResult
    mutating func baselineLegacySeenTracking(at date: Date) -> Bool {
        guard seenTrackingVersion != Self.currentSeenTrackingVersion else { return false }
        seenTrackingVersion = Self.currentSeenTrackingVersion
        lastSeenAt = date
        lastUsedAt = max(lastUsedAt ?? .distantPast, date)
        updatedAt = date
        return true
    }

    @discardableResult
    mutating func baselineNotificationTracking(at date: Date) -> Bool {
        guard notificationTrackingVersion != Self.currentNotificationTrackingVersion else { return false }
        notificationTrackingVersion = Self.currentNotificationTrackingVersion
        notificationTrackingStartedAt = date
        updatedAt = date
        return true
    }

    @discardableResult
    mutating func record(
        envelope: HolyAgentStateEnvelope,
        observedAt: Date
    ) -> Bool {
        guard lastAuthoritativeEventID != envelope.eventIdentity else { return false }
        let occurredAt = min(envelope.occurredAt, observedAt)
        lastAuthoritativeEventID = envelope.eventIdentity
        lastAuthoritativeEventOccurredAt = occurredAt
        lastAuthoritativeEventObservedAt = observedAt
        lastUsedAt = max(lastUsedAt ?? .distantPast, occurredAt)
        lastAttentionWasActiveWork = envelope.lifecycle == .working
        switch envelope.lifecycle {
        case .finished:
            lastAuthoritativeFinishedEventID = envelope.eventIdentity
            lastAgentFinishedAt = occurredAt
            lastAgentFinishedSource = envelope.source
            lastAgentFinishedReasonCode = envelope.reasonCode
        case .working, .needsUser, .failed, .idle, .ended:
            // A question or failure is actionable, but it is not a completed
            // reply. When its operational lease expires it must degrade to
            // recency, never masquerade as the white unread-finish dot.
            break
        }
        updatedAt = observedAt
        return true
    }

    /// Incorporates the independent durable completion register without
    /// replacing the latest lifecycle register (which may already be `ended`).
    @discardableResult
    mutating func recordFinished(
        envelope: HolyAgentStateEnvelope,
        observedAt: Date
    ) -> Bool {
        guard envelope.lifecycle == .finished else {
            return false
        }
        let occurredAt = min(envelope.occurredAt, observedAt)
        if let lastAgentFinishedAt {
            if occurredAt < lastAgentFinishedAt {
                return false
            }
            if occurredAt == lastAgentFinishedAt,
               envelope.eventIdentity <= (lastAuthoritativeFinishedEventID ?? "") {
                return false
            }
        } else if lastAuthoritativeFinishedEventID == envelope.eventIdentity {
            return false
        }

        lastAuthoritativeFinishedEventID = envelope.eventIdentity
        lastAgentFinishedAt = occurredAt
        lastAgentFinishedSource = envelope.source
        lastAgentFinishedReasonCode = envelope.reasonCode
        lastUsedAt = max(lastUsedAt ?? .distantPast, occurredAt)
        updatedAt = observedAt
        return true
    }

    @discardableResult
    mutating func markSeen(at date: Date) -> Bool {
        guard lastSeenAt.map({ $0 < date }) ?? true else { return false }
        lastSeenAt = date
        lastUsedAt = max(lastUsedAt ?? .distantPast, date)
        updatedAt = date
        return true
    }

    /// Operator-initiated "Mark Unread": clears the seen timestamp so the
    /// finished reply reads as unread again. The next genuine visit re-marks
    /// seen through the ordinary event-driven path. Never touches
    /// `lastUsedAt` — marking unread is not using the session.
    @discardableResult
    mutating func markUnread(at date: Date) -> Bool {
        guard lastAgentFinishedAt != nil, lastSeenAt != nil else { return false }
        lastSeenAt = nil
        updatedAt = date
        return true
    }

    var hasUnreadAgentReply: Bool {
        guard let lastAgentFinishedAt else { return false }
        return lastAgentFinishedAt > (lastSeenAt ?? .distantPast)
    }

    /// Advances notification acknowledgement without ever moving backward.
    /// Focused visibility and successful system scheduling both use this same
    /// operation, so an older independent register cannot become a late alert.
    @discardableResult
    mutating func acknowledgeAuthoritativeNotification(
        eventID: String,
        occurredAtMilliseconds: Int64,
        at date: Date
    ) -> Bool {
        if let previousMilliseconds = lastNotifiedEventAtMilliseconds {
            if occurredAtMilliseconds < previousMilliseconds {
                return false
            }
            if occurredAtMilliseconds == previousMilliseconds,
               eventID <= (lastNotifiedAuthoritativeEventID ?? "") {
                return false
            }
        } else if lastNotifiedAuthoritativeEventID == eventID {
            return false
        }

        lastNotifiedAuthoritativeEventID = eventID
        lastNotifiedEventAtMilliseconds = occurredAtMilliseconds
        updatedAt = date
        return true
    }
}

struct HolySessionAttentionPresentation: Equatable {
    let kind: HolySessionAttentionKind
    let symbolName: String
    let title: String
    let detail: String?
    let isProminent: Bool
    let becameAvailableAt: Date?

    var helpText: String {
        guard let detail, !detail.isEmpty else { return title }
        return "\(title): \(detail)"
    }
}

/// Pure evidence consumed by the six-state indicator policy. There is
/// intentionally no preview, title, spinner glyph, or screen-text field here.
struct HolySessionIndicatorEvidence: Equatable {
    let lifecycle: HolyAgentLifecycleState?
    let lifecycleOccurredAt: Date?
    let processExited: Bool
    let lastAgentFinishedAt: Date?
    let lastSeenAt: Date?
    let lastUsedAt: Date
    let now: Date
}

enum HolySessionIndicatorPolicy {
    static let workingLease: TimeInterval = 30 * 60
    static let needsUserLease: TimeInterval = 30 * 60
    static let usedTodayInterval: TimeInterval = 24 * 60 * 60
    static let sleepingInterval: TimeInterval = 48 * 60 * 60

    static func kind(
        for evidence: HolySessionIndicatorEvidence,
        workingLease: TimeInterval = workingLease,
        needsUserLease: TimeInterval = needsUserLease,
        usedTodayInterval: TimeInterval = usedTodayInterval,
        sleepingInterval: TimeInterval = sleepingInterval
    ) -> HolySessionAttentionKind {
        if !evidence.processExited,
           let lifecycle = evidence.lifecycle {
            switch lifecycle {
            case .needsUser, .failed:
                if let occurredAt = evidence.lifecycleOccurredAt {
                    let age = evidence.now.timeIntervalSince(occurredAt)
                    if age >= 0, age < needsUserLease {
                        return .needsUser
                    }
                }
            case .working:
                if let occurredAt = evidence.lifecycleOccurredAt {
                    let age = evidence.now.timeIntervalSince(occurredAt)
                    if age >= 0, age < workingLease {
                        return .working
                    }
                }
            case .finished, .idle, .ended:
                break
            }
        }

        if let finishedAt = evidence.lastAgentFinishedAt,
           finishedAt > (evidence.lastSeenAt ?? .distantPast) {
            return .unread
        }

        let age = max(0, evidence.now.timeIntervalSince(evidence.lastUsedAt))
        if age < usedTodayInterval {
            return .usedToday
        }
        if age < sleepingInterval {
            return .inactive
        }
        return .sleeping
    }
}

struct HolyAgentNotificationEvidence {
    let envelope: HolyAgentStateEnvelope
    let observedAt: Date
    let trackingStartedAt: Date
    let lastNotifiedEventID: String?
    let lastNotifiedOccurredAtMilliseconds: Int64?
    let processExited: Bool
    let now: Date
}

/// Restart-stable notification gate. `trackingStartedAt` is persisted at the
/// first hook-aware launch: older register contents are adopted silently,
/// while events committed during a later app absence still notify once.
enum HolyAgentNotificationPolicy {
    static let requestIdentifierPrefix = "holy-agent|"

    static func requestIdentifier(
        sessionID: UUID,
        envelope: HolyAgentStateEnvelope
    ) -> String {
        requestIdentifier(sessionID: sessionID, eventID: envelope.eventIdentity)
    }

    static func requestIdentifier(
        sessionID: UUID,
        eventID: String
    ) -> String {
        "\(requestIdentifierPrefix)\(sessionID.uuidString)|\(eventID)"
    }

    static func shouldNotify(for evidence: HolyAgentNotificationEvidence) -> Bool {
        let committedAtMilliseconds = committedAtMilliseconds(
            envelope: evidence.envelope,
            observedAt: evidence.observedAt
        )
        let trackingStartedAtMilliseconds = timestampMilliseconds(for: evidence.trackingStartedAt)
        guard committedAtMilliseconds >= trackingStartedAtMilliseconds,
              isAfterAcknowledgement(
                eventID: evidence.envelope.eventIdentity,
                occurredAtMilliseconds: committedAtMilliseconds,
                lastEventID: evidence.lastNotifiedEventID,
                lastOccurredAtMilliseconds: evidence.lastNotifiedOccurredAtMilliseconds
              ) else {
            return false
        }
        switch evidence.envelope.lifecycle {
        case .finished:
            return true
        case .needsUser, .failed:
            guard !evidence.processExited else { return false }
            let age = evidence.now.timeIntervalSince(
                Date(timeIntervalSince1970: TimeInterval(committedAtMilliseconds) / 1_000)
            )
            return age >= 0 && age < HolySessionIndicatorPolicy.needsUserLease
        case .working, .idle, .ended:
            return false
        }
    }

    static func committedAtMilliseconds(
        envelope: HolyAgentStateEnvelope,
        observedAt: Date
    ) -> Int64 {
        min(envelope.occurredAtMilliseconds, timestampMilliseconds(for: observedAt))
    }

    static func timestampMilliseconds(for date: Date) -> Int64 {
        let value = date.timeIntervalSince1970 * 1_000
        guard value.isFinite else { return value.sign == .minus ? Int64.min : Int64.max }
        if value <= Double(Int64.min) { return Int64.min }
        if value >= Double(Int64.max) { return Int64.max }
        return Int64(value.rounded(.down))
    }

    private static func isAfterAcknowledgement(
        eventID: String,
        occurredAtMilliseconds: Int64,
        lastEventID: String?,
        lastOccurredAtMilliseconds: Int64?
    ) -> Bool {
        guard let lastOccurredAtMilliseconds else {
            return eventID != lastEventID
        }
        if occurredAtMilliseconds != lastOccurredAtMilliseconds {
            return occurredAtMilliseconds > lastOccurredAtMilliseconds
        }
        return eventID > (lastEventID ?? "")
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

enum HolySessionBudgetStatus: String, Codable {
    case none
    case healthy
    case warning
    case exceeded

    var displayName: String {
        switch self {
        case .none: "No Budget"
        case .healthy: "Within Budget"
        case .warning: "Budget Watch"
        case .exceeded: "Budget Exceeded"
        }
    }
}

enum HolySessionBudgetEnforcementPolicy: String, Codable, CaseIterable {
    case warn
    case requireApproval

    var displayName: String {
        switch self {
        case .warn:
            return "Warn"
        case .requireApproval:
            return "Require Approval"
        }
    }
}

struct HolySessionBudget: Codable, Equatable {
    var tokenLimit: Int?
    var costLimitUSD: Double?
    var warningThreshold: Double = 0.8
    var enforcementPolicy: HolySessionBudgetEnforcementPolicy = .warn

    static let none = Self()

    var isConfigured: Bool {
        tokenLimit != nil || costLimitUSD != nil
    }
}

struct HolySessionBudgetTelemetry: Codable, Equatable {
    var inputTokens: Int?
    var outputTokens: Int?
    var totalTokens: Int?
    var estimatedCostUSD: Double?
    var lastUpdatedAt: Date?
    var evidence: String?

    static let empty = Self()

    var resolvedTotalTokens: Int? {
        if let totalTokens {
            return totalTokens
        }

        guard inputTokens != nil || outputTokens != nil else { return nil }
        return (inputTokens ?? 0) + (outputTokens ?? 0)
    }

    var hasUsage: Bool {
        resolvedTotalTokens != nil || estimatedCostUSD != nil
    }
}

enum HolySessionActivityKind: String, Codable {
    case idle
    case approval
    case planningQuestion
    case progress
    case swarming
    case reading
    case editing
    case command
    case stalled
    case looping
    case failure
    case completion

    var displayName: String {
        switch self {
        case .idle: "Idle"
        case .approval: "Needs Approval"
        case .planningQuestion: "Planning Questions"
        case .progress: "Progress"
        case .swarming: "Swarming"
        case .reading: "Reading"
        case .editing: "Editing"
        case .command: "Command"
        case .stalled: "Stalled"
        case .looping: "Looping"
        case .failure: "Failure"
        case .completion: "Complete"
        }
    }
}

struct HolySessionRuntimeTelemetry: Codable, Equatable {
    var activityKind: HolySessionActivityKind = .idle
    var headline: String?
    var detail: String?
    var command: String?
    var filePath: String?
    var nextStepHint: String?
    var artifactSummary: String?
    var artifactPath: String?
    var progressPercent: Int?
    var stagnantSeconds: Int?
    var repeatedEvidenceCount: Int?
    var lastUpdatedAt: Date?
    var evidence: String?

    static let empty = Self()

    var isMeaningful: Bool {
        activityKind != .idle
            || headline != nil
            || detail != nil
            || command != nil
            || filePath != nil
            || nextStepHint != nil
            || artifactSummary != nil
            || artifactPath != nil
            || progressPercent != nil
            || stagnantSeconds != nil
            || repeatedEvidenceCount != nil
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
    var budgetTelemetry: HolySessionBudgetTelemetry
    var runtimeTelemetry: HolySessionRuntimeTelemetry
    var gitSnapshot: HolyGitSnapshot?
    var lastKnownWorkingDirectory: String?
    var lastActivityAt: Date
    var archivedAt: Date
    var recoveryReason: String?
    var recoveryCleanupSummary: String?

    init(
        id: UUID = UUID(),
        sourceSessionID: UUID,
        record: HolySessionRecord,
        phase: HolySessionPhase,
        preview: String,
        signals: [HolySessionSignal],
        commandTelemetry: HolySessionCommandTelemetry,
        budgetTelemetry: HolySessionBudgetTelemetry,
        runtimeTelemetry: HolySessionRuntimeTelemetry,
        gitSnapshot: HolyGitSnapshot?,
        lastKnownWorkingDirectory: String?,
        lastActivityAt: Date,
        archivedAt: Date = .init(),
        recoveryReason: String? = nil,
        recoveryCleanupSummary: String? = nil
    ) {
        self.id = id
        self.sourceSessionID = sourceSessionID
        self.record = record
        self.phase = phase
        self.preview = preview
        self.signals = signals
        self.commandTelemetry = commandTelemetry
        self.budgetTelemetry = budgetTelemetry
        self.runtimeTelemetry = runtimeTelemetry
        self.gitSnapshot = gitSnapshot
        self.lastKnownWorkingDirectory = lastKnownWorkingDirectory
        self.lastActivityAt = lastActivityAt
        self.archivedAt = archivedAt
        self.recoveryReason = recoveryReason
        self.recoveryCleanupSummary = recoveryCleanupSummary
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sourceSessionID
        case record
        case phase
        case preview
        case signals
        case commandTelemetry
        case budgetTelemetry
        case runtimeTelemetry
        case gitSnapshot
        case lastKnownWorkingDirectory
        case lastActivityAt
        case archivedAt
        case recoveryReason
        case recoveryCleanupSummary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sourceSessionID = try container.decode(UUID.self, forKey: .sourceSessionID)
        record = try container.decode(HolySessionRecord.self, forKey: .record)
        phase = try container.decode(HolySessionPhase.self, forKey: .phase)
        preview = try container.decodeIfPresent(String.self, forKey: .preview) ?? ""
        signals = try container.decodeIfPresent([HolySessionSignal].self, forKey: .signals) ?? []
        commandTelemetry = try container.decodeIfPresent(HolySessionCommandTelemetry.self, forKey: .commandTelemetry) ?? .empty
        budgetTelemetry = try container.decodeIfPresent(HolySessionBudgetTelemetry.self, forKey: .budgetTelemetry) ?? .empty
        runtimeTelemetry = try container.decodeIfPresent(HolySessionRuntimeTelemetry.self, forKey: .runtimeTelemetry) ?? .empty
        gitSnapshot = try container.decodeIfPresent(HolyGitSnapshot.self, forKey: .gitSnapshot)
        lastKnownWorkingDirectory = try container.decodeIfPresent(String.self, forKey: .lastKnownWorkingDirectory)
        lastActivityAt = try container.decodeIfPresent(Date.self, forKey: .lastActivityAt) ?? record.updatedAt
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt) ?? .init()
        recoveryReason = try container.decodeIfPresent(String.self, forKey: .recoveryReason)
        recoveryCleanupSummary = try container.decodeIfPresent(String.self, forKey: .recoveryCleanupSummary)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sourceSessionID, forKey: .sourceSessionID)
        try container.encode(record, forKey: .record)
        try container.encode(phase, forKey: .phase)
        try container.encode(preview, forKey: .preview)
        try container.encode(signals, forKey: .signals)
        try container.encode(commandTelemetry, forKey: .commandTelemetry)
        try container.encode(budgetTelemetry, forKey: .budgetTelemetry)
        try container.encode(runtimeTelemetry, forKey: .runtimeTelemetry)
        try container.encode(gitSnapshot, forKey: .gitSnapshot)
        try container.encode(lastKnownWorkingDirectory, forKey: .lastKnownWorkingDirectory)
        try container.encode(lastActivityAt, forKey: .lastActivityAt)
        try container.encode(archivedAt, forKey: .archivedAt)
        try container.encodeIfPresent(recoveryReason, forKey: .recoveryReason)
        try container.encodeIfPresent(recoveryCleanupSummary, forKey: .recoveryCleanupSummary)
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

    var relaunchActionTitle: String {
        recoveryReason == nil ? "Relaunch" : "Retry Launch"
    }

    var recoverySuggestedAction: String? {
        guard recoveryReason != nil else { return nil }

        switch record.launchSpec.workspace?.strategy ?? .directDirectory {
        case .createManagedWorktree:
            return "Retry launch after Holy Ghostty repairs or recreates the managed worktree."
        case .attachExistingWorktree:
            return "Repair or recreate the external worktree, then retry launch."
        case .directDirectory:
            return "Restore the missing directory or update the launch path, then retry launch."
        }
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
    var note: String?
    /// Millisecond epoch for the last local or merged note edit. A non-nil
    /// stamp with a nil note is the deletion tombstone used by tmux sync.
    var noteUpdatedAtMilliseconds: Int64?
    /// User-pinned "focus / today" flag. Optional so existing persisted
    /// launch-spec JSON (without this key) still decodes; nil == not focused.
    var isFocused: Bool? = nil
    /// Millisecond epoch for the last Today-pin edit. The flag may be nil while
    /// this stamp remains present, which represents an authoritative unpin.
    var todayPinUpdatedAtMilliseconds: Int64?
    var task: HolyExternalTaskReference?
    var budget: HolySessionBudget?
    var transport: HolySessionTransportSpec
    var tmux: HolySessionTmuxSpec?
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
            note: nil,
            task: nil,
            budget: nil,
            transport: .local,
            tmux: nil,
            workingDirectory: nil,
            command: nil,
            initialInput: nil,
            waitAfterCommand: false,
            environment: [:],
            workspace: nil
        )
    }

    static func interactiveTmuxShell(title: String = "Shell") -> Self {
        var spec = interactiveShell(title: title)
        spec.tmux = .holyManagedDefault
        return spec
    }

    static func localTmuxClientShell(title: String = "Shell", workingDirectory: String) -> Self {
        .init(
            runtime: .shell,
            title: title,
            objective: nil,
            task: nil,
            budget: nil,
            transport: .local,
            tmux: nil,
            workingDirectory: workingDirectory,
            command: "tmux",
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
        note: String? = nil,
        noteUpdatedAtMilliseconds: Int64? = nil,
        isFocused: Bool? = nil,
        todayPinUpdatedAtMilliseconds: Int64? = nil,
        task: HolyExternalTaskReference? = nil,
        budget: HolySessionBudget? = nil,
        transport: HolySessionTransportSpec = .local,
        tmux: HolySessionTmuxSpec? = nil,
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
        self.note = note
        self.noteUpdatedAtMilliseconds = noteUpdatedAtMilliseconds
        self.isFocused = isFocused
        self.todayPinUpdatedAtMilliseconds = todayPinUpdatedAtMilliseconds
        self.task = task
        self.budget = budget
        self.transport = transport
        self.tmux = tmux
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
        self.note = nil
        self.noteUpdatedAtMilliseconds = nil
        self.isFocused = nil
        self.todayPinUpdatedAtMilliseconds = nil
        self.task = nil
        self.budget = nil
        self.transport = .local
        self.tmux = nil
        self.workingDirectory = config.workingDirectory
        self.command = config.command
        self.initialInput = config.initialInput
        self.waitAfterCommand = config.waitAfterCommand
        self.environment = config.environmentVariables
        self.workspace = nil
    }

    var surfaceConfiguration: Ghostty.SurfaceConfiguration {
        HolyTmuxCommandBuilder.surfaceConfiguration(for: self)
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
        copy.note = nil
        copy.noteUpdatedAtMilliseconds = nil
        copy.isFocused = nil
        copy.todayPinUpdatedAtMilliseconds = nil
        copy.task = nil
        copy.workingDirectory = nil
        copy.tmux = copy.tmux?.normalized
        copy.tmux?.sessionName = nil
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

enum HolyPaneLayoutKind: String, Codable, Equatable {
    case single
    case splitRight
    case splitDown
    case triple
    case quad

    var maxPaneCount: Int {
        switch self {
        case .single:
            return 1
        case .splitRight, .splitDown:
            return 2
        case .triple:
            return 3
        case .quad:
            return 4
        }
    }

    var isSplit: Bool {
        self != .single
    }

    static func countToKind(_ paneCount: Int, preserving orientation: HolyPaneLayoutKind = .splitRight) -> Self {
        switch paneCount {
        case ...1:
            return .single
        case 2:
            return orientation == .splitDown ? .splitDown : .splitRight
        case 3:
            return .triple
        default:
            return .quad
        }
    }
}

struct HolyPaneLayout: Codable, Equatable {
    static let maxSlotCount = 4

    var kind: HolyPaneLayoutKind
    var slotSessionIDs: [UUID?]

    static let single = Self(kind: .single, sessionIDs: [])

    var sessionIDs: [UUID] {
        slotSessionIDs.compactMap(\.self)
    }

    var renderedSlotSessionIDs: [UUID?] {
        Array(normalizedSlotStorage().prefix(kind.maxPaneCount))
    }

    var highestOccupiedSlot: Int? {
        normalizedSlotStorage().lastIndex { $0 != nil }.map { $0 + 1 }
    }

    var occupiedSlotCount: Int {
        sessionIDs.count
    }

    init(kind: HolyPaneLayoutKind, sessionIDs: [UUID]) {
        self.kind = kind
        self.slotSessionIDs = Self.slots(fromPackedSessionIDs: sessionIDs)
    }

    init(kind: HolyPaneLayoutKind, slotSessionIDs: [UUID?]) {
        self.kind = kind
        self.slotSessionIDs = Self.normalizedSlotStorage(slotSessionIDs)
    }

    func normalized(
        availableSessionIDs: [UUID],
        selectedSessionID: UUID?,
        fillsEmptySlots: Bool = true
    ) -> Self {
        let available = Set(availableSessionIDs)
        var seenIDs: Set<UUID> = []
        var slots = normalizedSlotStorage().map { candidate -> UUID? in
            guard let candidate,
                  available.contains(candidate),
                  !seenIDs.contains(candidate) else {
                return nil
            }
            seenIDs.insert(candidate)
            return candidate
        }

        if fillsEmptySlots,
           slots.allSatisfy({ $0 == nil }),
           let selectedSessionID,
           available.contains(selectedSessionID) {
            slots[0] = selectedSessionID
            seenIDs.insert(selectedSessionID)
        }

        if fillsEmptySlots,
           slots.allSatisfy({ $0 == nil }),
           let fallback = availableSessionIDs.first {
            slots[0] = fallback
        }

        let resolvedKind = resolvedKind(for: slots)

        return .init(
            kind: resolvedKind,
            slotSessionIDs: slots
        )
    }

    func label(for sessionID: UUID) -> String? {
        guard let slot = slot(for: sessionID) else { return nil }

        switch kind {
        case .single:
            return nil
        case .splitRight:
            return slot == 1 ? "Left" : "Right"
        case .splitDown:
            return slot == 1 ? "Top" : "Bottom"
        case .triple:
            let labels = ["Left", "Top Right", "Bottom Right"]
            return slot <= labels.count ? labels[slot - 1] : nil
        case .quad:
            let labels = ["Top Left", "Top Right", "Bottom Left", "Bottom Right"]
            return slot <= labels.count ? labels[slot - 1] : nil
        }
    }

    func slot(for sessionID: UUID) -> Int? {
        normalizedSlotStorage().firstIndex { $0 == sessionID }.map { $0 + 1 }
    }

    func sessionID(atSlot slot: Int) -> UUID? {
        guard (1...Self.maxSlotCount).contains(slot) else { return nil }
        return normalizedSlotStorage()[slot - 1]
    }

    func assigning(_ sessionID: UUID, toSlot slot: Int) -> Self {
        guard (1...Self.maxSlotCount).contains(slot) else { return self }
        var slots = normalizedSlotStorage().map { $0 == sessionID ? nil : $0 }
        slots[slot - 1] = sessionID
        return Self(kind: resolvedKind(for: slots), slotSessionIDs: slots)
    }

    func removingSession(_ sessionID: UUID) -> Self {
        let slots = normalizedSlotStorage().map { $0 == sessionID ? nil : $0 }
        return Self(kind: resolvedKind(for: slots), slotSessionIDs: slots)
    }

    func removingSlot(_ slot: Int) -> Self {
        guard (1...Self.maxSlotCount).contains(slot) else { return self }
        var slots = normalizedSlotStorage()
        slots[slot - 1] = nil
        return Self(kind: resolvedKind(for: slots), slotSessionIDs: slots)
    }

    func oriented(_ targetKind: HolyPaneLayoutKind) -> Self {
        var slots = normalizedSlotStorage()
        if targetKind.maxPaneCount < Self.maxSlotCount {
            for index in targetKind.maxPaneCount..<Self.maxSlotCount {
                slots[index] = nil
            }
        }
        return Self(kind: targetKind, slotSessionIDs: slots)
    }

    private func resolvedKind(for slots: [UUID?]) -> HolyPaneLayoutKind {
        let normalizedSlots = Self.normalizedSlotStorage(slots)
        guard let highestSlot = normalizedSlots.lastIndex(where: { $0 != nil }).map({ $0 + 1 }) else {
            return .single
        }

        if sessionCount(in: normalizedSlots) <= 1, highestSlot == 1 {
            return .single
        }

        return .countToKind(highestSlot, preserving: kind)
    }

    private func normalizedSlotStorage() -> [UUID?] {
        Self.normalizedSlotStorage(slotSessionIDs)
    }

    private func sessionCount(in slots: [UUID?]) -> Int {
        slots.reduce(0) { count, slot in count + (slot == nil ? 0 : 1) }
    }

    private static func normalizedSlotStorage(_ slots: [UUID?]) -> [UUID?] {
        var result = Array(slots.prefix(maxSlotCount))
        while result.count < maxSlotCount {
            result.append(nil)
        }
        return result
    }

    private static func slots(fromPackedSessionIDs sessionIDs: [UUID]) -> [UUID?] {
        var slots = [UUID?](repeating: nil, count: maxSlotCount)
        for (index, sessionID) in sessionIDs.prefix(maxSlotCount).enumerated() {
            slots[index] = sessionID
        }
        return slots
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case sessionIDs
        case slotSessionIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(HolyPaneLayoutKind.self, forKey: .kind) ?? .single

        if let decodedSlots = try container.decodeIfPresent([UUID?].self, forKey: .slotSessionIDs) {
            slotSessionIDs = Self.normalizedSlotStorage(decodedSlots)
        } else {
            let legacySessionIDs = try container.decodeIfPresent([UUID].self, forKey: .sessionIDs) ?? []
            slotSessionIDs = Self.slots(fromPackedSessionIDs: legacySessionIDs)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(sessionIDs, forKey: .sessionIDs)
        try container.encode(normalizedSlotStorage(), forKey: .slotSessionIDs)
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
    var paneLayout: HolyPaneLayout
    var attentionMetadata: [HolySessionAttentionMetadata]

    static let empty = Self(
        sessions: [],
        selectedSessionID: nil,
        templates: [],
        archivedSessions: [],
        paneLayout: .single,
        attentionMetadata: []
    )

    init(
        sessions: [HolySessionRecord],
        selectedSessionID: UUID?,
        templates: [HolySessionTemplate] = [],
        archivedSessions: [HolyArchivedSession] = [],
        paneLayout: HolyPaneLayout = .single,
        attentionMetadata: [HolySessionAttentionMetadata] = []
    ) {
        self.sessions = sessions
        self.selectedSessionID = selectedSessionID
        self.templates = templates
        self.archivedSessions = archivedSessions
        self.paneLayout = paneLayout
        self.attentionMetadata = attentionMetadata
    }

    private enum CodingKeys: String, CodingKey {
        case sessions
        case selectedSessionID
        case templates
        case archivedSessions
        case paneLayout
        case attentionMetadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessions = try container.decodeIfPresent([HolySessionRecord].self, forKey: .sessions) ?? []
        selectedSessionID = try container.decodeIfPresent(UUID.self, forKey: .selectedSessionID)
        templates = try container.decodeIfPresent([HolySessionTemplate].self, forKey: .templates) ?? []
        archivedSessions = try container.decodeIfPresent([HolyArchivedSession].self, forKey: .archivedSessions) ?? []
        paneLayout = try container.decodeIfPresent(HolyPaneLayout.self, forKey: .paneLayout) ?? .single
        attentionMetadata = try container.decodeIfPresent([HolySessionAttentionMetadata].self, forKey: .attentionMetadata) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessions, forKey: .sessions)
        try container.encode(selectedSessionID, forKey: .selectedSessionID)
        try container.encode(templates, forKey: .templates)
        try container.encode(archivedSessions, forKey: .archivedSessions)
        try container.encode(paneLayout, forKey: .paneLayout)
        try container.encode(attentionMetadata, forKey: .attentionMetadata)
    }
}

struct HolySessionDraft: Equatable {
    var runtime: HolySessionRuntime = .shell
    var title: String = ""
    var objective: String = ""
    var linkedTask: HolyExternalTaskReference?
    var tokenBudget: String = ""
    var costBudgetUSD: String = ""
    var budgetEnforcementPolicy: HolySessionBudgetEnforcementPolicy = .warn
    var transportKind: HolySessionTransportKind = .local
    var remoteHostLabel: String = ""
    var remoteHostDestination: String = ""
    var useTmuxBacking: Bool = false
    var tmuxSocketName: String = HolySessionTmuxSpec.defaultSocketName
    var tmuxSessionName: String = ""
    var tmuxCreateIfMissing: Bool = true
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
        linkedTask = launchSpec.task
        tokenBudget = launchSpec.budget?.tokenLimit.map { String($0) } ?? ""
        costBudgetUSD = launchSpec.budget?.costLimitUSD.map { Self.costString(from: $0) } ?? ""
        budgetEnforcementPolicy = launchSpec.budget?.enforcementPolicy ?? .warn
        transportKind = launchSpec.transport.kind
        remoteHostLabel = launchSpec.transport.hostLabel ?? ""
        remoteHostDestination = launchSpec.transport.sshDestination ?? ""
        let tmuxSpec = launchSpec.tmux?.normalized
        useTmuxBacking = tmuxSpec != nil
        tmuxSocketName = tmuxSpec?.socketName ?? HolySessionTmuxSpec.defaultSocketName
        tmuxSessionName = tmuxSpec?.sessionName ?? ""
        tmuxCreateIfMissing = tmuxSpec?.createIfMissing ?? true
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
            task: linkedTask,
            budget: budget,
            transport: .init(
                kind: transportKind,
                hostLabel: remoteHostLabel.nilIfBlank,
                sshDestination: remoteHostDestination.nilIfBlank
            ),
            tmux: useTmuxBacking ? .init(
                socketName: tmuxSocketName.nilIfBlank,
                sessionName: tmuxSessionName.nilIfBlank,
                createIfMissing: tmuxCreateIfMissing
            ) : nil,
            workingDirectory: workingDirectory.nilIfBlank,
            command: command.nilIfBlank,
            initialInput: initialInput.nilIfBlank,
            waitAfterCommand: waitAfterCommand,
            environment: environment,
            workspace: workspaceSpec
        )
    }

    var workspaceSpec: HolySessionWorkspaceSpec? {
        guard transportKind == .local else {
            return nil
        }

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

    var budget: HolySessionBudget? {
        let tokenLimit = Self.parseInteger(tokenBudget)
        let costLimitUSD = Self.parseCurrency(costBudgetUSD)
        let budget = HolySessionBudget(
            tokenLimit: tokenLimit,
            costLimitUSD: costLimitUSD,
            warningThreshold: 0.8,
            enforcementPolicy: budgetEnforcementPolicy
        )
        return budget.isConfigured ? budget : nil
    }

    var hasValidBudgetInput: Bool {
        if !tokenBudget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           Self.parseInteger(tokenBudget) == nil {
            return false
        }

        if !costBudgetUSD.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           Self.parseCurrency(costBudgetUSD) == nil {
            return false
        }

        return true
    }

    private static func parseInteger(_ value: String) -> Int? {
        let cleaned = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard !cleaned.isEmpty else { return nil }
        return Int(cleaned)
    }

    private static func parseCurrency(_ value: String) -> Double? {
        let cleaned = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }

    private static func costString(from value: Double) -> String {
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }

        return String(format: "%.2f", value)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
