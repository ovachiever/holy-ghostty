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
    /// Independent committed-user-prompt register. Later tool, finish, and
    /// ended events cannot erase the only evidence allowed to earn blue.
    let lastUsedEnvelope: HolyAgentStateEnvelope?
    /// Session-scoped human acknowledgement written by any attached Holy.
    /// nil is fail-closed: a missing or malformed value never clears unread.
    let seenState: HolyAgentSeenState?
    /// Preserved only when there is a single unambiguous producer value.
    /// Conflicts intentionally expose neither candidate as authoritative.
    let rawWireValue: String?
    let rawLastFinishedWireValue: String?
    let rawLastUsedWireValue: String?
    /// Whether the single pane that published the latest-state register still
    /// runs a non-shell foreground process. When an agent dies, tmux shows
    /// the pane's shell again, which proves the producer is gone. nil when
    /// there is no unambiguous producer pane or the command is unreadable —
    /// unknown must degrade to lease behavior, never invalidate a claim.
    let producerHasLiveProcess: Bool?
    /// Last output activity in the producer pane's window. Diagnostic evidence
    /// for stalled-agent handling only; pane redraws cannot renew a hook lease.
    let producerLastOutputAt: Date?
    /// When the session's armed /loop wakeup will fire (mn-f4d77b). Read from
    /// the independent @holy_watcher_v1 register; nil when no pane publishes
    /// a valid claim or when multiple panes disagree.
    let watcherFireAt: Date?
    var harnessIdentityEnvelope: HolyAgentStateEnvelope? = nil
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

    private struct RegisterResolution {
        let envelope: HolyAgentStateEnvelope?
        let rawWireValue: String?
        let isConflicting: Bool
        let isInvalid: Bool
    }

    static func commandPlan(
        for endpoint: HolyTmuxAgentStateEndpoint
    ) throws -> CommandPlan {
        switch endpoint.location {
        case .local:
            // GUI applications do not inherit the user's interactive shell
            // PATH. Resolve Homebrew (and other user-installed) tmux binaries
            // through a login shell, while treating every tmux argument as
            // data rather than executable shell syntax.
            let mirror = HolyHostStateMirror.command(
                tmuxPrefix: ["tmux"] + (endpoint.socketName.map { ["-L", $0] } ?? []),
                databasePath: HolyDatabasePaths.databaseURL.path, monitor: true
            )
            let script = "unset TMUX TMUX_PANE TMUX_TMPDIR; exec \(mirror)"

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

            let mirror = HolyHostStateMirror.command(
                tmuxPrefix: ["tmux"] + (endpoint.socketName.map { ["-L", $0] } ?? []),
                databasePath: "", monitor: true
            )
            let script = "unset TMUX TMUX_PANE TMUX_TMPDIR; exec \(mirror)"

            let transport = try HolySSHTransportManager.shared.command(
                destination: destination,
                purpose: .control,
                options: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=1",
                    "-o", "ServerAliveInterval=1",
                    "-o", "ServerAliveCountMax=1",
                ],
                remoteCommand: ["zsh -lc \(posixQuote(script))"]
            )
            return CommandPlan(
                executablePath: transport.executablePath,
                arguments: transport.arguments,
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
            let rawLastUsedWireValue: String?
            let rawSeenValue: String?
            let isDead: Bool
            let currentCommand: String?
            let windowActivityAt: Date?
            let rawWatcherValue: String?
            let rawIdentityValue: String?
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
            // Accept snapshots emitted by generation 5 during a rolling upgrade.
            guard (10 ... 11).contains(fields.count),
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
                rawLastFinishedWireValue: rawLastFinishedWireValue,
                rawLastUsedWireValue: fields[4].isEmpty ? nil : String(fields[4]),
                rawSeenValue: fields[5].isEmpty ? nil : String(fields[5]),
                isDead: fields[6] == "1",
                currentCommand: fields[7].isEmpty ? nil : String(fields[7]),
                windowActivityAt: Int64(fields[8]).map { Date(timeIntervalSince1970: TimeInterval($0)) },
                rawWatcherValue: fields[9].isEmpty ? nil : String(fields[9]),
                rawIdentityValue: fields.count == 11 && !fields[10].isEmpty ? String(fields[10]) : nil
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
            let nonEmptyUsedValues = paneValues.compactMap(\.rawLastUsedWireValue)
            let used = resolveRegister(
                nonEmptyUsedValues,
                requiringReasonCode: HolySessionAttentionMetadata.humanUseReasonCode
            )
            let identityValues = paneValues.compactMap(\.rawIdentityValue)
            let identity = resolveRegister(identityValues, requiringReasonCode: "identity")
            // Older hosts have no identity register. Their committed prompt
            // can supply identity, but never downgrade an explicit conflict.
            let identityEnvelope = identityValues.isEmpty ? used.envelope : identity.envelope
            let seenState = seenState(fromRawValues: paneValues.map(\.rawSeenValue))

            guard !nonEmptyValues.isEmpty || !nonEmptyFinishedValues.isEmpty else {
                observations[key] = HolyTmuxAgentStateObservation(
                    key: key,
                    observedAt: observedAt,
                    paneIDs: paneIDs,
                    integrity: .noState,
                    envelope: nil,
                    lastFinishedEnvelope: nil,
                    lastUsedEnvelope: used.envelope,
                    seenState: seenState,
                    rawWireValue: nil,
                    rawLastFinishedWireValue: nil,
                    rawLastUsedWireValue: used.rawWireValue,
                    producerHasLiveProcess: nil,
                    producerLastOutputAt: nil,
                    watcherFireAt: watcherFireAt(fromRawValues: paneValues.compactMap(\.rawWatcherValue)),
                    harnessIdentityEnvelope: identityEnvelope
                )
                continue
            }

            // A long-running tmux session can retain a pane value from before
            // harness identity rode the wire beside a newer identified value.
            // That is migration residue, not an eternal conflict. Resolve each
            // independent register by wire authority first and producer time
            // second. Equal-authority, equal-time disagreement still fails
            // closed and becomes an explicit workspace conflict.
            let current = resolveRegister(nonEmptyValues)
            let finished = resolveRegister(
                nonEmptyFinishedValues,
                requiring: .finished
            )
            let currentEnvelope = current.envelope
            let finishedEnvelope = finished.envelope

            // Process evidence belongs to the elected current producer, not to
            // every stale pane that carries a superseded register value.
            // Duplicate winning producers remain ambiguous and fail closed.
            let producerPanes = currentEnvelope.map { envelope in
                paneValues.filter { pane in
                    guard let raw = pane.rawWireValue,
                          let candidate = try? HolyAgentStateEnvelope(wireValue: raw) else {
                        return false
                    }
                    return candidate == envelope
                }
            } ?? []
            let producerHasLiveProcess: Bool?
            let producerLastOutputAt: Date?
            if producerPanes.count == 1, let producer = producerPanes.first {
                if producer.isDead {
                    producerHasLiveProcess = false
                } else if let command = producer.currentCommand {
                    if shellCommandNames.contains(command.lowercased()) {
                        // Claude runs tool calls as shell children, so sampling
                        // zsh/bash is not proof that Claude exited. Unknown can
                        // invalidate nothing; the hook lease carries the claim.
                        producerHasLiveProcess = currentEnvelope?.source == HolyAgentStateSource.claude
                            ? nil
                            : false
                    } else {
                        producerHasLiveProcess = true
                    }
                } else {
                    producerHasLiveProcess = nil
                }
                producerLastOutputAt = producer.windowActivityAt
            } else {
                producerHasLiveProcess = nil
                producerLastOutputAt = nil
            }

            // Latest lifecycle and last-finished are separate integrity
            // domains. One malformed register cannot erase a valid envelope
            // from the other domain.
            let integrity: HolyTmuxAgentStateObservationIntegrity
            if current.isConflicting || finished.isConflicting {
                integrity = .conflicting
            } else if current.isInvalid || finished.isInvalid {
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
                lastUsedEnvelope: used.envelope,
                seenState: seenState,
                rawWireValue: current.rawWireValue,
                rawLastFinishedWireValue: finished.rawWireValue,
                rawLastUsedWireValue: used.rawWireValue,
                producerHasLiveProcess: producerHasLiveProcess,
                producerLastOutputAt: producerLastOutputAt,
                watcherFireAt: watcherFireAt(fromRawValues: paneValues.compactMap(\.rawWatcherValue)),
                    harnessIdentityEnvelope: identityEnvelope
            )
        }

        return observations
    }

    /// Elects one authoritative pane register without letting stale migration
    /// residue become a permanent conflict. Identified envelopes outrank the
    /// legacy blank-session shape; within one shape, the newest producer
    /// timestamp wins. Only disagreement at the winning rank is ambiguous.
    private static func resolveRegister(
        _ rawValues: [String],
        requiring lifecycle: HolyAgentLifecycleState? = nil,
        requiringReasonCode reasonCode: String? = nil
    ) -> RegisterResolution {
        var validByCanonicalWire: [String: HolyAgentStateEnvelope] = [:]
        var invalidValues: Set<String> = []

        for rawValue in rawValues {
            do {
                let envelope = try HolyAgentStateEnvelope(wireValue: rawValue)
                guard lifecycle == nil || envelope.lifecycle == lifecycle,
                      reasonCode == nil || envelope.reasonCode == reasonCode else {
                    invalidValues.insert(rawValue)
                    continue
                }
                validByCanonicalWire[envelope.wireValue] = envelope
            } catch {
                invalidValues.insert(rawValue)
            }
        }

        guard !validByCanonicalWire.isEmpty else {
            return .init(
                envelope: nil,
                rawWireValue: invalidValues.count == 1 ? invalidValues.first : nil,
                isConflicting: false,
                isInvalid: !invalidValues.isEmpty
            )
        }

        // Unknown or malformed values remain a real conflict beside valid
        // state. They might be a future format with facts this build cannot
        // interpret. Only parseable stale values may be superseded.
        guard invalidValues.isEmpty else {
            return .init(
                envelope: nil,
                rawWireValue: nil,
                isConflicting: true,
                isInvalid: false
            )
        }

        let values = Array(validByCanonicalWire.values)
        let identifiedRank = values.contains(where: { $0.sessionID != nil })
        let formatCandidates = values.filter { ($0.sessionID != nil) == identifiedRank }
        let newestTimestamp = formatCandidates
            .map(\.occurredAtMilliseconds)
            .max()
        let finalists = formatCandidates.filter {
            $0.occurredAtMilliseconds == newestTimestamp
        }

        guard finalists.count == 1, let winner = finalists.first else {
            return .init(
                envelope: nil,
                rawWireValue: nil,
                isConflicting: true,
                isInvalid: false
            )
        }

        return .init(
            envelope: winner,
            rawWireValue: winner.wireValue,
            isConflicting: false,
            isInvalid: false
        )
    }

    /// Foreground commands that prove the producer process exited: when an
    /// agent dies, tmux reports the pane's shell as the current command.
    private static let shellCommandNames: Set<String> = [
        "zsh", "bash", "fish", "sh", "dash", "tcsh", "csh", "ksh", "login",
    ]

    /// Parses the independent watcher register. Exactly one distinct valid
    /// claim across the session's panes is required; disagreement or any
    /// malformed value fails closed to nil.
    private static func watcherFireAt(fromRawValues rawWatcherValues: [String]) -> Date? {
        let rawValues = Set(rawWatcherValues)
        guard rawValues.count == 1, let raw = rawValues.first else { return nil }
        let fields = raw.split(separator: "|", omittingEmptySubsequences: false)
        guard fields.count == 5,
              fields[0] == "v1",
              fields[2] == "watching",
              let fireAtMilliseconds = Int64(fields[3]),
              fireAtMilliseconds > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: TimeInterval(fireAtMilliseconds) / 1_000)
    }

    /// A session option is inherited by each pane, so duplicates are expected.
    /// Any disagreement or malformed value is uncertainty and cannot clear an
    /// unread event from a local cache.
    private static func seenState(fromRawValues rawSeenValues: [String?]) -> HolyAgentSeenState? {
        guard !rawSeenValues.isEmpty,
              rawSeenValues.allSatisfy({ $0 != nil }) else { return nil }
        let rawValues = Set(rawSeenValues.compactMap(\.self))
        guard rawValues.count == 1, let raw = rawValues.first else { return nil }
        return try? HolyAgentSeenState(wireValue: raw)
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
