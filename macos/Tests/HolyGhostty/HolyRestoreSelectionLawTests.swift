import Foundation
import Testing
@testable import Ghostty

// The selection law: a small fresh batch (<= freshPreselectionLimit) opens
// fully selected, a big one opens with nothing selected, and older rows
// never preselect. Select All / Select None act on caller-visible rows.
// Restore All is scoped to the fresh batch; Restore Selected follows
// selection wherever it lives. "Restore Selected (N)" must always be true.

private struct StubBatchResolver: HolyRestoreBatchResolving {
    func resolveBatch(
        _ requests: [HolyRestoreResolveBatchRequest]
    ) async -> HolyRestoreBatchResolveOutcome {
        .resolverUnavailable("stub")
    }
}

private final class RecordingTmux: HolyRestoreTmuxControlling, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var liveSessionNames: Set<String> = []
    private(set) var createdSessionNames: [String] = []

    func liveness(for identity: HolyTmuxLiveIdentity) async -> HolyTmuxLiveness {
        lock.lock()
        defer { lock.unlock() }
        return liveSessionNames.contains(identity.sessionName) ? .present : .absent
    }

    func createDetached(for launchSpec: HolySessionLaunchSpec) async -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let sessionName = launchSpec.tmux?.sessionName {
            createdSessionNames.append(sessionName)
            liveSessionNames.insert(sessionName)
        }
        return nil
    }
}

private struct StubEnvironment: HolyRestoreEnvironmentProbing {
    func directoryExists(_ path: String) -> Bool { true }
    func executableExists(_ name: String) async -> Bool { true }
}

@MainActor
private final class BatchAdapter: HolyRestoreWorkspaceAdapting {
    var fresh: [HolyArchivedSession]
    var older: [HolyArchivedSession]
    private(set) var attachedArchiveIDs: [UUID] = []

    init(fresh: [HolyArchivedSession], older: [HolyArchivedSession] = []) {
        self.fresh = fresh
        self.older = older
    }

    var restoreCandidateBatch: HolyCrashRestoreBatch {
        .init(fresh: fresh, older: older)
    }

    func rosterOwnsSession(withHolyID id: UUID) -> Bool { false }
    func rosterOwnsTmuxSessionName(_ name: String) -> Bool { false }
    func persistPlannedLaunchSpec(archiveID: UUID, launchSpec: HolySessionLaunchSpec) {}

    func attachRestoredArchive(archiveID: UUID, launchSpec: HolySessionLaunchSpec) -> Bool {
        attachedArchiveIDs.append(archiveID)
        return true
    }
}

@MainActor
struct HolyRestoreSelectionLawTests {
    private static let coldBootReason =
        "Saved layout — the holy tmux server was not running at launch (probably a macOS reboot). Relaunch from history to recreate."

    private func archived(index: Int, prefix: String = "lane") -> HolyArchivedSession {
        var spec = HolySessionLaunchSpec.interactiveTmuxShell(title: "\(prefix)-\(index)")
        spec.runtime = .shell
        spec.command = nil
        spec.workingDirectory = "/tmp/\(prefix)-\(index)"
        spec.tmux = .init(
            socketName: "holy",
            sessionName: "holy-\(prefix)-\(index)",
            createIfMissing: true
        )

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
            lastKnownWorkingDirectory: "/tmp/\(prefix)-\(index)",
            lastActivityAt: Date(timeIntervalSince1970: 1_785_261_280),
            recoveryReason: Self.coldBootReason
        )
    }

    private func makeEngine(
        freshCount: Int,
        olderCount: Int = 0
    ) -> (HolyRestoreEngine, BatchAdapter, RecordingTmux) {
        let adapter = BatchAdapter(
            fresh: (0 ..< freshCount).map { archived(index: $0) },
            older: (0 ..< olderCount).map { archived(index: $0, prefix: "older") }
        )
        let tmux = RecordingTmux()
        let engine = HolyRestoreEngine(
            batchResolver: StubBatchResolver(),
            tmux: tmux,
            environment: StubEnvironment(),
            adapter: adapter
        )
        return (engine, adapter, tmux)
    }

    // MARK: - Preselection law

    @Test func smallFreshBatchOpensFullySelected() {
        let (engine, _, _) = makeEngine(freshCount: HolyRestoreEngine.freshPreselectionLimit)

        engine.buildPlan()

        #expect(engine.selectedCount == HolyRestoreEngine.freshPreselectionLimit)
        #expect(engine.freshRows.allSatisfy { $0.isSelected })
    }

    @Test func bigFreshBatchOpensWithNothingSelected() {
        let (engine, _, _) = makeEngine(freshCount: HolyRestoreEngine.freshPreselectionLimit + 1)

        engine.buildPlan()

        #expect(engine.selectedCount == 0)
        #expect(engine.rows.allSatisfy { !$0.isSelected })
    }

    @Test func olderRowsNeverPreselectEvenWhenTheFreshBatchIsSmall() {
        let (engine, _, _) = makeEngine(freshCount: 2, olderCount: 40)

        engine.buildPlan()

        #expect(engine.freshRows.allSatisfy { $0.isSelected })
        #expect(engine.olderRows.allSatisfy { !$0.isSelected })
        #expect(engine.selectedCount == 2)
    }

    // MARK: - Honest counts

    @Test func interruptedCountSpeaksOnlyForTheFreshBatch() {
        let (engine, _, _) = makeEngine(freshCount: 3, olderCount: 51)

        engine.buildPlan()

        #expect(engine.interruptedCount == 3)
        #expect(engine.olderCount == 51)
        #expect(engine.rows.count == 54)
    }

    // MARK: - Bulk selection

    @Test func bulkSelectionActsOnExactlyThePassedRows() {
        let (engine, _, _) = makeEngine(freshCount: 3, olderCount: 2)
        engine.buildPlan()
        #expect(engine.selectedCount == 3)

        // Select None over the fresh (visible) section only.
        engine.setSelection(false, rowIDs: engine.freshRows.map(\.id))
        #expect(engine.selectedCount == 0)

        // Select All over fresh + older, as when the older section is open.
        engine.setSelection(true, rowIDs: engine.rows.map(\.id))
        #expect(engine.selectedCount == 5)

        // Ids not passed stay untouched.
        engine.setSelection(false, rowIDs: engine.olderRows.map(\.id))
        #expect(engine.selectedCount == 3)
        #expect(engine.freshRows.allSatisfy { $0.isSelected })
    }

    // MARK: - Restore scope

    @Test func restoreAllRecreatesOnlyTheFreshBatch() async {
        let (engine, _, tmux) = makeEngine(freshCount: 2, olderCount: 3)
        engine.buildPlan()
        await engine.runPreflight()

        await engine.restoreAll()

        #expect(tmux.createdSessionNames.sorted() == ["holy-lane-0", "holy-lane-1"])
        #expect(engine.olderRows.allSatisfy { $0.phase == .ready })
    }

    @Test func restoreSelectedFollowsSelectionIntoTheOlderSection() async {
        let (engine, adapter, tmux) = makeEngine(freshCount: 1, olderCount: 2)
        engine.buildPlan()
        await engine.runPreflight()

        let olderPick = engine.olderRows[0]
        engine.setSelection(false, rowIDs: engine.freshRows.map(\.id))
        engine.setSelected(true, rowID: olderPick.id)
        #expect(engine.selectedCount == 1)

        await engine.restoreSelected()

        #expect(tmux.createdSessionNames == ["holy-older-0"])
        #expect(adapter.attachedArchiveIDs == [olderPick.id])
    }
}
