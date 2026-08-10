import Foundation
import SwiftUI
import Testing
@testable import Ghostty

// Crash-group laws for the restore surface. The partition must speak the
// same language as the fresh/older split (stamped ids exact, legacy rows
// clustered around a fixed anchor), ranks must follow recency and nothing
// else, per-crash restore must carry exactly one batch's parents, and the
// lineage ticks must report sibling archives without ever granting a row a
// second membership.

// MARK: - Partition (pure)

struct HolyRestoreCrashPartitionTests {
    private static let coldBootReason =
        "Saved layout — the holy tmux server was not running at launch (probably a macOS reboot)."

    private let now = Date(timeIntervalSince1970: 1_785_261_280)

    private func archived(
        archivedAt: Date,
        bootBatchID: UUID? = nil,
        sourceSessionID: UUID = UUID(),
        title: String = "Lane"
    ) -> HolyArchivedSession {
        let spec = HolySessionLaunchSpec.interactiveTmuxShell(title: title)
        return .init(
            sourceSessionID: sourceSessionID,
            record: .init(launchSpec: spec),
            phase: .completed,
            preview: "",
            signals: [],
            commandTelemetry: .empty,
            budgetTelemetry: .empty,
            runtimeTelemetry: .empty,
            gitSnapshot: nil,
            lastKnownWorkingDirectory: nil,
            lastActivityAt: archivedAt,
            archivedAt: archivedAt,
            recoveryReason: Self.coldBootReason,
            recoveryBootBatchID: bootBatchID
        )
    }

    @Test func stampedRowsPartitionByExactBootBatchID() {
        let newerBoot = UUID()
        let olderBoot = UUID()
        let sessions = [
            archived(archivedAt: now, bootBatchID: newerBoot),
            archived(archivedAt: now.addingTimeInterval(-3 * 86_400), bootBatchID: olderBoot),
            archived(archivedAt: now.addingTimeInterval(-30), bootBatchID: newerBoot),
            archived(archivedAt: now.addingTimeInterval(-3 * 86_400 - 60), bootBatchID: olderBoot),
        ]

        let groups = HolyRestoreCrashGrouping.groups(from: sessions)

        #expect(groups.count == 2)
        #expect(groups[0].key == .stamped(newerBoot))
        #expect(groups[0].sessions.count == 2)
        #expect(groups[0].newestArchivedAt == now)
        #expect(groups[1].key == .stamped(olderBoot))
        #expect(groups[1].sessions.count == 2)
    }

    @Test func legacyRowsClusterWithinTheWindowOfAFixedAnchor() {
        // The anchor is the cluster's newest member, never a rolling
        // neighbor: -11m sits 2m from the -9m row but outside the window
        // from the anchor, so it opens a NEW cluster.
        let sessions = [
            archived(archivedAt: now),
            archived(archivedAt: now.addingTimeInterval(-9 * 60)),
            archived(archivedAt: now.addingTimeInterval(-11 * 60)),
            archived(archivedAt: now.addingTimeInterval(-19 * 60)),
            archived(archivedAt: now.addingTimeInterval(-5 * 86_400)),
        ]

        let groups = HolyRestoreCrashGrouping.groups(from: sessions)

        #expect(groups.count == 3)
        #expect(groups[0].sessions.map(\.archivedAt) == [
            now, now.addingTimeInterval(-9 * 60),
        ])
        #expect(groups[0].key == .legacyCluster(anchor: now))
        #expect(groups[1].sessions.map(\.archivedAt) == [
            now.addingTimeInterval(-11 * 60), now.addingTimeInterval(-19 * 60),
        ])
        #expect(groups[2].sessions.count == 1)
    }

    @Test func stampedAndLegacyRowsNeverMergeEvenInsideTheWindow() {
        let boot = UUID()
        let sessions = [
            archived(archivedAt: now),
            archived(archivedAt: now.addingTimeInterval(-60), bootBatchID: boot),
            archived(archivedAt: now.addingTimeInterval(-120)),
        ]

        let groups = HolyRestoreCrashGrouping.groups(from: sessions)

        #expect(groups.count == 2)
        let legacy = groups.first { $0.key == .legacyCluster(anchor: now) }
        let stamped = groups.first { $0.key == .stamped(boot) }
        #expect(legacy?.sessions.count == 2)
        #expect(stamped?.sessions.count == 1)
    }

    @Test func partitionIsStableAcrossInputPermutations() {
        let boot = UUID()
        let sessions = [
            archived(archivedAt: now, bootBatchID: boot),
            archived(archivedAt: now.addingTimeInterval(-40), bootBatchID: boot),
            archived(archivedAt: now.addingTimeInterval(-2 * 86_400)),
            archived(archivedAt: now.addingTimeInterval(-2 * 86_400 - 300)),
            archived(archivedAt: now.addingTimeInterval(-9 * 86_400)),
        ]

        let baseline = HolyRestoreCrashGrouping.groups(from: sessions)

        #expect(HolyRestoreCrashGrouping.groups(from: sessions.reversed()) == baseline)
        #expect(HolyRestoreCrashGrouping.groups(from: sessions.shuffled()) == baseline)
        #expect(baseline.map(\.newestArchivedAt) == baseline.map(\.newestArchivedAt).sorted(by: >))
    }

    // MARK: Hue ramp

    @Test func hueRampIsDistinctForRecentRanksAndConvergesToStale() {
        let recent = [
            HolyGhosttyTheme.crashBatchHue(rank: 0),
            HolyGhosttyTheme.crashBatchHue(rank: 1),
            HolyGhosttyTheme.crashBatchHue(rank: 2),
        ]
        #expect(recent[0] != recent[1])
        #expect(recent[1] != recent[2])
        #expect(recent[0] != recent[2])

        #expect(HolyGhosttyTheme.crashBatchHue(rank: 3) == HolyGhosttyTheme.crashBatchStale)
        #expect(HolyGhosttyTheme.crashBatchHue(rank: 9) == HolyGhosttyTheme.crashBatchStale)
        #expect(!recent.contains(HolyGhosttyTheme.crashBatchStale))
    }
}

// MARK: - Engine fixtures

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

    func deleteArchives(archiveIDs: [UUID]) {
        let targets = Set(archiveIDs)
        fresh.removeAll { targets.contains($0.id) }
        older.removeAll { targets.contains($0.id) }
    }
}

// MARK: - Engine laws

@MainActor
struct HolyRestoreCrashGroupEngineTests {
    private static let coldBootReason =
        "Saved layout — the holy tmux server was not running at launch (probably a macOS reboot)."

    private let now = Date(timeIntervalSince1970: 1_785_261_280)
    private let bootA = UUID()
    private let bootB = UUID()

    private func archived(
        title: String,
        sessionName: String,
        archivedAt: Date,
        bootBatchID: UUID? = nil,
        sourceSessionID: UUID = UUID()
    ) -> HolyArchivedSession {
        var spec = HolySessionLaunchSpec.interactiveTmuxShell(title: title)
        spec.runtime = .shell
        spec.command = nil
        spec.workingDirectory = "/tmp/\(sessionName)"
        spec.tmux = .init(
            socketName: "holy",
            sessionName: sessionName,
            createIfMissing: true
        )

        return .init(
            sourceSessionID: sourceSessionID,
            record: .init(launchSpec: spec),
            phase: .completed,
            preview: "",
            signals: [],
            commandTelemetry: .empty,
            budgetTelemetry: .empty,
            runtimeTelemetry: .empty,
            gitSnapshot: nil,
            lastKnownWorkingDirectory: "/tmp/\(sessionName)",
            lastActivityAt: archivedAt,
            archivedAt: archivedAt,
            recoveryReason: Self.coldBootReason,
            recoveryBootBatchID: bootBatchID
        )
    }

    private func helperTitle(_ index: Int) -> String {
        "holy-shell-\(index)-shell-" + String(format: "%08X", index)
    }

    /// Fresh: one parent now. Crash A (2 days ago): two parents + one
    /// helper. Crash B (9 days ago): one parent.
    private func makeGroupedEngine(
        freshSource: UUID = UUID(),
        crashASources: (UUID, UUID) = (UUID(), UUID()),
        crashBSource: UUID = UUID()
    ) -> (HolyRestoreEngine, BatchAdapter, RecordingTmux) {
        let crashADate = now.addingTimeInterval(-2 * 86_400)
        let crashBDate = now.addingTimeInterval(-9 * 86_400)
        let adapter = BatchAdapter(
            fresh: [
                archived(
                    title: "Fresh Lane", sessionName: "holy-fresh-0",
                    archivedAt: now, sourceSessionID: freshSource
                ),
            ],
            older: [
                archived(
                    title: "Crash A Lane 0", sessionName: "holy-a-0",
                    archivedAt: crashADate, bootBatchID: bootA,
                    sourceSessionID: crashASources.0
                ),
                archived(
                    title: "Crash A Lane 1", sessionName: "holy-a-1",
                    archivedAt: crashADate.addingTimeInterval(-30), bootBatchID: bootA,
                    sourceSessionID: crashASources.1
                ),
                archived(
                    title: helperTitle(7), sessionName: "holy-a-helper",
                    archivedAt: crashADate.addingTimeInterval(-45), bootBatchID: bootA
                ),
                archived(
                    title: "Crash B Lane 0", sessionName: "holy-b-0",
                    archivedAt: crashBDate, bootBatchID: bootB,
                    sourceSessionID: crashBSource
                ),
            ]
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

    // MARK: Sections and ranks

    @Test func olderSectionsRankFromOneByRecencyAndFreshIsRankZero() {
        let (engine, _, _) = makeGroupedEngine()
        engine.buildPlan()

        let sections = engine.olderCrashSections

        #expect(HolyRestoreEngine.freshCrashRank == 0)
        #expect(sections.map(\.rank) == [1, 2])
        #expect(sections[0].key == .stamped(bootA))
        #expect(sections[0].parentRows.count == 2)
        #expect(sections[0].helperRows.count == 1)
        #expect(sections[1].key == .stamped(bootB))
        #expect(sections[1].parentRows.count == 1)
        #expect(sections[1].helperRows.isEmpty)
    }

    @Test func ranksIgnoreDisclosureState() {
        let (engine, _, _) = makeGroupedEngine()
        engine.buildPlan()
        let before = engine.olderCrashSections

        // Every disclosure combination projects visibility; none may move a
        // rank. Newest stays rank 1 whether it is open, shut, or alone open.
        for groups in [Set<HolyRestoreCrashGroupKey>(), [before[0].key], [before[1].key]] {
            _ = engine.visibleRowIDs(
                freshHelpersExpanded: true,
                expandedOlderGroups: groups,
                expandedOlderHelperGroups: groups
            )
            #expect(engine.olderCrashSections == before)
        }
    }

    @Test func aCrashOfOnlyHelpersIsStillASectionAndSaysSo() {
        let helperOnly = archived(
            title: helperTitle(3), sessionName: "holy-lonely-helper",
            archivedAt: now.addingTimeInterval(-4 * 86_400), bootBatchID: UUID()
        )
        let adapter = BatchAdapter(
            fresh: [archived(title: "Fresh", sessionName: "holy-f", archivedAt: now)],
            older: [helperOnly]
        )
        let engine = HolyRestoreEngine(
            batchResolver: StubBatchResolver(),
            tmux: RecordingTmux(),
            environment: StubEnvironment(),
            adapter: adapter
        )
        engine.buildPlan()

        let sections = engine.olderCrashSections
        #expect(sections.count == 1)
        #expect(sections[0].parentRows.isEmpty)
        #expect(sections[0].helperRows.count == 1)
    }

    // MARK: Per-crash restore scope

    @Test func restoreCrashGroupRecreatesExactlyThatBatchsParents() async {
        let (engine, adapter, tmux) = makeGroupedEngine()
        engine.buildPlan()
        await engine.runPreflight()
        engine.setSelection(false, rowIDs: engine.rows.map(\.id))

        await engine.restoreCrashGroup(key: .stamped(bootA))

        // Crash A's two parents, headless: no helper, no fresh row, no
        // crash B, no attach.
        #expect(tmux.createdSessionNames.sorted() == ["holy-a-0", "holy-a-1"])
        #expect(adapter.attachedArchiveIDs.isEmpty)
        #expect(engine.restoringCrashGroupKey == nil)
    }

    @Test func restoreCrashGroupWithOnlyHelpersDoesNothing() async {
        let helperBoot = UUID()
        let adapter = BatchAdapter(
            fresh: [archived(title: "Fresh", sessionName: "holy-f", archivedAt: now)],
            older: [
                archived(
                    title: helperTitle(1), sessionName: "holy-h-1",
                    archivedAt: now.addingTimeInterval(-3 * 86_400), bootBatchID: helperBoot
                ),
            ]
        )
        let tmux = RecordingTmux()
        let engine = HolyRestoreEngine(
            batchResolver: StubBatchResolver(),
            tmux: tmux,
            environment: StubEnvironment(),
            adapter: adapter
        )
        engine.buildPlan()
        await engine.runPreflight()

        await engine.restoreCrashGroup(key: .stamped(helperBoot))

        #expect(tmux.createdSessionNames.isEmpty)
        #expect(engine.restoringCrashGroupKey == nil)
    }

    // MARK: Lineage overlap

    @Test func sameSourceInTwoBatchesTicksEachOtherAndOnlyEachOther() throws {
        let shared = UUID()
        let (engine, _, _) = makeGroupedEngine(
            freshSource: shared,
            crashASources: (shared, UUID())
        )
        engine.buildPlan()

        let freshRow = engine.freshParentRows[0]
        let freshTicks = engine.lineageTicks(for: freshRow)
        #expect(freshTicks.map(\.sectionID) == [.older(.stamped(bootA))])
        #expect(freshTicks.map(\.rank) == [1])
        #expect(freshTicks[0].occurredAt == now.addingTimeInterval(-2 * 86_400))

        let sections = engine.olderCrashSections
        let sharedRow = try #require(sections[0].parentRows.first {
            $0.archived.sourceSessionID == shared
        })
        let siblingRow = try #require(sections[0].parentRows.first {
            $0.archived.sourceSessionID != shared
        })
        let sharedTicks = engine.lineageTicks(for: sharedRow)
        #expect(sharedTicks.map(\.sectionID) == [.fresh])
        #expect(sharedTicks.map(\.rank) == [0])
        #expect(engine.lineageTicks(for: siblingRow).isEmpty)
    }

    @Test func sameSourceInThreeBatchesTicksBothOthersSortedByRank() {
        let shared = UUID()
        let (engine, _, _) = makeGroupedEngine(
            freshSource: shared,
            crashASources: (shared, UUID()),
            crashBSource: shared
        )
        engine.buildPlan()

        let freshTicks = engine.lineageTicks(for: engine.freshParentRows[0])
        #expect(freshTicks.map(\.rank) == [1, 2])

        let crashBRow = engine.olderCrashSections[1].parentRows[0]
        let crashBTicks = engine.lineageTicks(for: crashBRow)
        #expect(crashBTicks.map(\.rank) == [0, 1])
        #expect(crashBTicks.map(\.sectionID) == [.fresh, .older(.stamped(bootA))])
    }

    @Test func uniqueSourcesProduceNoTicks() {
        let (engine, _, _) = makeGroupedEngine()
        engine.buildPlan()

        for row in engine.rows {
            #expect(engine.lineageTicks(for: row).isEmpty)
        }
    }

    @Test func lineageNeverGrantsDualMembership() {
        let shared = UUID()
        let (engine, _, _) = makeGroupedEngine(
            freshSource: shared,
            crashASources: (shared, UUID()),
            crashBSource: shared
        )
        engine.buildPlan()

        // Every row id appears exactly once across fresh + all sections;
        // the tick is information, not a second seat.
        var seen: [UUID] = engine.freshRows.map(\.id)
        for section in engine.olderCrashSections {
            seen += (section.parentRows + section.helperRows).map(\.id)
        }
        #expect(seen.count == engine.rows.count)
        #expect(Set(seen).count == seen.count)
    }

    // MARK: Helper nesting and visibility inside crash groups

    @Test func olderCrashRowsNeverPreselect() {
        let (engine, _, _) = makeGroupedEngine()
        engine.buildPlan()

        for section in engine.olderCrashSections {
            #expect((section.parentRows + section.helperRows).allSatisfy { !$0.isSelected })
        }
        #expect(engine.freshParentRows.allSatisfy { $0.isSelected })
    }

    @Test func visibleRowIDsHonorsPerGroupDisclosure() {
        let (engine, _, _) = makeGroupedEngine()
        engine.buildPlan()
        let sections = engine.olderCrashSections
        let crashA = sections[0]
        let crashB = sections[1]

        // Everything shut: fresh parents only.
        #expect(engine.visibleRowIDs(
            freshHelpersExpanded: false,
            expandedOlderGroups: [],
            expandedOlderHelperGroups: []
        ) == engine.freshParentRows.map(\.id))

        // Crash A open: its parents join; its helpers stay behind their own
        // disclosure; crash B contributes nothing.
        let crashAOpen = engine.visibleRowIDs(
            freshHelpersExpanded: false,
            expandedOlderGroups: [crashA.key],
            expandedOlderHelperGroups: []
        )
        #expect(Set(crashAOpen) == Set(
            engine.freshParentRows.map(\.id) + crashA.parentRows.map(\.id)
        ))

        // Crash A's helper disclosure open too: exactly its helpers join.
        let crashAHelpersOpen = engine.visibleRowIDs(
            freshHelpersExpanded: false,
            expandedOlderGroups: [crashA.key],
            expandedOlderHelperGroups: [crashA.key]
        )
        #expect(Set(crashAHelpersOpen) == Set(
            engine.freshParentRows.map(\.id)
                + crashA.parentRows.map(\.id)
                + crashA.helperRows.map(\.id)
        ))

        // A helper disclosure whose group is shut reveals nothing: nesting
        // law, per group.
        #expect(engine.visibleRowIDs(
            freshHelpersExpanded: false,
            expandedOlderGroups: [crashA.key],
            expandedOlderHelperGroups: [crashB.key]
        ) == crashAOpen)
    }

    @Test func legacyProjectionMatchesThePerGroupLawWithEverythingNamedOpen() {
        let (engine, _, _) = makeGroupedEngine()
        engine.buildPlan()
        let allKeys = Set(engine.olderCrashSections.map(\.key))

        #expect(Set(engine.visibleRowIDs(
            olderExpanded: true,
            freshHelpersExpanded: true,
            olderHelpersExpanded: true
        )) == Set(engine.visibleRowIDs(
            freshHelpersExpanded: true,
            expandedOlderGroups: allKeys,
            expandedOlderHelperGroups: allKeys
        )))

        #expect(engine.visibleRowIDs(
            olderExpanded: false,
            freshHelpersExpanded: false,
            olderHelpersExpanded: false
        ) == engine.freshParentRows.map(\.id))
    }
}
