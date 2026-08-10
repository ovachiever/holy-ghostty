import Foundation
import Testing
@testable import Ghostty

// Provenance and row-identity laws for crash restore.
//
// Holy carries no parent/child edge, so the sheet separates the sessions a
// human named from the helper shells a sub-agent run left behind using one
// heuristic: the machine-generated adoption title. These tests pin what that
// heuristic may and may not claim, what it changes about selection and bulk
// restore, what the row shows so two identical-looking rows can be told
// apart, and that clearing older interruptions removes exactly those.

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
    func resolveExecutable(_ name: String) async -> String? { name }
}

@MainActor
private final class ProvenanceAdapter: HolyRestoreWorkspaceAdapting {
    var fresh: [HolyArchivedSession]
    var older: [HolyArchivedSession]
    private(set) var deletedArchiveIDs: [UUID] = []

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
    func attachRestoredArchive(archiveID: UUID, launchSpec: HolySessionLaunchSpec) -> Bool { true }

    func deleteArchives(archiveIDs: [UUID]) {
        let targets = Set(archiveIDs)
        deletedArchiveIDs += archiveIDs
        fresh.removeAll { targets.contains($0.id) }
        older.removeAll { targets.contains($0.id) }
    }
}

@MainActor
struct HolyRestoreProvenanceTests {
    private static let coldBootReason =
        "Saved layout — the holy tmux server was not running at launch (probably a macOS reboot)."

    private func archived(
        title: String,
        sessionName: String,
        note: String? = nil
    ) -> HolyArchivedSession {
        var spec = HolySessionLaunchSpec.interactiveTmuxShell(title: title)
        spec.runtime = .shell
        spec.command = nil
        spec.note = note
        spec.workingDirectory = "/tmp/\(sessionName)"
        spec.tmux = .init(
            socketName: "holy",
            sessionName: sessionName,
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
            lastKnownWorkingDirectory: "/tmp/\(sessionName)",
            lastActivityAt: Date(timeIntervalSince1970: 1_785_261_280),
            recoveryReason: Self.coldBootReason
        )
    }

    private func parent(_ index: Int, note: String? = nil) -> HolyArchivedSession {
        archived(
            title: "Versova Research \(index)",
            sessionName: "holy-parent-\(index)",
            note: note
        )
    }

    /// Mirrors what Holy writes when it adopts a sub-agent's pane: the pane
    /// label, then "-shell-", then exactly eight uppercase hex digits.
    private func helperTitle(_ index: Int) -> String {
        "holy-shell-\(index)-shell-" + String(format: "%08X", index)
    }

    private func helper(_ index: Int) -> HolyArchivedSession {
        archived(
            title: helperTitle(index),
            sessionName: "holy-helper-\(index)"
        )
    }

    private func makeEngine(
        fresh: [HolyArchivedSession],
        older: [HolyArchivedSession] = []
    ) -> (HolyRestoreEngine, ProvenanceAdapter, RecordingTmux) {
        let adapter = ProvenanceAdapter(fresh: fresh, older: older)
        let tmux = RecordingTmux()
        let engine = HolyRestoreEngine(
            batchResolver: StubBatchResolver(),
            tmux: tmux,
            environment: StubEnvironment(),
            adapter: adapter
        )
        return (engine, adapter, tmux)
    }

    // MARK: - The heuristic itself

    @Test(arguments: [
        // Live evidence from Erik's own board: Holy's adoption titles.
        "holy-shell-12-shell-EC0053C9",
        "holy-shell-9-shell-837CC2E3",
        // The pattern is the suffix, not the "holy-" prefix.
        "worktree-agent-shell-ABCDEF01",
        // Trailing whitespace is trimmed before matching.
        "holy-shell-1-shell-00000000 ",
    ] as [String])
    func machineGeneratedAdoptionTitlesReadAsHelpers(_ title: String) {
        #expect(HolyRestoreProvenance.isHelperSessionTitle(title))
    }

    @Test(arguments: [
        // Human titles, including ones that talk about shells.
        "Versova Research",
        "Agent Do",
        "shell",
        "shell scripts",
        "My Shell Session",
        "Rewrite the shell-startup path",
        // Lowercase hex is not what Holy writes; accepting it would start
        // swallowing hand-written titles.
        "holy-shell-12-shell-ec0053c9",
        // Wrong digit count either way.
        "holy-shell-12-shell-EC0053C",
        "holy-shell-12-shell-EC0053C90",
        // Non-hex letters in the suffix.
        "holy-shell-12-shell-GHIJKLMN",
        // The literal separator is "-shell-", with the leading dash.
        "shell-EC0053C9",
        // Anchored at the end: a human who appends anything reclaims the row.
        "holy-shell-12-shell-EC0053C9 (rebase in flight)",
        "",
    ] as [String])
    func humanAndNearMissTitlesNeverReadAsHelpers(_ title: String) {
        #expect(!HolyRestoreProvenance.isHelperSessionTitle(title))
    }

    @Test func rowsCarryTheHeuristicFromTheirArchivedTitle() {
        let (engine, _, _) = makeEngine(fresh: [parent(0), helper(1)])

        engine.buildPlan()

        #expect(engine.freshParentRows.map(\.archived.title) == ["Versova Research 0"])
        #expect(engine.freshHelperRows.map(\.archived.title) == [helperTitle(1)])
        #expect(engine.freshHelperRows.allSatisfy { $0.isHelperSession })
        #expect(engine.freshParentRows.allSatisfy { !$0.isHelperSession })
    }

    // MARK: - Helpers are never preselected

    @Test func helpersNeverPreselectEvenInATinyBatch() {
        let (engine, _, _) = makeEngine(fresh: [parent(0), helper(1), helper(2)])

        engine.buildPlan()

        #expect(engine.selectedCount == 1)
        #expect(engine.freshParentRows.allSatisfy { $0.isSelected })
        #expect(engine.freshHelperRows.allSatisfy { !$0.isSelected })
    }

    @Test func helperVolumeNeverSuppressesParentPreselection() {
        // Forty helpers plus two parents: the old fresh-count limit would
        // have opened the sheet with nothing selected. The limit counts the
        // rows that can actually preselect, so both parents open checked.
        let helpers = (0 ..< 40).map { helper($0) }
        let (engine, _, _) = makeEngine(fresh: [parent(100), parent(101)] + helpers)

        engine.buildPlan()

        #expect(engine.selectedCount == 2)
        #expect(engine.freshParentRows.allSatisfy { $0.isSelected })
        #expect(engine.freshHelperRows.allSatisfy { !$0.isSelected })
    }

    @Test func tooManyParentsStillOpensWithNothingSelected() {
        let parents = (0 ..< HolyRestoreEngine.freshPreselectionLimit + 1).map { parent($0) }
        let (engine, _, _) = makeEngine(fresh: parents + [helper(500)])

        engine.buildPlan()

        #expect(engine.selectedCount == 0)
    }

    // MARK: - Honest counts

    @Test func interruptedCountIsParentsOnlyAndHelpersAreNamedSeparately() {
        let (engine, _, _) = makeEngine(
            fresh: [parent(0), parent(1)] + (0 ..< 7).map { helper($0) },
            older: [parent(50), helper(51)]
        )

        engine.buildPlan()

        #expect(engine.interruptedCount == 2)
        #expect(engine.freshHelperCount == 7)
        // Older stays a container total: its contents are itemized one level
        // down, inside the disclosure.
        #expect(engine.olderCount == 2)
        #expect(engine.olderParentRows.count == 1)
        #expect(engine.olderHelperRows.count == 1)
    }

    // MARK: - Visible-rows law

    @Test func selectAllWithHelpersCollapsedTouchesParentsOnly() {
        let (engine, _, _) = makeEngine(
            fresh: [parent(0), helper(1)],
            older: [parent(50), helper(51)]
        )
        engine.buildPlan()

        let visible = engine.visibleRowIDs(
            olderExpanded: false,
            freshHelpersExpanded: false,
            olderHelpersExpanded: false
        )
        engine.setSelection(true, rowIDs: visible)

        #expect(visible == engine.freshParentRows.map(\.id))
        #expect(engine.selectedCount == 1)
        #expect(engine.rows.filter(\.isSelected).allSatisfy { !$0.isHelperSession })
    }

    @Test func expandingADisclosureAddsExactlyItsRowsToTheVisibleSet() {
        let (engine, _, _) = makeEngine(
            fresh: [parent(0), helper(1)],
            older: [parent(50), helper(51)]
        )
        engine.buildPlan()

        let freshOpen = engine.visibleRowIDs(
            olderExpanded: false,
            freshHelpersExpanded: true,
            olderHelpersExpanded: false
        )
        #expect(Set(freshOpen) == Set(engine.freshRows.map(\.id)))

        // The older helper group is nested: opening it alone reveals nothing
        // while the older section itself is shut.
        let olderHelpersOnly = engine.visibleRowIDs(
            olderExpanded: false,
            freshHelpersExpanded: false,
            olderHelpersExpanded: true
        )
        #expect(Set(olderHelpersOnly) == Set(engine.freshParentRows.map(\.id)))

        let olderOpen = engine.visibleRowIDs(
            olderExpanded: true,
            freshHelpersExpanded: false,
            olderHelpersExpanded: false
        )
        #expect(Set(olderOpen) == Set(
            engine.freshParentRows.map(\.id) + engine.olderParentRows.map(\.id)
        ))

        let everythingOpen = engine.visibleRowIDs(
            olderExpanded: true,
            freshHelpersExpanded: true,
            olderHelpersExpanded: true
        )
        #expect(Set(everythingOpen) == Set(engine.rows.map(\.id)))
    }

    // MARK: - Bulk restore scope

    @Test func restoreAllSkipsHelperShells() async {
        let (engine, _, tmux) = makeEngine(fresh: [parent(0), helper(1), helper(2)])
        engine.buildPlan()
        await engine.runPreflight()

        await engine.restoreAll()

        #expect(tmux.createdSessionNames == ["holy-parent-0"])
    }

    @Test func helpersStayRestorableThroughExplicitSelection() async {
        let (engine, _, tmux) = makeEngine(fresh: [parent(0), helper(1)])
        engine.buildPlan()
        await engine.runPreflight()

        let helperRow = engine.freshHelperRows[0]
        engine.setSelection(false, rowIDs: engine.rows.map(\.id))
        engine.setSelected(true, rowID: helperRow.id)

        await engine.restoreSelected()

        #expect(tmux.createdSessionNames == ["holy-helper-1"])
    }

    // MARK: - Note on the row

    @Test func rowRendersATrimmedSingleLineNote() {
        let (engine, _, _) = makeEngine(fresh: [
            parent(0, note: "  rebasing auth,\n  do not kill  "),
            parent(1, note: "   "),
            parent(2),
        ])

        engine.buildPlan()

        #expect(engine.rows[0].noteDisplay == "rebasing auth, do not kill")
        #expect(engine.rows[1].noteDisplay == nil)
        #expect(engine.rows[2].noteDisplay == nil)
    }

    @Test func aNoteAtTheLimitIsShownWholeAndOneOverIsCut() {
        let limit = HolyRestoreRow.noteDisplayLimit
        let exact = String(repeating: "a", count: limit)
        let overflowing = String(repeating: "b", count: limit + 1)
        let long = String(repeating: "c", count: 500)

        let (engine, _, _) = makeEngine(fresh: [
            parent(0, note: exact),
            parent(1, note: overflowing),
            parent(2, note: long),
        ])

        engine.buildPlan()

        #expect(engine.rows[0].noteDisplay == exact)

        let cut = engine.rows[1].noteDisplay
        #expect(cut?.count == limit)
        #expect(cut?.hasSuffix("…") == true)
        #expect(cut == String(repeating: "b", count: limit - 1) + "…")

        #expect(engine.rows[2].noteDisplay?.count == limit)
        #expect(engine.rows[2].noteDisplay?.hasSuffix("…") == true)
    }

    // MARK: - Clear older interruptions

    @Test func clearingOlderRemovesExactlyTheOlderSet() {
        let (engine, adapter, _) = makeEngine(
            fresh: [parent(0), helper(1)],
            older: [parent(50), parent(51), helper(52)]
        )
        engine.buildPlan()
        let freshIDs = engine.freshRows.map(\.id)
        let olderIDs = engine.olderRows.map(\.id)

        let cleared = engine.clearOlderInterruptions()

        #expect(cleared == 3)
        #expect(Set(adapter.deletedArchiveIDs) == Set(olderIDs))
        #expect(engine.olderCount == 0)
        #expect(engine.rows.map(\.id) == freshIDs)
        #expect(adapter.older.isEmpty)
        #expect(adapter.fresh.count == 2)
    }

    @Test func clearingWithNoOlderRowsTouchesNothing() {
        let (engine, adapter, _) = makeEngine(fresh: [parent(0)])
        engine.buildPlan()

        let cleared = engine.clearOlderInterruptions()

        #expect(cleared == 0)
        #expect(adapter.deletedArchiveIDs.isEmpty)
        #expect(engine.rows.count == 1)
    }

    @Test func clearingOlderNeverTouchesSelectionInTheFreshBatch() {
        let (engine, _, _) = makeEngine(
            fresh: [parent(0), parent(1)],
            older: [parent(50)]
        )
        engine.buildPlan()
        #expect(engine.selectedCount == 2)

        engine.clearOlderInterruptions()

        #expect(engine.selectedCount == 2)
        #expect(engine.interruptedCount == 2)
    }
}
