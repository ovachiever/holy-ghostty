import Foundation

/// One exact tmux server whose pane-scoped agent-state options should be read.
///
/// Callers expand any socket probing into explicit endpoints before starting the
/// monitor. That keeps every poll to exactly one `list-panes` command for one
/// host/socket pair instead of re-running the heavyweight discovery pipeline.
struct HolyTmuxAgentStateEndpoint: Hashable, Sendable {
    enum Location: Hashable, Sendable {
        case local
        case remote(sshDestination: String)
    }

    let hostID: UUID
    let hostLabel: String
    let location: Location
    let socketName: String?

    init(
        hostID: UUID,
        hostLabel: String,
        location: Location,
        socketName: String?
    ) {
        self.hostID = hostID
        self.hostLabel = hostLabel
        self.location = location
        self.socketName = socketName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    var pollInterval: TimeInterval {
        switch location {
        case .local:
            1
        case .remote:
            0.75
        }
    }

    var commandTimeout: TimeInterval {
        switch location {
        case .local:
            0.8
        case .remote:
            1.2
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.location == rhs.location
            && lhs.socketName == rhs.socketName
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(location)
        hasher.combine(socketName)
    }
}

/// Stable identity for one observed tmux session.
struct HolyTmuxAgentStateObservationKey: Hashable, Sendable {
    let hostID: UUID
    let socketName: String?
    let sessionName: String
}

/// Integrity result for all pane producers found under one tmux session.
enum HolyTmuxAgentStateObservationIntegrity: String, Equatable, Sendable {
    /// The panes exist, but none has published the reserved option.
    case noState
    /// Every non-empty producer published the same valid envelope.
    case valid
    /// No valid envelope exists and at least one producer value is malformed.
    case invalid
    /// Producers disagree. Consumers must not choose a winner.
    case conflicting
}

/// A grouped, fail-closed observation of every pane producer in one session.
struct HolyTmuxAgentStateObservation: Equatable, Sendable {
    let key: HolyTmuxAgentStateObservationKey
    let observedAt: Date
    let paneIDs: [String]
    let integrity: HolyTmuxAgentStateObservationIntegrity
    let envelope: HolyAgentStateEnvelope?
    /// Independent completion register. A later `ended` or `idle` latest-state
    /// write cannot erase an unread completion while Holy is detached.
    let lastFinishedEnvelope: HolyAgentStateEnvelope?
    /// Preserved only when there is a single unambiguous producer value.
    /// Conflicts intentionally expose neither candidate as authoritative.
    let rawWireValue: String?
    let rawLastFinishedWireValue: String?
}

struct HolyTmuxAgentStateSnapshot: Equatable, Sendable {
    let endpoint: HolyTmuxAgentStateEndpoint
    let observedAt: Date
    let observations: [HolyTmuxAgentStateObservationKey: HolyTmuxAgentStateObservation]
    let failure: HolyTmuxAgentStateMonitorFailure?
}

struct HolyTmuxAgentStateMonitorFailure: Error, Equatable, LocalizedError, Sendable {
    enum Kind: String, Equatable, Sendable {
        case invalidEndpoint
        case launchFailed
        case timedOut
        case commandFailed
        case outputTooLarge
        case malformedOutput
    }

    let kind: Kind
    let context: String

    var errorDescription: String? {
        switch kind {
        case .invalidEndpoint:
            "Invalid tmux agent-state endpoint: \(context)"
        case .launchFailed:
            "Could not launch tmux agent-state inspection: \(context)"
        case .timedOut:
            "Tmux agent-state inspection timed out: \(context)"
        case .commandFailed:
            "Tmux agent-state inspection failed: \(context)"
        case .outputTooLarge:
            "Tmux agent-state inspection exceeded its bounded output limit"
        case .malformedOutput:
            "Tmux agent-state inspection returned malformed grouped output"
        }
    }
}

/// Fast durable-state reader used beside the OSC delivery path.
///
/// The monitor reads every pane on a server in one grouped query. Local
/// endpoints run on a one-second cadence. Remote starts are at most 750
/// ms apart and each read is bounded at 1.2 seconds, keeping a successful
/// durable observation inside the two-second transport target even when the
/// immediate OSC path is unavailable. Polls are sequential and never overlap.
actor HolyTmuxAgentStateMonitor {
    static let shared = HolyTmuxAgentStateMonitor()

    typealias SnapshotSink = @MainActor @Sendable (HolyTmuxAgentStateSnapshot) -> Void
    typealias SnapshotProvider = @Sendable (
        HolyTmuxAgentStateEndpoint
    ) async -> HolyTmuxAgentStateSnapshot

    private static let fieldSeparator = "\u{1F}"
    private static let listPanesFormat =
        "#{session_name}\u{1F}#{pane_id}\u{1F}#{@holy_agent_state_v1}\u{1F}#{@holy_agent_last_finished_v1}"
    private static let maximumOutputBytes = 4 * 1_024 * 1_024
    private static let maximumLineBytes = 2 * 1_024
    private static let maximumPaneRows = 4_096

    private let snapshotProvider: SnapshotProvider?
    private var pollTasks: [HolyTmuxAgentStateEndpoint: Task<Void, Never>] = [:]
    private var configurationGeneration: UInt64 = 0

    init(snapshotProvider: SnapshotProvider? = nil) {
        self.snapshotProvider = snapshotProvider
    }

    deinit {
        for task in pollTasks.values {
            task.cancel()
        }
    }

    /// Starts (or replaces) polling for the exact endpoint set. Duplicate
    /// endpoints collapse through `Set`, guaranteeing one command per server
    /// and cadence.
    func start(
        endpoints: [HolyTmuxAgentStateEndpoint],
        requestedGeneration: UInt64? = nil,
        onSnapshot: @escaping SnapshotSink
    ) {
        let generation = requestedGeneration ?? (configurationGeneration &+ 1)
        // Main-actor callers may enqueue rapid reconfigurations in separate
        // Tasks. Those Tasks can reach this actor out of creation order, so a
        // caller-issued generation is the authority on which set is newest.
        guard generation > configurationGeneration else { return }
        configurationGeneration = generation
        cancelPollTasks()

        for endpoint in Set(endpoints) {
            pollTasks[endpoint] = Task { [weak self] in
                while !Task.isCancelled {
                    let startedAt = Date()
                    guard let snapshot = await self?.snapshot(for: endpoint) else { return }
                    guard await self?.deliver(
                        snapshot,
                        generation: generation,
                        to: onSnapshot
                    ) == true else {
                        return
                    }

                    let elapsed = Date().timeIntervalSince(startedAt)
                    let remaining = max(0.05, endpoint.pollInterval - elapsed)
                    try? await Task.sleep(
                        nanoseconds: UInt64(remaining * 1_000_000_000)
                    )
                }
            }
        }
    }

    func stop() {
        configurationGeneration &+= 1
        cancelPollTasks()
    }

    private func cancelPollTasks() {
        for task in pollTasks.values {
            task.cancel()
        }
        pollTasks.removeAll()
    }

    /// The generation check and callback dispatch are serialized on this
    /// actor. A read from a replaced endpoint set may still finish, but it can
    /// no longer publish into the replacement configuration.
    private func deliver(
        _ snapshot: HolyTmuxAgentStateSnapshot,
        generation: UInt64,
        to onSnapshot: @escaping SnapshotSink
    ) async -> Bool {
        guard generation == configurationGeneration,
              !Task.isCancelled else {
            return false
        }

        await onSnapshot(snapshot)
        return generation == configurationGeneration && !Task.isCancelled
    }

    /// Performs one bounded grouped read and throws on transport failure.
    /// Existing state should remain untouched when this throws.
    func read(
        endpoint: HolyTmuxAgentStateEndpoint
    ) async throws -> [HolyTmuxAgentStateObservationKey: HolyTmuxAgentStateObservation] {
        let observedAt = Date()
        let plan = try Self.commandPlan(for: endpoint)
        let result = await Self.run(plan: plan, timeout: endpoint.commandTimeout)

        switch result {
        case let .completed(stdout, stderr, exitCode, outputOverflowed):
            guard !outputOverflowed else {
                throw HolyTmuxAgentStateMonitorFailure(
                    kind: .outputTooLarge,
                    context: endpoint.hostLabel
                )
            }
            guard exitCode == 0 else {
                let detail = stderr
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(1_024)
                throw HolyTmuxAgentStateMonitorFailure(
                    kind: .commandFailed,
                    context: detail.isEmpty
                        ? "\(endpoint.hostLabel) exited \(exitCode)"
                        : "\(endpoint.hostLabel): \(detail)"
                )
            }
            return try Self.parse(
                stdout: stdout,
                endpoint: endpoint,
                observedAt: observedAt
            )

        case let .launchFailed(description):
            throw HolyTmuxAgentStateMonitorFailure(
                kind: .launchFailed,
                context: "\(endpoint.hostLabel): \(description)"
            )

        case .timedOut:
            throw HolyTmuxAgentStateMonitorFailure(
                kind: .timedOut,
                context: "\(endpoint.hostLabel) after \(endpoint.commandTimeout) seconds"
            )
        }
    }

    private func snapshot(
        for endpoint: HolyTmuxAgentStateEndpoint
    ) async -> HolyTmuxAgentStateSnapshot {
        if let snapshotProvider {
            return await snapshotProvider(endpoint)
        }

        let observedAt = Date()
        do {
            return HolyTmuxAgentStateSnapshot(
                endpoint: endpoint,
                observedAt: observedAt,
                observations: try await read(endpoint: endpoint),
                failure: nil
            )
        } catch let failure as HolyTmuxAgentStateMonitorFailure {
            return HolyTmuxAgentStateSnapshot(
                endpoint: endpoint,
                observedAt: observedAt,
                observations: [:],
                failure: failure
            )
        } catch {
            return HolyTmuxAgentStateSnapshot(
                endpoint: endpoint,
                observedAt: observedAt,
                observations: [:],
                failure: HolyTmuxAgentStateMonitorFailure(
                    kind: .launchFailed,
                    context: "\(endpoint.hostLabel): \(error.localizedDescription)"
                )
            )
        }
    }
}

// MARK: - Command construction and grouped parsing

extension HolyTmuxAgentStateMonitor {
    struct CommandPlan: Equatable, Sendable {
        let executablePath: String
        let arguments: [String]
        let scrubLocalTmuxEnvironment: Bool
    }

    static func commandPlan(
        for endpoint: HolyTmuxAgentStateEndpoint
    ) throws -> CommandPlan {
        let tmuxArguments = tmuxCommandArguments(socketName: endpoint.socketName)

        switch endpoint.location {
        case .local:
            // GUI applications do not inherit the user's interactive shell
            // PATH. Resolve Homebrew (and other user-installed) tmux binaries
            // through a login shell, while treating every tmux argument as
            // data rather than executable shell syntax.
            let command = (["tmux"] + tmuxArguments)
                .map(posixQuote)
                .joined(separator: " ")
            let script = "unset TMUX TMUX_PANE TMUX_TMPDIR; exec \(command)"

            return CommandPlan(
                executablePath: "/bin/zsh",
                arguments: ["-lc", script],
                scrubLocalTmuxEnvironment: true
            )

        case let .remote(sshDestination):
            let destination = sshDestination
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !destination.isEmpty,
                  !destination.hasPrefix("-"),
                  !destination.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            else {
                throw HolyTmuxAgentStateMonitorFailure(
                    kind: .invalidEndpoint,
                    context: endpoint.hostLabel
                )
            }

            let command = (["tmux"] + tmuxArguments)
                .map(posixQuote)
                .joined(separator: " ")
            let script = "unset TMUX TMUX_PANE TMUX_TMPDIR; exec \(command)"

            return CommandPlan(
                executablePath: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=1",
                    "-o", "ServerAliveInterval=1",
                    "-o", "ServerAliveCountMax=1",
                    destination,
                    "zsh -lc \(posixQuote(script))",
                ],
                scrubLocalTmuxEnvironment: false
            )
        }
    }

    static func parse(
        stdout: String,
        endpoint: HolyTmuxAgentStateEndpoint,
        observedAt: Date
    ) throws -> [HolyTmuxAgentStateObservationKey: HolyTmuxAgentStateObservation] {
        guard stdout.utf8.count <= maximumOutputBytes else {
            throw HolyTmuxAgentStateMonitorFailure(
                kind: .outputTooLarge,
                context: endpoint.hostLabel
            )
        }

        let lines = stdout.split(whereSeparator: { $0.isNewline })
        guard lines.count <= maximumPaneRows else {
            throw HolyTmuxAgentStateMonitorFailure(
                kind: .outputTooLarge,
                context: endpoint.hostLabel
            )
        }

        struct PaneValue {
            let paneID: String
            let rawWireValue: String?
            let rawLastFinishedWireValue: String?
        }

        var grouped: [String: [PaneValue]] = [:]
        for line in lines {
            guard line.utf8.count <= maximumLineBytes else {
                throw HolyTmuxAgentStateMonitorFailure(
                    kind: .outputTooLarge,
                    context: endpoint.hostLabel
                )
            }

            let fields = line.split(
                separator: Character(fieldSeparator),
                omittingEmptySubsequences: false
            )
            guard fields.count == 4,
                  !fields[0].isEmpty,
                  !fields[1].isEmpty else {
                throw HolyTmuxAgentStateMonitorFailure(
                    kind: .malformedOutput,
                    context: endpoint.hostLabel
                )
            }

            let sessionName = String(fields[0])
            let paneID = String(fields[1])
            let rawWireValue = fields[2].isEmpty ? nil : String(fields[2])
            let rawLastFinishedWireValue = fields[3].isEmpty ? nil : String(fields[3])
            grouped[sessionName, default: []].append(PaneValue(
                paneID: paneID,
                rawWireValue: rawWireValue,
                rawLastFinishedWireValue: rawLastFinishedWireValue
            ))
        }

        var observations: [HolyTmuxAgentStateObservationKey: HolyTmuxAgentStateObservation] = [:]
        for (sessionName, paneValues) in grouped {
            let key = HolyTmuxAgentStateObservationKey(
                hostID: endpoint.hostID,
                socketName: endpoint.socketName,
                sessionName: sessionName
            )
            let paneIDs = Array(Set(paneValues.map(\.paneID))).sorted()
            let nonEmptyValues = paneValues.compactMap(\.rawWireValue)
            let nonEmptyFinishedValues = paneValues.compactMap(\.rawLastFinishedWireValue)

            guard !nonEmptyValues.isEmpty || !nonEmptyFinishedValues.isEmpty else {
                observations[key] = HolyTmuxAgentStateObservation(
                    key: key,
                    observedAt: observedAt,
                    paneIDs: paneIDs,
                    integrity: .noState,
                    envelope: nil,
                    lastFinishedEnvelope: nil,
                    rawWireValue: nil,
                    rawLastFinishedWireValue: nil
                )
                continue
            }

            var validByCanonicalWire: [String: HolyAgentStateEnvelope] = [:]
            var invalidValues: Set<String> = []
            for rawWireValue in nonEmptyValues {
                do {
                    let envelope = try HolyAgentStateEnvelope(wireValue: rawWireValue)
                    validByCanonicalWire[envelope.wireValue] = envelope
                } catch {
                    invalidValues.insert(rawWireValue)
                }
            }

            var validFinishedByCanonicalWire: [String: HolyAgentStateEnvelope] = [:]
            var invalidFinishedValues: Set<String> = []
            for rawWireValue in nonEmptyFinishedValues {
                do {
                    let envelope = try HolyAgentStateEnvelope(wireValue: rawWireValue)
                    guard envelope.lifecycle == .finished else {
                        invalidFinishedValues.insert(rawWireValue)
                        continue
                    }
                    validFinishedByCanonicalWire[envelope.wireValue] = envelope
                } catch {
                    invalidFinishedValues.insert(rawWireValue)
                }
            }

            // The latest lifecycle and independent last-finished register have
            // separate integrity domains. A malformed future latest value must
            // not erase a uniquely valid offline finish, and vice versa.
            let currentConflicting = validByCanonicalWire.count > 1
                || (!validByCanonicalWire.isEmpty && !invalidValues.isEmpty)
            let finishedConflicting = validFinishedByCanonicalWire.count > 1
                || (!validFinishedByCanonicalWire.isEmpty && !invalidFinishedValues.isEmpty)
            let currentInvalid = !invalidValues.isEmpty && validByCanonicalWire.isEmpty
            let finishedInvalid = !invalidFinishedValues.isEmpty
                && validFinishedByCanonicalWire.isEmpty
            let currentEnvelope = currentConflicting || currentInvalid
                ? nil
                : validByCanonicalWire.values.first
            let finishedEnvelope = finishedConflicting || finishedInvalid
                ? nil
                : validFinishedByCanonicalWire.values.first
            let integrity: HolyTmuxAgentStateObservationIntegrity
            if currentConflicting || finishedConflicting {
                integrity = .conflicting
            } else if currentInvalid || finishedInvalid {
                integrity = .invalid
            } else if currentEnvelope != nil || finishedEnvelope != nil {
                integrity = .valid
            } else {
                integrity = .invalid
            }

            observations[key] = HolyTmuxAgentStateObservation(
                key: key,
                observedAt: observedAt,
                paneIDs: paneIDs,
                integrity: integrity,
                envelope: currentEnvelope,
                lastFinishedEnvelope: finishedEnvelope,
                rawWireValue: currentConflicting
                    ? nil
                    : currentEnvelope?.wireValue
                        ?? (invalidValues.count == 1 ? invalidValues.first : nil),
                rawLastFinishedWireValue: finishedConflicting
                    ? nil
                    : finishedEnvelope?.wireValue
                        ?? (invalidFinishedValues.count == 1 ? invalidFinishedValues.first : nil)
            )
        }

        return observations
    }

    private static func tmuxCommandArguments(socketName: String?) -> [String] {
        var arguments: [String] = []
        if let socketName {
            arguments += ["-L", socketName]
        }
        arguments += ["list-panes", "-a", "-F", listPanesFormat]
        return arguments
    }

    private static func posixQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}

// MARK: - Bounded process execution

extension HolyTmuxAgentStateMonitor {
    enum RunOutcome {
        case completed(
            stdout: String,
            stderr: String,
            exitCode: Int32,
            outputOverflowed: Bool
        )
        case launchFailed(String)
        case timedOut
    }

    static func run(
        plan: CommandPlan,
        timeout: TimeInterval,
        inheritedEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> RunOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: plan.executablePath)
        process.arguments = plan.arguments

        var environment = inheritedEnvironment
        if plan.scrubLocalTmuxEnvironment {
            environment.removeValue(forKey: "TMUX")
            environment.removeValue(forKey: "TMUX_PANE")
            environment.removeValue(forKey: "TMUX_TMPDIR")
        }
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let stdoutBuffer = HolyTmuxAgentStateOutputBuffer(limit: maximumOutputBytes)
        let stderrBuffer = HolyTmuxAgentStateOutputBuffer(limit: 64 * 1_024)
        stdout.fileHandleForReading.readabilityHandler = { handle in
            stdoutBuffer.append(handle.availableData)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            stderrBuffer.append(handle.availableData)
        }

        let resumeBox = HolyTmuxAgentStateRunResumeBox()
        return await withCheckedContinuation { continuation in
            resumeBox.store(continuation)

            process.terminationHandler = { finishedProcess in
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                stdoutBuffer.append(stdout.fileHandleForReading.readDataToEndOfFile())
                stderrBuffer.append(stderr.fileHandleForReading.readDataToEndOfFile())

                let stdoutSnapshot = stdoutBuffer.snapshot()
                let stderrSnapshot = stderrBuffer.snapshot()
                resumeBox.resume(returning: .completed(
                    stdout: String(bytes: stdoutSnapshot.data, encoding: .utf8) ?? "",
                    stderr: String(bytes: stderrSnapshot.data, encoding: .utf8) ?? "",
                    exitCode: finishedProcess.terminationStatus,
                    outputOverflowed: stdoutSnapshot.overflowed || stderrSnapshot.overflowed
                ))
            }

            do {
                try process.run()
            } catch {
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                resumeBox.resume(returning: .launchFailed(error.localizedDescription))
                return
            }

            Task.detached {
                try? await Task.sleep(
                    nanoseconds: UInt64(max(0.1, timeout) * 1_000_000_000)
                )
                if resumeBox.resume(returning: .timedOut), process.isRunning {
                    // Escalate like HolyRemoteAgentStateBridgeService.run: this
                    // spawns ssh every poll, and an ssh that shrugs off SIGTERM
                    // during teardown would otherwise accumulate per tick.
                    process.terminate()
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if process.isRunning {
                        _ = Darwin.kill(process.processIdentifier, SIGKILL)
                    }
                }
            }
        }
    }
}

private final class HolyTmuxAgentStateOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var data = Data()
    private var overflowed = false

    init(limit: Int) {
        self.limit = limit
    }

    func append(_ newData: Data) {
        guard !newData.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        let remaining = max(0, limit - data.count)
        if newData.count > remaining {
            overflowed = true
        }
        if remaining > 0 {
            data.append(newData.prefix(remaining))
        }
    }

    func snapshot() -> (data: Data, overflowed: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (data, overflowed)
    }
}

private final class HolyTmuxAgentStateRunResumeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<HolyTmuxAgentStateMonitor.RunOutcome, Never>?
    private var didResume = false

    func store(
        _ continuation: CheckedContinuation<HolyTmuxAgentStateMonitor.RunOutcome, Never>
    ) {
        lock.lock()
        if didResume {
            lock.unlock()
            continuation.resume(returning: .timedOut)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    @discardableResult
    func resume(
        returning value: HolyTmuxAgentStateMonitor.RunOutcome
    ) -> Bool {
        lock.lock()
        guard !didResume, let continuation else {
            lock.unlock()
            return false
        }
        didResume = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(returning: value)
        return true
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
