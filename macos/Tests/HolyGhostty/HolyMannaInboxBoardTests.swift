import Foundation
import Testing
@testable import Ghostty

/// Board scope and the refresh tick. Boards are discovered by probing
/// `<repository_root>/.manna` for every live Holy session, plus the nearest
/// umbrella board above them (that is how `/Users/erik/Custom-Coding/.manna`
/// joins a session running in `/Users/erik/Custom-Coding/holy-ghostty`).
struct HolyMannaInboxBoardTests {
    static func locate(
        _ roots: [String],
        home: String = "/Users/erik",
        boards: Set<String>,
        maxBoards: Int = HolyMannaBoardLocator.maxBoards
    ) -> [String] {
        HolyMannaBoardLocator.boardRoots(
            repositoryRoots: roots,
            homeDirectory: home,
            maxBoards: maxBoards,
            hasBoard: { boards.contains($0) }
        )
    }

    // MARK: - Locator

    @Test func everySessionRepoWithABoardIsRead_focusedFirst() {
        let found = Self.locate(
            ["/Users/erik/Custom-Coding/holy-ghostty", "/Users/erik/Custom-Coding/agent-do"],
            boards: ["/Users/erik/Custom-Coding/holy-ghostty", "/Users/erik/Custom-Coding/agent-do"]
        )
        #expect(found == [
            "/Users/erik/Custom-Coding/holy-ghostty",
            "/Users/erik/Custom-Coding/agent-do",
        ])
    }

    /// The umbrella workspace board joins by discovery, never by hardcoding,
    /// and sorts after the repo boards it sits above.
    @Test func theNearestAncestorBoardJoinsAfterTheRepoBoards() {
        let found = Self.locate(
            ["/Users/erik/Custom-Coding/holy-ghostty"],
            boards: ["/Users/erik/Custom-Coding/holy-ghostty", "/Users/erik/Custom-Coding"]
        )
        #expect(found == [
            "/Users/erik/Custom-Coding/holy-ghostty",
            "/Users/erik/Custom-Coding",
        ])
    }

    @Test func aRepoWithNoBoardStillContributesItsAncestorBoard() {
        let found = Self.locate(
            ["/Users/erik/Custom-Coding/no-board-here"],
            boards: ["/Users/erik/Custom-Coding"]
        )
        #expect(found == ["/Users/erik/Custom-Coding"])
    }

    @Test func onlyTheNearestAncestorBoardIsTakenNotEveryAncestor() {
        let found = Self.locate(
            ["/Users/erik/Custom-Coding/holy-ghostty"],
            boards: ["/Users/erik/Custom-Coding", "/Users/erik"]
        )
        #expect(found == ["/Users/erik/Custom-Coding"])
    }

    @Test func repeatedSessionsInOneRepoReadItsBoardOnce() {
        let found = Self.locate(
            [
                "/Users/erik/Custom-Coding/holy-ghostty",
                "/Users/erik/Custom-Coding/holy-ghostty/",
                "/Users/erik/Custom-Coding/holy-ghostty",
            ],
            boards: ["/Users/erik/Custom-Coding/holy-ghostty", "/Users/erik/Custom-Coding"]
        )
        #expect(found == [
            "/Users/erik/Custom-Coding/holy-ghostty",
            "/Users/erik/Custom-Coding",
        ])
    }

    @Test func theWalkNeverClimbsAboveHome() {
        // A board at /Users would be someone else's business.
        let found = Self.locate(
            ["/Users/erik/project"],
            home: "/Users/erik",
            boards: ["/Users", "/"]
        )
        #expect(found.isEmpty)
    }

    @Test func homesOwnBoardIsReachableButNothingBeyondIt() {
        let found = Self.locate(
            ["/Users/erik/project"],
            home: "/Users/erik",
            boards: ["/Users/erik"]
        )
        #expect(found == ["/Users/erik"])
    }

    /// A repo outside home still gets a bounded walk, never one to `/`.
    @Test func aRepoOutsideHomeWalksABoundedNumberOfAncestors() {
        #expect(Self.locate(["/opt/a/b/c/d"], boards: ["/opt/a"]) == ["/opt/a"])
        #expect(Self.locate(["/opt/a/b/c/d/e/f"], boards: ["/opt"]).isEmpty)
    }

    /// Each board costs two subprocesses per tick; a workspace full of
    /// sessions must not turn the inbox into a fork bomb.
    @Test func theBoardCountIsCapped() {
        let roots = (1...20).map { "/Users/erik/Custom-Coding/repo\($0)" }
        let found = Self.locate(roots, boards: Set(roots), maxBoards: 4)
        #expect(found.count == 4)
        #expect(found.first == "/Users/erik/Custom-Coding/repo1")
    }

    @Test func pathsAreNormalizedBeforeProbing() {
        let found = Self.locate(
            ["/Users/erik/Custom-Coding/agent-do/../holy-ghostty/"],
            boards: ["/Users/erik/Custom-Coding/holy-ghostty"]
        )
        #expect(found == ["/Users/erik/Custom-Coding/holy-ghostty"])
    }

    @Test func emptyAndRelativeRootsAreIgnored() {
        #expect(Self.locate([], boards: ["/Users/erik/Custom-Coding"]).isEmpty)
        #expect(Self.locate(["", "  ", "relative/path"], boards: ["/Users/erik"]).isEmpty)
    }

    // MARK: - Refresh

    /// A temp workspace: `<tmp>/work/repo/.manna` and `<tmp>/work/.manna`,
    /// probed by the real FileManager so discovery is not faked in this test.
    static func makeWorkspace() throws -> (home: String, repo: String, umbrella: String) {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-manna-\(UUID().uuidString)")
        let umbrella = home.appendingPathComponent("work")
        let repo = umbrella.appendingPathComponent("repo")
        for board in [umbrella, repo] {
            try FileManager.default.createDirectory(
                at: board.appendingPathComponent(".manna"),
                withIntermediateDirectories: true
            )
        }
        return (
            home.standardizedFileURL.path,
            repo.standardizedFileURL.path,
            umbrella.standardizedFileURL.path
        )
    }

    @Test func refreshReadsEveryDiscoveredBoardAndKeepsTheFocusedOneFirst() async throws {
        let workspace = try Self.makeWorkspace()
        defer { try? FileManager.default.removeItem(atPath: workspace.home) }

        let dream = HolyMannaIssueSummary(
            id: "mn-aaa111",
            title: "a dream",
            status: .open,
            claimedBy: nil,
            type: .dream,
            track: nil,
            updated: "2026-08-01 (2d ago)",
            gate: "[DREAM: not claimable, needs conversion]"
        )

        let source = HolyMannaInboxSource(
            repositoryRootsProvider: { [workspace.repo] },
            homeDirectory: workspace.home,
            boardReader: { root in
                HolyMannaBoardReading(root: root, issues: [dream])
            }
        )

        let snapshot = await source.refresh(context: HolyInboxRefreshContext())
        let dreams = try #require(snapshot.sections.first { $0.id == "manna.dreams" })
        #expect(dreams.rows.map(\.id) == [
            HolyMannaInboxSectioner.rowID(boardRoot: workspace.repo, issueID: "mn-aaa111"),
            HolyMannaInboxSectioner.rowID(boardRoot: workspace.umbrella, issueID: "mn-aaa111"),
        ])
    }

    @Test func noSessionsMeansNoBoardsAndNothingToSay() async {
        let source = HolyMannaInboxSource(
            repositoryRootsProvider: { [] },
            boardReader: { root in
                Issue.record("read a board with no sessions: \(root)")
                return HolyMannaBoardReading(root: root)
            }
        )
        #expect(await source.refresh(context: HolyInboxRefreshContext()) == .empty)
    }

    @Test func aBoardThatFailsToReadDegradesInsteadOfEmptyingThePane() async throws {
        let workspace = try Self.makeWorkspace()
        defer { try? FileManager.default.removeItem(atPath: workspace.home) }

        let source = HolyMannaInboxSource(
            repositoryRootsProvider: { [workspace.repo] },
            homeDirectory: workspace.home,
            boardReader: { root in
                HolyMannaBoardReading(root: root, degradedDetail: "exited with status 1.")
            }
        )

        let snapshot = await source.refresh(context: HolyInboxRefreshContext())
        let degraded = try #require(snapshot.sections.first { $0.id == "manna.degraded" })
        #expect(degraded.rows.count == 2)
        #expect(degraded.rows.allSatisfy { $0.isDegraded })
        #expect(HolyInboxEngine.badgeCount(for: snapshot.sections) == 0)
    }

    @Test func aMissingCLIDegradesQuietlyUnderThisSourcesIdentifier() {
        let snapshot = HolyMannaInboxSource.degradedSnapshot(detail: "not on PATH.")
        #expect(snapshot.sections.count == 1)
        #expect(snapshot.sections[0].sourceID == HolyMannaInboxSectioner.sourceID)
        #expect(snapshot.sections[0].countsTowardBadge == false)
        #expect(snapshot.sections[0].rows.count == 1)
        #expect(snapshot.sections[0].rows[0].isDegraded)
        #expect(snapshot.sections[0].rows[0].subtitle == "not on PATH.")
    }

    /// Rows clear by the source re-stating truth: the dream is gone from the
    /// board on the next tick, so it is gone from the pane.
    @Test func aRowAbsentFromTheNextReadLeavesThePane() async throws {
        let workspace = try Self.makeWorkspace()
        defer { try? FileManager.default.removeItem(atPath: workspace.home) }

        let board = HolyMannaMutableBoard()
        board.issues = [HolyMannaIssueSummary(
            id: "mn-aaa111",
            title: "a dream",
            status: .open,
            claimedBy: nil,
            type: .dream,
            track: nil,
            updated: "2026-08-01 (2d ago)",
            gate: nil
        )]

        let source = HolyMannaInboxSource(
            repositoryRootsProvider: { [workspace.repo] },
            homeDirectory: workspace.home,
            boardReader: { root in
                HolyMannaBoardReading(root: root, issues: board.issues)
            }
        )

        #expect(await source.refresh(context: HolyInboxRefreshContext()).sections.isEmpty == false)
        board.issues = []
        #expect(await source.refresh(context: HolyInboxRefreshContext()) == .empty)
    }
}

/// A board whose contents change between refresh ticks.
final class HolyMannaMutableBoard: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [HolyMannaIssueSummary] = []

    var issues: [HolyMannaIssueSummary] {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }
}
