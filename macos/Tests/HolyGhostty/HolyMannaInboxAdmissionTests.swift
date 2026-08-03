import Foundation
import Testing
@testable import Ghostty

/// The manna admission law. Most manna traffic is agent-to-agent and must
/// never reach the pane; exactly three states are a human decision:
///
///   1. dreams awaiting triage      — cleared by conversion (type moves off
///                                    dream) or closure (status done)
///   2. unblocked but unclaimed     — reconcile `blocker_desync` on an issue
///                                    nobody claimed; cleared by a claim or a
///                                    blocker-state change
///   3. stale claims                — reconcile `dead_claim`; cleared by a
///                                    reclaim or an abandon
///
/// Everything else — open backlogs, in_progress work, tracks, landed_open,
/// dangling_track, doc_reference, prompt_pairing, skipped — stays out. The
/// inbox is not a board mirror.
struct HolyMannaInboxAdmissionTests {
    static let holyBoard = "/Users/erik/Custom-Coding/holy-ghostty"
    static let workspaceBoard = "/Users/erik/Custom-Coding"

    static func issue(
        _ id: String,
        title: String = "t",
        type: HolyMannaIssueType = .item,
        status: HolyMannaIssueStatus = .open,
        claimedBy: String? = nil,
        updated: String = "2026-08-01 (2d ago)"
    ) -> HolyMannaIssueSummary {
        HolyMannaIssueSummary(
            id: id,
            title: title,
            status: status,
            claimedBy: claimedBy,
            type: type,
            track: nil,
            updated: updated,
            gate: type == .dream ? "[DREAM: not claimable, needs conversion]" : nil
        )
    }

    static func finding(
        _ kind: HolyMannaFindingKind,
        _ issueID: String?,
        detail: String = "d",
        evidence: String? = nil
    ) -> HolyMannaReconcileFinding {
        HolyMannaReconcileFinding(
            kind: kind,
            issueID: issueID,
            detail: detail,
            evidence: evidence,
            proposedFix: nil
        )
    }

    static func board(
        root: String,
        issues: [HolyMannaIssueSummary] = [],
        findings: [HolyMannaReconcileFinding] = [],
        degradedDetail: String? = nil
    ) -> HolyMannaBoardReading {
        HolyMannaBoardReading(
            root: root,
            issues: issues,
            findings: findings,
            degradedDetail: degradedDetail
        )
    }

    static func sections(
        _ boards: [HolyMannaBoardReading],
        focusedBoardRoot: String? = nil
    ) -> [HolyInboxSection] {
        HolyMannaInboxSectioner.sections(boards: boards, focusedBoardRoot: focusedBoardRoot)
    }

    static func rowIDs(_ sections: [HolyInboxSection], _ sectionID: String) -> [String] {
        sections.first { $0.id == sectionID }?.rows.map(\.id) ?? []
    }

    // MARK: - 1. Dreams awaiting triage

    @Test func openDreamsAreAdmittedAndClosedDreamsAreNot() {
        let result = Self.sections([Self.board(
            root: Self.holyBoard,
            issues: [
                Self.issue("mn-aaa111", type: .dream, status: .open),
                Self.issue("mn-aaa222", type: .dream, status: .blocked),
                Self.issue("mn-aaa333", type: .dream, status: .done),
            ]
        )])

        #expect(Self.rowIDs(result, "manna.dreams") == [
            "manna:\(Self.holyBoard):mn-aaa111",
            "manna:\(Self.holyBoard):mn-aaa222",
        ])
    }

    /// The two clear conditions the grammar names: converted, or closed.
    @Test func aConvertedDreamLeavesThePaneBecauseItsTypeMoved() {
        let before = Self.sections([Self.board(
            root: Self.holyBoard,
            issues: [Self.issue("mn-aaa111", type: .dream, status: .open)]
        )])
        #expect(Self.rowIDs(before, "manna.dreams").count == 1)

        // Conversion: same id, now an item on a track.
        let after = Self.sections([Self.board(
            root: Self.holyBoard,
            issues: [Self.issue("mn-aaa111", type: .item, status: .open)]
        )])
        #expect(after.contains { $0.id == "manna.dreams" } == false)
    }

    @Test func aStaleDreamFindingChipsTheDreamRowInsteadOfAddingASecondOne() throws {
        let result = Self.sections([Self.board(
            root: Self.holyBoard,
            issues: [
                Self.issue("mn-aaa111", type: .dream, status: .open),
                Self.issue("mn-aaa222", type: .dream, status: .open),
            ],
            findings: [Self.finding(.staleDream, "mn-aaa111", evidence: "created_at 2026-07-16")]
        )])

        let dreams = try #require(result.first { $0.id == "manna.dreams" })
        #expect(dreams.rows.count == 2)

        let stale = try #require(dreams.rows.first { $0.id.hasSuffix("mn-aaa111") })
        #expect(stale.chips.contains(HolyInboxChip("stale", emphasis: .warning)))
        let fresh = try #require(dreams.rows.first { $0.id.hasSuffix("mn-aaa222") })
        #expect(fresh.chips.contains(HolyInboxChip("stale", emphasis: .warning)) == false)
    }

    // MARK: - 2. Unblocked but unclaimed

    @Test func blockerDesyncOnAnUnclaimedItemIsAdmitted() throws {
        let result = Self.sections([Self.board(
            root: Self.holyBoard,
            issues: [Self.issue("mn-bbb111", title: "Reap true orphans", status: .blocked)],
            findings: [Self.finding(
                .blockerDesync,
                "mn-bbb111",
                detail: "all blockers resolved but status is still blocked",
                evidence: "mn-495322 (done)"
            )]
        )])

        let section = try #require(result.first { $0.id == "manna.unblocked" })
        #expect(section.rows.count == 1)
        #expect(section.rows[0].title == "Reap true orphans")
        #expect(section.rows[0].chips.contains(HolyInboxChip("unblocked", emphasis: .attention)))
        // Evidence names which blocker resolved; the row must carry it.
        #expect(section.rows[0].subtitle?.contains("mn-495322 (done)") == true)
    }

    @Test func aClaimedIssueClearsTheUnblockedRow() {
        let result = Self.sections([Self.board(
            root: Self.holyBoard,
            issues: [Self.issue("mn-bbb111", status: .inProgress, claimedBy: "ses_live")],
            findings: [Self.finding(.blockerDesync, "mn-bbb111")]
        )])
        #expect(result.contains { $0.id == "manna.unblocked" } == false)
    }

    @Test func aFindingNamingAnIssueTheBoardDoesNotListProducesNoRow() {
        let result = Self.sections([Self.board(
            root: Self.holyBoard,
            issues: [Self.issue("mn-bbb111")],
            findings: [
                Self.finding(.blockerDesync, "mn-ghost1"),
                Self.finding(.deadClaim, "mn-ghost2"),
                Self.finding(.blockerDesync, nil),
            ]
        )])
        #expect(result.isEmpty)
    }

    // MARK: - 3. Stale claims

    @Test func deadClaimOnAClaimedIssueIsAdmittedAsASecondaryRow() throws {
        let result = Self.sections([Self.board(
            root: Self.holyBoard,
            issues: [Self.issue("mn-ccc111", status: .inProgress, claimedBy: "ses_pid999_1")],
            findings: [Self.finding(
                .deadClaim,
                "mn-ccc111",
                detail: "claimed by dead session ses_pid999_1",
                evidence: "pid 999 not running"
            )]
        )])

        let section = try #require(result.first { $0.id == "manna.staleclaims" })
        #expect(section.rows.count == 1)
        #expect(section.rows[0].chips.contains(HolyInboxChip("stale claim", emphasis: .warning)))
        // Drift cleanup is real but secondary: it must not inflate the badge.
        #expect(section.countsTowardBadge == false)
        #expect(section.collapsedByDefault)
    }

    @Test func anAbandonedClaimClearsTheStaleClaimRow() {
        let result = Self.sections([Self.board(
            root: Self.holyBoard,
            issues: [Self.issue("mn-ccc111", status: .open, claimedBy: nil)],
            findings: [Self.finding(.deadClaim, "mn-ccc111")]
        )])
        #expect(result.contains { $0.id == "manna.staleclaims" } == false)
    }

    // MARK: - Everything else stays out

    @Test func ordinaryBoardTrafficNeverReachesThePane() {
        let result = Self.sections([Self.board(
            root: Self.holyBoard,
            issues: [
                Self.issue("mn-ddd111", status: .open),
                Self.issue("mn-ddd222", status: .inProgress, claimedBy: "ses_live"),
                Self.issue("mn-ddd333", status: .blocked),
                Self.issue("mn-ddd444", status: .done),
                Self.issue("mn-ddd555", type: .track, status: .blocked),
                Self.issue("mn-ddd666", type: .unknown, status: .unknown),
            ]
        )])
        #expect(result.isEmpty)
    }

    @Test func agentBookkeepingFindingsNeverBecomeRows() {
        let ignored: [HolyMannaFindingKind] = [
            .landedOpen, .danglingTrack, .docReference, .promptPairing, .skipped, .unknown,
        ]
        let result = Self.sections([Self.board(
            root: Self.holyBoard,
            issues: [Self.issue("mn-eee111", status: .blocked)],
            findings: ignored.map { Self.finding($0, "mn-eee111") }
        )])
        #expect(result.isEmpty)
    }

    /// A track is a grouping, never a human decision; and a dream is never
    /// claimable, so it can never be an unblocked-unclaimed row either.
    @Test func tracksAndDreamsAreNeverUnblockedRows() {
        let result = Self.sections([Self.board(
            root: Self.holyBoard,
            issues: [
                Self.issue("mn-fff111", type: .track, status: .blocked),
                Self.issue("mn-fff222", type: .dream, status: .blocked),
            ],
            findings: [
                Self.finding(.blockerDesync, "mn-fff111"),
                Self.finding(.blockerDesync, "mn-fff222"),
            ]
        )])
        #expect(result.contains { $0.id == "manna.unblocked" } == false)
        // The dream is still a dream row — admitted by rule 1, once.
        #expect(Self.rowIDs(result, "manna.dreams") == ["manna:\(Self.holyBoard):mn-fff222"])
    }

    @Test func repeatedFindingsForOneIssueProduceOneRow() {
        let result = Self.sections([Self.board(
            root: Self.holyBoard,
            issues: [Self.issue("mn-ggg111", status: .blocked)],
            findings: [
                Self.finding(.blockerDesync, "mn-ggg111", detail: "status blocked but blocked_by is empty"),
                Self.finding(.blockerDesync, "mn-ggg111", detail: "all blockers resolved but status is still blocked"),
            ]
        )])
        #expect(Self.rowIDs(result, "manna.unblocked") == ["manna:\(Self.holyBoard):mn-ggg111"])
    }

    // MARK: - Multi-board merge and focused-first ordering

    @Test func boardsMergeIntoOneSectionPerKindWithFocusedBoardFirst() {
        let boards = [
            Self.board(
                root: Self.workspaceBoard,
                issues: [Self.issue("mn-w00001", type: .dream, updated: "2026-08-02 (1d ago)")]
            ),
            Self.board(
                root: Self.holyBoard,
                issues: [Self.issue("mn-h00001", type: .dream, updated: "2026-07-01 (33d ago)")]
            ),
        ]

        // Focus reorders, never filters: the older focused row leads.
        let focused = Self.sections(boards, focusedBoardRoot: Self.holyBoard)
        #expect(Self.rowIDs(focused, "manna.dreams") == [
            "manna:\(Self.holyBoard):mn-h00001",
            "manna:\(Self.workspaceBoard):mn-w00001",
        ])

        // With no focus, newest activity leads.
        let unfocused = Self.sections(boards)
        #expect(Self.rowIDs(unfocused, "manna.dreams") == [
            "manna:\(Self.workspaceBoard):mn-w00001",
            "manna:\(Self.holyBoard):mn-h00001",
        ])
    }

    @Test func rowsFromDifferentBoardsSharingAnIssueIDStayDistinct() {
        let boards = [
            Self.board(root: Self.holyBoard, issues: [Self.issue("mn-same01", type: .dream)]),
            Self.board(root: Self.workspaceBoard, issues: [Self.issue("mn-same01", type: .dream)]),
        ]
        #expect(Set(Self.rowIDs(Self.sections(boards), "manna.dreams")).count == 2)
    }

    @Test func everySectionCarriesTheSourcesOwnIdentifier() {
        let result = Self.sections([Self.board(
            root: Self.holyBoard,
            issues: [
                Self.issue("mn-aaa111", type: .dream),
                Self.issue("mn-bbb111", status: .blocked),
                Self.issue("mn-ccc111", status: .inProgress, claimedBy: "ses_dead"),
            ],
            findings: [
                Self.finding(.blockerDesync, "mn-bbb111"),
                Self.finding(.deadClaim, "mn-ccc111"),
            ],
            degradedDetail: "boom"
        )])

        #expect(result.map(\.id) == [
            "manna.dreams", "manna.unblocked", "manna.staleclaims", "manna.degraded",
        ])
        #expect(result.allSatisfy { $0.sourceID == HolyMannaInboxSectioner.sourceID })
    }

    /// The badge counts first-person attention only, and never a degraded row.
    @Test func badgeCountsDreamsAndUnblockedWorkOnly() {
        let result = Self.sections([Self.board(
            root: Self.holyBoard,
            issues: [
                Self.issue("mn-aaa111", type: .dream),
                Self.issue("mn-bbb111", status: .blocked),
                Self.issue("mn-ccc111", status: .inProgress, claimedBy: "ses_dead"),
            ],
            findings: [
                Self.finding(.blockerDesync, "mn-bbb111"),
                Self.finding(.deadClaim, "mn-ccc111"),
            ],
            degradedDetail: "boom"
        )])
        #expect(HolyInboxEngine.badgeCount(for: result) == 2)
    }

    // MARK: - Degraded boards

    @Test func aBrokenBoardShowsOneQuietRowNamingIt() throws {
        let result = Self.sections([Self.board(
            root: Self.holyBoard,
            degradedDetail: "agent-do manna list exited with status 1."
        )])

        let section = try #require(result.first { $0.id == "manna.degraded" })
        #expect(section.rows.count == 1)
        #expect(section.rows[0].isDegraded)
        #expect(section.rows[0].title == "manna unavailable — holy-ghostty")
        #expect(section.rows[0].subtitle == "agent-do manna list exited with status 1.")
        #expect(section.rows[0].action == .none)
        #expect(section.countsTowardBadge == false)
    }

    /// One board breaking must not silence the others.
    @Test func aBrokenBoardDoesNotSuppressAHealthyOne() {
        let result = Self.sections([
            Self.board(root: Self.workspaceBoard, degradedDetail: "not found"),
            Self.board(root: Self.holyBoard, issues: [Self.issue("mn-aaa111", type: .dream)]),
        ])
        #expect(Self.rowIDs(result, "manna.dreams") == ["manna:\(Self.holyBoard):mn-aaa111"])
        #expect(Self.rowIDs(result, "manna.degraded").count == 1)
    }

    /// Half a board is still honest: dreams come from `list`, so they survive
    /// a `reconcile` failure — but the pane must say the drift half is blind.
    @Test func aFailedReconcileKeepsDreamRowsAndStillReportsTheGap() {
        let result = Self.sections([Self.board(
            root: Self.holyBoard,
            issues: [Self.issue("mn-aaa111", type: .dream)],
            degradedDetail: "agent-do manna reconcile did not finish within 45 seconds."
        )])
        #expect(Self.rowIDs(result, "manna.dreams").count == 1)
        #expect(Self.rowIDs(result, "manna.degraded").count == 1)
    }

    @Test func noBoardsAtAllIsSilenceNotADegradedRow() {
        #expect(Self.sections([]).isEmpty)
    }

    // MARK: - Row action

    /// Clicking a row opens a shell in the board's repo with a read-only
    /// `manna show` prefilled. It must never mutate the board: `initial_input`
    /// is piped to the shell's stdin, so anything placed there RUNS.
    @Test func rowActionSpawnsAShellInTheBoardWithAReadOnlyShowPrefilled() throws {
        let result = Self.sections([Self.board(
            root: Self.holyBoard,
            issues: [Self.issue("mn-aaa111", type: .dream)]
        )])
        let row = try #require(result.first { $0.id == "manna.dreams" }?.rows.first)

        guard case let .openURL(url) = row.action else {
            Issue.record("expected an openURL action, got \(row.action)")
            return
        }
        #expect(url.scheme == "holy-ghostty")

        let spec = try #require(HolyAutomationURLParser.launchSpec(from: url))
        #expect(spec.runtime == .shell)
        #expect(spec.workingDirectory == Self.holyBoard)
        #expect(spec.initialInput == "agent-do manna show mn-aaa111")
        #expect(spec.command == nil)
        #expect(row.acknowledgeable == false)
    }

    @Test func everyAdmittedRowKindGetsTheSameSafeReadOnlyAction() {
        let result = Self.sections([Self.board(
            root: Self.holyBoard,
            issues: [
                Self.issue("mn-aaa111", type: .dream),
                Self.issue("mn-bbb111", status: .blocked),
                Self.issue("mn-ccc111", status: .inProgress, claimedBy: "ses_dead"),
            ],
            findings: [
                Self.finding(.blockerDesync, "mn-bbb111"),
                Self.finding(.deadClaim, "mn-ccc111"),
            ]
        )])

        let inputs = result.flatMap(\.rows).compactMap { row -> String? in
            guard case let .openURL(url) = row.action else { return nil }
            return HolyAutomationURLParser.launchSpec(from: url)?.initialInput
        }
        #expect(inputs.count == 3)
        #expect(inputs.allSatisfy { $0.hasPrefix("agent-do manna show mn-") })
        // No claim, abandon, done, or reconcile --fix ever rides a click.
        #expect(inputs.allSatisfy { !$0.contains("claim") && !$0.contains("abandon") })
    }

    /// Board roots with characters the automation URL round-trip mangles:
    /// `URLComponents` leaves `+` literal and the parser turns it back into a
    /// space, so the builder has to encode it.
    @Test func awkwardBoardPathsSurviveTheURLRoundTrip() throws {
        let awkward = "/Users/erik/Custom Coding/a+b & c"
        let result = Self.sections([Self.board(
            root: awkward,
            issues: [Self.issue("mn-aaa111", type: .dream)]
        )])
        let row = try #require(result.first { $0.id == "manna.dreams" }?.rows.first)

        guard case let .openURL(url) = row.action else {
            Issue.record("expected an openURL action")
            return
        }
        let spec = try #require(HolyAutomationURLParser.launchSpec(from: url))
        #expect(spec.workingDirectory == awkward)
    }
}
