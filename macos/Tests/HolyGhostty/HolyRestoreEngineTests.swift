import Foundation
import Testing
@testable import Ghostty

// The engine orchestrates restore end to end: plan from archived sessions,
// preflight local facts per row, resolve every provider row through ONE
// batch call with globally unique assignment, create detached tmux sessions
// in bounded batches, and adopt instead of duplicating on every retry. All
// side effects live behind fakes here; the real tmux and resolver are
// covered by the integration suite.

/// Opens once; every waiter before that suspends. Lets a test hold the
/// batch resolver mid-flight while the rest of the engine keeps moving.
private actor BatchGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        opened = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
}

private final class FakeBatchResolver: HolyRestoreBatchResolving, @unchecked Sendable {
    private let lock = NSLock()
    private let candidatesByCwd: [String: [HolyRestoreResolveCandidate]]
    private let errorsByCwd: [String: String]
    private let unavailableReason: String?
    private(set) var calls: [[HolyRestoreResolveBatchRequest]] = []
    var gate: BatchGate?
    /// Extra results appended to violate the positional contract on purpose.
    var extraResults: [HolyRestoreResolveBatchResult] = []

    init(
        candidatesByCwd: [String: [HolyRestoreResolveCandidate]] = [:],
        errorsByCwd: [String: String] = [:],
        unavailableReason: String? = nil
    ) {
        self.candidatesByCwd = candidatesByCwd
        self.errorsByCwd = errorsByCwd
        self.unavailableReason = unavailableReason
    }

    func resolveBatch(
        _ requests: [HolyRestoreResolveBatchRequest]
    ) async -> HolyRestoreBatchResolveOutcome {
        lock.lock()
        calls.append(requests)
        lock.unlock()

        if let gate {
            await gate.wait()
        }
        if let unavailableReason {
            return .resolverUnavailable(unavailableReason)
        }
        // Positional 1:1, echoing the CANONICAL harness the way the real CLI
        // does ("claude" in, "claude-code" out) — any engine keying on the
        // request's harness string would break here, exactly as it would in
        // the field.
        return .resolved(requests.map { request in
            .init(
                cwd: request.cwd,
                harness: request.harness == "claude" ? "claude-code" : request.harness,
                runtime: request.harness,
                candidates: errorsByCwd[request.cwd] == nil ? (candidatesByCwd[request.cwd] ?? []) : [],
                error: errorsByCwd[request.cwd]
            )
        } + extraResults)
    }
}

private final class FakeTmux: HolyRestoreTmuxControlling, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var liveSessionNames: Set<String> = []
    private(set) var createdSpecs: [HolySessionLaunchSpec] = []
    private(set) var maxObservedConcurrentCreates = 0
    private var currentConcurrentCreates = 0
    var undeterminedSessionNames: Set<String> = []
    var createDelayNanoseconds: UInt64 = 0

    func markLive(_ sessionName: String) {
        lock.lock()
        defer { lock.unlock() }
        liveSessionNames.insert(sessionName)
    }

    func createCount(forSessionName sessionName: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return createdSpecs.filter { $0.tmux?.sessionName == sessionName }.count
    }

    func liveness(for identity: HolyTmuxLiveIdentity) async -> HolyTmuxLiveness {
        lock.lock()
        defer { lock.unlock() }
        if undeterminedSessionNames.contains(identity.sessionName) {
            return .undetermined(.init(
                stage: .probe,
                socketName: identity.socketName,
                target: "=\(identity.sessionName)",
                stderr: "scripted undetermined",
                underlyingDescription: nil
            ))
        }
        return liveSessionNames.contains(identity.sessionName) ? .present : .absent
    }

    func createDetached(for launchSpec: HolySessionLaunchSpec) async -> String? {
        lock.lock()
        currentConcurrentCreates += 1
        maxObservedConcurrentCreates = max(maxObservedConcurrentCreates, currentConcurrentCreates)
        lock.unlock()

        if createDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: createDelayNanoseconds)
        }

        lock.lock()
        defer { lock.unlock() }
        currentConcurrentCreates -= 1
        createdSpecs.append(launchSpec)
        if let sessionName = launchSpec.tmux?.sessionName {
            liveSessionNames.insert(sessionName)
        }
        return nil
    }
}

private final class FakeEnvironment: HolyRestoreEnvironmentProbing, @unchecked Sendable {
    var existingDirectories: Set<String>
    var availableExecutables: Set<String>

    init(existingDirectories: Set<String>, availableExecutables: Set<String>) {
        self.existingDirectories = existingDirectories
        self.availableExecutables = availableExecutables
    }

    func directoryExists(_ path: String) -> Bool {
        existingDirectories.contains(path)
    }

    // Returns the bare name so command assertions stay readable; production
    // resolves an absolute path (see HolyRestoreEnvironmentProbe).
    func resolveExecutable(_ name: String) async -> String? {
        availableExecutables.contains(name) ? name : nil
    }
}

@MainActor
private final class FakeAdapter: HolyRestoreWorkspaceAdapting {
    var archives: [HolyArchivedSession]
    var olderArchives: [HolyArchivedSession] = []
    var rosterHolyIDs: Set<UUID> = []
    var rosterTmuxSessionNames: Set<String> = []
    private(set) var persistedSpecsByArchiveID: [UUID: [HolySessionLaunchSpec]] = [:]
    private(set) var attachedArchiveIDs: [UUID] = []
    private(set) var deletedArchiveIDs: [UUID] = []
    var attachSucceeds = true

    init(archives: [HolyArchivedSession]) {
        self.archives = archives
    }

    var restoreCandidateBatch: HolyCrashRestoreBatch {
        .init(fresh: archives, older: olderArchives)
    }

    func rosterOwnsSession(withHolyID id: UUID) -> Bool {
        rosterHolyIDs.contains(id)
    }

    func rosterOwnsTmuxSessionName(_ name: String) -> Bool {
        rosterTmuxSessionNames.contains(name)
    }

    func persistPlannedLaunchSpec(archiveID: UUID, launchSpec: HolySessionLaunchSpec) {
        persistedSpecsByArchiveID[archiveID, default: []].append(launchSpec)
        if let index = archives.firstIndex(where: { $0.id == archiveID }) {
            archives[index].record.launchSpec = launchSpec
        }
        if let index = olderArchives.firstIndex(where: { $0.id == archiveID }) {
            olderArchives[index].record.launchSpec = launchSpec
        }
    }

    func attachRestoredArchive(archiveID: UUID, launchSpec: HolySessionLaunchSpec) -> Bool {
        guard attachSucceeds else { return false }
        attachedArchiveIDs.append(archiveID)
        return true
    }

    func deleteArchives(archiveIDs: [UUID]) {
        let targets = Set(archiveIDs)
        deletedArchiveIDs += archiveIDs
        archives.removeAll { targets.contains($0.id) }
        olderArchives.removeAll { targets.contains($0.id) }
    }
}

@MainActor
struct HolyRestoreEngineTests {
    private static let coldBootReason = "Saved layout — the holy tmux server was not running at launch."
    /// The default archive last-activity instant, unix seconds.
    private static let lastActivity = 1_785_261_280

    private func archived(
        title: String = "Lane",
        runtime: HolySessionRuntime = .claude,
        workingDirectory: String? = "/tmp/lane-a",
        command: String? = "claude",
        sessionName: String? = "holy-lane-claude-11111111",
        lastActivityAt: Date = Date(timeIntervalSince1970: TimeInterval(lastActivity))
    ) -> HolyArchivedSession {
        var spec = HolySessionLaunchSpec.interactiveTmuxShell(title: title)
        spec.runtime = runtime
        spec.command = command
        spec.workingDirectory = workingDirectory
        spec.initialInput = "stale initial input"
        spec.tmux = .init(socketName: "holy", sessionName: sessionName, createIfMissing: true)

        return .init(
            sourceSessionID: UUID(),
            record: .init(launchSpec: spec),
            phase: .completed,
            preview: "",
            signals: [],
            commandTelemetry: .empty,
            budgetTelemetry: .empty,
            runtimeTelemetry: .empty,
            gitSnapshot: nil,
            lastKnownWorkingDirectory: workingDirectory,
            lastActivityAt: lastActivityAt,
            recoveryReason: Self.coldBootReason
        )
    }

    private func candidate(
        _ id: String,
        end: Int = lastActivity,
        preview: String = "preview"
    ) -> HolyRestoreResolveCandidate {
        .init(id: id, timestampEnd: end, preview: preview)
    }

    private func makeEngine(
        archives: [HolyArchivedSession],
        resolver: FakeBatchResolver,
        tmux: FakeTmux = FakeTmux(),
        environment: FakeEnvironment? = nil
    ) -> (HolyRestoreEngine, FakeAdapter, FakeTmux) {
        let adapter = FakeAdapter(archives: archives)
        let engine = HolyRestoreEngine(
            batchResolver: resolver,
            tmux: tmux,
            environment: environment ?? FakeEnvironment(
                existingDirectories: ["/tmp/lane-a", "/tmp/lane-b"],
                availableExecutables: ["claude", "codex", "opencode"]
            ),
            adapter: adapter
        )
        return (engine, adapter, tmux)
    }

    private func row(
        _ engine: HolyRestoreEngine,
        sessionName: String
    ) throws -> HolyRestoreRow {
        try #require(engine.rows.first {
            $0.plannedLaunchSpec.tmux?.sessionName == sessionName
        })
    }

    // MARK: - Plan + preflight

    @Test func preflightMapsADecisiveAssignmentToExactResumeRow() async throws {
        let resolver = FakeBatchResolver(candidatesByCwd: ["/tmp/lane-a": [candidate("aaa-111")]])
        let (engine, _, _) = makeEngine(archives: [archived()], resolver: resolver)

        engine.buildPlan()
        await engine.runPreflight()

        #expect(engine.rows.count == 1)
        #expect((try #require(engine.rows.first)).state == .exactResume(providerSessionID: "aaa-111"))
        #expect((try #require(engine.rows.first)).phase == .ready)
    }

    @Test func preflightShipsTheWholeSheetAsOneBatchCall() async throws {
        let resolver = FakeBatchResolver(candidatesByCwd: [
            "/tmp/lane-a": [candidate("aaa-111")],
            "/tmp/lane-b": [candidate("bbb-222")],
        ])
        let (engine, _, _) = makeEngine(
            archives: [
                archived(workingDirectory: "/tmp/lane-a", sessionName: "holy-one"),
                archived(runtime: .codex, workingDirectory: "/tmp/lane-b", command: "codex", sessionName: "holy-two"),
            ],
            resolver: resolver
        )

        engine.buildPlan()
        await engine.runPreflight()

        #expect(resolver.calls.count == 1)
        let requests = try #require(resolver.calls.first)
        #expect(requests.count == 2)
        #expect(requests[0] == .init(cwd: "/tmp/lane-a", harness: "claude", near: Self.lastActivity))
        #expect(requests[1] == .init(cwd: "/tmp/lane-b", harness: "codex", near: Self.lastActivity))
    }

    @Test func planGeneratesAndPersistsAMissingTmuxIdentityOnce() async throws {
        let resolver = FakeBatchResolver(candidatesByCwd: ["/tmp/lane-a": [candidate("aaa-111")]])
        let (engine, adapter, _) = makeEngine(
            archives: [archived(sessionName: nil)],
            resolver: resolver
        )

        engine.buildPlan()
        await engine.runPreflight()

        let row = (try #require(engine.rows.first))
        let generatedName = row.plannedLaunchSpec.tmux?.sessionName
        #expect(generatedName?.isEmpty == false)
        let persisted = adapter.persistedSpecsByArchiveID[row.id]?.first
        #expect(persisted?.tmux?.sessionName == generatedName)

        engine.buildPlan()
        #expect((try #require(engine.rows.first)).plannedLaunchSpec.tmux?.sessionName == generatedName)
    }

    @Test func duplicateIdentitiesAcrossRowsConflictBothWays() async throws {
        let resolver = FakeBatchResolver(candidatesByCwd: ["/tmp/lane-a": [candidate("aaa-111")]])
        let (engine, _, _) = makeEngine(
            archives: [
                archived(sessionName: "holy-shared-name"),
                archived(sessionName: "holy-shared-name"),
            ],
            resolver: resolver
        )

        engine.buildPlan()
        await engine.runPreflight()

        for row in engine.rows {
            guard case .conflict = row.state else {
                Issue.record("Expected conflict, got \(row.state)")
                return
            }
        }
    }

    @Test func rosterOwnedHolySessionIsAlreadyRestored() async throws {
        let archive = archived()
        let resolver = FakeBatchResolver()
        let (engine, adapter, _) = makeEngine(archives: [archive], resolver: resolver)
        adapter.rosterHolyIDs = [archive.sourceSessionID]

        engine.buildPlan()
        await engine.runPreflight()

        #expect((try #require(engine.rows.first)).state == .alreadyRestored)
        #expect(resolver.calls.isEmpty)
    }

    // MARK: - Assignment uniqueness (the e3565698 field failure)

    @Test func eriksSameCwdSwarmNeverRestoresTheSameConversationTwice_e3565698() async throws {
        // Field failure 2026-08-06: holy-shell-12 and holy-shell-9, both in
        // /Users/erik/Custom-Coding, were each resolved independently to the
        // nearest end timestamp in that cwd — and BOTH "restored"
        // conversation e3565698…. Global unique assignment makes the
        // collision impossible by construction: each row pairs with the
        // conversation hugging its own last activity, and no id is spent
        // twice.
        let cwd = "/Users/erik/Custom-Coding"
        let lane12 = archived(
            title: "holy-shell-12",
            workingDirectory: cwd,
            sessionName: "holy-shell-12",
            lastActivityAt: Date(timeIntervalSince1970: TimeInterval(Self.lastActivity))
        )
        let lane9 = archived(
            title: "holy-shell-9",
            workingDirectory: cwd,
            sessionName: "holy-shell-9",
            lastActivityAt: Date(timeIntervalSince1970: TimeInterval(Self.lastActivity - 180))
        )
        let resolver = FakeBatchResolver(candidatesByCwd: [cwd: [
            candidate("e3565698-repro", end: Self.lastActivity),
            candidate("41d7e2aa-sibling", end: Self.lastActivity - 180),
        ]])
        let (engine, _, tmux) = makeEngine(
            archives: [lane12, lane9],
            resolver: resolver,
            environment: FakeEnvironment(
                existingDirectories: [cwd],
                availableExecutables: ["claude"]
            )
        )

        engine.buildPlan()
        await engine.runPreflight()

        #expect(try row(engine, sessionName: "holy-shell-12").state
            == .exactResume(providerSessionID: "e3565698-repro"))
        #expect(try row(engine, sessionName: "holy-shell-9").state
            == .exactResume(providerSessionID: "41d7e2aa-sibling"))

        await engine.restoreAll()

        let commands = tmux.createdSpecs.compactMap(\.command)
        #expect(commands.count == 2)
        #expect(Set(commands).count == 2, "Two rows restored the same conversation: \(commands)")
    }

    @Test func nearTieCandidatesLeftUnclaimedDemoteToThePicker() async throws {
        // One row, two conversations ending 10s apart: auto-picking either
        // would be the old guess in new clothes. The row goes ambiguous and
        // the human picks.
        let resolver = FakeBatchResolver(candidatesByCwd: ["/tmp/lane-a": [
            candidate("aaa", end: Self.lastActivity, preview: "first"),
            candidate("bbb", end: Self.lastActivity - 10, preview: "second"),
        ]])
        let (engine, _, _) = makeEngine(archives: [archived()], resolver: resolver)

        engine.buildPlan()
        await engine.runPreflight()

        guard case let .ambiguous(candidates) = (try #require(engine.rows.first)).state else {
            Issue.record("Expected ambiguous, got \((try #require(engine.rows.first)).state)")
            return
        }
        #expect(candidates.map(\.id) == ["aaa", "bbb"])
    }

    @Test func pickCandidateRefusesAConversationAnotherRowAlreadyCarries() async throws {
        // Two same-cwd rows, three near-tie conversations: both rows demote
        // to the picker and both pickers list the unclaimed "b". Once one
        // row picks it, the other row's pick of the same id must bounce —
        // the uniqueness law survives human clicks too.
        let resolver = FakeBatchResolver(candidatesByCwd: ["/tmp/lane-a": [
            candidate("aa-pick", end: Self.lastActivity),
            candidate("bb-pick", end: Self.lastActivity - 5),
            candidate("cc-pick", end: Self.lastActivity - 12),
        ]])
        let (engine, _, _) = makeEngine(
            archives: [
                archived(sessionName: "holy-amb-1"),
                archived(
                    sessionName: "holy-amb-2",
                    lastActivityAt: Date(timeIntervalSince1970: TimeInterval(Self.lastActivity - 10))
                ),
            ],
            resolver: resolver
        )

        engine.buildPlan()
        await engine.runPreflight()

        let first = try row(engine, sessionName: "holy-amb-1")
        let second = try row(engine, sessionName: "holy-amb-2")
        guard case .ambiguous = first.state, case .ambiguous = second.state else {
            Issue.record("Expected both rows ambiguous, got \(first.state) / \(second.state)")
            return
        }

        engine.pickCandidate(rowID: first.id, candidateID: "bb-pick")
        #expect(try row(engine, sessionName: "holy-amb-1").state
            == .exactResume(providerSessionID: "bb-pick"))

        // The same conversation cannot be picked into a second row.
        engine.pickCandidate(rowID: second.id, candidateID: "bb-pick")
        guard case .ambiguous = (try row(engine, sessionName: "holy-amb-2")).state else {
            Issue.record("Expected the second row to stay ambiguous after a duplicate pick")
            return
        }

        // A different candidate remains pickable.
        engine.pickCandidate(rowID: second.id, candidateID: "cc-pick")
        #expect(try row(engine, sessionName: "holy-amb-2").state
            == .exactResume(providerSessionID: "cc-pick"))
    }

    // MARK: - Resolver outage and speed

    @Test func batchResolverOutageBlocksRowsRetryablyNeverGuesses() async throws {
        let resolver = FakeBatchResolver(unavailableReason: "resolve-batch timed out")
        let (engine, _, tmux) = makeEngine(archives: [archived()], resolver: resolver)

        engine.buildPlan()
        await engine.runPreflight()

        #expect((try #require(engine.rows.first)).state == .blocked("resolve-batch timed out"))
        #expect((try #require(engine.rows.first)).phase == .ready)

        await engine.restoreAll()
        #expect(tmux.createdSpecs.isEmpty)
    }

    @Test func perRequestResolverErrorBlocksOnlyItsOwnRow() async throws {
        // The CLI exits 0 and answers every request even when one carries an
        // "error" (e.g. unknown harness). The erroring row blocks retryably —
        // never shell-only demotion, because "the resolver could not answer"
        // is not "no history exists" — and its neighbors resolve normally.
        let resolver = FakeBatchResolver(
            candidatesByCwd: ["/tmp/lane-a": [candidate("aaa-111")]],
            errorsByCwd: ["/tmp/lane-b": "unknown harness 'emacs'; expected one of claude, claude-code, codex, opencode"]
        )
        let (engine, _, _) = makeEngine(
            archives: [
                archived(sessionName: "holy-good"),
                archived(workingDirectory: "/tmp/lane-b", sessionName: "holy-errored"),
            ],
            resolver: resolver
        )

        engine.buildPlan()
        await engine.runPreflight()

        #expect(try row(engine, sessionName: "holy-good").state
            == .exactResume(providerSessionID: "aaa-111"))
        #expect(try row(engine, sessionName: "holy-errored").state
            == .blocked("unknown harness 'emacs'; expected one of claude, claude-code, codex, opencode"))
    }

    @Test func resultCountMismatchFailsClosedForEveryPendingRow() async throws {
        // results[i] answers requests[i]; a count mismatch means the pairing
        // is unknowable, and fail-closed beats guessing which row lost its
        // answer.
        let resolver = FakeBatchResolver(candidatesByCwd: ["/tmp/lane-a": [candidate("aaa-111")]])
        resolver.extraResults = [
            .init(cwd: "/tmp/phantom", harness: "claude-code", runtime: "claude", candidates: [], error: nil),
        ]
        let (engine, _, tmux) = makeEngine(archives: [archived()], resolver: resolver)

        engine.buildPlan()
        await engine.runPreflight()

        guard case let .blocked(reason) = (try #require(engine.rows.first)).state else {
            Issue.record("Expected blocked, got \((try #require(engine.rows.first)).state)")
            return
        }
        #expect(reason.contains("2 results for 1 requests"))

        await engine.restoreAll()
        #expect(tmux.createdSpecs.isEmpty)
    }

    @Test func readyRowsRestoreWhileTheResolverIsStillRunning() async throws {
        // The field failure's wall clock: 25 minutes of resolver starvation
        // held even shell rows hostage. Local facts finish in milliseconds;
        // rows they verify must be restorable before the batch returns.
        let gate = BatchGate()
        let resolver = FakeBatchResolver(candidatesByCwd: ["/tmp/lane-a": [candidate("aaa-111")]])
        resolver.gate = gate
        let (engine, _, tmux) = makeEngine(
            archives: [
                archived(),
                archived(
                    title: "Fast Shell",
                    runtime: .shell,
                    workingDirectory: "/tmp/lane-b",
                    command: "htop",
                    sessionName: "holy-shell-fast"
                ),
            ],
            resolver: resolver
        )

        engine.buildPlan()
        let preflight = Task { await engine.runPreflight() }

        var shellReady = false
        for _ in 0 ..< 2_000 {
            if (try? row(engine, sessionName: "holy-shell-fast"))?.phase == .ready {
                shellReady = true
                break
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(shellReady, "Shell row never reached ready while the resolver hung")
        #expect(engine.isPreflighting)

        await engine.restoreSelected()

        #expect(tmux.createCount(forSessionName: "holy-shell-fast") == 1)
        #expect(try row(engine, sessionName: "holy-shell-fast").phase == .restored(attached: true))
        // The provider row was skipped honestly, not restored blind.
        #expect(tmux.createCount(forSessionName: "holy-lane-claude-11111111") == 0)

        await gate.open()
        await preflight.value
        #expect(try row(engine, sessionName: "holy-lane-claude-11111111").state
            == .exactResume(providerSessionID: "aaa-111"))
    }

    // MARK: - Restore execution

    @Test func restoreCreatesDetachedSessionWithExactResumeCommand() async throws {
        let resolver = FakeBatchResolver(candidatesByCwd: ["/tmp/lane-a": [candidate("aaa-111")]])
        let (engine, adapter, tmux) = makeEngine(archives: [archived()], resolver: resolver)

        engine.buildPlan()
        await engine.runPreflight()
        await engine.restoreAll()

        #expect(tmux.createdSpecs.count == 1)
        let spec = tmux.createdSpecs[0]
        #expect(spec.command == "'claude' '--resume' 'aaa-111'")
        #expect(spec.initialInput == nil)
        #expect((try #require(engine.rows.first)).phase == .restored(attached: false))
        #expect(adapter.attachedArchiveIDs.isEmpty)
        let persisted = adapter.persistedSpecsByArchiveID[(try #require(engine.rows.first)).id]?.last
        #expect(persisted?.command == "'claude' '--resume' 'aaa-111'")
    }

    @Test func restoreNeverReResolvesAfterLaunching() async throws {
        // The argv is the identity. One batch call at preflight is the only
        // resolver traffic; restore adds none, so a post-restore re-resolve
        // can neither bless a wrong pairing nor false-flag a right one.
        let resolver = FakeBatchResolver(candidatesByCwd: ["/tmp/lane-a": [candidate("aaa-111")]])
        let (engine, _, _) = makeEngine(archives: [archived()], resolver: resolver)

        engine.buildPlan()
        await engine.runPreflight()
        #expect(resolver.calls.count == 1)

        await engine.restoreSelected()

        #expect(resolver.calls.count == 1)
        #expect((try #require(engine.rows.first)).phase == .restored(attached: true))
    }

    @Test func restoreSelectedAttachesTheSelectedRow() async throws {
        let resolver = FakeBatchResolver(candidatesByCwd: ["/tmp/lane-a": [candidate("aaa-111")]])
        let (engine, adapter, _) = makeEngine(archives: [archived()], resolver: resolver)

        engine.buildPlan()
        await engine.runPreflight()
        await engine.restoreSelected()

        #expect((try #require(engine.rows.first)).phase == .restored(attached: true))
        #expect(adapter.attachedArchiveIDs == [(try #require(engine.rows.first)).id])
    }

    @Test func retryAdoptsTheAlreadyLiveSessionInsteadOfDuplicating() async throws {
        let resolver = FakeBatchResolver(candidatesByCwd: ["/tmp/lane-a": [candidate("aaa-111")]])
        let (engine, _, tmux) = makeEngine(archives: [archived()], resolver: resolver)

        engine.buildPlan()
        await engine.runPreflight()
        await engine.restoreAll()
        #expect(tmux.createCount(forSessionName: "holy-lane-claude-11111111") == 1)

        await engine.restoreAll()

        #expect(tmux.createCount(forSessionName: "holy-lane-claude-11111111") == 1)
        #expect((try #require(engine.rows.first)).phase == .restored(attached: false))
    }

    @Test func liveSessionAtRestoreTimeIsAdoptedNotRecreated() async throws {
        let resolver = FakeBatchResolver(candidatesByCwd: ["/tmp/lane-a": [candidate("aaa-111")]])
        let tmux = FakeTmux()
        tmux.markLive("holy-lane-claude-11111111")
        let (engine, adapter, _) = makeEngine(
            archives: [archived()],
            resolver: resolver,
            tmux: tmux
        )

        engine.buildPlan()
        await engine.runPreflight()
        #expect((try #require(engine.rows.first)).state == .alreadyRestored)
        // A live identity needs no conversation resolution at all.
        #expect(resolver.calls.isEmpty)

        await engine.restoreSelected()

        #expect(tmux.createdSpecs.isEmpty)
        #expect((try #require(engine.rows.first)).phase == .restored(attached: true))
        #expect(adapter.attachedArchiveIDs == [(try #require(engine.rows.first)).id])
    }

    @Test func restoresRunInBoundedBatches() async throws {
        var archives: [HolyArchivedSession] = []
        var candidatesByCwd: [String: [HolyRestoreResolveCandidate]] = [:]
        var directories: Set<String> = []
        for index in 0 ..< 10 {
            let cwd = "/tmp/batch-\(index)"
            archives.append(archived(
                workingDirectory: cwd,
                sessionName: "holy-batch-\(index)"
            ))
            candidatesByCwd[cwd] = [candidate("id-\(index)")]
            directories.insert(cwd)
        }
        let tmux = FakeTmux()
        tmux.createDelayNanoseconds = 30_000_000
        let resolver = FakeBatchResolver(candidatesByCwd: candidatesByCwd)
        let (engine, _, _) = makeEngine(
            archives: archives,
            resolver: resolver,
            tmux: tmux,
            environment: FakeEnvironment(
                existingDirectories: directories,
                availableExecutables: ["claude"]
            )
        )

        engine.buildPlan()
        await engine.runPreflight()
        await engine.restoreAll()

        #expect(resolver.calls.count == 1)
        #expect(tmux.createdSpecs.count == 10)
        #expect(tmux.maxObservedConcurrentCreates <= HolyRestoreEngine.maxConcurrentRestores)
        #expect(engine.rows.allSatisfy { $0.phase == .restored(attached: false) })
    }

    // MARK: - Ambiguity and honest non-resumes

    @Test func ambiguousRowsAreSkippedUntilACandidateIsPicked() async throws {
        let resolver = FakeBatchResolver(candidatesByCwd: ["/tmp/lane-a": [
            candidate("aaa", end: Self.lastActivity, preview: "first"),
            candidate("bbb", end: Self.lastActivity - 10, preview: "second"),
        ]])
        let (engine, _, tmux) = makeEngine(archives: [archived()], resolver: resolver)

        engine.buildPlan()
        await engine.runPreflight()
        await engine.restoreAll()
        #expect(tmux.createdSpecs.isEmpty)

        engine.pickCandidate(rowID: (try #require(engine.rows.first)).id, candidateID: "bbb")
        #expect((try #require(engine.rows.first)).state == .exactResume(providerSessionID: "bbb"))

        await engine.restoreAll()
        #expect(tmux.createdSpecs.count == 1)
        #expect(tmux.createdSpecs[0].command == "'claude' '--resume' 'bbb'")
    }

    @Test func missingHistoryRecreatesAnHonestShellNeverAFreshConversation() async throws {
        let resolver = FakeBatchResolver(candidatesByCwd: ["/tmp/lane-a": []])
        let (engine, _, tmux) = makeEngine(archives: [archived()], resolver: resolver)

        engine.buildPlan()
        await engine.runPreflight()
        #expect((try #require(engine.rows.first)).state == .missingHistory)
        await engine.restoreAll()

        #expect(tmux.createdSpecs.count == 1)
        let spec = tmux.createdSpecs[0]
        #expect(spec.runtime == .shell)
        #expect(spec.command == nil)
        #expect((try #require(engine.rows.first)).phase == .restored(attached: false))
    }

    @Test func shellRowsRecreateTheExplicitCommandOnlyWithoutTheResolver() async throws {
        let resolver = FakeBatchResolver()
        let (engine, _, tmux) = makeEngine(
            archives: [archived(runtime: .shell, command: "htop", sessionName: "holy-shell-1")],
            resolver: resolver
        )

        engine.buildPlan()
        await engine.runPreflight()
        #expect((try #require(engine.rows.first)).state == .shellOnly)
        await engine.restoreAll()

        #expect(tmux.createdSpecs.count == 1)
        #expect(tmux.createdSpecs[0].command == "htop")
        #expect(tmux.createdSpecs[0].initialInput == nil)
        #expect(resolver.calls.isEmpty)
    }
}
