import Foundation
import Testing
@testable import Ghostty

// The engine orchestrates restore end to end: plan from archived sessions,
// preflight to a row state, create detached tmux sessions in bounded
// batches, confirm the provider identity, and adopt instead of duplicating
// on every retry. All side effects live behind fakes here; the real tmux
// and resolver are covered by the integration suite.

private final class FakeResolver: HolyRestoreResolving, @unchecked Sendable {
    private let lock = NSLock()
    private var outcomesByCwd: [String: HolyRestoreResolveOutcome]
    private(set) var queries: [HolyRestoreResolveQuery] = []

    init(outcomesByCwd: [String: HolyRestoreResolveOutcome] = [:]) {
        self.outcomesByCwd = outcomesByCwd
    }

    func setOutcome(_ outcome: HolyRestoreResolveOutcome, forCwd cwd: String) {
        lock.lock()
        defer { lock.unlock() }
        outcomesByCwd[cwd] = outcome
    }

    func resolve(_ query: HolyRestoreResolveQuery) async -> HolyRestoreResolveOutcome {
        lock.lock()
        defer { lock.unlock() }
        queries.append(query)
        return outcomesByCwd[query.workingDirectory]
            ?? .resolverUnavailable("no scripted outcome for \(query.workingDirectory)")
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

    func executableExists(_ name: String) async -> Bool {
        availableExecutables.contains(name)
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
}

@MainActor
struct HolyRestoreEngineTests {
    private static let coldBootReason = "Saved layout — the holy tmux server was not running at launch."

    private func archived(
        title: String = "Lane",
        runtime: HolySessionRuntime = .claude,
        workingDirectory: String? = "/tmp/lane-a",
        command: String? = "claude",
        sessionName: String? = "holy-lane-claude-11111111",
        lastActivityAt: Date = Date(timeIntervalSince1970: 1_785_261_280)
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

    private func exactOutcome(id: String) -> HolyRestoreResolveOutcome {
        .resolved(.init(
            matched: true,
            providerSessionID: id,
            harness: "claude-code",
            runtime: "claude",
            projectPath: "/tmp/lane-a",
            resumeCommand: "claude --resume \(id)",
            confidence: .exact,
            candidates: [.init(id: id, timestampEnd: 1_785_261_280, preview: "preview")]
        ))
    }

    private func makeEngine(
        archives: [HolyArchivedSession],
        resolver: FakeResolver,
        tmux: FakeTmux = FakeTmux(),
        environment: FakeEnvironment? = nil
    ) -> (HolyRestoreEngine, FakeAdapter, FakeTmux) {
        let adapter = FakeAdapter(archives: archives)
        let engine = HolyRestoreEngine(
            resolver: resolver,
            tmux: tmux,
            environment: environment ?? FakeEnvironment(
                existingDirectories: ["/tmp/lane-a", "/tmp/lane-b"],
                availableExecutables: ["claude", "codex", "opencode"]
            ),
            adapter: adapter
        )
        return (engine, adapter, tmux)
    }

    // MARK: - Plan + preflight

    @Test func preflightMapsExactResolutionToExactResumeRow() async throws {
        let resolver = FakeResolver(outcomesByCwd: ["/tmp/lane-a": exactOutcome(id: "aaa-111")])
        let (engine, _, _) = makeEngine(archives: [archived()], resolver: resolver)

        engine.buildPlan()
        await engine.runPreflight()

        #expect(engine.rows.count == 1)
        #expect((try #require(engine.rows.first)).state == .exactResume(providerSessionID: "aaa-111"))
        #expect((try #require(engine.rows.first)).phase == .ready)
    }

    @Test func preflightPassesArchiveCoordinatesToTheResolver() async throws {
        let resolver = FakeResolver(outcomesByCwd: ["/tmp/lane-a": exactOutcome(id: "aaa-111")])
        let (engine, _, _) = makeEngine(archives: [archived()], resolver: resolver)

        engine.buildPlan()
        await engine.runPreflight()

        #expect(resolver.queries.count == 1)
        #expect(resolver.queries[0].workingDirectory == "/tmp/lane-a")
        #expect(resolver.queries[0].harness == "claude")
        #expect(resolver.queries[0].nearUnixSeconds == 1_785_261_280)
    }

    @Test func planGeneratesAndPersistsAMissingTmuxIdentityOnce() async throws {
        let resolver = FakeResolver(outcomesByCwd: ["/tmp/lane-a": exactOutcome(id: "aaa-111")])
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
        let resolver = FakeResolver(outcomesByCwd: ["/tmp/lane-a": exactOutcome(id: "aaa-111")])
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
        let resolver = FakeResolver()
        let (engine, adapter, _) = makeEngine(archives: [archive], resolver: resolver)
        adapter.rosterHolyIDs = [archive.sourceSessionID]

        engine.buildPlan()
        await engine.runPreflight()

        #expect((try #require(engine.rows.first)).state == .alreadyRestored)
    }

    // MARK: - Restore execution

    @Test func restoreCreatesDetachedSessionWithExactResumeCommand() async throws {
        let resolver = FakeResolver(outcomesByCwd: ["/tmp/lane-a": exactOutcome(id: "aaa-111")])
        let (engine, adapter, tmux) = makeEngine(archives: [archived()], resolver: resolver)

        engine.buildPlan()
        await engine.runPreflight()
        await engine.restoreAll()

        #expect(tmux.createdSpecs.count == 1)
        let spec = tmux.createdSpecs[0]
        #expect(spec.command == "'claude' '--resume' 'aaa-111'")
        #expect(spec.initialInput == nil)
        #expect((try #require(engine.rows.first)).phase == .restored(attached: false))
        #expect((try #require(engine.rows.first)).confirmation == .confirmed)
        #expect(adapter.attachedArchiveIDs.isEmpty)
        let persisted = adapter.persistedSpecsByArchiveID[(try #require(engine.rows.first)).id]?.last
        #expect(persisted?.command == "'claude' '--resume' 'aaa-111'")
    }

    @Test func restoreSelectedAttachesTheSelectedRow() async throws {
        let resolver = FakeResolver(outcomesByCwd: ["/tmp/lane-a": exactOutcome(id: "aaa-111")])
        let (engine, adapter, _) = makeEngine(archives: [archived()], resolver: resolver)

        engine.buildPlan()
        await engine.runPreflight()
        await engine.restoreSelected()

        #expect((try #require(engine.rows.first)).phase == .restored(attached: true))
        #expect(adapter.attachedArchiveIDs == [(try #require(engine.rows.first)).id])
    }

    @Test func retryAdoptsTheAlreadyLiveSessionInsteadOfDuplicating() async throws {
        let resolver = FakeResolver(outcomesByCwd: ["/tmp/lane-a": exactOutcome(id: "aaa-111")])
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
        let resolver = FakeResolver(outcomesByCwd: ["/tmp/lane-a": exactOutcome(id: "aaa-111")])
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

        await engine.restoreSelected()

        #expect(tmux.createdSpecs.isEmpty)
        #expect((try #require(engine.rows.first)).phase == .restored(attached: true))
        #expect(adapter.attachedArchiveIDs == [(try #require(engine.rows.first)).id])
    }

    @Test func restoresRunInBoundedBatches() async throws {
        var archives: [HolyArchivedSession] = []
        var outcomes: [String: HolyRestoreResolveOutcome] = [:]
        var directories: Set<String> = []
        for index in 0 ..< 10 {
            let cwd = "/tmp/batch-\(index)"
            archives.append(archived(
                workingDirectory: cwd,
                sessionName: "holy-batch-\(index)"
            ))
            outcomes[cwd] = exactOutcome(id: "id-\(index)")
            directories.insert(cwd)
        }
        let tmux = FakeTmux()
        tmux.createDelayNanoseconds = 30_000_000
        let (engine, _, _) = makeEngine(
            archives: archives,
            resolver: FakeResolver(outcomesByCwd: outcomes),
            tmux: tmux,
            environment: FakeEnvironment(
                existingDirectories: directories,
                availableExecutables: ["claude"]
            )
        )

        engine.buildPlan()
        await engine.runPreflight()
        await engine.restoreAll()

        #expect(tmux.createdSpecs.count == 10)
        #expect(tmux.maxObservedConcurrentCreates <= HolyRestoreEngine.maxConcurrentRestores)
        #expect(engine.rows.allSatisfy { $0.phase == .restored(attached: false) })
    }

    // MARK: - Identity confirmation

    @Test func confirmationMismatchBlocksTheRow() async throws {
        let resolver = FakeResolver(outcomesByCwd: ["/tmp/lane-a": exactOutcome(id: "aaa-111")])
        let (engine, adapter, tmux) = makeEngine(archives: [archived()], resolver: resolver)

        engine.buildPlan()
        await engine.runPreflight()
        resolver.setOutcome(exactOutcome(id: "zzz-999"), forCwd: "/tmp/lane-a")
        await engine.restoreSelected()

        guard case .failed = (try #require(engine.rows.first)).phase else {
            Issue.record("Expected failed phase, got \((try #require(engine.rows.first)).phase)")
            return
        }
        #expect((try #require(engine.rows.first)).confirmation == .mismatch(expected: "aaa-111", resolved: "zzz-999"))
        #expect(adapter.attachedArchiveIDs.isEmpty)
        #expect(tmux.createdSpecs.count == 1)
    }

    @Test func confirmationOutageIsUnverifiedNotAMismatch() async throws {
        let resolver = FakeResolver(outcomesByCwd: ["/tmp/lane-a": exactOutcome(id: "aaa-111")])
        let (engine, _, _) = makeEngine(archives: [archived()], resolver: resolver)

        engine.buildPlan()
        await engine.runPreflight()
        resolver.setOutcome(.resolverUnavailable("resolver died mid-batch"), forCwd: "/tmp/lane-a")
        await engine.restoreAll()

        #expect((try #require(engine.rows.first)).phase == .restored(attached: false))
        guard case .unverified = (try #require(engine.rows.first)).confirmation else {
            Issue.record("Expected unverified, got \((try #require(engine.rows.first)).confirmation)")
            return
        }
    }

    // MARK: - Ambiguity and honest non-resumes

    @Test func ambiguousRowsAreSkippedUntilACandidateIsPicked() async throws {
        let candidates: [HolyRestoreResolveCandidate] = [
            .init(id: "aaa", timestampEnd: 100, preview: "first"),
            .init(id: "bbb", timestampEnd: 200, preview: "second"),
        ]
        let resolver = FakeResolver(outcomesByCwd: ["/tmp/lane-a": .resolved(.init(
            matched: false,
            providerSessionID: nil,
            harness: "claude-code",
            runtime: "claude",
            projectPath: "/tmp/lane-a",
            resumeCommand: nil,
            confidence: .ambiguous,
            candidates: candidates
        ))])
        let (engine, _, tmux) = makeEngine(archives: [archived()], resolver: resolver)

        engine.buildPlan()
        await engine.runPreflight()
        await engine.restoreAll()
        #expect(tmux.createdSpecs.isEmpty)

        engine.pickCandidate(rowID: (try #require(engine.rows.first)).id, candidateID: "bbb")
        #expect((try #require(engine.rows.first)).state == .exactResume(providerSessionID: "bbb"))

        resolver.setOutcome(exactOutcome(id: "bbb"), forCwd: "/tmp/lane-a")
        await engine.restoreAll()
        #expect(tmux.createdSpecs.count == 1)
        #expect(tmux.createdSpecs[0].command == "'claude' '--resume' 'bbb'")
    }

    @Test func missingHistoryRecreatesAnHonestShellNeverAFreshConversation() async throws {
        let resolver = FakeResolver(outcomesByCwd: ["/tmp/lane-a": .resolved(.init(
            matched: false,
            providerSessionID: nil,
            harness: "claude-code",
            runtime: "claude",
            projectPath: "/tmp/lane-a",
            resumeCommand: nil,
            confidence: .none,
            candidates: []
        ))])
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
        #expect((try #require(engine.rows.first)).confirmation == .notApplicable)
    }

    @Test func shellRowsRecreateTheExplicitCommandOnly() async throws {
        let resolver = FakeResolver()
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
        #expect(resolver.queries.isEmpty)
    }
}
