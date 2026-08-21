import Foundation
import Testing
@testable import Ghostty

/// Erik, 2026-08-21: the coordination footer read "30 overlapping files · Same
/// worktree with 1 session" while the two sessions had co-edited exactly zero
/// files. Both sessions lived in one checkout, so both `git status` runs
/// described the same directory, the two changed-file sets were identical by
/// construction, and the intersection was simply every dirty file in the tree.
///
/// These tests hold the line that a shared checkout is counted, never
/// attributed, and that genuinely independent worktrees keep their intersection
/// math untouched.
struct HolyCoordinationFileAttributionTests {
    private let peerID = UUID()
    private let otherPeerID = UUID()

    // MARK: - The reported regression

    @Test func sharedCheckoutFilesAreNeverReportedAsOverlap() {
        // The observed state: one checkout, 30 dirty files, two sessions, and
        // therefore two identical git-status readings.
        let dirtyTree = Set((1...30).map { "src/file\($0).swift" })

        let attribution = HolyCoordinationFileAttribution.attribute(
            sessionFiles: dirtyTree,
            peers: [.init(id: peerID, sharesWorktree: true, changedFiles: Array(dirtyTree))]
        )

        #expect(attribution.overlappingFiles.isEmpty)
        #expect(attribution.overlappingSessionIDs.isEmpty)
        #expect(attribution.sharedWorktreeChangedFiles == dirtyTree)
        #expect(attribution.sharedWorktreeChangedFiles.count == 30)
    }

    @Test func sharedCheckoutFooterSaysCheckoutAndNeverSaysOverlapping() {
        let coordination = makeCoordination(
            sharedWorktreeSessionIDs: [peerID],
            sharedWorktreeChangedFiles: (1...30).map { "src/file\($0).swift" }
        )

        let texts = coordination
            .riskStatusItems(hasBranchOwnershipDrift: false)
            .map(\.text)

        #expect(texts == ["Same worktree with 1 session · 30 uncommitted files"])
        #expect(!texts.contains { $0.localizedCaseInsensitiveContains("overlapping") })
    }

    @Test func sharedCheckoutChipCarriesNoDangerEmphasis() {
        let coordination = makeCoordination(
            sharedWorktreeSessionIDs: [peerID],
            sharedWorktreeChangedFiles: (1...30).map { "src/file\($0).swift" }
        )

        let items = coordination.riskStatusItems(hasBranchOwnershipDrift: false)

        #expect(items.count == 1)
        #expect(items.first?.emphasis == .secondary)
        #expect(items.first?.symbol == "link")
    }

    // MARK: - Different worktrees keep their math

    @Test func differentWorktreesStillIntersect() {
        let attribution = HolyCoordinationFileAttribution.attribute(
            sessionFiles: ["a.swift", "b.swift", "c.swift"],
            peers: [.init(
                id: peerID,
                sharesWorktree: false,
                changedFiles: ["b.swift", "c.swift", "d.swift"]
            )]
        )

        #expect(attribution.overlappingFiles == ["b.swift", "c.swift"])
        #expect(attribution.overlappingSessionIDs == [peerID])
        #expect(attribution.sharedWorktreeChangedFiles.isEmpty)
    }

    @Test func differentWorktreesWithDisjointSetsReportNothing() {
        let attribution = HolyCoordinationFileAttribution.attribute(
            sessionFiles: ["a.swift"],
            peers: [.init(id: peerID, sharesWorktree: false, changedFiles: ["z.swift"])]
        )

        #expect(attribution.overlappingFiles.isEmpty)
        #expect(attribution.overlappingSessionIDs.isEmpty)
        #expect(attribution.sharedWorktreeChangedFiles.isEmpty)
    }

    /// The degenerate case is keyed on the shared worktree, not on set
    /// equality. Two sessions in separate worktrees that edited exactly the
    /// same files are colliding as hard as it gets, and must still read as
    /// overlap.
    @Test func identicalSetsInDifferentWorktreesAreStillOverlap() {
        let sameFiles: Set<String> = ["a.swift", "b.swift", "c.swift"]

        let attribution = HolyCoordinationFileAttribution.attribute(
            sessionFiles: sameFiles,
            peers: [.init(id: peerID, sharesWorktree: false, changedFiles: Array(sameFiles))]
        )

        #expect(attribution.overlappingFiles == sameFiles)
        #expect(attribution.overlappingSessionIDs == [peerID])
        #expect(attribution.sharedWorktreeChangedFiles.isEmpty)
    }

    @Test func differentWorktreeOverlapKeepsDangerEmphasis() {
        let coordination = makeCoordination(
            overlappingSessionIDs: [peerID],
            overlappingFiles: ["a.swift", "b.swift"]
        )

        let items = coordination.riskStatusItems(hasBranchOwnershipDrift: false)

        #expect(items.map(\.text) == ["2 overlapping files"])
        #expect(items.first?.emphasis == .danger)
    }

    // MARK: - Mixed groups

    /// Three sessions: one shares this session's checkout, one works in a
    /// separate worktree. Each relationship keeps its own truth, and the shared
    /// checkout's dirty count must not inflate the cross-worktree overlap total.
    @Test func mixedGroupKeepsEachRelationshipSeparate() {
        let dirtyTree: Set<String> = ["a.swift", "b.swift", "c.swift", "d.swift"]

        let attribution = HolyCoordinationFileAttribution.attribute(
            sessionFiles: dirtyTree,
            peers: [
                .init(id: peerID, sharesWorktree: true, changedFiles: Array(dirtyTree)),
                .init(id: otherPeerID, sharesWorktree: false, changedFiles: ["d.swift", "e.swift"]),
            ]
        )

        // Only the separate worktree contributes contention, and only the one
        // file both sides actually touched.
        #expect(attribution.overlappingFiles == ["d.swift"])
        #expect(attribution.overlappingSessionIDs == [otherPeerID])

        // The checkout's four dirty files stay a property of the checkout.
        #expect(attribution.sharedWorktreeChangedFiles == dirtyTree)
        #expect(attribution.overlappingFiles.count < attribution.sharedWorktreeChangedFiles.count)
    }

    @Test func mixedGroupFooterStatesBothFactsWithoutBlendingThem() {
        let coordination = makeCoordination(
            sharedWorktreeSessionIDs: [peerID],
            sharedWorktreeChangedFiles: ["a.swift", "b.swift", "c.swift", "d.swift"],
            overlappingSessionIDs: [otherPeerID],
            overlappingFiles: ["d.swift"]
        )

        #expect(coordination.riskStatusItems(hasBranchOwnershipDrift: false).map(\.text) == [
            "1 overlapping file",
            "Same worktree with 1 session · 4 uncommitted files",
        ])
    }

    @Test func twoSharedWorktreePeersUnionTheCheckoutRatherThanDoubleCounting() {
        let dirtyTree: Set<String> = ["a.swift", "b.swift"]

        let attribution = HolyCoordinationFileAttribution.attribute(
            sessionFiles: dirtyTree,
            peers: [
                .init(id: peerID, sharesWorktree: true, changedFiles: Array(dirtyTree)),
                .init(id: otherPeerID, sharesWorktree: true, changedFiles: Array(dirtyTree)),
            ]
        )

        #expect(attribution.sharedWorktreeChangedFiles.count == 2)
        #expect(attribution.overlappingFiles.isEmpty)
    }

    // MARK: - Snapshot gaps

    /// A peer with no comparable snapshot still shares the checkout, and this
    /// session's own snapshot is a valid reading of that checkout.
    @Test func sharedWorktreePeerWithoutSnapshotStillCountsTheCheckout() {
        let attribution = HolyCoordinationFileAttribution.attribute(
            sessionFiles: ["a.swift", "b.swift"],
            peers: [.init(id: peerID, sharesWorktree: true, changedFiles: nil)]
        )

        #expect(attribution.sharedWorktreeChangedFiles == ["a.swift", "b.swift"])
        #expect(attribution.overlappingFiles.isEmpty)
    }

    @Test func differentWorktreePeerWithoutSnapshotContributesNothing() {
        let attribution = HolyCoordinationFileAttribution.attribute(
            sessionFiles: ["a.swift"],
            peers: [.init(id: peerID, sharesWorktree: false, changedFiles: nil)]
        )

        #expect(attribution == .init())
    }

    @Test func sessionWithoutOwnChangesInheritsThePeersViewOfTheSharedCheckout() {
        let attribution = HolyCoordinationFileAttribution.attribute(
            sessionFiles: [],
            peers: [.init(id: peerID, sharesWorktree: true, changedFiles: ["a.swift"])]
        )

        #expect(attribution.sharedWorktreeChangedFiles == ["a.swift"])
        #expect(attribution.overlappingFiles.isEmpty)
    }

    // MARK: - Wording

    @Test func sharedCheckoutWordingNamesTheCheckoutNotTheSessions() {
        #expect(
            HolyCoordinationPhrase.sharedCheckoutFiles(count: 30)
                == "30 uncommitted files in the shared checkout"
        )
        #expect(
            HolyCoordinationPhrase.sharedCheckoutFiles(count: 1)
                == "1 uncommitted file in the shared checkout"
        )
    }

    @Test func aCleanSharedCheckoutOmitsTheCount() {
        #expect(
            HolyCoordinationPhrase.sameWorktree(sessionCount: 1, changedFileCount: 0)
                == "Same worktree with 1 session"
        )
        #expect(
            HolyCoordinationPhrase.sharedWorktree(sessionCount: 2, changedFileCount: 0)
                == "Shared worktree with 2 sessions"
        )
    }

    @Test func summaryPhrasesPluralizeOnBothCounts() {
        #expect(
            HolyCoordinationPhrase.sharedWorktree(sessionCount: 1, changedFileCount: 1)
                == "Shared worktree with 1 session · 1 uncommitted file"
        )
        #expect(
            HolyCoordinationPhrase.sharedWorktree(sessionCount: 3, changedFileCount: 12)
                == "Shared worktree with 3 sessions · 12 uncommitted files"
        )
        #expect(HolyCoordinationPhrase.overlappingFiles(count: 1) == "1 overlapping file")
        #expect(HolyCoordinationPhrase.overlappingFiles(count: 4) == "4 overlapping files")
    }

    // MARK: - Helpers

    private func makeCoordination(
        sharedWorktreeSessionIDs: [UUID] = [],
        sharedWorktreeChangedFiles: [String] = [],
        sharedBranchSessionIDs: [UUID] = [],
        overlappingSessionIDs: [UUID] = [],
        overlappingFiles: [String] = []
    ) -> HolySessionCoordination {
        .init(
            attention: .none,
            summary: "",
            sharedWorktreeSessionIDs: sharedWorktreeSessionIDs,
            sharedWorktreeSessionTitles: sharedWorktreeSessionIDs.map { _ in "peer" },
            sharedWorktreeChangedFiles: sharedWorktreeChangedFiles,
            sharedBranchSessionIDs: sharedBranchSessionIDs,
            sharedBranchSessionTitles: sharedBranchSessionIDs.map { _ in "peer" },
            overlappingSessionIDs: overlappingSessionIDs,
            overlappingSessionTitles: overlappingSessionIDs.map { _ in "peer" },
            overlappingFiles: overlappingFiles
        )
    }
}
