import Foundation
import Testing
@testable import Ghostty

// A restore pass leaves a receipt (mn-3c4b23): when, what asked for it,
// which archives, and what became of each. The engine hands one record per
// pass to the adapter; the store keeps it in its own file; Session History
// renders it. On 2026-09-26 Erik restored about 38 sessions and history
// showed nothing.

// MARK: - Fakes

private struct StubBatchResolver: HolyRestoreBatchResolving {
    func resolveBatch(
        _ requests: [HolyRestoreResolveBatchRequest]
    ) async -> HolyRestoreBatchResolveOutcome {
        .resolverUnavailable("stub")
    }
}

private final class ScriptedTmux: HolyRestoreTmuxControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var liveSessionNames: Set<String> = []
    /// Session names whose create is scripted to fail with this reason.
    var createFailures: [String: String] = [:]
    private(set) var createdSessionNames: [String] = []

    func liveness(for identity: HolyTmuxLiveIdentity) async -> HolyTmuxLiveness {
        lock.lock()
        defer { lock.unlock() }
        return liveSessionNames.contains(identity.sessionName) ? .present : .absent
    }

    func createDetached(for launchSpec: HolySessionLaunchSpec) async -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let sessionName = launchSpec.tmux?.sessionName else { return "no identity" }
        if let failure = createFailures[sessionName] { return failure }
        createdSessionNames.append(sessionName)
        liveSessionNames.insert(sessionName)
        return nil
    }

    func serverGlobalPath(socketName: String?) async -> String? { nil }
}

private struct ScriptedEnvironment: HolyRestoreEnvironmentProbing {
    let existingDirectories: Set<String>

    func directoryExists(_ path: String) -> Bool { existingDirectories.contains(path) }

    func discoverExecutable(
        _ name: String,
        tmuxServerPath: String?
    ) async -> HolyRestoreExecutableDiscovery {
        .tmuxServerPath(name)
    }
}

@MainActor
private final class RecordingAdapter: HolyRestoreWorkspaceAdapting {
    var fresh: [HolyArchivedSession]
    var older: [HolyArchivedSession]
    private(set) var recordedRuns: [HolyRestoreRunRecord] = []
    private(set) var attachedArchiveIDs: [UUID] = []
    var lastShutdown: HolyRestoreShutdownEvent?

    init(fresh: [HolyArchivedSession], older: [HolyArchivedSession] = []) {
        self.fresh = fresh
        self.older = older
    }

    var restoreCandidateBatch: HolyCrashRestoreBatch { .init(fresh: fresh, older: older) }
    func rosterOwnsSession(withHolyID id: UUID) -> Bool { false }
    func rosterOwnsTmuxSessionName(_ name: String) -> Bool { false }
    func persistPlannedLaunchSpec(archiveID: UUID, launchSpec: HolySessionLaunchSpec) {}

    func attachRestoredArchive(archiveID: UUID, launchSpec: HolySessionLaunchSpec) -> Bool {
        attachedArchiveIDs.append(archiveID)
        return true
    }

    func deleteArchives(archiveIDs: [UUID]) {}

    func recordRestoreRun(_ run: HolyRestoreRunRecord) {
        recordedRuns.append(run)
    }
}

private let coldBootReason =
    "Saved layout — the holy tmux server was not running at launch (probably a macOS reboot)."

private func shellArchive(
    title: String,
    sessionName: String,
    workingDirectory: String,
    lastKnownWorkingDirectory: String? = nil
) -> HolyArchivedSession {
    var spec = HolySessionLaunchSpec.interactiveTmuxShell(title: title)
    spec.runtime = .shell
    spec.command = nil
    spec.workingDirectory = workingDirectory
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
        lastKnownWorkingDirectory: lastKnownWorkingDirectory ?? workingDirectory,
        lastActivityAt: Date(timeIntervalSince1970: 1_790_440_000),
        archivedAt: Date(timeIntervalSince1970: 1_790_440_100),
        recoveryReason: coldBootReason,
        recoveryBootBatchID: UUID()
    )
}

// MARK: - Engine records every pass

@MainActor
struct HolyRestoreRunRecordingTests {
    private func makeEngine(
        fresh: [HolyArchivedSession],
        older: [HolyArchivedSession] = [],
        tmux: ScriptedTmux = ScriptedTmux(),
        existingDirectories: Set<String> = ["/tmp/a", "/tmp/b", "/tmp/c"]
    ) -> (HolyRestoreEngine, RecordingAdapter, ScriptedTmux) {
        let adapter = RecordingAdapter(fresh: fresh, older: older)
        let engine = HolyRestoreEngine(
            batchResolver: StubBatchResolver(),
            tmux: tmux,
            environment: ScriptedEnvironment(existingDirectories: existingDirectories),
            adapter: adapter
        )
        return (engine, adapter, tmux)
    }

    @Test func restoreAllRecordsOneRunWithEveryRequestedRowAndItsOutcome() async throws {
        let tmux = ScriptedTmux()
        tmux.createFailures["holy-b"] = "tmux: server refused"
        let (engine, adapter, _) = makeEngine(
            fresh: [
                shellArchive(title: "Egora", sessionName: "holy-a", workingDirectory: "/tmp/a"),
                shellArchive(title: "SubDub", sessionName: "holy-b", workingDirectory: "/tmp/b"),
                shellArchive(title: "Yed Prior", sessionName: "holy-c", workingDirectory: "/tmp/gone"),
            ],
            tmux: tmux
        )
        engine.buildPlan()
        await engine.runPreflight()

        await engine.restoreAll()

        #expect(adapter.recordedRuns.count == 1)
        let run = try #require(adapter.recordedRuns.first)
        #expect(run.trigger == .restoreAll)
        #expect(run.attach == false)
        #expect(run.requestedCount == 3)
        #expect(run.restoredCount == 1)
        #expect(run.failedCount == 1)
        #expect(run.skippedCount == 1)
        #expect(run.finishedAt >= run.startedAt)
        #expect(Set(run.archiveIDs) == Set(engine.rows.map(\.id)))

        let byTitle = Dictionary(uniqueKeysWithValues: run.rows.map { ($0.title, $0) })
        #expect(byTitle["Egora"]?.outcome == .restored(attached: false))
        #expect(byTitle["Egora"]?.workingDirectory == "/tmp/a")
        #expect(byTitle["Egora"]?.runtime == "shell")
        #expect(byTitle["SubDub"]?.outcome == .failed("tmux: server refused"))
        // The skipped row names the blocked verdict, sources included.
        guard case let .skipped(reason)? = byTitle["Yed Prior"]?.outcome else {
            Issue.record("Yed Prior should have been skipped as blocked")
            return
        }
        #expect(reason.contains("last known directory /tmp/gone"))
        #expect(run.errors.map(\.title) == ["SubDub"])
    }

    @Test func restoreSelectedRecordsAttachedOutcomesAndOnlyTheSelectedRows() async throws {
        let (engine, adapter, _) = makeEngine(fresh: [
            shellArchive(title: "One", sessionName: "holy-a", workingDirectory: "/tmp/a"),
            shellArchive(title: "Two", sessionName: "holy-b", workingDirectory: "/tmp/b"),
        ])
        engine.buildPlan()
        await engine.runPreflight()
        engine.setSelection(false, rowIDs: engine.rows.map(\.id))
        let two = try #require(engine.rows.first { $0.archived.title == "Two" })
        engine.setSelected(true, rowID: two.id)

        await engine.restoreSelected()

        let run = try #require(adapter.recordedRuns.first)
        #expect(adapter.recordedRuns.count == 1)
        #expect(run.trigger == .restoreSelected)
        #expect(run.attach == true)
        #expect(run.rows.map(\.title) == ["Two"])
        #expect(run.rows.first?.outcome == .restored(attached: true))
        #expect(run.attachedCount == 1)
        #expect(adapter.attachedArchiveIDs == [two.id])
    }

    @Test func retryAttachAndShutdownGroupEachRecordTheirOwnTrigger() async throws {
        let older = shellArchive(title: "Older", sessionName: "holy-c", workingDirectory: "/tmp/c")
        let (engine, adapter, _) = makeEngine(
            fresh: [shellArchive(title: "Fresh", sessionName: "holy-a", workingDirectory: "/tmp/a")],
            older: [older]
        )
        engine.buildPlan()
        await engine.runPreflight()
        let fresh = try #require(engine.freshParentRows.first)

        await engine.retry(rowID: fresh.id)
        await engine.attach(rowID: fresh.id)
        let section = try #require(engine.olderCrashSections.first)
        await engine.restoreCrashGroup(key: section.key)

        #expect(adapter.recordedRuns.map(\.trigger) == [.retry, .attach, .restoreShutdownGroup])
        #expect(adapter.recordedRuns[0].rows.first?.outcome == .restored(attached: false))
        #expect(adapter.recordedRuns[1].rows.first?.outcome == .restored(attached: true))
        #expect(adapter.recordedRuns[2].rows.map(\.title) == ["Older"])
    }

    @Test func aPassWithNothingRequestedRecordsNothing() async {
        let (engine, adapter, _) = makeEngine(fresh: [])
        engine.buildPlan()
        await engine.restoreAll()
        #expect(adapter.recordedRuns.isEmpty)
    }
}

// MARK: - The run log file

struct HolyRestoreRunLogFileTests {
    @Test func runsRoundTripThroughTheFileNewestFirst() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-restore-runs-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = HolyRestoreRunLogStore.url(in: directory)
        #expect(HolyRestoreRunLogStore.load(from: url).isEmpty)

        let started = Date(timeIntervalSince1970: 1_790_441_000)
        let runs = [
            HolyRestoreRunRecord(
                startedAt: started, finishedAt: started.addingTimeInterval(12),
                trigger: .restoreAll, attach: false,
                rows: [
                    .init(archiveID: UUID(), sourceSessionID: UUID(), title: "Egora", runtime: "claude",
                          workingDirectory: "/tmp/egora", providerSessionID: "a1b2c3d4-e5f6", outcome: .restored(attached: false)),
                    .init(archiveID: UUID(), sourceSessionID: UUID(), title: "SubDub", runtime: "codex",
                          workingDirectory: nil, providerSessionID: nil, outcome: .failed("tmux did not report the restored session after creation.")),
                    .init(archiveID: UUID(), sourceSessionID: UUID(), title: "Yed Prior", runtime: "shell",
                          workingDirectory: nil, providerSessionID: nil, outcome: .skipped("The working directory no longer exists — last known directory /tmp/gone.")),
                ]
            ),
            HolyRestoreRunRecord(
                startedAt: started.addingTimeInterval(-3_600), finishedAt: started.addingTimeInterval(-3_590),
                trigger: .attach, attach: true,
                rows: [
                    .init(archiveID: UUID(), sourceSessionID: UUID(), title: "One", runtime: "shell",
                          workingDirectory: "/tmp/one", providerSessionID: nil, outcome: .restored(attached: true)),
                ]
            ),
        ]
        try HolyRestoreRunLogStore.save(runs, to: url)
        #expect(HolyRestoreRunLogStore.load(from: url) == runs)
    }
}

// MARK: - Session History renders a run

struct HolyRestoreRunSignageTests {
    private let started = Date(timeIntervalSince1970: 1_790_441_000)

    private func run(rows: [HolyRestoreRunRecord.RowResult], trigger: HolyRestoreRunRecord.Trigger = .restoreAll) -> HolyRestoreRunRecord {
        .init(startedAt: started, finishedAt: started.addingTimeInterval(3), trigger: trigger, attach: false, rows: rows)
    }

    private func row(_ title: String, _ outcome: HolyRestoreRunRecord.Outcome, id: String? = nil, dir: String? = nil) -> HolyRestoreRunRecord.RowResult {
        .init(archiveID: UUID(), sourceSessionID: UUID(), title: title, runtime: "claude",
              workingDirectory: dir, providerSessionID: id, outcome: outcome)
    }

    @Test func titleCarriesTheHonestCountsAndOnlyTheNonzeroOnes() {
        let mixed = run(rows: [
            row("A", .restored(attached: false)),
            row("B", .restored(attached: true)),
            row("C", .failed("boom")),
            row("D", .skipped("blocked")),
        ])
        let title = HolySessionHistorySheet.restoreRunTitle(mixed)
        #expect(title.hasPrefix(started.formatted(date: .abbreviated, time: .shortened)))
        #expect(title.hasSuffix("Restore All · 2 of 4 restored · 1 attached · 1 failed · 1 skipped"))

        let clean = run(rows: [row("A", .restored(attached: false))], trigger: .restoreShutdownGroup)
        #expect(HolySessionHistorySheet.restoreRunTitle(clean).hasSuffix("Restore this shutdown · 1 of 1 restored"))
    }

    @Test func rowLineNamesOutcomeConversationAndDirectory() {
        #expect(HolySessionHistorySheet.restoreRunRowLine(
            row("Egora", .restored(attached: false), id: "a1b2c3d4-e5f6-7890", dir: "/tmp/egora")
        ) == "Egora · restored headless · conversation a1b2c3d4… · /tmp/egora")
        #expect(HolySessionHistorySheet.restoreRunRowLine(
            row("SubDub", .failed("tmux: server refused"))
        ) == "SubDub · failed: tmux: server refused")
        #expect(HolySessionHistorySheet.restoreRunRowLine(
            row("Yed Prior", .skipped("remote session — restore is local-only"))
        ) == "Yed Prior · skipped: remote session — restore is local-only")
    }

    @Test func headerCountsRuns() {
        #expect(HolySessionHistorySheet.restoreRunsHeader(count: 1) == "1 restore run")
        #expect(HolySessionHistorySheet.restoreRunsHeader(count: 3) == "3 restore runs")
    }
}
