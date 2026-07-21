import Foundation
import Testing
@testable import Ghostty

struct HolyTmuxAgentStateMonitorTests {
    private let hostID = UUID(uuidString: "88A70BD5-A783-4CD3-9727-69C34450D719")!
    private let observedAt = Date(timeIntervalSince1970: 1_752_500_000)

    @Test func localPlanIsOneGroupedListPanesQueryForTheExactSocket() throws {
        let endpoint = localEndpoint(socketName: "holy state")
        let plan = try HolyTmuxAgentStateMonitor.commandPlan(for: endpoint)
        let command = try #require(plan.arguments.last)

        #expect(plan.executablePath == "/bin/zsh")
        #expect(plan.arguments.first == "-lc")
        #expect(plan.arguments.count == 2)
        #expect(command == [
            "unset TMUX TMUX_PANE TMUX_TMPDIR; exec 'tmux' '-L' 'holy state'",
            "'list-panes' '-a' '-F'",
            "'#{session_name}\u{1F}#{pane_id}\u{1F}#{@holy_agent_state_v1}\u{1F}#{@holy_agent_last_finished_v1}\u{1F}#{pane_dead}\u{1F}#{pane_current_command}'",
        ].joined(separator: " "))
        #expect(command.components(separatedBy: "list-panes").count == 2)
        #expect(!command.contains("show-options"))
        #expect(!command.contains("display-message"))
        #expect(plan.scrubLocalTmuxEnvironment)
        #expect(endpoint.pollInterval == 1)
        #expect(endpoint.commandTimeout < endpoint.pollInterval)
    }

    @Test func localPlanFindsProfileTmuxWhenInheritedPathLacksHomebrew() async throws {
        let fileManager = FileManager.default
        let fixtureURL = fileManager.temporaryDirectory
            .appendingPathComponent("holy-tmux-monitor-\(UUID().uuidString)", isDirectory: true)
        let binURL = fixtureURL.appendingPathComponent("bin", isDirectory: true)
        try fileManager.createDirectory(
            at: binURL,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: fixtureURL) }

        try "export PATH=\"$ZDOTDIR/bin:$PATH\"\n".write(
            to: fixtureURL.appendingPathComponent(".zprofile"),
            atomically: true,
            encoding: .utf8
        )
        let fakeTmuxURL = binURL.appendingPathComponent("tmux")
        try """
        #!/bin/sh
        printf '<%s>\\n' "$@"
        printf 'TMUX=%s\\n' "${TMUX-unset}"
        printf 'TMUX_PANE=%s\\n' "${TMUX_PANE-unset}"
        printf 'TMUX_TMPDIR=%s\\n' "${TMUX_TMPDIR-unset}"
        """.write(to: fakeTmuxURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fakeTmuxURL.path
        )

        let plan = try HolyTmuxAgentStateMonitor.commandPlan(
            for: localEndpoint(socketName: "holy state")
        )
        var inheritedEnvironment = ProcessInfo.processInfo.environment
        inheritedEnvironment["HOME"] = fixtureURL.path
        inheritedEnvironment["ZDOTDIR"] = fixtureURL.path
        inheritedEnvironment["PATH"] = "/usr/bin:/bin"
        inheritedEnvironment["TMUX"] = "ambient-server"
        inheritedEnvironment["TMUX_PANE"] = "%99"
        inheritedEnvironment["TMUX_TMPDIR"] = "/ambient/tmux"

        let result = await HolyTmuxAgentStateMonitor.run(
            plan: plan,
            timeout: 2,
            inheritedEnvironment: inheritedEnvironment
        )
        switch result {
        case let .completed(stdout, stderr, exitCode, outputOverflowed):
            #expect(exitCode == 0)
            #expect(stderr.isEmpty)
            #expect(!outputOverflowed)
            #expect(stdout.contains("<holy state>"))
            #expect(stdout.contains("<list-panes>"))
            #expect(stdout.contains("#{@holy_agent_state_v1}"))
            #expect(stdout.contains("TMUX=unset"))
            #expect(stdout.contains("TMUX_PANE=unset"))
            #expect(stdout.contains("TMUX_TMPDIR=unset"))
        case .launchFailed:
            Issue.record("Login-shell tmux fixture failed to launch")
        case .timedOut:
            Issue.record("Login-shell tmux fixture timed out")
        }
    }

    @Test func remotePlanIsOneSshCallAndOneGroupedTmuxQuery() throws {
        let endpoint = HolyTmuxAgentStateEndpoint(
            hostID: hostID,
            hostLabel: "Build Host",
            location: .remote(sshDestination: "build@example.test"),
            socketName: "holy'prod"
        )
        let plan = try HolyTmuxAgentStateMonitor.commandPlan(for: endpoint)
        let command = try #require(plan.arguments.last)

        #expect(plan.executablePath == "/usr/bin/ssh")
        #expect(plan.arguments.contains("build@example.test"))
        #expect(command.components(separatedBy: "list-panes").count == 2)
        #expect(command.contains("holy"))
        #expect(command.contains("prod"))
        #expect(command.contains("#{@holy_agent_state_v1}"))
        #expect(command.contains("#{@holy_agent_last_finished_v1}"))
        #expect(!command.contains("show-options"))
        #expect(!command.contains("display-message"))
        #expect(!plan.scrubLocalTmuxEnvironment)
        #expect(endpoint.pollInterval == 0.75)
        #expect(endpoint.pollInterval + endpoint.commandTimeout < 2)
    }

    @Test func duplicatePaneProducersCollapseToOneValidEnvelope() throws {
        let wire = try envelope(
            lifecycle: .finished,
            timestamp: 1_752_500_123_456,
            token: "event-1"
        ).wireValue
        let output = [
            row(session: "alpha", pane: "%1", wire: wire),
            row(session: "alpha", pane: "%2", wire: wire),
            row(session: "alpha", pane: "%3", wire: nil),
        ].joined(separator: "\n")

        let observations = try parse(output)
        let observation = try #require(observations.values.first)

        #expect(observations.count == 1)
        #expect(observation.integrity == .valid)
        #expect(observation.envelope?.eventToken == "event-1")
        #expect(observation.rawWireValue == wire)
        #expect(observation.paneIDs == ["%1", "%2", "%3"])
        #expect(observation.observedAt == observedAt)
    }

    @Test func conflictingValidPaneProducersFailClosed() throws {
        let first = try envelope(
            lifecycle: .working,
            timestamp: 1_752_500_123_456,
            token: "event-1"
        ).wireValue
        let second = try envelope(
            lifecycle: .needsUser,
            timestamp: 1_752_500_123_457,
            token: "event-2"
        ).wireValue
        let observations = try parse([
            row(session: "alpha", pane: "%1", wire: first),
            row(session: "alpha", pane: "%2", wire: second),
        ].joined(separator: "\n"))
        let observation = try #require(observations.values.first)

        #expect(observation.integrity == .conflicting)
        #expect(observation.envelope == nil)
        #expect(observation.rawWireValue == nil)
    }

    @Test func laterEndedStateDoesNotEraseDurableFinishedEnvelope() throws {
        let finished = try envelope(
            lifecycle: .finished,
            timestamp: 1_752_500_123_456,
            token: "finish-1"
        ).wireValue
        let ended = try envelope(
            lifecycle: .ended,
            timestamp: 1_752_500_123_457,
            token: "ended-1"
        ).wireValue
        let observations = try parse(row(
            session: "alpha",
            pane: "%1",
            wire: ended,
            lastFinishedWire: finished
        ))
        let observation = try #require(observations.values.first)

        #expect(observation.integrity == .valid)
        #expect(observation.envelope?.lifecycle == .ended)
        #expect(observation.lastFinishedEnvelope?.lifecycle == .finished)
        #expect(observation.lastFinishedEnvelope?.eventToken == "finish-1")
    }

    @Test func malformedLatestCannotEraseIndependentValidFinish() throws {
        let finished = try envelope(
            lifecycle: .finished,
            timestamp: 1_752_500_123_456,
            token: "finish-1"
        ).wireValue
        let observations = try parse(row(
            session: "alpha",
            pane: "%1",
            wire: "v999|future-format",
            lastFinishedWire: finished
        ))
        let observation = try #require(observations.values.first)

        #expect(observation.integrity == .invalid)
        #expect(observation.envelope == nil)
        #expect(observation.lastFinishedEnvelope?.eventToken == "finish-1")
    }

    @Test func malformedFinishedRegisterCannotPoisonValidLatestState() throws {
        let current = try envelope(
            lifecycle: .working,
            timestamp: 1_752_500_123_457,
            token: "working-1"
        ).wireValue
        let observations = try parse(row(
            session: "alpha",
            pane: "%1",
            wire: current,
            lastFinishedWire: "not-a-finish"
        ))
        let observation = try #require(observations.values.first)

        #expect(observation.integrity == .invalid)
        #expect(observation.envelope?.eventToken == "working-1")
        #expect(observation.lastFinishedEnvelope == nil)
    }

    @Test func validAndMalformedProducersAlsoFailClosed() throws {
        let valid = try envelope(
            lifecycle: .working,
            timestamp: 1_752_500_123_456,
            token: "event-1"
        ).wireValue
        let observations = try parse([
            row(session: "alpha", pane: "%1", wire: valid),
            row(session: "alpha", pane: "%2", wire: "not-an-envelope"),
        ].joined(separator: "\n"))
        let observation = try #require(observations.values.first)

        #expect(observation.integrity == .conflicting)
        #expect(observation.envelope == nil)
        #expect(observation.rawWireValue == nil)
    }

    @Test func validAndMalformedFinishedProducersHideRawCandidates() throws {
        let valid = try envelope(
            lifecycle: .finished,
            timestamp: 1_752_500_123_456,
            token: "finish-1"
        ).wireValue
        let observations = try parse([
            row(
                session: "alpha",
                pane: "%1",
                wire: nil,
                lastFinishedWire: valid
            ),
            row(
                session: "alpha",
                pane: "%2",
                wire: nil,
                lastFinishedWire: "not-an-envelope"
            ),
        ].joined(separator: "\n"))
        let observation = try #require(observations.values.first)

        #expect(observation.integrity == .conflicting)
        #expect(observation.lastFinishedEnvelope == nil)
        #expect(observation.rawLastFinishedWireValue == nil)
    }

    @Test func stoppedGenerationCannotPublishAnInFlightSnapshot() async throws {
        let endpoint = localEndpoint(socketName: "old")
        let provider = ControlledSnapshotSource()
        let recorder = await MainActor.run {
            HolyTmuxAgentStateSnapshotRecorder()
        }
        let monitor = HolyTmuxAgentStateMonitor { endpoint in
            await provider.snapshot(for: endpoint)
        }

        await monitor.start(endpoints: [endpoint]) { snapshot in
            recorder.record(snapshot)
        }
        await provider.waitUntilRequested(socketName: "old")
        await monitor.stop()
        await provider.resume(snapshot(for: endpoint), socketName: "old")
        try await Task.sleep(for: .milliseconds(100))

        let deliveredSockets = await MainActor.run { recorder.socketNames }
        #expect(deliveredSockets.isEmpty)
    }

    @Test func replacedGenerationCannotPublishIntoNewConfiguration() async throws {
        let oldEndpoint = localEndpoint(socketName: "old")
        let currentEndpoint = localEndpoint(socketName: "current")
        let provider = ControlledSnapshotSource()
        let recorder = await MainActor.run {
            HolyTmuxAgentStateSnapshotRecorder()
        }
        let monitor = HolyTmuxAgentStateMonitor { endpoint in
            await provider.snapshot(for: endpoint)
        }

        await monitor.start(endpoints: [oldEndpoint]) { snapshot in
            recorder.record(snapshot)
        }
        await provider.waitUntilRequested(socketName: "old")

        await monitor.start(endpoints: [currentEndpoint]) { snapshot in
            recorder.record(snapshot)
        }
        await provider.waitUntilRequested(socketName: "current")
        await provider.resume(snapshot(for: oldEndpoint), socketName: "old")
        await provider.resume(snapshot(for: currentEndpoint), socketName: "current")
        try await Task.sleep(for: .milliseconds(100))
        await monitor.stop()

        let deliveredSockets = await MainActor.run { recorder.socketNames }
        #expect(deliveredSockets == ["current"])
    }

    @Test func callerGenerationRejectsOutOfOrderConfigurationTasks() async throws {
        let staleEndpoint = localEndpoint(socketName: "stale")
        let currentEndpoint = localEndpoint(socketName: "current")
        let provider = ControlledSnapshotSource()
        let recorder = await MainActor.run {
            HolyTmuxAgentStateSnapshotRecorder()
        }
        let monitor = HolyTmuxAgentStateMonitor { endpoint in
            await provider.snapshot(for: endpoint)
        }

        await monitor.start(endpoints: [currentEndpoint], requestedGeneration: 2) { snapshot in
            recorder.record(snapshot)
        }
        await provider.waitUntilRequested(socketName: "current")
        await monitor.start(endpoints: [staleEndpoint], requestedGeneration: 1) { snapshot in
            recorder.record(snapshot)
        }
        await provider.resume(snapshot(for: currentEndpoint), socketName: "current")
        try await Task.sleep(for: .milliseconds(100))
        await monitor.stop()

        let requestedSockets = await provider.requestedSocketNames
        let deliveredSockets = await MainActor.run { recorder.socketNames }
        #expect(!requestedSockets.contains("stale"))
        #expect(deliveredSockets == ["current"])
    }

    @Test func invalidOnlyAndEmptySessionsRemainExplicitlyUnknown() throws {
        let observations = try parse([
            row(session: "invalid", pane: "%1", wire: "not-an-envelope"),
            row(session: "empty", pane: "%2", wire: nil),
        ].joined(separator: "\n"))
        let invalidKey = HolyTmuxAgentStateObservationKey(
            hostID: hostID,
            socketName: "holy",
            sessionName: "invalid"
        )
        let emptyKey = HolyTmuxAgentStateObservationKey(
            hostID: hostID,
            socketName: "holy",
            sessionName: "empty"
        )

        #expect(observations[invalidKey]?.integrity == .invalid)
        #expect(observations[invalidKey]?.rawWireValue == "not-an-envelope")
        #expect(observations[invalidKey]?.envelope == nil)
        #expect(observations[emptyKey]?.integrity == .noState)
        #expect(observations[emptyKey]?.rawWireValue == nil)
        #expect(observations[emptyKey]?.envelope == nil)
    }

    // Producer-process evidence: known only for a single unambiguous
    // producer pane; a shell foreground or dead pane proves the agent exited.
    @Test func producerProcessEvidenceReadsTheProducerPaneForeground() throws {
        let working = try envelope(
            lifecycle: .working,
            timestamp: 1_752_500_123_456,
            token: "working-1"
        ).wireValue

        let alive = try parse(row(session: "alpha", pane: "%1", wire: working, command: "claude.exe"))
        #expect(alive.values.first?.producerHasLiveProcess == true)

        let fellBackToShell = try parse(row(session: "alpha", pane: "%1", wire: working, command: "zsh"))
        #expect(fellBackToShell.values.first?.producerHasLiveProcess == false)

        let deadPane = try parse(row(session: "alpha", pane: "%1", wire: working, dead: true, command: "claude.exe"))
        #expect(deadPane.values.first?.producerHasLiveProcess == false)

        let unknownCommand = try parse(row(session: "alpha", pane: "%1", wire: working))
        #expect(unknownCommand.values.first?.producerHasLiveProcess == nil)

        let ambiguousProducers = try parse([
            row(session: "alpha", pane: "%1", wire: working, command: "claude.exe"),
            row(session: "alpha", pane: "%2", wire: working, command: "zsh"),
        ].joined(separator: "\n"))
        #expect(ambiguousProducers.values.first?.producerHasLiveProcess == nil)

        let noState = try parse(row(session: "alpha", pane: "%1", wire: nil, command: "claude.exe"))
        #expect(noState.values.first?.producerHasLiveProcess == nil)
    }

    @Test func malformedGroupedRowsRejectTheWholeSnapshot() {
        do {
            _ = try parse("alpha\u{1F}%1")
            Issue.record("Expected malformed grouped output to fail")
        } catch let failure as HolyTmuxAgentStateMonitorFailure {
            #expect(failure.kind == .malformedOutput)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func observationKeysKeepHostsAndSocketsDistinct() throws {
        let wire = try envelope(
            lifecycle: .idle,
            timestamp: 1_752_500_123_456,
            token: "event-1"
        ).wireValue
        let observations = try parse(row(session: "alpha", pane: "%1", wire: wire))
        let key = try #require(observations.keys.first)

        #expect(key.hostID == hostID)
        #expect(key.socketName == "holy")
        #expect(key.sessionName == "alpha")
    }

    private func parse(
        _ output: String
    ) throws -> [HolyTmuxAgentStateObservationKey: HolyTmuxAgentStateObservation] {
        try HolyTmuxAgentStateMonitor.parse(
            stdout: output,
            endpoint: localEndpoint(socketName: "holy"),
            observedAt: observedAt
        )
    }

    private func localEndpoint(socketName: String?) -> HolyTmuxAgentStateEndpoint {
        HolyTmuxAgentStateEndpoint(
            hostID: hostID,
            hostLabel: "This Mac",
            location: .local,
            socketName: socketName
        )
    }

    private func row(
        session: String,
        pane: String,
        wire: String?,
        lastFinishedWire: String? = nil,
        dead: Bool = false,
        command: String? = nil
    ) -> String {
        [session, pane, wire ?? "", lastFinishedWire ?? "", dead ? "1" : "0", command ?? ""]
            .joined(separator: "\u{1F}")
    }

    private func envelope(
        lifecycle: HolyAgentLifecycleState,
        timestamp: Int64,
        token: String
    ) throws -> HolyAgentStateEnvelope {
        try HolyAgentStateEnvelope(
            source: "future-harness.v1",
            lifecycle: lifecycle,
            occurredAtMilliseconds: timestamp,
            eventToken: token,
            reasonCode: "test"
        )
    }

    private func snapshot(
        for endpoint: HolyTmuxAgentStateEndpoint
    ) -> HolyTmuxAgentStateSnapshot {
        HolyTmuxAgentStateSnapshot(
            endpoint: endpoint,
            observedAt: observedAt,
            observations: [:],
            failure: nil
        )
    }
}

private actor ControlledSnapshotSource {
    private var snapshotContinuations: [
        String: CheckedContinuation<HolyTmuxAgentStateSnapshot, Never>
    ] = [:]
    private var requestContinuations: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var requestedSocketNameSet: Set<String> = []

    var requestedSocketNames: Set<String> {
        requestedSocketNameSet
    }

    func snapshot(
        for endpoint: HolyTmuxAgentStateEndpoint
    ) async -> HolyTmuxAgentStateSnapshot {
        let socketName = endpoint.socketName ?? ""
        requestedSocketNameSet.insert(socketName)
        return await withCheckedContinuation { continuation in
            snapshotContinuations[socketName] = continuation
            let waiters = requestContinuations.removeValue(forKey: socketName) ?? []
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    func waitUntilRequested(socketName: String) async {
        guard snapshotContinuations[socketName] == nil else { return }
        await withCheckedContinuation { continuation in
            requestContinuations[socketName, default: []].append(continuation)
        }
    }

    func resume(
        _ snapshot: HolyTmuxAgentStateSnapshot,
        socketName: String
    ) {
        snapshotContinuations.removeValue(forKey: socketName)?.resume(returning: snapshot)
    }
}

@MainActor
private final class HolyTmuxAgentStateSnapshotRecorder {
    private(set) var socketNames: [String] = []

    func record(_ snapshot: HolyTmuxAgentStateSnapshot) {
        socketNames.append(snapshot.endpoint.socketName ?? "")
    }
}
