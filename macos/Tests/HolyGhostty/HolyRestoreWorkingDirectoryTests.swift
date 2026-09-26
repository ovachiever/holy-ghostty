import Foundation
import Testing
@testable import Ghostty

// A row whose working directory no longer exists names the source of the
// path and still restores into the last known valid directory (mn-3c4b23,
// deliverable 4). Row 985BC829 on 2026-09-26 claimed
// "/Users/erik/Custom-Coding/Research Comprehensive App Security" — a pane
// title appended to a folder by tmux discovery — while the launch record
// still knew "/Users/erik/Custom-Coding".

private let inferredBad = "/Users/erik/Custom-Coding/Research Comprehensive App Security"
private let launchGood = "/Users/erik/Custom-Coding"

private func resolve(
    lastKnown: String? = inferredBad,
    launch: String? = launchGood,
    worktree: String? = nil,
    root: String? = nil,
    existing: Set<String>
) -> HolyRestoreWorkingDirectoryResolution {
    .resolve(
        lastKnownWorkingDirectory: lastKnown,
        launchWorkingDirectory: launch,
        gitWorktreePath: worktree,
        repositoryRoot: root,
        directoryExists: { existing.contains($0) }
    )
}

struct HolyRestoreWorkingDirResolutionTests {
    @Test func theInferredPathLosesToTheLaunchDirectoryThatExists() {
        let resolution = resolve(existing: [launchGood])
        #expect(resolution.path == launchGood)
        #expect(resolution.source == .launchDirectory)
        #expect(resolution.usedFallback)
        #expect(resolution.missingBeforeChosen.map(\.path) == [inferredBad])
        #expect(resolution.displayLine
            == "\(launchGood) — launch directory (last known directory \(inferredBad) no longer exists)")
    }

    @Test func theFirstRecordedDirectoryWinsWhenItExists() {
        let resolution = resolve(existing: [inferredBad, launchGood])
        #expect(resolution.path == inferredBad)
        #expect(resolution.source == .lastKnownDirectory)
        #expect(!resolution.usedFallback)
        #expect(resolution.displayLine == inferredBad)
    }

    @Test func gitEvidenceIsTheNextFallbackInOrder() {
        let resolution = resolve(
            worktree: "/Users/erik/Custom-Coding/.claude/worktrees/lane",
            root: "/Users/erik/Custom-Coding/holy-ghostty",
            existing: ["/Users/erik/Custom-Coding/holy-ghostty"]
        )
        #expect(resolution.source == .repositoryRoot)
        #expect(resolution.candidates.map(\.source)
            == [.lastKnownDirectory, .launchDirectory, .gitWorktree, .repositoryRoot])
        #expect(resolution.missingBeforeChosen.count == 3)
    }

    @Test func whenEveryRecordedPathIsGoneTheParentIsTheLastKnownValidDirectory() {
        let resolution = resolve(launch: "/Users/erik/Custom-Coding/lane-gone", existing: ["/Users/erik/Custom-Coding"])
        #expect(resolution.path == "/Users/erik/Custom-Coding")
        #expect(resolution.source == .parentOfLastKnownDirectory)
        #expect(resolution.displayLine
            == "/Users/erik/Custom-Coding — parent of the last known directory (last known directory \(inferredBad) no longer exists)")
    }

    @Test func parentsAreNeverOfferedWhileARecordedPathExists() {
        let resolution = resolve(existing: [launchGood, "/Users/erik"])
        #expect(resolution.candidates.map(\.source) == [.lastKnownDirectory, .launchDirectory])
    }

    @Test func nothingExistingBlocksWithEverySourceNamed() {
        let resolution = resolve(existing: [])
        #expect(resolution.path == nil)
        #expect(resolution.hasRecordedDirectory)
        // The inferred path's parent IS the launch directory, so it is named
        // once, under the source that recorded it first.
        #expect(resolution.missingReason
            == "The working directory no longer exists — last known directory \(inferredBad); "
            + "launch directory \(launchGood); parent of the launch directory /Users/erik.")
        #expect(resolution.displayLine == "\(inferredBad) — last known directory, no longer exists")
    }

    @Test func duplicatesAndBlanksCollapseAndNothingRecordedIsUnassigned() {
        let same = resolve(lastKnown: " \(launchGood)/ ", launch: launchGood, existing: [launchGood])
        #expect(same.candidates.count == 1)
        #expect(same.source == .lastKnownDirectory)

        let none = resolve(lastKnown: "", launch: nil, existing: [])
        #expect(none == .empty)
        #expect(none.displayLine == "Unassigned")
        #expect(none.missingReason == "No working directory was recorded for this session.")
    }
}

// MARK: - Preflight names the sources

struct HolyRestoreWorkingDirPreflightTests {
    private func context(resolution: HolyRestoreWorkingDirectoryResolution) -> HolyRestorePreflightContext {
        .init(
            hostSupported: true,
            workingDirectoryExists: resolution.hasRecordedDirectory ? (resolution.path != nil) : nil,
            workingDirectory: resolution.path,
            executable: .tmuxServerPath("claude"),
            resolveOutcome: nil,
            liveness: .absent,
            conflictReason: nil,
            workingDirectoryResolution: resolution
        )
    }

    @Test func shellAndProviderRowsBlockWithTheSourcesNamed() {
        let gone = resolve(existing: [])
        let shell = HolyRestorePreflight.rowState(runtime: .shell, context: context(resolution: gone))
        let claude = HolyRestorePreflight.rowState(runtime: .claude, context: context(resolution: gone))
        #expect(shell == .blocked(gone.missingReason))
        #expect(claude == .blocked(gone.missingReason))
        #expect(gone.missingReason.contains("last known directory \(inferredBad)"))
        #expect(gone.missingReason.contains("launch directory \(launchGood)"))
    }

    @Test func aFallbackDirectoryIsNotABlocker() {
        let fallback = resolve(existing: [launchGood])
        #expect(HolyRestorePreflight.rowState(runtime: .shell, context: context(resolution: fallback)) == .shellOnly)
        #expect(HolyRestorePreflight.rowState(runtime: .claude, context: context(resolution: fallback))
            == .blocked("The conversation resolver has not run yet."))
    }

    @Test func contextsWithoutAResolutionKeepTheSinglePathMessage() {
        let legacy = HolyRestorePreflightContext(
            hostSupported: true,
            workingDirectoryExists: false,
            workingDirectory: "/tmp/gone",
            executable: nil,
            resolveOutcome: nil,
            liveness: .absent,
            conflictReason: nil
        )
        #expect(HolyRestorePreflight.rowState(runtime: .shell, context: legacy)
            == .blocked("The working directory /tmp/gone no longer exists."))
    }
}

// MARK: - Engine restores into the fallback and the row says so

private struct StubBatchResolver: HolyRestoreBatchResolving {
    func resolveBatch(
        _ requests: [HolyRestoreResolveBatchRequest]
    ) async -> HolyRestoreBatchResolveOutcome {
        .resolverUnavailable("stub")
    }
}

private final class RecordingTmux: HolyRestoreTmuxControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var liveSessionNames: Set<String> = []
    private(set) var createdSpecs: [HolySessionLaunchSpec] = []

    func liveness(for identity: HolyTmuxLiveIdentity) async -> HolyTmuxLiveness {
        lock.lock()
        defer { lock.unlock() }
        return liveSessionNames.contains(identity.sessionName) ? .present : .absent
    }

    func createDetached(for launchSpec: HolySessionLaunchSpec) async -> String? {
        lock.lock()
        defer { lock.unlock() }
        createdSpecs.append(launchSpec)
        if let sessionName = launchSpec.tmux?.sessionName {
            liveSessionNames.insert(sessionName)
        }
        return nil
    }

    func serverGlobalPath(socketName: String?) async -> String? { nil }
}

private struct ScriptedEnvironment: HolyRestoreEnvironmentProbing {
    var existingDirectories: Set<String>

    func directoryExists(_ path: String) -> Bool { existingDirectories.contains(path) }

    func discoverExecutable(
        _ name: String,
        tmuxServerPath: String?
    ) async -> HolyRestoreExecutableDiscovery {
        .tmuxServerPath(name)
    }
}

@MainActor
private final class PlainAdapter: HolyRestoreWorkspaceAdapting {
    let fresh: [HolyArchivedSession]
    private(set) var persistedSpecs: [HolySessionLaunchSpec] = []

    init(fresh: [HolyArchivedSession]) { self.fresh = fresh }

    var restoreCandidateBatch: HolyCrashRestoreBatch { .init(fresh: fresh, older: []) }
    func rosterOwnsSession(withHolyID id: UUID) -> Bool { false }
    func rosterOwnsTmuxSessionName(_ name: String) -> Bool { false }
    func persistPlannedLaunchSpec(archiveID: UUID, launchSpec: HolySessionLaunchSpec) {
        persistedSpecs.append(launchSpec)
    }
    func attachRestoredArchive(archiveID: UUID, launchSpec: HolySessionLaunchSpec) -> Bool { true }
    func deleteArchives(archiveIDs: [UUID]) {}
}

@MainActor
struct HolyRestoreWorkingDirectoryEngineTests {
    private func row985BC829() -> HolyArchivedSession {
        var spec = HolySessionLaunchSpec.interactiveTmuxShell(title: "Research Comprehensive App Security")
        spec.runtime = .shell
        spec.command = nil
        spec.workingDirectory = launchGood
        spec.tmux = .init(socketName: "holy", sessionName: "holy-985bc829", createIfMissing: true)
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
            lastKnownWorkingDirectory: inferredBad,
            lastActivityAt: Date(timeIntervalSince1970: 1_790_440_000),
            archivedAt: Date(timeIntervalSince1970: 1_790_440_100),
            recoveryReason: "Saved layout — the holy tmux server was not running at launch (probably a macOS reboot).",
            recoveryBootBatchID: UUID()
        )
    }

    @Test func theRowNamesTheFallbackAndRestoreRunsThere() async throws {
        let tmux = RecordingTmux()
        let adapter = PlainAdapter(fresh: [row985BC829()])
        let engine = HolyRestoreEngine(
            batchResolver: StubBatchResolver(),
            tmux: tmux,
            environment: ScriptedEnvironment(existingDirectories: [launchGood]),
            adapter: adapter
        )
        engine.buildPlan()
        let planned = try #require(engine.rows.first)
        #expect(planned.workingDirectoryResolution.source == .launchDirectory)
        #expect(planned.workingDirectoryDisplay
            == "\(launchGood) — launch directory (last known directory \(inferredBad) no longer exists)")

        await engine.runPreflight()
        let ready = try #require(engine.rows.first)
        #expect(ready.state == .shellOnly)

        await engine.restoreAll()
        let created = try #require(tmux.createdSpecs.first)
        #expect(created.workingDirectory == launchGood)
        #expect(adapter.persistedSpecs.last?.workingDirectory == launchGood)
        #expect(engine.rows.first?.phase == .restored(attached: false))
    }

    @Test func aDirectoryRecreatedBetweenPassesCountsOnTheNextPreflight() async throws {
        var environment = ScriptedEnvironment(existingDirectories: [])
        let engine = HolyRestoreEngine(
            batchResolver: StubBatchResolver(),
            tmux: RecordingTmux(),
            environment: environment,
            adapter: PlainAdapter(fresh: [row985BC829()])
        )
        engine.buildPlan()
        await engine.runPreflight()
        let blocked = try #require(engine.rows.first)
        guard case let .blocked(reason) = blocked.state else {
            Issue.record("expected a blocked verdict, got \(blocked.state)")
            return
        }
        #expect(reason.contains("last known directory \(inferredBad)"))
        #expect(reason.contains("launch directory \(launchGood)"))
        #expect(blocked.workingDirectoryDisplay == "\(inferredBad) — last known directory, no longer exists")

        // The engine re-resolves each pass; a new engine over the same
        // rows with the directory back sees it (environments are values).
        environment.existingDirectories = [launchGood]
        let recovered = HolyRestoreEngine(
            batchResolver: StubBatchResolver(),
            tmux: RecordingTmux(),
            environment: environment,
            adapter: PlainAdapter(fresh: [row985BC829()])
        )
        recovered.buildPlan()
        await recovered.runPreflight()
        #expect(recovered.rows.first?.state == .shellOnly)
    }
}
