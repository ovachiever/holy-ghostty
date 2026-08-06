import Foundation
import Testing
@testable import Ghostty

// The restore surface must speak for one reboot at a time. These tests pin
// the batch split: stamped rows scope by exact boot-batch id, legacy rows
// cluster by proximity to the newest candidate, and everything older stays
// reachable in `older` without ever inflating the fresh count. The banner
// predicate matrix rides along because it consumes the same split.
struct HolyCrashRestoreBatchScopingTests {
    private static let coldBootReason =
        "Saved layout — the holy tmux server was not running at launch (probably a macOS reboot). Relaunch from history to recreate."

    private func archived(
        title: String = "Lane",
        transport: HolySessionTransportSpec = .local,
        recoveryReason: String? = HolyCrashRestoreBatchScopingTests.coldBootReason,
        archivedAt: Date,
        bootBatchID: UUID? = nil
    ) -> HolyArchivedSession {
        var spec = HolySessionLaunchSpec.interactiveTmuxShell(title: title)
        spec.transport = transport
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
            lastKnownWorkingDirectory: nil,
            lastActivityAt: archivedAt,
            archivedAt: archivedAt,
            recoveryReason: recoveryReason,
            recoveryBootBatchID: bootBatchID
        )
    }

    private let now = Date(timeIntervalSince1970: 1_785_261_280)

    // MARK: - Batch-id scoping

    @Test func freshIsExactlyTheNewestStampedBootBatch() {
        let thisBoot = UUID()
        let lastWeekBoot = UUID()
        let sessions = [
            archived(archivedAt: now, bootBatchID: thisBoot),
            archived(archivedAt: now.addingTimeInterval(-1), bootBatchID: thisBoot),
            archived(archivedAt: now.addingTimeInterval(-7 * 86_400), bootBatchID: lastWeekBoot),
            archived(archivedAt: now.addingTimeInterval(-14 * 86_400), bootBatchID: UUID()),
        ]

        let batch = HolyWorkspaceStore.crashRestoreBatch(from: sessions)

        #expect(batch.fresh.count == 2)
        #expect(batch.fresh.allSatisfy { $0.recoveryBootBatchID == thisBoot })
        #expect(batch.older.count == 2)
        #expect(batch.older.allSatisfy { $0.recoveryBootBatchID != thisBoot })
    }

    @Test func stampedScopingIgnoresWallClockProximity() {
        // Two boots minutes apart (crash loop): the id keeps them separate
        // where any wall-clock window would have merged them.
        let secondBoot = UUID()
        let firstBoot = UUID()
        let sessions = [
            archived(archivedAt: now, bootBatchID: secondBoot),
            archived(archivedAt: now.addingTimeInterval(-120), bootBatchID: firstBoot),
        ]

        let batch = HolyWorkspaceStore.crashRestoreBatch(from: sessions)

        #expect(batch.fresh.count == 1)
        #expect(batch.fresh.first?.recoveryBootBatchID == secondBoot)
        #expect(batch.older.count == 1)
    }

    // MARK: - Legacy clustering (rows persisted before the marker existed)

    @Test func legacyRowsClusterAroundTheNewestCandidate() {
        let sessions = [
            archived(archivedAt: now),
            archived(archivedAt: now.addingTimeInterval(-120)),
            archived(archivedAt: now.addingTimeInterval(-3 * 86_400)),
            archived(archivedAt: now.addingTimeInterval(-20 * 86_400)),
        ]

        let batch = HolyWorkspaceStore.crashRestoreBatch(from: sessions)

        #expect(batch.fresh.count == 2)
        #expect(batch.older.count == 2)
        #expect(batch.fresh.map(\.archivedAt) == [now, now.addingTimeInterval(-120)])
    }

    @Test func legacyClusterNeverAdoptsStampedRows() {
        // A stamped row inside the legacy window belongs to its own batch,
        // not to the legacy cluster.
        let sessions = [
            archived(archivedAt: now),
            archived(archivedAt: now.addingTimeInterval(-60), bootBatchID: UUID()),
        ]

        let batch = HolyWorkspaceStore.crashRestoreBatch(from: sessions)

        #expect(batch.fresh.count == 1)
        #expect(batch.fresh.first?.recoveryBootBatchID == nil)
        #expect(batch.older.count == 1)
    }

    // MARK: - Candidacy filtering

    @Test func nonCandidatesNeverEnterEitherSection() {
        let sessions = [
            archived(archivedAt: now),
            archived(recoveryReason: nil, archivedAt: now),
            archived(recoveryReason: "Managed worktree was missing at launch.", archivedAt: now),
            archived(
                transport: .init(kind: .ssh, hostLabel: "MacBook", sshDestination: "erik@mb"),
                archivedAt: now
            ),
        ]

        let batch = HolyWorkspaceStore.crashRestoreBatch(from: sessions)

        #expect(batch.totalCount == 1)
        #expect(batch.fresh.count == 1)
    }

    @Test func noCandidatesMeansAnEmptyBatch() {
        let batch = HolyWorkspaceStore.crashRestoreBatch(from: [
            archived(recoveryReason: nil, archivedAt: now),
        ])

        #expect(batch.isEmpty)
        #expect(batch == .empty)
    }

    // MARK: - Banner predicate matrix

    @Test(arguments: [
        // (dismissed, presented, freshCount, expected)
        (false, false, 1, true),
        (false, false, 54, true),
        (false, false, 0, false),
        (true, false, 5, false),
        (false, true, 5, false),
        (true, true, 5, false),
    ] as [(Bool, Bool, Int, Bool)])
    func bannerOffersExactlyWhenFreshRowsExistUndismissedUnpresented(
        _ matrix: (Bool, Bool, Int, Bool)
    ) {
        let (dismissed, presented, freshCount, expected) = matrix
        #expect(HolyWorkspaceStore.shouldOfferCrashRestore(
            bannerDismissed: dismissed,
            restorePresented: presented,
            freshBatchCount: freshCount
        ) == expected)
    }

    // MARK: - Durable entry-point enablement

    @Test func menuEnablementFollowsAnyBatchNotJustFresh() {
        // The View menu item enables whenever ANY cold-boot archive exists,
        // fresh or older — it is the durable path after the banner is gone.
        let anyBatch = HolyWorkspaceStore.crashRestoreBatch(from: [
            archived(archivedAt: now.addingTimeInterval(-30 * 86_400)),
        ])
        #expect(!anyBatch.isEmpty)

        let empty = HolyWorkspaceStore.crashRestoreBatch(from: [])
        #expect(empty.isEmpty)
    }
}
